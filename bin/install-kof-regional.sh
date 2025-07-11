#!/usr/bin/env bash

# Script: install-kof-regional.sh
# Purpose: Install KOF on regional cluster
# Usage: bash install-kof-regional.sh [deploy|uninstall|status|help]
# Prerequisites: KOF mothership installed, regional cluster accessible

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
        "  deploy     Install KOF on regional cluster
  uninstall  Remove KOF from regional cluster
  status     Show KOF regional installation status
  help       Show this help message" \
        "  -y, --yes        Skip confirmation prompts
  --no-wait        Skip waiting for resources" \
        "  $0 deploy        # Install KOF on regional cluster
  $0 status        # Check installation status
  $0 uninstall     # Remove KOF from regional cluster"
}

check_prerequisites() {
    print_info "Checking prerequisites for KOF regional deployment..."
    
    # Check if k0rdent is installed
    if [[ "$(get_state "k0rdent_installed")" != "true" ]]; then
        print_error "k0rdent must be installed before deploying KOF"
        print_info "Run: ./bin/install-k0rdent.sh deploy"
        return 1
    fi
    
    # Check if KOF mothership is installed
    if [[ "$(get_state "kof_mothership_installed")" != "true" ]]; then
        print_error "KOF mothership must be installed before deploying regional cluster"
        print_info "Run: ./bin/install-kof-mothership.sh deploy"
        return 1
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

deploy_kof_regional() {
    print_header "Deploying KOF Regional Cluster"
    
    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi
    
    # Get configuration values
    local kof_version=$(get_kof_config "version" "1.1.0")
    local kof_namespace=$(get_kof_config "regional.namespace" "kof")
    local cluster_label=$(get_kof_config "regional.cluster_label" "k0rdent.mirantis.com/istio-role=child")
    
    print_info "KOF Version: $kof_version"
    print_info "Namespace: $kof_namespace"
    print_info "Cluster Label: $cluster_label"
    
    # Update deployment state
    update_state "phase" "kof_regional_deployment"
    add_event "kof_regional_deployment_started" "Starting KOF regional deployment v$kof_version"
    
    # Step 1: Prepare KOF namespace
    print_header "Step 1: Preparing KOF Namespace"
    if ! prepare_kof_namespace "$kof_namespace"; then
        print_error "Failed to prepare KOF namespace"
        return 1
    fi
    
    # Step 2: Apply cluster labels
    print_header "Step 2: Labeling Cluster for Regional Role"
    print_info "Applying cluster labels for regional configuration..."
    
    # Parse the cluster label to get key and value
    local label_key="${cluster_label%=*}"
    local label_value="${cluster_label#*=}"
    
    # Apply the label to the cluster (using a node as proxy for cluster labeling)
    local cluster_name=$(kubectl config current-context)
    print_info "Labeling cluster '$cluster_name' with '$label_key=$label_value'"
    
    # In Istio deployment model, we label nodes to indicate the cluster role
    if kubectl label nodes --all "$label_key=$label_value" --overwrite; then
        print_success "Cluster labeled for regional role"
        add_event "kof_regional_cluster_labeled" "Cluster labeled with $cluster_label"
    else
        print_error "Failed to label cluster for regional role"
        add_event "kof_regional_labeling_failed" "Failed to apply cluster labels"
        return 1
    fi
    
    # Step 3: Create ClusterProfile for regional configuration
    print_header "Step 3: Creating Regional ClusterProfile"
    print_info "Creating ClusterProfile for regional cluster configuration..."
    
    # Create a ClusterProfile manifest for regional cluster
    local clusterprofile_yaml="/tmp/kof-regional-clusterprofile.yaml"
    cat > "$clusterprofile_yaml" << EOF
apiVersion: kcm.mirantis.com/v1alpha1
kind: ClusterProfile
metadata:
  name: kof-regional-profile
  namespace: $kof_namespace
spec:
  description: "KOF Regional Cluster Profile"
  config:
    # Regional-specific configuration can be added here
    role: "regional"
    istio:
      enabled: true
      role: "child"  # In Istio model, regional clusters are also "child" role
  # Regional-specific collectors from configuration
  collectors: $(get_kof_config "regional.collectors" "{}")
EOF
    
    if kubectl apply -f "$clusterprofile_yaml"; then
        print_success "Regional ClusterProfile created"
        add_event "kof_regional_clusterprofile_created" "ClusterProfile for regional cluster created"
        rm -f "$clusterprofile_yaml"
    else
        print_error "Failed to create regional ClusterProfile"
        add_event "kof_regional_clusterprofile_failed" "Failed to create ClusterProfile"
        rm -f "$clusterprofile_yaml"
        return 1
    fi
    
    # Step 4: Verify regional cluster connectivity
    print_header "Step 4: Verifying Regional Cluster Configuration"
    print_info "Verifying regional cluster is properly configured..."
    
    # Check that the cluster has the correct labels
    if kubectl get nodes -l "$label_key=$label_value" --no-headers | grep -q .; then
        print_success "Regional cluster nodes properly labeled"
    else
        print_warning "Regional cluster labels may not be properly applied"
    fi
    
    # Check that the ClusterProfile exists
    if kubectl get clusterprofile kof-regional-profile -n "$kof_namespace" &>/dev/null; then
        print_success "Regional ClusterProfile verified"
    else
        print_warning "Regional ClusterProfile verification failed"
    fi
    
    # Update state
    update_state "kof_regional_installed" "true"
    update_state "kof_regional_version" "$kof_version"
    update_state "kof_regional_namespace" "$kof_namespace"
    update_state "kof_regional_cluster_label" "$cluster_label"
    add_event "kof_regional_deployment_completed" "KOF regional deployment completed successfully"
    
    print_success "KOF regional cluster deployment completed!"
    print_info "Regional cluster is now configured for KOF operations"
    print_info "You can now proceed to install KOF on child clusters if needed"
}

uninstall_kof_regional() {
    print_header "Uninstalling KOF Regional Configuration"
    
    # Check VPN connectivity for cluster operations
    if ! check_vpn_connectivity; then
        print_error "VPN connectivity required for cluster operations"
        print_info "Connect to VPN first: ./bin/manage-vpn.sh connect"
        return 1
    fi
    
    # Check if KOF regional is installed
    if [[ "$(get_state "kof_regional_installed")" != "true" ]]; then
        print_info "KOF regional is not installed"
        return 0
    fi
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    # Get configuration
    local kof_namespace=$(get_kof_config "regional.namespace" "kof")
    local cluster_label=$(get_kof_config "regional.cluster_label" "k0rdent.mirantis.com/istio-role=child")
    
    # Confirm uninstall
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        print_warning "This will remove KOF regional configuration from the cluster"
        if ! confirm_action "Proceed with uninstall?"; then
            print_info "Uninstall cancelled"
            return 0
        fi
    fi
    
    # Step 1: Remove ClusterProfile
    print_info "Removing regional ClusterProfile..."
    if kubectl delete clusterprofile kof-regional-profile -n "$kof_namespace" --ignore-not-found; then
        print_success "Regional ClusterProfile removed"
        add_event "kof_regional_clusterprofile_removed" "ClusterProfile for regional cluster removed"
    else
        print_warning "Failed to remove regional ClusterProfile or it was not found"
    fi
    
    # Step 2: Remove cluster labels
    print_info "Removing regional cluster labels..."
    local label_key="${cluster_label%=*}"
    
    if kubectl label nodes --all "$label_key-" --ignore-not-found; then
        print_success "Regional cluster labels removed"
        add_event "kof_regional_labels_removed" "Cluster labels for regional role removed"
    else
        print_warning "Failed to remove regional cluster labels or they were not found"
    fi
    
    # Update state
    update_state "kof_regional_installed" "false"
    remove_state_key "kof_regional_version"
    remove_state_key "kof_regional_namespace"
    remove_state_key "kof_regional_cluster_label"
    add_event "kof_regional_uninstall_completed" "KOF regional uninstall completed"
    
    print_success "KOF regional uninstall completed!"
}

show_kof_regional_status() {
    print_header "KOF Regional Status"
    
    # Check if KOF is enabled
    if ! check_kof_enabled; then
        print_info "KOF is not enabled in configuration"
        return 0
    fi
    
    # Check installation state
    local installed=$(get_state "kof_regional_installed")
    if [[ "$installed" != "true" ]]; then
        print_info "KOF regional is not installed"
        return 0
    fi
    
    # Show configuration
    local version=$(get_state "kof_regional_version")
    local namespace=$(get_state "kof_regional_namespace")
    local cluster_label=$(get_state "kof_regional_cluster_label")
    
    print_info "KOF Regional Information:"
    print_info "  Version: $version"
    print_info "  Namespace: $namespace"
    print_info "  Cluster Label: $cluster_label"
    print_info "  Status: Installed"
    
    # Check cluster connectivity
    if [[ -f "$KUBECONFIG_FILE" ]]; then
        export KUBECONFIG="$KUBECONFIG_FILE"
        
        if kubectl get nodes &>/dev/null; then
            print_info ""
            print_info "Cluster Nodes with Regional Labels:"
            local label_key="${cluster_label%=*}"
            kubectl get nodes -l "$label_key" --show-labels 2>/dev/null || true
            
            print_info ""
            print_info "Regional ClusterProfile:"
            kubectl get clusterprofile kof-regional-profile -n "$namespace" 2>/dev/null || print_warning "ClusterProfile not found"
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
    "deploy" "deploy_kof_regional" \
    "uninstall" "uninstall_kof_regional" \
    "status" "show_kof_regional_status" \
    "usage" "show_usage"