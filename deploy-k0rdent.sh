#!/usr/bin/env bash

# deploy-k0rdent.sh
# Master deployment script for k0rdent Azure setup
# Orchestrates the entire deployment process

set -euo pipefail

# Check if configuration exists before loading
CONFIG_YAML="./config/k0rdent.yaml"
CONFIG_DEFAULT_YAML="./config/k0rdent-default.yaml"

if [[ ! -f "$CONFIG_YAML" ]] && [[ ! -f "$CONFIG_DEFAULT_YAML" ]]; then
    echo "ERROR: No configuration found!"
    echo
    echo "Please create a configuration first using one of these commands:"
    echo
    echo "  # Use minimal configuration (default):"
    echo "  ./bin/configure.sh init"
    echo
    echo "  # Use a specific template:"
    echo "  ./bin/configure.sh init --template development"
    echo "  ./bin/configure.sh init --template production"
    echo
    echo "  # List available templates:"
    echo "  ./bin/configure.sh templates"
    echo
    exit 1
fi

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh
source ./etc/state-management.sh

# Function to stop desktop notifier
stop_desktop_notifier() {
    # Always try to stop notifier if the script exists, regardless of flag
    # This ensures cleanup even if notifier was started manually
    if [[ -f "./bin/utils/desktop-notifier.sh" ]]; then
        # Check for any notifier PID files
        if ls state/notifier-*.pid >/dev/null 2>&1; then
            print_info "Stopping desktop notifier(s)..."
            # Stop deployment notifier specifically
            if [[ -f "state/notifier-deployment.pid" ]]; then
                ./bin/utils/desktop-notifier.sh --stop || true
            fi
        fi
    fi
}

# Default values
SKIP_PROMPTS=false
NO_WAIT=false
WITH_AZURE_CHILDREN=false
WITH_KOF=false
FAST_RESET=false
WITH_DESKTOP_NOTIFICATIONS=false
DEPLOY_FLAGS=""

# Custom argument parsing to handle our specific flags
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            SKIP_PROMPTS=true
            shift
            ;;
        --no-wait)
            NO_WAIT=true
            shift
            ;;
        --with-azure-children)
            WITH_AZURE_CHILDREN=true
            shift
            ;;
        --with-kof)
            WITH_KOF=true
            shift
            ;;
        --fast)
            FAST_RESET=true
            shift
            ;;
        --with-desktop-notifications)
            WITH_DESKTOP_NOTIFICATIONS=true
            shift
            ;;
        -h|--help)
            SHOW_HELP=true
            shift
            ;;
        -*)
            print_error "Unknown option: $1"
            print_info "Use -h or --help for usage information"
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

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
    echo "  Cluster ID: $K0RDENT_CLUSTERID"
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
    
    echo
    echo "Deployment Options:"
    echo "  Azure Child Clusters: $(if [[ "$WITH_AZURE_CHILDREN" == "true" ]]; then echo "ENABLED"; else echo "Disabled"; fi)"
    echo "  KOF Installation: $(if [[ "$WITH_KOF" == "true" ]]; then echo "ENABLED"; else echo "Disabled"; fi)"
    
    if [[ -f "./k0sctl-config/${K0RDENT_CLUSTERID}-kubeconfig" ]]; then
        echo
        echo "Kubeconfig:"
        echo "  Location: ./k0sctl-config/${K0RDENT_CLUSTERID}-kubeconfig"
    fi
}

