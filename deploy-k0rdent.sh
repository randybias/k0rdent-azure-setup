#!/usr/bin/env bash

# deploy-k0rdent.sh
# Master deployment script for k0rdent Azure setup
# Orchestrates the entire deployment process

set -euo pipefail

DEFAULT_CONFIG_YAML="./config/k0rdent.yaml"
FALLBACK_CONFIG_YAML="./config/k0rdent-default.yaml"

# Load common functions early for logging helpers (used during arg parsing)
source ./etc/common-functions.sh

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
CONFIG_FILE=""
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
        --config)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --config requires a file path argument"
                exit 1
            fi
            CONFIG_FILE="$2"
            shift 2
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

# Apply custom configuration file if provided
if [[ -n "$CONFIG_FILE" ]]; then
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "Custom configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    export K0RDENT_CONFIG_FILE="$CONFIG_FILE"
else
    if [[ ! -f "$DEFAULT_CONFIG_YAML" ]] && [[ ! -f "$FALLBACK_CONFIG_YAML" ]]; then
        print_error "ERROR: No configuration found!"
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
fi

# Load central configuration and state management helpers
source ./etc/k0rdent-config.sh
source ./etc/state-management.sh
source ./etc/kof-functions.sh

# Build flags to pass to child scripts
if [[ "$SKIP_PROMPTS" == "true" ]]; then
    DEPLOY_FLAGS="$DEPLOY_FLAGS -y"
fi
if [[ "$NO_WAIT" == "true" ]]; then
    DEPLOY_FLAGS="$DEPLOY_FLAGS --no-wait"
fi

azure_cli_ready() {
    command -v az >/dev/null 2>&1
}

phase_display_name() {
    case "$1" in
        prepare_deployment) echo "Deployment preparation" ;;
        setup_network) echo "Azure network setup" ;;
        create_vms) echo "Azure VM creation" ;;
        setup_vpn) echo "WireGuard VPN setup" ;;
        connect_vpn) echo "WireGuard VPN connection" ;;
        install_k0s) echo "k0s installation" ;;
        install_k0rdent) echo "k0rdent installation" ;;
        setup_azure_children) echo "Azure child cluster setup" ;;
        install_azure_csi) echo "Azure CSI install" ;;
        install_kof_mothership) echo "KOF mothership install" ;;
        install_kof_regional) echo "KOF regional install" ;;
        *) echo "$1" ;;
    esac
}

ensure_state_structure() {
    if state_file_exists; then
        : # state_file_exists already runs migration logic
    fi
}

validate_prepare_phase() {
    ensure_state_structure || return 1
    local keys_generated=$(get_state "wg_keys_generated" 2>/dev/null || echo "false")
    if [[ "$keys_generated" != "true" ]]; then
        return 1
    fi
    for host in "${VM_HOSTS[@]}"; do
        if [[ ! -f "$CLOUD_INIT_DIR/${host}-cloud-init.yaml" ]]; then
            return 1
        fi
    done
    return 0
}

validate_network_phase() {
    ensure_state_structure || return 1
    if [[ "$(get_state "azure_rg_status" 2>/dev/null)" != "created" ]]; then
        return 1
    fi
    if [[ "$(get_state "azure_network_status" 2>/dev/null)" != "created" ]]; then
        return 1
    fi
    if [[ "$(get_state "azure_ssh_key_status" 2>/dev/null)" != "created" ]]; then
        return 1
    fi

    if ! azure_cli_ready; then
        return 0
    fi

    if ! check_azure_resource_exists "group" "$RG"; then
        return 1
    fi
    if ! check_azure_resource_exists "vnet" "$VNET_NAME" "$RG"; then
        return 1
    fi
    if ! check_azure_resource_exists "nsg" "$NSG_NAME" "$RG"; then
        return 1
    fi
    if ! check_azure_resource_exists "sshkey" "$SSH_KEY_NAME" "$RG"; then
        return 1
    fi
    return 0
}

