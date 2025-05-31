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
    echo "1. Wait for VMs to complete cloud-init (5-10 minutes)"
    echo "2. Retrieve VM public IPs for WireGuard configuration"
    echo "3. Configure your laptop WireGuard client"
    echo "4. Install and configure k0rdent on the VMs"
    echo ""
    echo "To clean up all resources:"
    echo "  bash setup-azure-network.sh reset"
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
        echo "  config    Show configuration"
        echo "  check     Check prerequisites only"
        echo "  help      Show this help"
        echo ""
        echo "To clean up:"
        echo "  bash setup-azure-network.sh reset"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information."
        exit 1
        ;;
esac 