run_deployment() {
    print_header "Starting k0rdent Deployment"
    
    # Set up cleanup trap
    trap 'stop_desktop_notifier' EXIT
    
    # Check prerequisites first
    print_info "Checking prerequisites..."
    if ! bash bin/check-prerequisites.sh; then
        print_error "Prerequisites check failed. Please install missing tools and try again."
        exit 1
    fi
    echo

    # Record start time
    DEPLOYMENT_START_TIME=$(date +%s)
    DEPLOYMENT_START_DATE=$(date "+%Y-%m-%d %H:%M:%S %Z")
    
    print_info "Deployment started at: $DEPLOYMENT_START_DATE"
    echo

    # Step 1: Prepare deployment (keys and cloud-init)
    print_header "Step 1: Preparing Deployment (Keys & Cloud-Init)"
    bash bin/prepare-deployment.sh deploy $DEPLOY_FLAGS

    # Record deployment flags in state (after state file is created)
    update_state "deployment_flags.azure_children" "$WITH_AZURE_CHILDREN"
    update_state "deployment_flags.kof" "$WITH_KOF"
    add_event "deployment_started" "Deployment started with flags: azure-children=$WITH_AZURE_CHILDREN, kof=$WITH_KOF"
    
    # Start desktop notifier if requested
    if [[ "$WITH_DESKTOP_NOTIFICATIONS" == "true" ]]; then
        print_info "Starting desktop notifier..."
        if [[ -f "./bin/utils/desktop-notifier.sh" ]]; then
            # Ensure state directory exists
            mkdir -p state
            ./bin/utils/desktop-notifier.sh --daemon
            # Check if it started successfully
            if [[ -f "state/notifier-deployment.pid" ]]; then
                local notifier_pid=$(cat state/notifier-deployment.pid)
                print_success "Desktop notifier started (PID: $notifier_pid)"
            else
                print_warning "Desktop notifier failed to start"
            fi
        else
            print_warning "Desktop notifier not found, continuing without notifications"
        fi
    fi

    # Step 2: Setup Azure network
    print_header "Step 2: Setting up Azure Network"
    local azure_rg_status=$(get_state "azure_rg_status" 2>/dev/null || echo "not_created")
    local azure_network_status=$(get_state "azure_network_status" 2>/dev/null || echo "not_created")
    local azure_ssh_key_status=$(get_state "azure_ssh_key_status" 2>/dev/null || echo "not_created")
    
    if [[ "$azure_rg_status" == "created" && "$azure_network_status" == "created" && "$azure_ssh_key_status" == "created" ]]; then
        print_warning "Azure network setup already complete. Skipping network setup."
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

    # Step 8: Setup Azure child cluster deployment (if requested)
    if [[ "$WITH_AZURE_CHILDREN" == "true" ]]; then
        print_header "Step 8: Setting up Azure Child Cluster Deployment"
        bash bin/setup-azure-cluster-deployment.sh setup $DEPLOY_FLAGS
    fi

    # Step 9: Install Azure CSI driver (if KOF requested)
    if [[ "$WITH_KOF" == "true" ]]; then
        print_header "Step 9: Installing Azure Disk CSI Driver for KOF"
        bash bin/install-k0s-azure-csi.sh deploy $DEPLOY_FLAGS
    fi

    # Step 10: Install KOF mothership (if requested)
    if [[ "$WITH_KOF" == "true" ]]; then
        print_header "Step 10: Installing KOF Mothership"
        bash bin/install-kof-mothership.sh deploy $DEPLOY_FLAGS
    fi

    # Step 11: Deploy KOF regional cluster (if requested)
    if [[ "$WITH_KOF" == "true" ]]; then
        print_header "Step 11: Deploying KOF Regional Cluster"
        bash bin/install-kof-regional.sh deploy $DEPLOY_FLAGS
    fi

    # Calculate and display total deployment time
    DEPLOYMENT_END_TIME=$(date +%s)
    DEPLOYMENT_END_DATE=$(date "+%Y-%m-%d %H:%M:%S %Z")
    DEPLOYMENT_DURATION=$((DEPLOYMENT_END_TIME - DEPLOYMENT_START_TIME))
    
    # Calculate hours, minutes, and seconds
    DEPLOYMENT_HOURS=$((DEPLOYMENT_DURATION / 3600))
    DEPLOYMENT_MINUTES=$(((DEPLOYMENT_DURATION % 3600) / 60))
    DEPLOYMENT_SECONDS=$((DEPLOYMENT_DURATION % 60))

    print_header "Deployment Completed"
    echo "End Time: $DEPLOYMENT_END_DATE"
    echo ""
    echo -n "Total Duration: "
    if [[ $DEPLOYMENT_HOURS -gt 0 ]]; then
        echo "${DEPLOYMENT_HOURS} hours ${DEPLOYMENT_MINUTES} minutes ${DEPLOYMENT_SECONDS} seconds"
    elif [[ $DEPLOYMENT_MINUTES -gt 0 ]]; then
        echo "${DEPLOYMENT_MINUTES} minutes ${DEPLOYMENT_SECONDS} seconds"
    else
        echo "${DEPLOYMENT_SECONDS} seconds"
    fi
    
    # Update state with timing information
    update_state "deployment_start_time" "$DEPLOYMENT_START_DATE"
    update_state "deployment_end_time" "$DEPLOYMENT_END_DATE"
    update_state "deployment_duration_seconds" "$DEPLOYMENT_DURATION"
    
    # Send deployment completed event
    add_event "deployment_completed" "k0rdent deployment completed successfully in ${DEPLOYMENT_DURATION} seconds"
}

