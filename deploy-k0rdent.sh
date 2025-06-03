#!/usr/bin/env bash

# deploy-k0rdent.sh
# Master deployment script for k0rdent Azure setup
# Orchestrates the entire deployment process

set -euo pipefail

# Load central configuration and common functions
source ./k0rdent-config.sh
source ./common-functions.sh

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check Azure CLI and WireGuard tools
    check_azure_cli
    check_wireguard_tools
    
    print_success "All prerequisites satisfied"
}

show_config() {
    print_header "Deployment Configuration"
    echo "Prefix: $K0RDENT_PREFIX"
    echo "Region: $LOCATION"
    echo "Resource Group: $RG"
    echo "VM Size: $VM_SIZE"
    echo "VM Count: ${#VM_HOSTS[@]}"
    echo "VMs: ${VM_HOSTS[*]}"
}

run_deployment() {
    print_header "Starting k0rdent Deployment"
    
    # Record start time
    DEPLOYMENT_START_TIME=$(date +%s)
    
    # Step 1: Generate WireGuard keys
    print_header "Step 1: Generating WireGuard Keys"
    if [[ -f "$WG_MANIFEST" ]]; then
        print_warning "WireGuard keys already exist. Skipping generation."
    else
        bash generate-wg-keys.sh
        print_success "WireGuard keys generated"
    fi
    
    # Step 2: Setup Azure network
    print_header "Step 2: Setting up Azure Network"
    if [[ -f "$AZURE_MANIFEST" ]]; then
        print_warning "Azure resources already exist. Skipping network setup."
    else
        bash setup-azure-network.sh
        print_success "Azure network setup complete"
    fi
    
    # Step 3: Generate cloud-init files
    print_header "Step 3: Generating Cloud-Init Files"
    bash generate-cloud-init.sh
    print_success "Cloud-init files generated"
    
    # Step 4: Create Azure VMs
    print_header "Step 4: Creating Azure VMs"
    bash create-azure-vms.sh
    print_success "VM creation complete"
    
    # Step 5: Generate laptop WireGuard configuration
    print_header "Step 5: Generating Laptop WireGuard Configuration"
    bash generate-laptop-wg-config.sh
    print_success "Laptop WireGuard configuration generated"
    
    # Step 6: Connect to WireGuard VPN
    print_header "Step 6: Connecting to WireGuard VPN"
    bash connect-laptop-wireguard.sh
    print_success "WireGuard VPN connected"
    
    # Step 7: Install k0s cluster
    print_header "Step 7: Installing k0s Cluster"
    bash install-k0s.sh deploy
    print_success "k0s cluster installation complete"
    
    # Step 8: Install k0rdent on cluster
    print_header "Step 8: Installing k0rdent on Cluster"
    bash install-k0rdent.sh deploy
    print_success "k0rdent installation complete"
    
    # Calculate and display total deployment time
    DEPLOYMENT_END_TIME=$(date +%s)
    DEPLOYMENT_DURATION=$((DEPLOYMENT_END_TIME - DEPLOYMENT_START_TIME))
    DEPLOYMENT_MINUTES=$((DEPLOYMENT_DURATION / 60))
    DEPLOYMENT_SECONDS=$((DEPLOYMENT_DURATION % 60))
    
    print_header "Deployment Time"
    echo "Total deployment time: ${DEPLOYMENT_MINUTES} minutes and ${DEPLOYMENT_SECONDS} seconds"
}

show_next_steps() {
    print_header "Deployment Complete!"
    echo "The k0rdent cluster has been successfully deployed and configured."
    echo ""
    echo "Cluster Access:"
    echo "  - WireGuard VPN is connected"
    echo "  - k0rdent cluster is installed and running"
    echo "  - kubectl configuration is available at: ./k0sctl-config/${K0RDENT_PREFIX}-kubeconfig"
    echo ""
    echo "Management Commands:"
    echo "  - Export kubeconfig: export KUBECONFIG=\$PWD/k0sctl-config/${K0RDENT_PREFIX}-kubeconfig"
    echo "  - Check cluster status: kubectl get nodes"
    echo "  - View k0rdent resources: kubectl get all -A"
    echo "  - Disconnect VPN: sudo wg-quick down k0rdent-laptop"
    echo "  - Reconnect VPN: sudo wg-quick up k0rdent-laptop"
    echo ""
    echo "To clean up all resources:"
    echo "  $0 reset"
}

