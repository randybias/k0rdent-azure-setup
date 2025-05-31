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
    print_success "VM creation initiated"
}

show_next_steps() {
    print_header "Next Steps"
    echo "1. Generate laptop WireGuard configuration:"
    echo "   ./generate-laptop-wg-config.sh"
    echo ""
    echo "2. Connect to the WireGuard VPN:"
    echo "   ./connect-laptop-wireguard.sh"
    echo ""
    echo "3. Install and configure k0rdent on the VMs"
    echo ""
    echo "To clean up all resources:"
    echo "  $0 reset"
}

run_full_reset() {
    print_header "Full k0rdent Deployment Reset"
    print_warning "This will remove ALL k0rdent resources in the following order:"
    echo "  1. Azure VMs and network resources"
    echo "  2. Cloud-init files"
    echo "  3. WireGuard keys"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Reset cancelled."
        return
    fi
    
    print_info "Resetting components..."
    
    # Step 1: Reset Azure resources (VMs and network)
    if [[ -f "$AZURE_MANIFEST" ]] || check_resource_group_exists "$RG"; then
        print_header "Step 1: Removing Azure Resources"
        echo "yes" | bash setup-azure-network.sh reset
        print_success "Azure resources removed"
    else
        print_info "Step 1: No Azure resources to remove"
    fi
    
    # Step 2: Reset cloud-init files
    if [[ -d "$CLOUDINITS" ]]; then
        print_header "Step 2: Removing Cloud-Init Files"
        bash generate-cloud-init.sh reset
        print_success "Cloud-init files removed"
    else
        print_info "Step 2: No cloud-init files to remove"
    fi
    
    # Step 3: Reset WireGuard keys
    if [[ -d "$KEYDIR" ]]; then
        print_header "Step 3: Removing WireGuard Keys"
        bash generate-wg-keys.sh reset
        print_success "WireGuard keys removed"
    else
        print_info "Step 3: No WireGuard keys to remove"
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