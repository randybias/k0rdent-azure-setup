#!/usr/bin/env bash

# Script: install-kof-child.sh
# Purpose: Install KOF on child cluster
# Usage: bash install-kof-child.sh [deploy|uninstall|status|help]
# Prerequisites: KOF regional installed, child cluster accessible

set -euo pipefail

# Load ALL existing k0rdent infrastructure
source ./etc/k0rdent-config.sh      # Loads CONFIG_YAML automatically
source ./etc/common-functions.sh     # All common functionality
source ./etc/state-management.sh     # State tracking
source ./etc/kof-functions.sh        # ONLY KOF-specific additions

# Output directory and file (reuse from k0rdent)
K0SCTL_DIR="./k0sctl-config"
KUBECONFIG_FILE="$K0SCTL_DIR/${K0RDENT_PREFIX}-kubeconfig"

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  deploy     Install KOF on child cluster
  uninstall  Remove KOF from child cluster
  status     Show KOF child installation status
  help       Show this help message" \
        "  -y, --yes        Skip confirmation prompts
  --no-wait        Skip waiting for resources" \
        "  $0 deploy        # Install KOF on child cluster
  $0 status        # Check installation status
  $0 uninstall     # Remove KOF from child cluster"
}

check_prerequisites() {
    print_info "Checking prerequisites for KOF child deployment..."
    
    # Check if k0rdent is installed
    if [[ "$(get_state "k0rdent_installed")" != "true" ]]; then
        print_error "k0rdent must be installed before deploying KOF"
        print_info "Run: ./bin/install-k0rdent.sh deploy"
        return 1
    fi
    
    # Check if KOF mothership is installed
    if [[ "$(get_state "kof_mothership_installed")" != "true" ]]; then
        print_error "KOF mothership must be installed before deploying child cluster"
        print_info "Run: ./bin/install-kof-mothership.sh deploy"
        return 1
    fi
    
    # Note: We don't strictly require regional to be installed as child clusters
    # can connect directly to mothership in some configurations
    local regional_installed=$(get_state "kof_regional_installed")
    if [[ "$regional_installed" != "true" ]]; then
        print_warning "KOF regional is not installed. Child cluster will connect directly to mothership."
        print_info "For better scalability, consider installing regional cluster first: ./bin/install-kof-regional.sh deploy"
    fi
    
    # Check VPN connectivity
    if ! check_vpn_connectivity; then
        print_error "VPN connectivity required for KOF operations"
        print_info "Connect to VPN: ./bin/manage-vpn.sh connect"
        return 1
    fi
    
    # Check if KOF is enabled in configuration
    if ! check_kof_enabled; then
        print_error "KOF is not enabled in configuration"
        print_info "Set 'kof.enabled: true' in your k0rdent.yaml"
        return 1
    fi
    
    # Check kubeconfig exists
    if [[ ! -f "$KUBECONFIG_FILE" ]]; then
        print_error "Kubeconfig not found at $KUBECONFIG_FILE"
        print_info "Ensure k0s cluster is deployed"
        return 1
    fi
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    # Test kubectl connectivity
    if ! kubectl get nodes &>/dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    print_success "All prerequisites satisfied"
    return 0
}