show_next_steps() {
    print_header "Deployment Complete!"
    echo "The k0rdent cluster has been successfully deployed and configured."
    echo ""
    echo "Cluster Access:"
    echo "  - WireGuard VPN is connected"
    echo "  - k0rdent cluster is installed and running"
    echo "  - kubectl configuration is available at: ./k0sctl-config/${K0RDENT_CLUSTERID}-kubeconfig"
    
    if [[ "$WITH_AZURE_CHILDREN" == "true" ]]; then
        echo ""
        echo "Azure Child Clusters:"
        echo "  - Azure credentials configured for child cluster deployment"
        echo "  - Deploy child clusters: ./bin/create-child.sh --help"
    fi
    
    if [[ "$WITH_KOF" == "true" ]]; then
        echo ""
        echo "KOF Components:"
        echo "  - KOF mothership installed on management cluster"
        echo "  - KOF regional cluster deployed in $(yq eval '.kof.regional.location' ./config/k0rdent.yaml)"
        echo "  - View KOF status: kubectl get pods -n kof"
    fi
    
    echo ""
    echo "Management Commands:"
    echo "  - Export kubeconfig: export KUBECONFIG=\$PWD/k0sctl-config/${K0RDENT_CLUSTERID}-kubeconfig"
    echo "  - Check cluster status: kubectl get nodes"
    echo "  - View k0rdent resources: kubectl get all -A"
    echo "  - Disconnect VPN: ./bin/manage-vpn.sh disconnect"
    echo "  - Reconnect VPN: ./bin/manage-vpn.sh connect"
    echo ""
    echo "To clean up all resources:"
    echo "  $0 reset"
}