validate_vm_phase() {
    ensure_state_structure || return 1

    local vm_total=${#VM_HOSTS[@]}
    local state_count
    state_count=$(yq eval '.vm_states | length' "$DEPLOYMENT_STATE_FILE" 2>/dev/null || echo "0")
    if [[ "$state_count" -lt "$vm_total" ]]; then
        return 1
    fi

    if ! azure_cli_ready; then
        return 0
    fi

    for host in "${VM_HOSTS[@]}"; do
        if ! check_azure_resource_exists "vm" "$host" "$RG"; then
            return 1
        fi
    done
    return 0
}

validate_vpn_setup_phase() {
    ensure_state_structure || return 1
    local setup_flag
    setup_flag=$(get_state "wg_laptop_config_created" 2>/dev/null || echo "false")
    if [[ "$setup_flag" != "true" ]]; then
        return 1
    fi
    [[ -f "$WG_CONFIG_FILE" ]]
}

validate_vpn_connection_phase() {
    ensure_state_structure || return 1
    local connected=$(get_state "wg_vpn_connected" 2>/dev/null || echo "false")
    if [[ "$connected" != "true" ]]; then
        return 1
    fi

    # Quick check using wg show if available
    if command -v wg >/dev/null 2>&1; then
        if [[ "$(uname)" == "Darwin" ]]; then
            if ! run_wg_command wg-show >/dev/null 2>&1; then
                return 1
            fi
        else
            local iface
            iface=$(basename "$WG_CONFIG_FILE" .conf)
            if ! run_wg_command wg-show "$iface" >/dev/null 2>&1; then
                return 1
            fi
        fi
    fi
    return 0
}

validate_k0s_phase() {
    ensure_state_structure || return 1
    local deployed=$(get_state "k0s_cluster_deployed" 2>/dev/null || echo "false")
    if [[ "$deployed" != "true" ]]; then
        return 1
    fi
    [[ -f "./k0sctl-config/${K0RDENT_CLUSTERID}-kubeconfig" ]]
}

validate_k0rdent_phase() {
    ensure_state_structure || return 1
    local installed=$(get_state "k0rdent_installed" 2>/dev/null || echo "false")
    [[ "$installed" == "true" ]]
}

# Enablement checker for KOF components (uses deploy script flag)
is_kof_deployment_enabled() {
    [[ "$WITH_KOF" == "true" ]]
}

# Enablement checker for Azure children components (uses deploy script flag)
is_azure_children_deployment_enabled() {
    [[ "$WITH_AZURE_CHILDREN" == "true" ]]
}

handle_completed_phase() {
    local phase="$1"
    local validator="$2"
    local label
    label=$(phase_display_name "$phase")

    if [[ -z "$validator" ]]; then
        print_info "$label already completed. Skipping."
        return 0
    fi

    if "$validator"; then
        print_success "$label already completed. Skipping."
        return 0
    fi

    print_warning "$label marked complete but validation failed. Re-running phase."
    phase_reset_from "$phase"
    return 1
}

# Check if a phase should run
# Args: $1 - phase name, $2 - validator function (optional), $3 - enablement checker function (optional)
# Returns: 0 if should run, 1 if should skip
should_run_phase() {
    local phase="$1"
    local validator="${2:-}"
    local enablement_checker="${3:-}"
    local label
    label=$(phase_display_name "$phase")

    # Check if component is enabled (if enablement checker provided)
    if [[ -n "$enablement_checker" ]]; then
        if ! "$enablement_checker" 2>/dev/null; then
            # Component is disabled - handle state transitions
            local current_status
            current_status=$(phase_status "$phase")

            if [[ "$current_status" == "completed" ]]; then
                # Phase was completed in previous run but now disabled
                phase_mark_skipped "$phase" "Component no longer enabled"
                print_info "$label - previously completed, now skipped (component disabled)."
            elif [[ "$current_status" != "skipped" ]]; then
                # Phase never run and component disabled
                phase_mark_skipped "$phase" "Component not enabled"
                print_info "$label skipped - component not enabled."
            else
                # Already skipped, just log
                print_info "$label skipped - component not enabled."
            fi
            return 1  # Don't run phase
        fi
    fi

    if ! state_file_exists; then
        return 0
    fi

    # Check if phase was previously skipped but now component is enabled
    if phase_is_skipped "$phase"; then
        # Component is now enabled, reset phase to pending so it can run
        phase_mark_pending "$phase"
        print_info "$label - was skipped, now enabled. Will run."
        return 0
    fi

    if phase_needs_run "$phase"; then
        return 0
    fi

    if handle_completed_phase "$phase" "$validator"; then
        return 1
    fi

    return 0
}


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
    DEPLOYMENT_START_DATE_UTC=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
    DEPLOYMENT_START_DATE=$(date "+%Y-%m-%d %H:%M:%S %Z")

    print_info "Deployment started at: $DEPLOYMENT_START_DATE"
    echo

    # Initialize state file early if it doesn't exist, so deployment flags are recorded immediately
    if ! state_file_exists; then
        init_deployment_state "$K0RDENT_CLUSTERID"
    fi

    # Record deployment flags immediately (before any phases run)
    # This ensures 'status' command shows correct flags even during first phase
    update_state "deployment_flags.azure_children" "$WITH_AZURE_CHILDREN"
    update_state "deployment_flags.kof" "$WITH_KOF"
    update_state "deployment_start_time" "$DEPLOYMENT_START_DATE_UTC"
    add_event "deployment_started" "Deployment started with flags: azure-children=$WITH_AZURE_CHILDREN, kof=$WITH_KOF"

    # Record deployment in history with deployer identity
    get_deployer_identity
    record_deployment_history "$K0RDENT_CLUSTERID" "$CONFIG_YAML" "$DEPLOYER_IDENTITY"

    # Step 1: Prepare deployment (keys and cloud-init)
    if should_run_phase "prepare_deployment" validate_prepare_phase; then
        print_header "Step 1: Preparing Deployment (Keys & Cloud-Init)"
        bash bin/prepare-deployment.sh deploy $DEPLOY_FLAGS
        phase_mark_completed "prepare_deployment"
    else
        print_success "Step 1 skipped - deployment preparation already complete."
    fi

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
    if should_run_phase "setup_network" validate_network_phase; then
        print_header "Step 2: Setting up Azure Network"
        bash bin/setup-azure-network.sh deploy $DEPLOY_FLAGS
        phase_mark_completed "setup_network"
    else
        print_success "Step 2 skipped - Azure network already configured."
    fi

    # Step 3: Create Azure VMs
    if should_run_phase "create_vms" validate_vm_phase; then
        print_header "Step 3: Creating Azure VMs"
        bash bin/create-azure-vms.sh deploy $DEPLOY_FLAGS
        phase_mark_completed "create_vms"
    else
        print_success "Step 3 skipped - Azure VMs already created."
    fi

    # Step 4: Setup WireGuard VPN (one-time setup)
    if should_run_phase "setup_vpn" validate_vpn_setup_phase; then
        print_header "Step 4: Setting Up WireGuard VPN"
        bash bin/manage-vpn.sh setup $DEPLOY_FLAGS
        phase_mark_completed "setup_vpn"
    else
        print_success "Step 4 skipped - WireGuard VPN already configured."
    fi

    # Step 5: Connect to WireGuard VPN
    if should_run_phase "connect_vpn" validate_vpn_connection_phase; then
        print_header "Step 5: Connecting to WireGuard VPN"
        bash bin/manage-vpn.sh connect $DEPLOY_FLAGS
        phase_mark_completed "connect_vpn"
    else
        print_success "Step 5 skipped - WireGuard VPN already connected."
    fi

    # Step 6: Install k0s cluster
    if should_run_phase "install_k0s" validate_k0s_phase; then
        print_header "Step 6: Installing k0s Cluster"
        bash bin/install-k0s.sh deploy $DEPLOY_FLAGS
        phase_mark_completed "install_k0s"
    else
        print_success "Step 6 skipped - k0s already deployed."
    fi

    # Step 7: Install k0rdent on cluster
    if should_run_phase "install_k0rdent" validate_k0rdent_phase; then
        print_header "Step 7: Installing k0rdent on Cluster"
        bash bin/install-k0rdent.sh deploy $DEPLOY_FLAGS
        phase_mark_completed "install_k0rdent"
    else
        print_success "Step 7 skipped - k0rdent already installed."
    fi

    # Step 8: Setup Azure child cluster deployment (optional - uses enablement checker)
    if should_run_phase "setup_azure_children" "" "is_azure_children_deployment_enabled"; then
        print_header "Step 8: Setting up Azure Child Cluster Deployment"
        bash bin/setup-azure-cluster-deployment.sh setup $DEPLOY_FLAGS
        phase_mark_completed "setup_azure_children"
    else
        local step8_status
        step8_status=$(phase_status "setup_azure_children")
        if [[ "$step8_status" == "completed" ]]; then
            print_success "Step 8 skipped - Azure child cluster deployment already configured."
        fi
        # If skipped, message was already printed by should_run_phase
    fi

    # Step 9: Install Azure CSI driver (optional - required for KOF)
    if should_run_phase "install_azure_csi" "" "is_kof_deployment_enabled"; then
        print_header "Step 9: Installing Azure Disk CSI Driver for KOF"
        bash bin/install-k0s-azure-csi.sh deploy $DEPLOY_FLAGS
        phase_mark_completed "install_azure_csi"
    else
        local step9_status
        step9_status=$(phase_status "install_azure_csi")
        if [[ "$step9_status" == "completed" ]]; then
            print_success "Step 9 skipped - Azure Disk CSI driver already installed."
        fi
    fi

    # Step 10: Install KOF mothership (optional - uses enablement checker)
    if should_run_phase "install_kof_mothership" "" "is_kof_deployment_enabled"; then
        print_header "Step 10: Installing KOF Mothership"
        bash bin/install-kof-mothership.sh deploy $DEPLOY_FLAGS
        phase_mark_completed "install_kof_mothership"
    else
        local step10_status
        step10_status=$(phase_status "install_kof_mothership")
        if [[ "$step10_status" == "completed" ]]; then
            print_success "Step 10 skipped - KOF mothership already installed."
        fi
    fi

    # Step 11: Deploy KOF regional cluster (optional - uses enablement checker)
    if should_run_phase "install_kof_regional" "" "is_kof_deployment_enabled"; then
        print_header "Step 11: Deploying KOF Regional Cluster"
        bash bin/install-kof-regional.sh deploy $DEPLOY_FLAGS
        phase_mark_completed "install_kof_regional"
    else
        local step11_status
        step11_status=$(phase_status "install_kof_regional")
        if [[ "$step11_status" == "completed" ]]; then
            print_success "Step 11 skipped - KOF regional cluster already deployed."
        fi
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
        echo "  - Deploy child clusters: ./bin/create-azure-child.sh --help"
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
    
    # Step 2.5: Clean up Azure credentials (Service Principal, secrets, etc.)
    integrate_azure_cleanup_in_reset
    
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

    # Step 5.5: Clean up Azure credentials (Service Principal, secrets, etc.)
    integrate_azure_cleanup_in_reset

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

# Azure credential cleanup integration for reset
integrate_azure_cleanup_in_reset() {
    print_header "Checking for Azure Credentials Cleanup"
    
    # Check local Azure state first
    if [[ -f "$AZURE_STATE_FILE" ]]; then
        local credentials_configured
        credentials_configured=$(get_azure_state "azure_credentials_configured" 2>/dev/null || echo "false")
        
        if [[ "$credentials_configured" == "true" ]]; then
            print_info "Azure credentials were configured - initiating cleanup..."
            
            # Set SKIP_CONFIRMATION to bypass manual prompts during reset
            local old_skip_confirmation="${SKIP_CONFIRMATION:-}"
            export SKIP_CONFIRMATION="true"
            
            # For fast reset, the Kubernetes cluster is being deleted, so skip cleanup
            if [[ "$FAST_RESET" == "true" ]]; then
                local cleanup_result
                print_info "Fast reset detected - cleaning up Azure Service Principal only (cluster being deleted)"
                if bash ./bin/setup-azure-cluster-deployment.sh cleanup --azure-only; then
                    cleanup_result="success"
                else
                    cleanup_result="partial"
                    print_warning "Azure Service Principal cleanup encountered issues"
                    print_info "Manual cleanup may be required with: ./bin/setup-azure-cluster-deployment.sh cleanup --azure-only"
                fi
            else
                # Full reset - clean up both Azure and Kubernetes resources
                if bash ./bin/setup-azure-cluster-deployment.sh cleanup; then
                    cleanup_result="success"
                else
                    cleanup_result="partial"
                    print_warning "Azure credentials cleanup encountered issues"
                    print_info "Manual cleanup may be required with: ./bin/setup-azure-cluster-deployment.sh cleanup"
                fi
            fi
            
            # Log cleanup results based on operation type and result
            if [[ "$FAST_RESET" == "true" ]]; then
                if [[ "$cleanup_result" == "success" ]]; then
                    print_success "Azure Service Principal cleaned up successfully"
                    add_event "azure_credentials_auto_cleanup" "Azure Service Principal automatically cleaned up during fast reset"
                else
                    add_event "azure_credentials_cleanup_partial" "Azure Service Principal cleanup partially failed during fast reset"
                fi
            else
                if [[ "$cleanup_result" == "success" ]]; then
                    print_success "Azure credentials cleaned up successfully"
                    add_event "azure_credentials_auto_cleanup" "Azure credentials automatically cleaned up during reset"
                else
                    add_event "azure_credentials_cleanup_partial" "Azure credentials cleanup partially failed during reset"
                fi
            fi
            
            # Restore original SKIP_CONFIRMATION setting
            if [[ -n "$old_skip_confirmation" ]]; then
                export SKIP_CONFIRMATION="$old_skip_confirmation"
            elif [[ -n "${SKIP_CONFIRMATION+x}" ]]; then
                unset SKIP_CONFIRMATION
            fi
        else
            print_info "No Azure credentials to clean up"
        fi
    else
        print_info "Azure state file not found - no credentials to clean up"
    fi
}

# Convert UTC timestamp to local timezone for display
# Input: ISO 8601 UTC timestamp (e.g., "2025-12-01T08:56:05Z")
# Output: Local time with timezone indicator (e.g., "2025-12-01 00:56:05 PST")
convert_utc_to_local() {
    local utc_time="$1"

    # Return empty if input is empty
    if [[ -z "$utc_time" ]]; then
        echo ""
        return 1
    fi

    # Detect OS and use appropriate date command
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: parse UTC time to epoch, then convert to local
        local epoch
        epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$utc_time" "+%s" 2>/dev/null)
        if [[ -n "$epoch" ]]; then
            date -r "$epoch" "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null || echo "$utc_time (UTC)"
        else
            echo "$utc_time (UTC)"
        fi
    else
        # Linux: use -d flag
        date -d "$utc_time" "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null || echo "$utc_time (UTC)"
    fi
}

# Calculate current runtime from start time to now
# Input: ISO 8601 UTC timestamp for start time
# Output: Formatted duration string (e.g., "15 minutes 32 seconds")
calculate_current_runtime() {
    local start_time="$1"

    # Return empty if input is empty
    if [[ -z "$start_time" ]]; then
        echo ""
        return 1
    fi

    # Parse start time to epoch
    local start_epoch
    if [[ "$OSTYPE" == "darwin"* ]]; then
        start_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start_time" +%s 2>/dev/null)
    else
        start_epoch=$(date -d "$start_time" +%s 2>/dev/null)
    fi

    # Return if parsing failed
    if [[ -z "$start_epoch" ]]; then
        echo ""
        return 1
    fi

    # Calculate elapsed time
    local current_epoch=$(date +%s)
    local elapsed=$((current_epoch - start_epoch))

    # Format as duration
    local hours=$((elapsed / 3600))
    local minutes=$(((elapsed % 3600) / 60))
    local seconds=$((elapsed % 60))

    if [[ $hours -gt 0 ]]; then
        echo "${hours} hours ${minutes} minutes ${seconds} seconds"
    elif [[ $minutes -gt 0 ]]; then
        echo "${minutes} minutes ${seconds} seconds"
    else
        echo "${seconds} seconds"
    fi
}

# Show comprehensive deployment status
show_deployment_status() {
    print_header "k0rdent Deployment Status"

    # Check if deployment state exists
    if ! state_file_exists; then
        echo ""
        print_info "Deployment State: NOT DEPLOYED"
        echo ""
        echo "No deployment state found at: $DEPLOYMENT_STATE_FILE"
        echo ""
        echo "To create a new deployment:"
        echo "  $0 deploy"
        echo ""
        return 0
    fi

    # Read deployment state
    local deployment_id=$(get_state "deployment_id" 2>/dev/null || echo "unknown")
    local phase=$(get_state "phase" 2>/dev/null || echo "unknown")
    local status=$(get_state "status" 2>/dev/null || echo "unknown")

    # Determine overall deployment state
    local deployment_state="UNKNOWN"
    if [[ "$status" == "completed" ]] && [[ "$phase" == "install_kof_regional" || "$phase" == "install_k0rdent" ]]; then
        deployment_state="DEPLOYED"
    elif [[ "$status" == "in_progress" ]]; then
        deployment_state="IN PROGRESS"
    elif [[ "$status" == "pending" ]]; then
        deployment_state="NOT STARTED"
    fi

    echo ""
    if [[ "$deployment_state" == "DEPLOYED" ]]; then
        print_success "Deployment State: $deployment_state"
    elif [[ "$deployment_state" == "IN PROGRESS" ]]; then
        print_info "Deployment State: $deployment_state"
    else
        print_warning "Deployment State: $deployment_state"
    fi

    echo "Cluster ID: $deployment_id"

    # Show configuration source
    echo "Configuration source: ${K0RDENT_CONFIG_SOURCE:-default}"

    # Display cluster configuration
    echo ""
    echo "Cluster Configuration:"
    local region=$(get_state "config.azure_location" 2>/dev/null || echo "$AZURE_LOCATION")
    local controller_count=$(get_state "config.controller_count" 2>/dev/null || echo "$K0S_CONTROLLER_COUNT")
    local worker_count=$(get_state "config.worker_count" 2>/dev/null || echo "$K0S_WORKER_COUNT")

    echo "  Region: $region"
    echo "  Controllers: $controller_count ($AZURE_CONTROLLER_VM_SIZE)"
    echo "  Workers: $worker_count ($AZURE_WORKER_VM_SIZE)"
    echo "  k0s Version: $K0S_VERSION"
    echo "  k0rdent Version: $K0RDENT_VERSION"

    # Display network information
    echo ""
    echo "Network:"
    local wg_network=$(get_state "config.wireguard_network" 2>/dev/null || echo "$WG_NETWORK")
    local vpn_connected=$(get_state "wg_vpn_connected" 2>/dev/null || echo "false")
    local wg_interface=$(get_state "wg_macos_interface" 2>/dev/null || echo "")

    echo "  VPN Network: $wg_network"
    if [[ "$vpn_connected" == "true" ]]; then
        if [[ -n "$wg_interface" ]]; then
            print_success "  VPN Status: Connected ($wg_interface)"
        else
            print_success "  VPN Status: Connected"
        fi
    else
        print_warning "  VPN Status: Disconnected"
    fi

    # Display deployment timeline if available
    local start_time=$(get_state "deployment_start_time" 2>/dev/null || echo "")

    # Fall back to created_at if deployment_start_time is missing or null
    if [[ -z "$start_time" ]] || [[ "$start_time" == "null" ]]; then
        start_time=$(get_state "created_at" 2>/dev/null || echo "")
    fi

    local end_time=$(get_state "deployment_end_time" 2>/dev/null || echo "")
    local duration=$(get_state "deployment_duration_seconds" 2>/dev/null || echo "")

    if [[ -n "$start_time" ]]; then
        echo ""
        echo "Deployment Timeline:"

        # Convert UTC start time to local timezone for display
        local start_time_local=$(convert_utc_to_local "$start_time")
        echo "  Started: $start_time_local"

        if [[ -n "$end_time" ]] && [[ "$end_time" != "null" ]]; then
            # Deployment completed - show completion time and duration
            echo "  Completed: $end_time"

            if [[ -n "$duration" ]] && [[ "$duration" =~ ^[0-9]+$ ]]; then
                local hours=$((duration / 3600))
                local minutes=$(((duration % 3600) / 60))
                local seconds=$((duration % 60))

                echo -n "  Duration: "
                if [[ $hours -gt 0 ]]; then
                    echo "${hours} hours ${minutes} minutes ${seconds} seconds"
                elif [[ $minutes -gt 0 ]]; then
                    echo "${minutes} minutes ${seconds} seconds"
                else
                    echo "${seconds} seconds"
                fi
            fi
        else
            # Deployment in progress - show current runtime
            local current_runtime=$(calculate_current_runtime "$start_time")
            if [[ -n "$current_runtime" ]]; then
                echo "  Current Run Time: $current_runtime"
            fi
            echo "  Status: In Progress"
        fi
    fi

    # Display deployment flags
    local azure_children=$(get_state "deployment_flags.azure_children" 2>/dev/null || echo "false")
    local kof=$(get_state "deployment_flags.kof" 2>/dev/null || echo "false")

    echo ""
    echo "Deployment Flags:"
    if [[ "$azure_children" == "true" ]]; then
        echo "  Azure Children: Enabled"
    else
        echo "  Azure Children: Disabled"
    fi
    if [[ "$kof" == "true" ]]; then
        echo "  KOF: Enabled"
    else
        echo "  KOF: Disabled"
    fi

    # Display deployment phases
    echo ""
    echo "Deployment Phases:"

    # Standard phases
    local phases=(
        "prepare_deployment:Prepare deployment"
        "setup_network:Setup network"
        "create_vms:Create VMs"
        "setup_vpn:Setup VPN"
        "connect_vpn:Connect VPN"
        "install_k0s:Install k0s"
        "install_k0rdent:Install k0rdent"
    )

    # Add optional phases based on deployment flags or if they've been executed/skipped
    # This ensures phases show up in status even if flags changed between deployments
    local azure_children_status
    local azure_csi_status kof_mothership_status kof_regional_status
    azure_children_status=$(get_state "phases.setup_azure_children.status" 2>/dev/null || echo "")
    azure_csi_status=$(get_state "phases.install_azure_csi.status" 2>/dev/null || echo "")
    kof_mothership_status=$(get_state "phases.install_kof_mothership.status" 2>/dev/null || echo "")
    kof_regional_status=$(get_state "phases.install_kof_regional.status" 2>/dev/null || echo "")

    if [[ "$azure_children" == "true" ]] || [[ -n "$azure_children_status" && "$azure_children_status" != "pending" ]]; then
        phases+=("setup_azure_children:Setup Azure children")
    fi
    if [[ "$kof" == "true" ]] || [[ -n "$azure_csi_status" && "$azure_csi_status" != "pending" ]]; then
        phases+=("install_azure_csi:Install Azure CSI")
    fi
    if [[ "$kof" == "true" ]] || [[ -n "$kof_mothership_status" && "$kof_mothership_status" != "pending" ]]; then
        phases+=("install_kof_mothership:Install KOF mothership")
    fi
    if [[ "$kof" == "true" ]] || [[ -n "$kof_regional_status" && "$kof_regional_status" != "pending" ]]; then
        phases+=("install_kof_regional:Install KOF regional")
    fi

    # Display each phase with status
    for phase_entry in "${phases[@]}"; do
        local phase_key="${phase_entry%%:*}"
        local phase_name="${phase_entry#*:}"
        local phase_status=$(get_state "phases.${phase_key}.status" 2>/dev/null || echo "pending")

        local symbol=""
        case "$phase_status" in
            "completed")
                symbol="✓"
                ;;
            "in_progress")
                symbol="⏳"
                ;;
            "pending")
                symbol="○"
                ;;
            "skipped")
                symbol="⏭"
                ;;
            "failed")
                symbol="✗"
                ;;
            *)
                symbol="○"
                ;;
        esac

        echo "  $symbol $phase_name"
    done

    # Display resource locations
    echo ""
    echo "Resource Locations:"

    local kubeconfig_path="./k0sctl-config/${deployment_id}-kubeconfig"
    if [[ -f "$kubeconfig_path" ]]; then
        echo "  Kubeconfig: $kubeconfig_path"
    else
        echo "  Kubeconfig: Not yet created"
    fi

    echo "  State File: $DEPLOYMENT_STATE_FILE"

    # Show next steps based on deployment state
    if [[ "$deployment_state" == "DEPLOYED" ]]; then
        echo ""
        echo "Quick Commands:"
        echo "  Connect to cluster: export KUBECONFIG=\$PWD/k0sctl-config/${deployment_id}-kubeconfig"
        echo "  Check nodes: kubectl get nodes"
        echo "  View resources: kubectl get all -A"
        if [[ "$vpn_connected" != "true" ]]; then
            echo "  Connect VPN: ./bin/manage-vpn.sh connect"
        fi
    elif [[ "$deployment_state" == "IN PROGRESS" ]]; then
        echo ""
        echo "Deployment is currently in progress at phase: $phase"
    else
        echo ""
        echo "To start deployment: $0 deploy"
    fi

    echo ""
}

# Show deployment history
show_history() {
    show_deployment_history
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
    "status")
        show_deployment_status
        ;;
    "check")
        bash bin/check-prerequisites.sh
        ;;
    "history")
        show_history
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [options] <command>"
        echo ""
        echo "Commands:"
        echo "  deploy    Run full deployment (default)"
        echo "  reset     Remove all k0rdent resources"
        echo "  config    Show configuration"
        echo "  status    Show deployment status"
        echo "  history   Show deployment history"
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
        echo "  --config <file>         Use alternate YAML configuration file"
        echo "  -h, --help              Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 status                        # Check deployment status"
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