deploy_kof_child() {
    print_header "Deploying KOF Child Cluster"
    
    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi
    
    # Get configuration values
    local kof_version=$(get_kof_config "version" "1.1.0")
    local kof_namespace=$(get_kof_config "child.namespace" "kof")
    local cluster_label=$(get_kof_config "child.cluster_label" "k0rdent.mirantis.com/istio-role=child")
    local regional_cluster=$(get_kof_config "child.regional_cluster" "")
    
    print_info "KOF Version: $kof_version"
    print_info "Namespace: $kof_namespace"
    print_info "Cluster Label: $cluster_label"
    if [[ -n "$regional_cluster" ]]; then
        print_info "Regional Cluster: $regional_cluster"
    else
        print_info "Regional Cluster: (direct to mothership)"
    fi
    
    # Update deployment state
    update_state "phase" "kof_child_deployment"
    add_event "kof_child_deployment_started" "Starting KOF child deployment v$kof_version"
    
    # Step 1: Prepare KOF namespace
    print_header "Step 1: Preparing KOF Namespace"
    if ! prepare_kof_namespace "$kof_namespace"; then
        print_error "Failed to prepare KOF namespace"
        return 1
    fi
    
    # Step 2: Apply cluster labels
    print_header "Step 2: Labeling Cluster for Child Role"
    print_info "Applying cluster labels for child configuration..."
    
    # Parse the cluster label to get key and value
    local label_key="${cluster_label%=*}"
    local label_value="${cluster_label#*=}"
    
    # Apply the label to the cluster (using nodes as proxy for cluster labeling)
    local cluster_name=$(kubectl config current-context)
    print_info "Labeling cluster '$cluster_name' with '$label_key=$label_value'"
    
    # In Istio deployment model, we label nodes to indicate the cluster role
    if kubectl label nodes --all "$label_key=$label_value" --overwrite; then
        print_success "Cluster labeled for child role"
        add_event "kof_child_cluster_labeled" "Cluster labeled with $cluster_label"
    else
        print_error "Failed to label cluster for child role"
        add_event "kof_child_labeling_failed" "Failed to apply cluster labels"
        return 1
    fi
    
    # Step 3: Create ClusterProfile for child configuration
    print_header "Step 3: Creating Child ClusterProfile"
    print_info "Creating ClusterProfile for child cluster configuration..."
    
    # Create a ClusterProfile manifest for child cluster
    local clusterprofile_yaml="/tmp/kof-child-clusterprofile.yaml"
    cat > "$clusterprofile_yaml" << EOF
apiVersion: kcm.mirantis.com/v1alpha1
kind: ClusterProfile
metadata:
  name: kof-child-profile
  namespace: $kof_namespace
spec:
  description: "KOF Child Cluster Profile"
  config:
    # Child-specific configuration
    role: "child"
    istio:
      enabled: true
      role: "child"
    # Optional regional cluster connection
    $(if [[ -n "$regional_cluster" ]]; then
        echo "    regional_cluster: \"$regional_cluster\""
    fi)
  # Child-specific collectors from configuration
  collectors: $(get_kof_config "child.collectors" "{}")
EOF
    
    if kubectl apply -f "$clusterprofile_yaml"; then
        print_success "Child ClusterProfile created"
        add_event "kof_child_clusterprofile_created" "ClusterProfile for child cluster created"
        rm -f "$clusterprofile_yaml"
    else
        print_error "Failed to create child ClusterProfile"
        add_event "kof_child_clusterprofile_failed" "Failed to create ClusterProfile"
        rm -f "$clusterprofile_yaml"
        return 1
    fi
    
    # Step 4: Configure minimal child footprint
    print_header "Step 4: Configuring Minimal Child Installation"
    print_info "Applying minimal configuration for child cluster..."
    
    # Child clusters typically have a smaller footprint
    # Create a minimal configuration ConfigMap
    local child_config_yaml="/tmp/kof-child-config.yaml"
    cat > "$child_config_yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kof-child-config
  namespace: $kof_namespace
data:
  config.yaml: |
    # Minimal child cluster configuration
    cluster:
      role: child
      minimal_footprint: true
    collectors:
      # Reduced collector set for child clusters
      basic_metrics: true
      full_tracing: false
    resources:
      # Resource limits for child clusters
      limits:
        cpu: "200m"
        memory: "256Mi"
      requests:
        cpu: "100m"
        memory: "128Mi"
EOF
    
    if kubectl apply -f "$child_config_yaml"; then
        print_success "Child configuration applied"
        add_event "kof_child_config_created" "Minimal child configuration created"
        rm -f "$child_config_yaml"
    else
        print_error "Failed to apply child configuration"
        add_event "kof_child_config_failed" "Failed to create child configuration"
        rm -f "$child_config_yaml"
        return 1
    fi
    
    # Step 5: Verify child cluster configuration
    print_header "Step 5: Verifying Child Cluster Configuration"
    print_info "Verifying child cluster is properly configured..."
    
    # Check that the cluster has the correct labels
    if kubectl get nodes -l "$label_key=$label_value" --no-headers | grep -q .; then
        print_success "Child cluster nodes properly labeled"
    else
        print_warning "Child cluster labels may not be properly applied"
    fi
    
    # Check that the ClusterProfile exists
    if kubectl get clusterprofile kof-child-profile -n "$kof_namespace" &>/dev/null; then
        print_success "Child ClusterProfile verified"
    else
        print_warning "Child ClusterProfile verification failed"
    fi
    
    # Check that the ConfigMap exists
    if kubectl get configmap kof-child-config -n "$kof_namespace" &>/dev/null; then
        print_success "Child configuration verified"
    else
        print_warning "Child configuration verification failed"
    fi
    
    # Update state
    update_state "kof_child_installed" "true"
    update_state "kof_child_version" "$kof_version"
    update_state "kof_child_namespace" "$kof_namespace"
    update_state "kof_child_cluster_label" "$cluster_label"
    if [[ -n "$regional_cluster" ]]; then
        update_state "kof_child_regional_cluster" "$regional_cluster"
    fi
    add_event "kof_child_deployment_completed" "KOF child deployment completed successfully"
    
    print_success "KOF child cluster deployment completed!"
    print_info "Child cluster is now configured for KOF operations with minimal footprint"
    if [[ -n "$regional_cluster" ]]; then
        print_info "Child cluster is configured to connect through regional cluster: $regional_cluster"
    else
        print_info "Child cluster will connect directly to the mothership"
    fi
}