run_fast_reset() {
    # Stop desktop notifier first
    stop_desktop_notifier
    
    print_header "Fast k0rdent Deployment Reset (Azure-specific)"
    print_warning "FAST RESET MODE: This will disconnect VPN and delete the entire Azure resource group"
    print_warning "Resource group to be deleted: $RG"
    print_info "Note: Fast reset is Azure-specific and leverages resource group deletion"
    echo ""
    
    if [[ "$SKIP_PROMPTS" == "false" ]]; then
        read -p "Are you sure you want to proceed with fast reset? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            echo "Fast reset cancelled."
            return
        fi
    fi
    
    print_info "Starting fast reset..."
    
    # Step 1: Disconnect WireGuard VPN if connected
    if [[ -f "$WG_CONFIG_FILE" ]]; then
        print_header "Step 1: Disconnecting WireGuard VPN"
        bash bin/manage-vpn.sh reset $DEPLOY_FLAGS || true
    else
        print_info "Step 1: No WireGuard VPN to disconnect"
    fi
    
    # Step 2: Delete Azure resource group (if it exists)
    if check_resource_group_exists "$RG"; then
        print_header "Step 2: Deleting Azure Resource Group"
        print_info "Deleting resource group: $RG"
        az group delete --name "$RG" --yes --no-wait
        print_success "Resource group deletion initiated (running in background)"
    else
        print_info "Step 2: No Azure resource group to delete"
    fi
    
    # Step 3: Clean up local files
    print_header "Step 3: Cleaning Up Local Files"
    
    # Archive state files before removal
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]] || [[ -f "$DEPLOYMENT_EVENTS_FILE" ]]; then
        print_info "Archiving state files to old_deployments..."
        archive_existing_state "fast-reset"
    fi
    
    # Remove WireGuard configuration
    if [[ -d "$WG_DIR" ]]; then
        rm -rf "$WG_DIR"
        print_info "Removed WireGuard directory"
    fi
    
    # Remove cloud-init files
    if [[ -d "$CLOUD_INIT_DIR" ]]; then
        rm -rf "$CLOUD_INIT_DIR"
        print_info "Removed cloud-init directory"
    fi
    
    # Remove k0sctl configuration
    if [[ -d "./k0sctl-config" ]]; then
        rm -rf ./k0sctl-config
        print_info "Removed k0sctl-config directory"
    fi
    
    # Remove project clusterid file
    if [[ -f "$CLUSTERID_FILE" ]]; then
        rm -f "$CLUSTERID_FILE"
        print_info "Removed project clusterid file"
    fi
    
    # Remove state files
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]] || [[ -f "$DEPLOYMENT_EVENTS_FILE" ]]; then
        rm -f "$DEPLOYMENT_STATE_FILE" "$DEPLOYMENT_EVENTS_FILE"
        rm -f "$KOF_STATE_FILE" "$KOF_EVENTS_FILE"
        rm -f "$AZURE_STATE_FILE" "$AZURE_EVENTS_FILE"
        print_info "Removed state files"
    fi
    
    # Remove logs directory
    if [[ -d "./logs" ]]; then
        rm -rf ./logs
        print_info "Removed logs directory"
    fi
    
    # Clean up SSH keys directory
    if [[ -d "./ssh-keys" ]]; then
        rm -rf ./ssh-keys
        print_info "Removed SSH keys directory"
    fi
    
    print_header "Fast Reset Complete"
    print_success "All k0rdent resources have been removed"
    print_info "Azure resource group deletion is running in background"
    print_info "You can now run a fresh deployment with: $0 deploy"
}

