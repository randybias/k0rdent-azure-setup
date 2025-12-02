#!/usr/bin/env bash

# Script: install-kof-mothership.sh
# Purpose: Install KOF mothership on k0rdent management cluster
# Usage: bash install-kof-mothership.sh [deploy|uninstall|status|help]
# Prerequisites: k0rdent installed, VPN connected, KOF enabled in configuration

set -euo pipefail

# Load ALL existing k0rdent infrastructure
source ./etc/k0rdent-config.sh      # Loads CONFIG_YAML automatically
source ./etc/common-functions.sh     # All common functionality
source ./etc/state-management.sh     # State tracking
source ./etc/kof-functions.sh        # ONLY KOF-specific additions

# Report configuration source (enhanced with state-based loading from OpenSpec change)
echo "==> Configuration source: ${K0RDENT_CONFIG_SOURCE:-default}"

# Output directory and file (reuse from k0rdent)
K0SCTL_DIR="./k0sctl-config"
KUBECONFIG_FILE="$K0SCTL_DIR/${K0RDENT_CLUSTERID}-kubeconfig"

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  deploy     Install KOF mothership on management cluster
  uninstall  Remove KOF mothership from cluster
  status     Show KOF mothership installation status
  help       Show this help message" \
        "  -y, --yes        Skip confirmation prompts
  --no-wait        Skip waiting for resources" \
        "  $0 deploy        # Install KOF mothership
  $0 status        # Check installation status
  $0 uninstall     # Remove KOF mothership"
}