uninstall_kof_child() {
    print_header "Uninstalling KOF Child Configuration"
    
    # Check VPN connectivity for cluster operations
    if ! check_vpn_connectivity; then
        print_error "VPN connectivity required for cluster operations"
        print_info "Connect to VPN first: ./bin/manage-vpn.sh connect"
        return 1
    fi
    
    # Check if KOF child is installed
    if [[ "$(get_state "kof_child_installed")" != "true" ]]; then
        print_info "KOF child is not installed"
        return 0
    fi
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    # Get configuration
    local kof_namespace=$(get_kof_config "child.namespace" "kof")
    local cluster_label=$(get_kof_config "child.cluster_label" "k0rdent.mirantis.com/istio-role=child")
    
    # Confirm uninstall
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        print_warning "This will remove KOF child configuration from the cluster"
        if ! confirm_action "Proceed with uninstall?"; then
            print_info "Uninstall cancelled"
            return 0
        fi
    fi
    
    # Step 1: Remove child configuration
    print_info "Removing child configuration..."
    if kubectl delete configmap kof-child-config -n "$kof_namespace" --ignore-not-found; then
        print_success "Child configuration removed"
        add_event "kof_child_config_removed" "ConfigMap for child cluster removed"
    else
        print_warning "Failed to remove child configuration or it was not found"
    fi
    
    # Step 2: Remove ClusterProfile
    print_info "Removing child ClusterProfile..."
    if kubectl delete clusterprofile kof-child-profile -n "$kof_namespace" --ignore-not-found; then
        print_success "Child ClusterProfile removed"
        add_event "kof_child_clusterprofile_removed" "ClusterProfile for child cluster removed"
    else
        print_warning "Failed to remove child ClusterProfile or it was not found"
    fi
    
    # Step 3: Remove cluster labels
    print_info "Removing child cluster labels..."
    local label_key="${cluster_label%=*}"
    
    if kubectl label nodes --all "$label_key-" --ignore-not-found; then
        print_success "Child cluster labels removed"
        add_event "kof_child_labels_removed" "Cluster labels for child role removed"
    else
        print_warning "Failed to remove child cluster labels or they were not found"
    fi
    
    # Update state
    update_state "kof_child_installed" "false"
    remove_state_key "kof_child_version"
    remove_state_key "kof_child_namespace"
    remove_state_key "kof_child_cluster_label"
    remove_state_key "kof_child_regional_cluster"
    add_event "kof_child_uninstall_completed" "KOF child uninstall completed"
    
    print_success "KOF child uninstall completed!"
}

show_kof_child_status() {
    print_header "KOF Child Status"
    
    # Check if KOF is enabled
    if ! check_kof_enabled; then
        print_info "KOF is not enabled in configuration"
        return 0
    fi
    
    # Check installation state
    local installed=$(get_state "kof_child_installed")
    if [[ "$installed" != "true" ]]; then
        print_info "KOF child is not installed"
        return 0
    fi
    
    # Show configuration
    local version=$(get_state "kof_child_version")
    local namespace=$(get_state "kof_child_namespace")
    local cluster_label=$(get_state "kof_child_cluster_label")
    local regional_cluster=$(get_state "kof_child_regional_cluster")
    
    print_info "KOF Child Information:"
    print_info "  Version: $version"
    print_info "  Namespace: $namespace"
    print_info "  Cluster Label: $cluster_label"
    if [[ -n "$regional_cluster" ]]; then
        print_info "  Regional Cluster: $regional_cluster"
    else
        print_info "  Regional Cluster: (direct to mothership)"
    fi
    print_info "  Status: Installed"
    
    # Check cluster connectivity
    if [[ -f "$KUBECONFIG_FILE" ]]; then
        export KUBECONFIG="$KUBECONFIG_FILE"
        
        if kubectl get nodes &>/dev/null; then
            print_info ""
            print_info "Cluster Nodes with Child Labels:"
            local label_key="${cluster_label%=*}"
            kubectl get nodes -l "$label_key" --show-labels 2>/dev/null || true
            
            print_info ""
            print_info "Child ClusterProfile:"
            kubectl get clusterprofile kof-child-profile -n "$namespace" 2>/dev/null || print_warning "ClusterProfile not found"
            
            print_info ""
            print_info "Child Configuration:"
            kubectl get configmap kof-child-config -n "$namespace" 2>/dev/null || print_warning "ConfigMap not found"
        else
            print_warning "Cannot connect to cluster to check runtime status"
        fi
    else
        print_warning "Kubeconfig not found, cannot check runtime status"
    fi
}

# Store original arguments for handle_standard_commands
ORIGINAL_ARGS=("$@")

# Parse standard arguments to get COMMAND
PARSED_ARGS=$(parse_standard_args "$@")
eval "$PARSED_ARGS"

# Get the command from positional arguments
COMMAND="${POSITIONAL_ARGS[0]:-}"

# Use consolidated command handling
handle_standard_commands "$0" "deploy uninstall status help" \
    "deploy" "deploy_kof_child" \
    "uninstall" "uninstall_kof_child" \
    "status" "show_kof_child_status" \
    "usage" "show_usage"