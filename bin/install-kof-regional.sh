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
source ./etc/azure-cluster-functions.sh  # Azure cluster deployment with retry logic

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
    
    # For KOF regional deployment, we only need kubectl access to management cluster
    # VPN connectivity is not required since we're creating a new k0rdent-managed cluster
    
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

# Core regional cluster creation function (used by retry logic)
create_regional_cluster_core() {
    local regional_cluster_name="$1"
    local wait_timeout="${2:-1800}"
    
    # Get configuration values
    local regional_domain=$(get_kof_config "regional.domain" "")
    local admin_email=$(get_kof_config "regional.admin_email" "")
    local location=$(get_kof_config "regional.location" "eastus")
    local template=$(get_kof_config "regional.template" "azure-standalone-cp-1-0-8")
    local credential=$(get_kof_config "regional.credential" "azure-cluster-credential")
    local cp_instance_size=$(get_kof_config "regional.cp_instance_size" "Standard_A4_v2")
    local worker_instance_size=$(get_kof_config "regional.worker_instance_size" "Standard_A4_v2")
    local root_volume_size=$(get_kof_config "regional.root_volume_size" "32")
    
    # Prepare cluster labels for KOF with Istio
    local cluster_labels="k0rdent.mirantis.com/istio-role=child"
    
    print_info "Creating cluster deployment for: $regional_cluster_name"
    print_info "Location: $location, Template: $template"
    
    # Use the enhanced create-child.sh script to deploy the regional cluster
    if ! bash bin/create-child.sh \
        --cluster-name "$regional_cluster_name" \
        --cloud azure \
        --location "$location" \
        --cp-instance-size "$cp_instance_size" \
        --worker-instance-size "$worker_instance_size" \
        --root-volume-size "$root_volume_size" \
        --namespace kcm-system \
        --template "$template" \
        --credential "$credential" \
        --cp-number 1 \
        --worker-number 3 \
        --cluster-identity-name azure-cluster-identity \
        --cluster-identity-namespace kcm-system \
        --cluster-labels "$cluster_labels"; then
        print_error "Failed to create ClusterDeployment"
        return 1
    fi
    
    print_info "Waiting for cluster '$regional_cluster_name' to become ready (timeout: ${wait_timeout}s)..."
    
    local wait_time=0
    local ready_status=""
    
    while [[ $wait_time -lt $wait_timeout ]]; do
        ready_status=$(kubectl get clusterdeployment "$regional_cluster_name" -n kcm-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        
        if [[ "$ready_status" == "True" ]]; then
            print_success "Regional cluster '$regional_cluster_name' is ready!"
            validate_azure_cluster_ready "$regional_cluster_name" "kcm-system"
            return 0
        elif [[ "$ready_status" == "False" ]]; then
            print_warning "Regional cluster '$regional_cluster_name' is not ready (status: False)"
        else
            print_info "Regional cluster '$regional_cluster_name' status: $ready_status"
        fi
        
        sleep 30
        wait_time=$((wait_time + 30))
        print_info "Waiting... ($wait_time/${wait_timeout}s)"
    done
    
    print_error "Regional cluster did not become ready within $wait_timeout seconds"
    print_info "Check cluster status with: kubectl describe clusterdeployment $regional_cluster_name -n kcm-system"
    return 1
}

deploy_kof_regional() {
    print_header "Deploying KOF Regional Cluster"
    
    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi
    
    # Get configuration values
    local kof_version=$(get_kof_config "version" "1.1.0")
    local location=$(get_kof_config "regional.location" "eastus")
    # Generate regional cluster name with location
    # Extract just the suffix part from K0RDENT_PREFIX (remove "k0rdent-" prefix)
    local prefix_suffix="${K0RDENT_PREFIX#k0rdent-}"
    local regional_cluster_name=$(get_kof_config "regional.cluster_name" "kof-regional-${prefix_suffix}-${location}")
    local regional_domain=$(get_kof_config "regional.domain" "")
    local admin_email=$(get_kof_config "regional.admin_email" "")
    local template=$(get_kof_config "regional.template" "azure-standalone-cp-1-0-8")
    local credential=$(get_kof_config "regional.credential" "azure-cluster-identity-cred")
    local cp_instance_size=$(get_kof_config "regional.cp_instance_size" "Standard_A4_v2")
    local worker_instance_size=$(get_kof_config "regional.worker_instance_size" "Standard_A4_v2")
    local root_volume_size=$(get_kof_config "regional.root_volume_size" "32")
    
    print_info "KOF Version: $kof_version"
    print_info "Regional Cluster: $regional_cluster_name"
    print_info "Regional Domain: $regional_domain"
    print_info "Admin Email: $admin_email"
    print_info "Location: $location"
    print_info "Template: $template"
    
    # Validate required KOF regional configuration
    if [[ -z "$regional_domain" ]]; then
        print_error "Regional domain is required for KOF regional cluster"
        print_info "Set 'kof.regional.domain' in your k0rdent.yaml"
        return 1
    fi
    
    if [[ -z "$admin_email" ]]; then
        print_error "Admin email is required for KOF regional cluster"
        print_info "Set 'kof.regional.admin_email' in your k0rdent.yaml"
        return 1
    fi
    
    # Update deployment state
    update_state "phase" "kof_regional_deployment"
    add_event "kof_regional_deployment_started" "Starting KOF regional cluster deployment v$kof_version"
    
    # Step 1: Check if Azure cluster deployment is configured
    print_header "Step 1: Checking Azure Cluster Deployment Prerequisites"
    if [[ "$(get_azure_state "azure_credentials_configured")" != "true" ]]; then
        print_error "Azure credentials not configured for cluster deployment"
        print_info "Run: bash bin/setup-azure-cluster-deployment.sh setup"
        return 1
    fi
    
    # Step 2: Create KOF regional cluster using k0rdent ClusterDeployment with retry logic
    print_header "Step 2: Creating KOF Regional Cluster with Retry Logic"
    print_info "Deploying regional cluster '$regional_cluster_name' using k0rdent..."
    
    # Use enhanced deployment with retry logic
    if ! deploy_cluster_with_retry "$regional_cluster_name" "create_regional_cluster_core" 3 "kcm-system" 1200; then
        print_error "Failed to create KOF regional cluster after retries"
        add_event "kof_regional_cluster_creation_failed" "Failed to create regional cluster $regional_cluster_name after retries"
        return 1
    fi
    
    # Step 3: Record KOF regional completion event
    print_header "Step 3: Recording KOF Regional Deployment Completion"
    add_cluster_event "$regional_cluster_name" "kof_regional_cluster_ready" "KOF regional cluster deployment completed successfully"
    add_cluster_event "$regional_cluster_name" "kof_regional_configured" "Domain: $regional_domain, Admin: $admin_email"
    
    # Update global state
    update_state "kof_regional_installed" "true"
    update_state "kof_regional_version" "$kof_version"
    update_state "kof_regional_cluster_name" "$regional_cluster_name"
    update_state "kof_regional_domain" "$regional_domain"
    add_event "kof_regional_deployment_completed" "KOF regional cluster '$regional_cluster_name' deployed successfully"
    
    print_success "KOF regional cluster deployment completed!"
    print_info "Regional cluster '$regional_cluster_name' is ready for KOF operations"
    print_info "Domain: $regional_domain"
    print_info "Monitor with: kubectl get clusterdeployment $regional_cluster_name -n kcm-system -w"
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