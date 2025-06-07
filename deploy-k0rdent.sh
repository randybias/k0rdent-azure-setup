#!/usr/bin/env bash

# deploy-k0rdent.sh
# Master deployment script for k0rdent Azure setup
# Orchestrates the entire deployment process

set -euo pipefail

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh

# Default values
SKIP_PROMPTS=false
NO_WAIT=false
DEPLOY_FLAGS=""

# Parse standard arguments
PARSED_ARGS=$(parse_standard_args "$@")
eval "$PARSED_ARGS"

# Build flags to pass to child scripts
if [[ "$SKIP_PROMPTS" == "true" ]]; then
    DEPLOY_FLAGS="$DEPLOY_FLAGS -y"
fi
if [[ "$NO_WAIT" == "true" ]]; then
    DEPLOY_FLAGS="$DEPLOY_FLAGS --no-wait"
fi


show_config() {
    print_header "k0rdent Deployment Configuration"
    
    echo
    echo "Project Settings:"
    echo "  Prefix: $K0RDENT_PREFIX"
    echo "  Region: $AZURE_LOCATION"
    echo "  Resource Group: $RG"
    
    echo
    echo "Cluster Topology:"
    echo "  Controllers: $K0S_CONTROLLER_COUNT nodes ($AZURE_CONTROLLER_VM_SIZE)"
    echo "  Workers: $K0S_WORKER_COUNT nodes ($AZURE_WORKER_VM_SIZE)"
    echo "  Total VMs: ${#VM_HOSTS[@]} nodes"
    
    echo
    echo "VM List:"
    for HOST in "${VM_HOSTS[@]}"; do
        if [[ "$HOST" =~ controller ]]; then
            echo "  $HOST ($AZURE_CONTROLLER_VM_SIZE)"
        else
            echo "  $HOST ($AZURE_WORKER_VM_SIZE)"
        fi
    done
    
    echo
    echo "Network Configuration:"
    echo "  VNet: $VNET_PREFIX"
    echo "  Subnet: $SUBNET_PREFIX"
    echo "  WireGuard Network: $WG_NETWORK"
    echo "  SSH User: $SSH_USERNAME"
    
    echo
    echo "Software Versions:"
    echo "  k0s: $K0S_VERSION"
    echo "  k0rdent: $K0RDENT_VERSION"
    echo "  Registry: $K0RDENT_OCI_REGISTRY"
    
    echo
    echo "Azure Settings:"
    echo "  VM Priority: $AZURE_VM_PRIORITY"
    echo "  Image: $AZURE_VM_IMAGE"
    
    if [[ -f "./k0sctl-config/${K0RDENT_PREFIX}-kubeconfig" ]]; then
        echo
        echo "Kubeconfig:"
        echo "  Location: ./k0sctl-config/${K0RDENT_PREFIX}-kubeconfig"
    fi
}

run_deployment() {
    print_header "Starting k0rdent Deployment"

    # Record start time
    DEPLOYMENT_START_TIME=$(date +%s)

    # Step 1: Prepare deployment (keys and cloud-init)
    print_header "Step 1: Preparing Deployment (Keys & Cloud-Init)"
    bash bin/prepare-deployment.sh deploy $DEPLOY_FLAGS

    # Step 2: Setup Azure network
    print_header "Step 2: Setting up Azure Network"
    if [[ -f "$AZURE_MANIFEST" ]]; then
        print_warning "Azure resources already exist. Skipping network setup."
    else
        bash bin/setup-azure-network.sh deploy $DEPLOY_FLAGS
    fi

    # Step 3: Create Azure VMs
    print_header "Step 3: Creating Azure VMs"
    bash bin/create-azure-vms.sh deploy $DEPLOY_FLAGS

    # Step 4: Setup WireGuard VPN (one-time setup)
    print_header "Step 4: Setting Up WireGuard VPN"
    bash bin/manage-vpn.sh setup $DEPLOY_FLAGS

    # Step 5: Connect to WireGuard VPN
    print_header "Step 5: Connecting to WireGuard VPN"
    bash bin/manage-vpn.sh connect $DEPLOY_FLAGS

    # Step 6: Install k0s cluster
    print_header "Step 6: Installing k0s Cluster"
    bash bin/install-k0s.sh deploy $DEPLOY_FLAGS

    # Step 7: Install k0rdent on cluster
    print_header "Step 7: Installing k0rdent on Cluster"
    bash bin/install-k0rdent.sh deploy $DEPLOY_FLAGS

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
    echo "  - Disconnect VPN: ./bin/manage-vpn.sh disconnect"
    echo "  - Reconnect VPN: ./bin/manage-vpn.sh connect"
    echo ""
    echo "To clean up all resources:"
    echo "  $0 reset"
}