run_full_reset() {
    # Stop desktop notifier first
    stop_desktop_notifier
    
    # Check if fast reset was requested
    if [[ "$FAST_RESET" == "true" ]]; then
        run_fast_reset
        return
    fi
    
    print_header "Full k0rdent Deployment Reset"
    
    # Define kubeconfig location
    local KUBECONFIG_FILE="./k0sctl-config/${K0RDENT_CLUSTERID}-kubeconfig"
    
    # Check if KOF was deployed and handle regional clusters first
    local kof_deployed=$(get_state "deployment_flags.kof" 2>/dev/null || echo "false")
    local kof_mothership_installed=$(get_state "kof_mothership_installed" 2>/dev/null || echo "false")
    local kof_regional_installed=$(get_state "kof_regional_installed" 2>/dev/null || echo "false")
    
    if [[ "$kof_deployed" == "true" ]] || [[ "$kof_mothership_installed" == "true" ]] || [[ "$kof_regional_installed" == "true" ]]; then
        print_warning "KOF deployment detected. Will remove KOF regional clusters first."
    fi
    
    print_warning "This will remove ALL k0rdent resources in the following order:"
    if [[ "$kof_deployed" == "true" ]] || [[ "$kof_mothership_installed" == "true" ]] || [[ "$kof_regional_installed" == "true" ]]; then
        echo "  1. Remove KOF regional clusters"
        echo "  2. Uninstall k0rdent from cluster"
        echo "  3. Remove k0s cluster"
        echo "  4. Disconnect and reset WireGuard VPN"
        echo "  5. Azure VMs and network resources"
        echo "  6. Deployment preparation files (keys & cloud-init)"
        echo "  7. Logs directory"
    else
        echo "  1. Uninstall k0rdent from cluster"
        echo "  2. Remove k0s cluster"
        echo "  3. Disconnect and reset WireGuard VPN"
        echo "  4. Azure VMs and network resources"
        echo "  5. Deployment preparation files (keys & cloud-init)"
        echo "  6. Logs directory"
    fi
    echo ""

    if [[ "$SKIP_PROMPTS" == "false" ]]; then
        read -p "Are you sure you want to proceed? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            echo "Reset cancelled."
            return
        fi
    fi

    print_info "Resetting components..."

    # Check VPN connectivity for k0s and k0rdent operations
    local vpn_connected=false
    if check_vpn_connectivity &>/dev/null; then
        vpn_connected=true
    fi
    
    # Step 0: Remove KOF regional clusters if KOF was deployed
    if [[ "$kof_deployed" == "true" ]] || [[ "$kof_mothership_installed" == "true" ]] || [[ "$kof_regional_installed" == "true" ]]; then
        if [[ "$vpn_connected" == "true" ]] && [[ -f "$KUBECONFIG_FILE" ]]; then
            print_header "Step 1: Removing KOF Regional Clusters"
            export KUBECONFIG="$KUBECONFIG_FILE"
            
            # Find all KOF regional clusters
            local kof_clusters=$(kubectl get clusterdeployments -n kcm-system \
                -l "k0rdent.mirantis.com/kof-cluster-role=regional" \
                --no-headers -o name 2>/dev/null || echo "")
            
            if [[ -n "$kof_clusters" ]]; then
                while IFS= read -r cluster; do
                    local cluster_name=$(basename "$cluster")
                    print_info "Deleting KOF regional cluster: $cluster_name"
                    kubectl delete clusterdeployment "$cluster_name" -n kcm-system --wait=false 2>/dev/null || true
                done <<< "$kof_clusters"
                
                print_info "Waiting for KOF regional cluster deletions to start..."
                sleep 10
            else
                print_info "No KOF regional clusters found"
            fi
        else
            print_warning "Cannot remove KOF regional clusters - VPN not connected or kubeconfig missing"
        fi
    fi

    # Step 2: Uninstall k0rdent from cluster
    if [[ -d "./k0sctl-config" ]]; then
        print_header "Step 2: Uninstalling k0rdent from Cluster"
        if [[ "$vpn_connected" == "false" ]]; then
            print_warning "VPN is not connected. k0rdent uninstall requires VPN connectivity."
            if [[ "$SKIP_PROMPTS" == "false" ]]; then
                read -p "Continue without uninstalling k0rdent? (y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "Reset cancelled."
                    return
                fi
                print_info "Skipping k0rdent uninstall due to no VPN connectivity"
            else
                print_info "Skipping k0rdent uninstall due to no VPN connectivity (-y flag used)"
            fi
        else
            bash bin/install-k0rdent.sh uninstall $DEPLOY_FLAGS || true
        fi
    else
        print_info "Step 2: No k0rdent to uninstall"
    fi

    # Step 3: Reset k0s cluster
    if [[ -d "./k0sctl-config" ]]; then
        print_header "Step 3: Removing k0s Cluster"
        if [[ "$vpn_connected" == "false" ]]; then
            print_warning "VPN is not connected. k0s uninstall requires VPN connectivity."
            if [[ "$SKIP_PROMPTS" == "false" ]]; then
                read -p "Continue without uninstalling k0s? (y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "Reset cancelled."
                    return
                fi
                print_info "Skipping k0s uninstall due to no VPN connectivity"
            else
                print_info "Skipping k0s uninstall due to no VPN connectivity (-y flag used)"
            fi
        else
            bash bin/install-k0s.sh uninstall $DEPLOY_FLAGS
        fi
        # Always attempt to reset configuration files even without VPN
        bash bin/install-k0s.sh reset $DEPLOY_FLAGS
    else
        print_info "Step 3: No k0s cluster to remove"
    fi

    # Step 4: Disconnect and reset WireGuard VPN
    if [[ -f "$WG_CONFIG_FILE" ]]; then
        print_header "Step 4: Disconnecting and Resetting WireGuard VPN"
        bash bin/manage-vpn.sh reset $DEPLOY_FLAGS
    else
        print_info "Step 4: No WireGuard VPN configuration to remove"
    fi

    # Step 5: Reset Azure resources (VMs and network)
    if state_file_exists || check_resource_group_exists "$RG"; then
        print_header "Step 5: Removing Azure Resources"
        bash bin/setup-azure-network.sh reset $DEPLOY_FLAGS
    else
        print_info "Step 5: No Azure resources to remove"
    fi

    # Step 6: Reset deployment preparation (keys and cloud-init)
    if [[ -d "$CLOUD_INIT_DIR" ]] || [[ -d "$WG_DIR" ]]; then
        print_header "Step 6: Removing Deployment Preparation Files"
        bash bin/prepare-deployment.sh reset $DEPLOY_FLAGS
    else
        print_info "Step 6: No deployment preparation files to remove"
    fi

    # Clean up project clusterid file (only when using deploy-k0rdent.sh reset)
    if [[ -f "$CLUSTERID_FILE" ]]; then
        print_info "Removing project clusterid file for fresh deployment"
        rm -f "$CLUSTERID_FILE"
    fi

    # Step 7: Clean up deployment state files
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]] || [[ -f "$DEPLOYMENT_EVENTS_FILE" ]]; then
        print_header "Step 7: Removing Deployment State Files"
        # Archive state files before removal
        print_info "Archiving state files to old_deployments..."
        archive_existing_state "full-reset"
        
        if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
            rm -f "$DEPLOYMENT_STATE_FILE"
            print_info "Removed deployment-state.yaml"
        fi
        if [[ -f "$DEPLOYMENT_EVENTS_FILE" ]]; then
            rm -f "$DEPLOYMENT_EVENTS_FILE"
            print_info "Removed deployment-events.yaml"
        fi
        # Also remove other state files
        if [[ -f "$KOF_STATE_FILE" ]]; then
            rm -f "$KOF_STATE_FILE"
            print_info "Removed kof-state.yaml"
        fi
        if [[ -f "$KOF_EVENTS_FILE" ]]; then
            rm -f "$KOF_EVENTS_FILE"
            print_info "Removed kof-events.yaml"
        fi
        if [[ -f "$AZURE_STATE_FILE" ]]; then
            rm -f "$AZURE_STATE_FILE"
            print_info "Removed azure-state.yaml"
        fi
        if [[ -f "$AZURE_EVENTS_FILE" ]]; then
            rm -f "$AZURE_EVENTS_FILE"
            print_info "Removed azure-events.yaml"
        fi
        print_success "Deployment state files removed"
    else
        print_info "Step 7: No deployment state files to remove"
    fi

    # Step 8: Clean up logs directory
    if [[ -d "./logs" ]]; then
        print_header "Step 8: Removing Logs Directory"
        rm -rf ./logs
        print_success "Logs directory removed"
    else
        print_info "Step 8: No logs directory to remove"
    fi

    print_header "Reset Complete"
    print_success "All k0rdent resources have been removed"
    print_info "You can now run a fresh deployment with: $0 deploy"
}

# Main execution
# Handle help flag
if [[ "${SHOW_HELP:-false}" == "true" ]]; then
    POSITIONAL_ARGS=("help")
fi

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
        bash bin/check-prerequisites.sh
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
        echo "  -y, --yes               Skip confirmation prompts"
        echo "  --no-wait               Skip waiting for resources (where applicable)"
        echo "  --with-azure-children   Enable Azure child cluster deployment capability"
        echo "  --with-kof              Deploy KOF (mothership + regional cluster)"
        echo "  --fast                  Fast reset (skip cleanup, delete resource group)"
        echo "  --with-desktop-notifications  Enable desktop notifications (macOS)"
        echo "  -h, --help              Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 deploy                        # Basic k0rdent deployment"
        echo "  $0 deploy --with-azure-children  # Deploy with Azure child cluster support"
        echo "  $0 deploy --with-kof             # Deploy with KOF components"
        echo "  $0 deploy --with-azure-children --with-kof  # Full deployment"
        echo "  $0 reset --fast                  # Fast reset for development"
        ;;
    *)
        print_error "Unknown command: ${POSITIONAL_ARGS[0]}"
        echo "Use '$0 help' for usage information."
        exit 1
        ;;
esac