check_prerequisites() {
    print_info "Checking prerequisites for KOF mothership..."
    
    # Check if k0rdent is installed
    if [[ "$(get_state "k0rdent_installed")" != "true" ]]; then
        print_error "k0rdent must be installed before deploying KOF"
        print_info "Run: ./bin/install-k0rdent.sh deploy"
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

deploy_kof_mothership() {
    print_header "Deploying KOF Mothership"
    
    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi

    if state_file_exists && phase_is_completed "install_kof_mothership"; then
        if [[ "$(get_state "kof_mothership_installed" 2>/dev/null || echo "false")" == "true" ]]; then
            print_success "KOF mothership already installed. Skipping deployment."
            return 0
        fi
        print_warning "KOF mothership phase recorded as complete but validation failed. Redeploying."
        phase_reset_from "install_kof_mothership"
    fi
    phase_mark_in_progress "install_kof_mothership"
    
    # Get configuration values
    local kof_version=$(get_kof_config "version" "1.1.0")
    local kof_namespace=$(get_kof_config "mothership.namespace" "kof")
    local storage_class=$(get_kof_config "mothership.storage_class" "default")
    
    print_info "KOF Version: $kof_version"
    print_info "Namespace: $kof_namespace"
    print_info "Storage Class: $storage_class"
    
    # Update deployment state
    update_state "phase" "kof_mothership_deployment"
    add_event "kof_mothership_deployment_started" "Starting KOF mothership deployment v$kof_version"
    
    # Step 1: Prepare KOF namespace first (needed by Istio installation)
    print_header "Step 1: Preparing KOF Namespace"
    if ! prepare_kof_namespace "$kof_namespace"; then
        print_error "Failed to prepare KOF namespace"
        return 1
    fi
    
    # Step 2: Install Istio if not present
    print_header "Step 2: Installing Istio for KOF"
    if check_istio_installed; then
        print_info "Istio already installed, skipping..."
    else
        if ! install_istio_for_kof; then
            print_error "Failed to install Istio"
            add_event "kof_istio_installation_failed" "Failed to install Istio for KOF"
            return 1
        fi
        add_event "kof_istio_installed" "Istio installed successfully for KOF"
    fi
    
    # Step 3: Install KOF operators
    print_header "Step 3: Installing KOF Operators"
    print_info "Installing kof-operators chart..."
    
    if helm upgrade -i --reset-values --wait \
        -n "$kof_namespace" kof-operators \
        oci://ghcr.io/k0rdent/kof/charts/kof-operators \
        --version "$kof_version"; then
        print_success "KOF operators installed successfully"
        add_event "kof_operators_installed" "KOF operators v$kof_version installed"
    else
        print_error "Failed to install KOF operators"
        add_event "kof_operators_installation_failed" "Failed to install KOF operators"
        return 1
    fi

    # Step 4: Install KOF mothership
    print_header "Step 4: Installing KOF Mothership"
    print_info "Installing kof-mothership chart..."
    
    # Prepare values for mothership installation
    local values_args=""
    if [[ "$storage_class" != "default" ]]; then
        values_args="--set storageClass=$storage_class"
    fi
    
    if helm upgrade -i --reset-values --wait \
        -n "$kof_namespace" kof-mothership \
        oci://ghcr.io/k0rdent/kof/charts/kof-mothership \
        --version "$kof_version" $values_args; then
        print_success "KOF mothership installed successfully"
        add_event "kof_mothership_installed" "KOF mothership v$kof_version installed"
    else
        print_error "Failed to install KOF mothership"
        add_event "kof_mothership_installation_failed" "Failed to install KOF mothership"
        return 1
    fi
    
    # Step 5: Verify installation
    print_header "Step 5: Verifying KOF Mothership Installation"
    print_info "Waiting for KOF components to be ready..."
    
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kof-mothership \
        -n "$kof_namespace" --timeout=300s; then
        print_success "KOF mothership pods are ready"
    else
        print_warning "Some KOF mothership pods may not be ready yet"
    fi
    
    # Update state
    update_state "kof_mothership_installed" "true"
    update_state "kof_mothership_version" "$kof_version"
    update_state "kof_mothership_namespace" "$kof_namespace"
    add_event "kof_mothership_deployment_completed" "KOF mothership deployment completed successfully"
    
    print_success "KOF mothership deployment completed!"
    print_info "You can now proceed to install KOF on regional clusters"
    phase_mark_completed "install_kof_mothership"
}

uninstall_kof_mothership() {
    print_header "Uninstalling KOF Mothership"
    
    # Check VPN connectivity for cluster operations
    if ! check_vpn_connectivity; then
        print_error "VPN connectivity required for cluster operations"
        print_info "Connect to VPN first: ./bin/manage-vpn.sh connect"
        return 1
    fi
    
    # Check if KOF mothership is installed
    if [[ "$(get_state "kof_mothership_installed")" != "true" ]]; then
        print_info "KOF mothership is not installed"
        return 0
    fi
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    # Get configuration
    local kof_namespace=$(get_kof_config "mothership.namespace" "kof")
    
    # Confirm uninstall
    if [[ "${SKIP_CONFIRMATION:-false}" != "true" ]]; then
        print_warning "This will remove KOF mothership from the cluster"
        if ! confirm_action "Proceed with uninstall?"; then
            print_info "Uninstall cancelled"
            return 0
        fi
    fi
    
    # Step 1: Uninstall KOF mothership
    print_info "Uninstalling kof-mothership..."
    if helm uninstall kof-mothership -n "$kof_namespace" --wait; then
        print_success "KOF mothership uninstalled"
        add_event "kof_mothership_uninstalled" "KOF mothership removed from cluster"
    else
        print_warning "Failed to uninstall KOF mothership or it was not installed"
    fi
    
    # Step 2: Uninstall KOF operators
    print_info "Uninstalling kof-operators..."
    if helm uninstall kof-operators -n "$kof_namespace" --wait; then
        print_success "KOF operators uninstalled"
        add_event "kof_operators_uninstalled" "KOF operators removed from cluster"
    else
        print_warning "Failed to uninstall KOF operators or it was not installed"
    fi
    
    # Step 3: Optionally uninstall Istio
    if check_istio_installed; then
        if [[ "${SKIP_CONFIRMATION:-false}" != "true" ]]; then
            print_warning "Istio is currently installed"
            if confirm_action "Also uninstall Istio?"; then
                print_info "Uninstalling Istio..."
                local istio_namespace=$(get_kof_config "istio.namespace" "istio-system")
                if helm uninstall kof-istio -n "$istio_namespace" --wait; then
                    print_success "Istio uninstalled"
                    add_event "kof_istio_uninstalled" "Istio removed from cluster"
                else
                    print_warning "Failed to uninstall Istio"
                fi
            fi
        fi
    fi
    
    # Step 4: Clean up namespace
    print_info "Cleaning up KOF namespace..."
    if kubectl delete namespace "$kof_namespace" --timeout=60s; then
        print_success "KOF namespace removed"
    else
        print_warning "Failed to remove KOF namespace or it doesn't exist"
    fi
    
    # Update state
    update_state "kof_mothership_installed" "false"
    remove_state_key "kof_mothership_version"
    remove_state_key "kof_mothership_namespace"
    add_event "kof_mothership_uninstall_completed" "KOF mothership uninstall completed"
    phase_reset_from "install_kof_mothership"
    
    print_success "KOF mothership uninstall completed!"
}

show_kof_mothership_status() {
    print_header "KOF Mothership Status"
    
    # Check if KOF is enabled
    if ! check_kof_enabled; then
        print_info "KOF is not enabled in configuration"
        return 0
    fi
    
    # Check installation state
    local installed=$(get_state "kof_mothership_installed")
    if [[ "$installed" != "true" ]]; then
        print_info "KOF mothership is not installed"
        return 0
    fi
    
    # Show configuration
    local version=$(get_state "kof_mothership_version")
    local namespace=$(get_state "kof_mothership_namespace")
    
    print_info "KOF Mothership Information:"
    print_info "  Version: $version"
    print_info "  Namespace: $namespace"
    print_info "  Status: Installed"
    
    # Check cluster connectivity
    if [[ -f "$KUBECONFIG_FILE" ]]; then
        export KUBECONFIG="$KUBECONFIG_FILE"
        
        if kubectl get nodes &>/dev/null; then
            print_info ""
            print_info "Helm Releases:"
            helm list -n "$namespace" 2>/dev/null || true
            
            print_info ""
            print_info "KOF Pods:"
            kubectl get pods -n "$namespace" 2>/dev/null || true
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
    "deploy" "deploy_kof_mothership" \
    "uninstall" "uninstall_kof_mothership" \
    "status" "show_kof_mothership_status" \
    "usage" "show_usage"