run_full_reset() {
    print_header "Full k0rdent Deployment Reset"
    print_warning "This will remove ALL k0rdent resources in the following order:"
    echo "  1. Uninstall k0rdent from cluster"
    echo "  2. Remove k0s cluster"
    echo "  3. Disconnect and reset WireGuard VPN"
    echo "  4. Azure VMs and network resources"
    echo "  5. Deployment preparation files (keys & cloud-init)"
    echo "  6. Logs directory"
    echo ""

    if [[ "$SKIP_PROMPTS" == "false" ]]; then
        read -p "Are you sure you want to proceed? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            echo "Reset cancelled."
            return
        fi
    fi

    print_info "Resetting components..."

    # Step 1: Uninstall k0rdent from cluster (script will check VPN connectivity)
    if [[ -d "./k0sctl-config" ]]; then
        print_header "Step 1: Uninstalling k0rdent from Cluster"
        bash bin/install-k0rdent.sh uninstall $DEPLOY_FLAGS || true
    else
        print_info "Step 1: No k0rdent to uninstall"
    fi

    # Step 2: Reset k0s cluster (script will check VPN connectivity)
    if [[ -d "./k0sctl-config" ]]; then
        print_header "Step 2: Removing k0s Cluster"
        bash bin/install-k0s.sh uninstall $DEPLOY_FLAGS
        bash bin/install-k0s.sh reset $DEPLOY_FLAGS
    else
        print_info "Step 2: No k0s cluster to remove"
    fi

    # Step 3: Disconnect and reset WireGuard VPN
    if [[ -d "./laptop-wg-config" ]]; then
        print_header "Step 3: Disconnecting and Resetting WireGuard VPN"
        bash bin/manage-vpn.sh reset $DEPLOY_FLAGS
    else
        print_info "Step 3: No WireGuard VPN configuration to remove"
    fi

    # Step 4: Reset Azure resources (VMs and network)
    if [[ -f "$AZURE_MANIFEST" ]] || check_resource_group_exists "$RG"; then
        print_header "Step 4: Removing Azure Resources"
        bash bin/setup-azure-network.sh reset $DEPLOY_FLAGS
    else
        print_info "Step 4: No Azure resources to remove"
    fi

    # Step 5: Reset deployment preparation (keys and cloud-init)
    if [[ -d "$CLOUD_INIT_DIR" ]] || [[ -d "$WG_DIR" ]]; then
        print_header "Step 5: Removing Deployment Preparation Files"
        bash bin/prepare-deployment.sh reset $DEPLOY_FLAGS
    else
        print_info "Step 5: No deployment preparation files to remove"
    fi

    # Clean up project suffix file (only when using deploy-k0rdent.sh reset)
    if [[ -f "$SUFFIX_FILE" ]]; then
        print_info "Removing project suffix file for fresh deployment"
        rm -f "$SUFFIX_FILE"
    fi

    # Step 6: Clean up logs directory
    if [[ -d "./logs" ]]; then
        print_header "Step 6: Removing Logs Directory"
        rm -rf ./logs
        print_success "Logs directory removed"
    else
        print_info "Step 6: No logs directory to remove"
    fi

    print_header "Reset Complete"
    print_success "All k0rdent resources have been removed"
    print_info "You can now run a fresh deployment with: $0 deploy"
}

# Main execution
case "${POSITIONAL_ARGS[0]:-deploy}" in
    "deploy")
        show_config
        echo ""
        if [[ "$SKIP_PROMPTS" == "false" ]]; then
            read -p "Continue with deployment? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Deployment cancelled."
                exit 0
            fi
        fi
        run_deployment
        show_next_steps
        ;;
    "reset")
        run_full_reset
        ;;
    "config")
        show_config
        ;;
    "check")
        print_info "Prerequisites are checked in the preparation script:"
        bash bin/prepare-deployment.sh check
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command] [options]"
        echo ""
        echo "Commands:"
        echo "  deploy    Run full deployment (default)"
        echo "  reset     Remove all k0rdent resources"
        echo "  config    Show configuration"
        echo "  check     Check prerequisites only"
        echo "  help      Show this help"
        echo ""
        echo "Options:"
        echo "  -y, --yes         Skip confirmation prompts"
        echo "  --no-wait         Skip waiting for resources (where applicable)"
        echo "  -h, --help        Show this help message"
        ;;
    *)
        print_error "Unknown command: ${POSITIONAL_ARGS[0]}"
        echo "Use '$0 help' for usage information."
        exit 1
        ;;
esac