run_full_reset() {
    print_header "Full k0rdent Deployment Reset"
    print_warning "This will remove ALL k0rdent resources in the following order:"
    echo "  1. Uninstall k0rdent from cluster"
    echo "  2. Remove k0s cluster"
    echo "  3. Disconnect WireGuard VPN"
    echo "  4. Laptop WireGuard configuration"
    echo "  5. Azure VMs and network resources"
    echo "  6. Cloud-init files"
    echo "  7. WireGuard keys"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Reset cancelled."
        return
    fi
    
    print_info "Resetting components..."
    
    # Step 1: Uninstall k0rdent from cluster (requires VPN connection)
    if [[ -d "./k0sctl-config" ]]; then
        print_header "Step 1: Uninstalling k0rdent from Cluster"
        bash install-k0rdent.sh uninstall || true
        print_success "k0rdent uninstalled"
    else
        print_info "Step 1: No k0rdent to uninstall"
    fi
    
    # Step 2: Reset k0s cluster (requires VPN connection)
    if [[ -d "./k0sctl-config" ]]; then
        print_header "Step 2: Removing k0s Cluster"
        bash install-k0s.sh uninstall
        bash install-k0s.sh reset
        print_success "k0s cluster removed"
    else
        print_info "Step 2: No k0s cluster to remove"
    fi
    
    # Step 3: Disconnect WireGuard VPN if connected
    if sudo wg show k0rdent-laptop &>/dev/null; then
        print_header "Step 3: Disconnecting WireGuard VPN"
        sudo wg-quick down k0rdent-laptop || true
        print_success "WireGuard VPN disconnected"
    else
        print_info "Step 3: WireGuard VPN not connected"
    fi
    
    # Step 4: Reset laptop WireGuard configuration
    if [[ -d "./laptop-wg-config" ]]; then
        print_header "Step 4: Removing Laptop WireGuard Configuration"
        bash generate-laptop-wg-config.sh reset
        print_success "Laptop WireGuard configuration removed"
    else
        print_info "Step 4: No laptop WireGuard configuration to remove"
    fi
    
    # Step 5: Reset Azure resources (VMs and network)
    if [[ -f "$AZURE_MANIFEST" ]] || check_resource_group_exists "$RG"; then
        print_header "Step 5: Removing Azure Resources"
        echo "yes" | bash setup-azure-network.sh reset
        print_success "Azure resources removed"
    else
        print_info "Step 5: No Azure resources to remove"
    fi
    
    # Step 6: Reset cloud-init files
    if [[ -d "$CLOUDINITS" ]]; then
        print_header "Step 6: Removing Cloud-Init Files"
        bash generate-cloud-init.sh reset
        print_success "Cloud-init files removed"
    else
        print_info "Step 6: No cloud-init files to remove"
    fi
    
    # Step 7: Reset WireGuard keys
    if [[ -d "$KEYDIR" ]]; then
        print_header "Step 7: Removing WireGuard Keys"
        bash generate-wg-keys.sh reset
        print_success "WireGuard keys removed"
    else
        print_info "Step 7: No WireGuard keys to remove"
    fi
    
    # Clean up project suffix file (only when using deploy-k0rdent.sh reset)
    if [[ -f "$SUFFIX_FILE" ]]; then
        print_info "Removing project suffix file for fresh deployment"
        rm -f "$SUFFIX_FILE"
    fi
    
    print_header "Reset Complete"
    print_success "All k0rdent resources have been removed"
    print_info "You can now run a fresh deployment with: $0 deploy"
}

# Main execution
case "${1:-deploy}" in
    "deploy")
        check_prerequisites
        show_config
        echo ""
        read -p "Continue with deployment? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            run_deployment
            show_next_steps
        else
            echo "Deployment cancelled."
        fi
        ;;
    "reset")
        run_full_reset
        ;;
    "config")
        show_config
        ;;
    "check")
        check_prerequisites
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  deploy    Run full deployment (default)"
        echo "  reset     Remove all k0rdent resources"
        echo "  config    Show configuration"
        echo "  check     Check prerequisites only"
        echo "  help      Show this help"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information."
        exit 1
        ;;
esac 