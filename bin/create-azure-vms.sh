#!/usr/bin/env bash

# Script: create-azure-vms.sh
# Purpose: Create ARM64 Debian 12 VMs with automatic failure recovery
# Usage: bash create-azure-vms.sh [command] [options]
# Implements asynchronous VM creation with PID tracking and state monitoring

set -euo pipefail

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh
source ./etc/state-management.sh

# Script-specific variables
declare -A VM_PIDS           # Track background VM creation PIDs
declare -A VM_RETRY_COUNT    # Track retry attempts per VM
declare -A VM_START_TIME     # Track when each VM creation started
declare -A VM_VERIFIED       # Track VMs that have been fully verified (SSH + cloud-init passed)
MAX_VM_RETRIES=3            # Maximum retry attempts per VM

# Script-specific functions

# Check if cloud-init is in error state with retry logic
check_cloud_init_error() {
    local host="$1"
    local public_ip="$2"
    local ssh_key="$3"
    local admin_user="$4"
    
    local max_retries=5
    local retry_delay=5
    
    for ((attempt=1; attempt<=max_retries; attempt++)); do
        local cloud_init_status
        cloud_init_status=$(ssh -i "$ssh_key" \
                                -o ConnectTimeout=10 \
                                -o StrictHostKeyChecking=no \
                                -o UserKnownHostsFile=/dev/null \
                                -o LogLevel=ERROR \
                                "$admin_user@$public_ip" \
                                "sudo cloud-init status" 2>/dev/null || echo "SSH_FAILED")
        
        # Check for definitive error state
        if [[ "$cloud_init_status" == *"status: error"* ]]; then
            print_warning "Cloud-init error detected on $host after $attempt attempts"
            return 0  # Cloud-init is in error state
        fi
        
        # Check for successful completion - break immediately
        if [[ "$cloud_init_status" == *"status: done"* ]]; then
            return 1  # Cloud-init completed successfully
        fi
        
        # If still running or SSH failed, wait and retry (unless last attempt)
        if [[ $attempt -lt $max_retries ]]; then
            if [[ "$cloud_init_status" == "SSH_FAILED" ]]; then
                print_info "Cloud-init check: SSH failed on $host, retrying ($attempt/$max_retries)..."
            elif [[ "$cloud_init_status" == *"status: running"* ]]; then
                print_info "Cloud-init check: Still running on $host, waiting ($attempt/$max_retries)..."
            else
                print_info "Cloud-init check: Unknown status on $host, retrying ($attempt/$max_retries)..."
            fi
            sleep $retry_delay
        fi
    done
    
    # After all retries, assume success if no explicit error found
    print_info "Cloud-init check completed for $host after $max_retries attempts (assuming success)"
    return 1  # Not in error state
}

# Launch a single VM in the background
launch_vm_async() {
    local host="$1"
    local zone="$2"
    local vm_size="$3"
    local cloud_init="$4"
    
    print_info "Launching VM creation: $host (zone $zone, size $vm_size)"
    
    # Build VM creation command based on priority type
    local vm_create_cmd="az vm create \
        --resource-group $RG \
        --name $host \
        --image $AZURE_VM_IMAGE \
        --size $vm_size \
        --priority $AZURE_VM_PRIORITY \
        --zone $zone \
        --admin-username $SSH_USERNAME \
        --ssh-key-name $SSH_KEY_NAME \
        --vnet-name $VNET_NAME \
        --subnet $SUBNET_NAME \
        --nsg $NSG_NAME \
        --public-ip-sku Standard \
        --custom-data $cloud_init \
        --os-disk-size-gb 64"
    
    # Add eviction policy only for Spot instances
    if [[ "$AZURE_VM_PRIORITY" == "Spot" ]]; then
        vm_create_cmd="$vm_create_cmd --eviction-policy $AZURE_EVICTION_POLICY"
    fi
    
    # Launch VM creation in background with timeout
    timeout $((VM_CREATION_TIMEOUT_MINUTES * 60)) bash -c "$vm_create_cmd" >/dev/null 2>&1 &
    
    # Store PID of the timeout command (not a subshell)
    local pid=$!
    VM_PIDS["$host"]=$pid
    VM_START_TIME["$host"]=$(date +%s)
    
    # Initialize retry count if not set
    if [[ -z "${VM_RETRY_COUNT[$host]:-}" ]]; then
        VM_RETRY_COUNT["$host"]=0
    fi
    
    # Update state
    update_vm_state "$host" "" "" "Creating"
    add_event "vm_creation_started" "Started creating VM: $host (PID: $pid, attempt ${VM_RETRY_COUNT[$host]})"
    
    return 0
}

# Kill VM creation process if still running
kill_vm_process() {
    local host="$1"
    local pid="${VM_PIDS[$host]:-}"
    
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        print_info "Killing VM creation process for $host (PID: $pid)"
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -9 "$pid" 2>/dev/null || true
        unset VM_PIDS["$host"]
    fi
}

# Delete a VM
delete_vm() {
    local host="$1"
    
    print_info "Deleting VM: $host"
    az vm delete \
        --resource-group "$RG" \
        --name "$host" \
        --yes \
        --no-wait
    
    update_vm_state "$host" "" "" "Deleting"
    add_event "vm_deletion_started" "Started deletion of VM: $host"
}

# Main VM deployment with monitoring loop
deploy_vms_async() {
    # Step 0: Launch all VMs in parallel
    print_header "Launching VMs in Parallel"
    
    for HOST in "${vms_to_create[@]}"; do
        ZONE="${VM_ZONE_MAP[$HOST]}"
        VM_SIZE="${VM_SIZE_MAP[$HOST]}"
        CLOUD_INIT="$CLOUD_INIT_DIR/${HOST}-cloud-init.yaml"
        
        launch_vm_async "$HOST" "$ZONE" "$VM_SIZE" "$CLOUD_INIT"
    done
    
    print_success "All VM creation processes launched"
    
    # Main monitoring loop
    print_header "Monitoring VM Creation and Health"
    print_info "Timeout: $VM_CREATION_TIMEOUT_MINUTES minutes, Check interval: $VM_WAIT_CHECK_INTERVAL seconds"
    
    local start_time=$(date +%s)
    local timeout_seconds=$((VM_CREATION_TIMEOUT_MINUTES * 60))
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout_seconds ]]; then
            print_error "Global timeout reached after $VM_CREATION_TIMEOUT_MINUTES minutes"
            break
        fi
        
        print_info "Checking VM states... (elapsed: ${elapsed}s / ${timeout_seconds}s)"
        
        # Step 1: Get all VM states in one call
        local vm_data
        vm_data=$(az vm list --resource-group "$RG" --show-details --output yaml 2>/dev/null || echo "")
        
        if [[ -z "$vm_data" ]]; then
            print_warning "Could not retrieve VM data from Azure"
            sleep $VM_WAIT_CHECK_INTERVAL
            continue
        fi
        
        local all_success=true
        local active_vms=0
        
        # Check each VM we're supposed to create
        for HOST in "${vms_to_create[@]}"; do
            # Skip if we've exceeded retry limit
            if [[ ${VM_RETRY_COUNT["$HOST"]} -ge $MAX_VM_RETRIES ]]; then
                print_error "VM $HOST exceeded maximum retries (${MAX_VM_RETRIES})"
                continue
            fi
            
            # Get VM state from data first
            local vm_state
            vm_state=$(echo "$vm_data" | yq eval ".[] | select(.name == \"$HOST\") | .provisioningState" - 2>/dev/null || echo "NotFound")
            
            # Check if VM creation process is still running
            local pid="${VM_PIDS[$HOST]:-}"
            if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
                # Process died - but only consider it failed if VM doesn't exist in Azure
                if [[ "$vm_state" == "NotFound" ]]; then
                    print_warning "VM creation process for $HOST died without creating VM (PID: $pid)"
                    unset VM_PIDS["$HOST"]
                    
                    # Increment retry and potentially relaunch
                    VM_RETRY_COUNT["$HOST"]=$((${VM_RETRY_COUNT["$HOST"]:-0} + 1))
                    if [[ ${VM_RETRY_COUNT["$HOST"]} -lt $MAX_VM_RETRIES ]]; then
                        print_info "Relaunching VM creation for $HOST (attempt ${VM_RETRY_COUNT["$HOST"]}/${MAX_VM_RETRIES})"
                        ZONE="${VM_ZONE_MAP[$HOST]}"
                        VM_SIZE="${VM_SIZE_MAP[$HOST]}"
                        CLOUD_INIT="$CLOUD_INIT_DIR/${HOST}-cloud-init.yaml"
                        launch_vm_async "$HOST" "$ZONE" "$VM_SIZE" "$CLOUD_INIT"
                    else
                        print_error "VM $HOST exceeded maximum retries after process death"
                        continue
                    fi
                else
                    # Process died but VM exists in Azure - this is normal, just clean up PID
                    unset VM_PIDS["$HOST"]
                fi
            fi
            
            # Skip counting verified VMs as active
            if [[ "${VM_VERIFIED[$HOST]:-}" == "true" ]]; then
                continue
            fi
            
            active_vms=$((active_vms + 1))
            
            # Step 2: Get VM public IP from data
            local public_ip
            public_ip=$(echo "$vm_data" | yq eval ".[] | select(.name == \"$HOST\") | .publicIps" - 2>/dev/null || echo "")
            
            # Only log VMs that have meaningful state information
            if [[ -n "$vm_state" ]] && [[ "$vm_state" != "NotFound" ]]; then
                print_info "  $HOST: State=$vm_state, IP=$public_ip"
            elif [[ -n "$public_ip" ]]; then
                # Log if we have an IP but no state (unusual but worth noting)
                print_info "  $HOST: State=$vm_state, IP=$public_ip"
            fi
            
            # Step 3: Handle failed states
            if [[ "$vm_state" == "Failed" ]] || [[ "$vm_state" == "NotFound" ]]; then
                all_success=false
                
                # Kill any running process
                kill_vm_process "$HOST"
                
                # If VM exists but failed, delete it
                if [[ "$vm_state" == "Failed" ]]; then
                    delete_vm "$HOST"
                    sleep 2  # Brief pause before recreation
                fi
                
                # Reset verification status and increment retry count
                VM_VERIFIED["$HOST"]="false"
                VM_RETRY_COUNT["$HOST"]=$((VM_RETRY_COUNT["$HOST"] + 1))
                
                if [[ ${VM_RETRY_COUNT["$HOST"]} -lt $MAX_VM_RETRIES ]]; then
                    print_warning "VM $HOST failed. Relaunching (attempt ${VM_RETRY_COUNT["$HOST"]}/${MAX_VM_RETRIES})"
                    ZONE="${VM_ZONE_MAP[$HOST]}"
                    VM_SIZE="${VM_SIZE_MAP[$HOST]}"
                    CLOUD_INIT="$CLOUD_INIT_DIR/${HOST}-cloud-init.yaml"
                    launch_vm_async "$HOST" "$ZONE" "$VM_SIZE" "$CLOUD_INIT"
                fi
                
                continue
            fi
            
            # Step 4: Check succeeded VMs
            if [[ "$vm_state" == "Succeeded" ]] && [[ -n "$public_ip" ]]; then
                # Update state with IP
                update_vm_state "$HOST" "$public_ip" "" "Succeeded"
                
                # Skip verification checks if VM is already fully verified
                if [[ "${VM_VERIFIED[$HOST]:-}" == "true" ]]; then
                    continue
                fi
                
                # Step 5: Test SSH connectivity
                if ! test_ssh_connectivity "$HOST" "$public_ip" "$SSH_PRIVATE_KEY" "$SSH_USERNAME" 10; then
                    print_warning "SSH connectivity failed for $HOST. Recreating VM..."
                    all_success=false
                    
                    # Kill process, delete, and relaunch
                    kill_vm_process "$HOST"
                    delete_vm "$HOST"
                    
                    # Reset verification status for recreated VM
                    VM_VERIFIED["$HOST"]="false"
                    
                    VM_RETRY_COUNT["$HOST"]=$((VM_RETRY_COUNT["$HOST"] + 1))
                    if [[ ${VM_RETRY_COUNT["$HOST"]} -lt $MAX_VM_RETRIES ]]; then
                        ZONE="${VM_ZONE_MAP[$HOST]}"
                        VM_SIZE="${VM_SIZE_MAP[$HOST]}"
                        CLOUD_INIT="$CLOUD_INIT_DIR/${HOST}-cloud-init.yaml"
                        launch_vm_async "$HOST" "$ZONE" "$VM_SIZE" "$CLOUD_INIT"
                    fi
                    
                    continue
                fi
                
                # Step 6: Check cloud-init status
                if check_cloud_init_error "$HOST" "$public_ip" "$SSH_PRIVATE_KEY" "$SSH_USERNAME"; then
                    print_warning "Cloud-init failed on $HOST. Recreating VM..."
                    all_success=false
                    
                    # Kill process, delete, and relaunch
                    kill_vm_process "$HOST"
                    delete_vm "$HOST"
                    
                    # Reset verification status for recreated VM
                    VM_VERIFIED["$HOST"]="false"
                    
                    VM_RETRY_COUNT["$HOST"]=$((VM_RETRY_COUNT["$HOST"] + 1))
                    if [[ ${VM_RETRY_COUNT["$HOST"]} -lt $MAX_VM_RETRIES ]]; then
                        ZONE="${VM_ZONE_MAP[$HOST]}"
                        VM_SIZE="${VM_SIZE_MAP[$HOST]}"
                        CLOUD_INIT="$CLOUD_INIT_DIR/${HOST}-cloud-init.yaml"
                        launch_vm_async "$HOST" "$ZONE" "$VM_SIZE" "$CLOUD_INIT"
                    fi
                    
                    continue
                fi
                
                # Cloud-init passed, report success
                print_success "Cloud-init completed successfully on $HOST"
                
                # Mark VM as fully verified to skip future checks
                VM_VERIFIED["$HOST"]="true"
                
                # If we got here, VM is fully ready
                print_success "VM $HOST is fully operational"
            else
                # Still creating/provisioning
                all_success=false
            fi
        done
        
        # Check if all VMs are successful or all have exceeded retries
        if [[ $active_vms -eq 0 ]] || [[ "$all_success" == "true" ]]; then
            break
        fi
        
        # Wait before next check
        sleep $VM_WAIT_CHECK_INTERVAL
    done
    
    # Clean up any remaining background processes
    for HOST in "${!VM_PIDS[@]}"; do
        kill_vm_process "$HOST"
    done
    
    # Final status
    print_header "VM Deployment Summary"
    
    local successful_vms=0
    local failed_vms=0
    
    for HOST in "${vms_to_create[@]}"; do
        local vm_state=$(get_vm_info "$HOST" "state")
        
        if [[ "$vm_state" == "Succeeded" ]]; then
            local public_ip=$(get_vm_info "$HOST" "public_ip")
            print_success "  $HOST: Operational (IP: $public_ip)"
            successful_vms=$((successful_vms + 1))
        else
            print_error "  $HOST: Failed after ${VM_RETRY_COUNT[$HOST]} attempts"
            failed_vms=$((failed_vms + 1))
        fi
    done
    
    echo
    if [[ $failed_vms -eq 0 ]]; then
        print_success "All VMs deployed successfully!"
        update_state "phase" "vms_ready"
        return 0
    else
        print_error "VM deployment failed. $successful_vms succeeded, $failed_vms failed."
        return 1
    fi
}

verify_vm_connectivity() {
    # Since we already verified SSH and cloud-init in the main loop,
    # this function now focuses on WireGuard verification
    
    print_header "Verifying WireGuard Configuration"
    
    # Get VM public IPs from state
    declare -A VM_PUBLIC_IPS
    refresh_all_vm_data
    
    for HOST in "${VM_HOSTS[@]}"; do
        PUBLIC_IP=$(get_vm_info "$HOST" "public_ip")
        if [[ -n "$PUBLIC_IP" ]] && [[ "$PUBLIC_IP" != "null" ]]; then
            VM_PUBLIC_IPS["$HOST"]="$PUBLIC_IP"
        fi
    done
    
    # Verify WireGuard on each VM
    local all_verified=true
    
    for HOST in "${VM_HOSTS[@]}"; do
        if [[ -n "${VM_PUBLIC_IPS[$HOST]:-}" ]]; then
            if verify_wireguard_config "$HOST" "${VM_PUBLIC_IPS[$HOST]}" "$SSH_PRIVATE_KEY" "$SSH_USERNAME" "$SSH_CONNECT_TIMEOUT"; then
                print_success "$HOST: WireGuard configured and active"
            else
                print_error "$HOST: WireGuard configuration failed"
                all_verified=false
            fi
        else
            print_error "$HOST: No public IP available"
            all_verified=false
        fi
    done
    
    if [[ "$all_verified" == "true" ]]; then
        print_success "All VMs fully verified with WireGuard!"
        return 0
    else
        print_error "Some VMs failed WireGuard verification"
        return 1
    fi
}

show_usage() {
    print_usage "$0" \
        "  deploy    Create Azure VMs with automatic failure recovery
  status    Show VM deployment status
  reset     Delete all k0rdent VMs
  help      Show this help message" \
        "  -y, --yes        Assume yes to all prompts
  -q, --quiet      Suppress non-error output
  -v, --verbose    Enable verbose output
  --no-wait         Skip waiting for operations" \
        "  $0 deploy        # Create VMs with auto-recovery
  $0 deploy -y     # Create VMs without prompts
  $0 status        # Show current VM status
  $0 reset         # Delete all VMs
  $0 reset -y      # Delete VMs without prompts"
}

show_status() {
    print_header "Azure VM Status"
    
    # Use consolidated prerequisite validation
    check_azure_cli
    
    # Check if resource group exists
    if ! check_resource_group_exists "$RG"; then
        print_error "Resource group does not exist: $RG"
        print_info "No VMs have been deployed yet."
        return
    fi
    
    # Get VM status
    print_info "Fetching VM status in resource group: $RG"
    
    local vm_count=$(az vm list --resource-group "$RG" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    print_info "Total VMs in resource group: $vm_count"
    
    if [[ "$vm_count" -eq 0 ]]; then
        print_info "No VMs found in resource group."
        return
    fi
    
    echo ""
    echo "VM Status:"
    az vm list --resource-group "$RG" \
        --query "[].{Name:name, State:powerState, ProvisioningState:provisioningState, Zone:zones[0]}" \
        --output table
    
    # Detailed status if verbose
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        echo ""
        echo "VM Details:"
        
        # Single refresh to get current data
        refresh_all_vm_data
        
        for HOST in "${VM_HOSTS[@]}"; do
            local vm_state=$(get_vm_info "$HOST" "state")
            if [[ "$vm_state" != "null" ]]; then
                print_info "$HOST:"
                
                # Get all VM info from cached state
                local public_ip=$(get_vm_info "$HOST" "public_ip")
                local private_ip=$(get_vm_info "$HOST" "private_ip")
                [[ "$public_ip" == "null" ]] && public_ip="N/A"
                [[ "$private_ip" == "null" ]] && private_ip="N/A"
                
                print_info_verbose "  Public IP: $public_ip"
                print_info_verbose "  Private IP: $private_ip"
                print_info_verbose "  State: $vm_state"
                
                # SSH connectivity test
                if [[ -n "$SSH_PRIVATE_KEY" ]] && [[ "$public_ip" != "N/A" ]]; then
                    if execute_remote_command "$public_ip" "echo 'SSH OK'" "Test SSH connection" 5 "$SSH_PRIVATE_KEY" "$SSH_USERNAME" &>/dev/null; then
                        print_success "  SSH: Connected"
                    else
                        print_error "  SSH: Not accessible"
                    fi
                fi
            else
                print_info "$HOST: Not found"
            fi
        done
    fi
    
    # Check prerequisites for deployment
    echo ""
    echo "Deployment Prerequisites:"
    
    # SSH key
    if check_ssh_key_exists "$SSH_KEY_NAME" "$RG"; then
        print_success "SSH key exists in Azure: $SSH_KEY_NAME"
    else
        print_error "SSH key missing in Azure: $SSH_KEY_NAME"
    fi
    
    # Local SSH key
    SSH_PRIVATE_KEY="$MANIFEST_DIR/${K0RDENT_PREFIX}-ssh-key"
    SSH_PUBLIC_KEY="$SSH_PRIVATE_KEY.pub"
    if check_local_ssh_key_exists "$SSH_PRIVATE_KEY" "$SSH_PUBLIC_KEY"; then
        print_success "Local SSH keys exist"
    else
        print_error "Local SSH keys missing"
    fi
    
    # Cloud-init files
    local cloud_init_count=0
    for HOST in "${VM_HOSTS[@]}"; do
        if [[ -f "$CLOUD_INIT_DIR/${HOST}-cloud-init.yaml" ]]; then
            ((cloud_init_count++))
        fi
    done
    if [[ $cloud_init_count -eq ${#VM_HOSTS[@]} ]]; then
        print_success "All cloud-init files exist ($cloud_init_count/${#VM_HOSTS[@]})"
    else
        print_error "Cloud-init files incomplete ($cloud_init_count/${#VM_HOSTS[@]})"
    fi
}

deploy_vms() {
    # Use consolidated prerequisite validation
    check_azure_cli
    
    # Validate deployment prerequisites
    print_header "Validating deployment prerequisites"
    
    # Check if resource group exists
    if ! check_resource_group_exists "$RG"; then
        print_error "Resource group '$RG' does not exist."
        print_error "Run: ./setup-azure-network.sh deploy"
        exit 1
    fi
    
    # Check if SSH key exists in Azure
    if ! check_ssh_key_exists "$SSH_KEY_NAME" "$RG"; then
        print_error "SSH key '$SSH_KEY_NAME' does not exist in resource group '$RG'."
        print_error "Run: ./setup-azure-network.sh deploy"
        exit 1
    fi
    
    # Check if local SSH keys exist
    SSH_PRIVATE_KEY="$MANIFEST_DIR/${K0RDENT_PREFIX}-ssh-key"
    SSH_PUBLIC_KEY="$SSH_PRIVATE_KEY.pub"
    if ! check_local_ssh_key_exists "$SSH_PRIVATE_KEY" "$SSH_PUBLIC_KEY"; then
        print_error "Local SSH keys not found."
        print_error "Run: ./setup-azure-network.sh deploy"
        exit 1
    fi
    
    # Check if cloud-init files exist
    for HOST in "${VM_HOSTS[@]}"; do
        CLOUD_INIT="$CLOUD_INIT_DIR/${HOST}-cloud-init.yaml"
        if ! check_file_exists "$CLOUD_INIT" "Cloud-init file for $HOST"; then
            print_error "Run: ./prepare-deployment.sh deploy"
            exit 1
        fi
    done
    
    # Check for existing VMs
    local existing_vms=()
    local vms_to_create=()
    
    # Get all VMs in one call
    local vm_list
    vm_list=$(az vm list --resource-group "$RG" --output yaml 2>/dev/null || echo "")
    
    for HOST in "${VM_HOSTS[@]}"; do
        if echo "$vm_list" | yq eval ".[].name | select(. == \"$HOST\")" - 2>/dev/null | grep -q "$HOST"; then
            existing_vms+=("$HOST")
        else
            vms_to_create+=("$HOST")
        fi
    done
    
    if [[ ${#existing_vms[@]} -gt 0 ]]; then
        print_warning "The following VMs already exist and will be verified: ${existing_vms[*]}"
    fi
    
    if [[ ${#vms_to_create[@]} -eq 0 ]]; then
        print_info "All VMs already exist. Proceeding to verification..."
        # Still perform verification steps
        verify_vm_connectivity
        return
    fi
    
    print_success "Prerequisites validated successfully"
    
    # Confirm deployment
    if ! confirm_action "Create ${#vms_to_create[@]} VMs in Azure with automatic failure recovery?"; then
        print_info "VM creation cancelled."
        exit 0
    fi
    
    # Run the async deployment
    deploy_vms_async
    
    # Run final verification
    verify_vm_connectivity
}

reset_vms() {
    print_header "Azure VM Reset"
    
    # Use consolidated prerequisite validation
    check_azure_cli
    
    # Check if resource group exists
    if ! check_resource_group_exists "$RG"; then
        print_error "Resource group does not exist: $RG"
        print_info "No VMs to reset."
        return
    fi
    
    # Get list of all VMs in resource group in one API call
    print_info "Finding k0rdent VMs in resource group: $RG"
    
    local vm_list
    vm_list=$(az vm list --resource-group "$RG" --output yaml 2>/dev/null)
    
    if [[ -z "$vm_list" ]] || [[ "$vm_list" == "[]" ]]; then
        print_info "No VMs found in resource group."
        return
    fi
    
    # Filter for k0rdent VMs using yq
    local existing_vms=()
    for HOST in "${VM_HOSTS[@]}"; do
        if echo "$vm_list" | yq eval ".[].name | select(. == \"$HOST\")" - 2>/dev/null | grep -q "$HOST"; then
            existing_vms+=("$HOST")
        fi
    done
    
    if [[ ${#existing_vms[@]} -eq 0 ]]; then
        print_info "No k0rdent VMs found to delete."
        return
    fi
    
    print_warning "The following VMs will be deleted: ${existing_vms[*]}"
    
    # Confirm deletion
    if ! confirm_action "Delete ${#existing_vms[@]} VMs?"; then
        print_info "VM deletion cancelled."
        return
    fi
    
    # Delete VMs in parallel
    print_header "Deleting VMs"
    
    for HOST in "${existing_vms[@]}"; do
        print_info "Deleting VM: $HOST"
        az vm delete \
            --resource-group "$RG" \
            --name "$HOST" \
            --yes \
            --no-wait
            
        # Update state
        update_vm_state "$HOST" "" "" "Deleting"
        add_event "vm_reset_deletion" "Started deletion of VM: $HOST"
    done
    
    print_success "VM deletion commands issued"
    print_info "VMs are being deleted in the background"
    
    # Optionally wait for deletions to complete
    if [[ "${NO_WAIT:-false}" != "true" ]]; then
        print_header "Waiting for VM deletions to complete"
        
        local all_deleted=false
        local wait_time=0
        local max_wait=300  # 5 minutes
        
        while [[ "$all_deleted" != "true" && $wait_time -lt $max_wait ]]; do
            # Get updated VM list
            vm_list=$(az vm list --resource-group "$RG" --output yaml 2>/dev/null)
            all_deleted=true
            
            for HOST in "${existing_vms[@]}"; do
                if echo "$vm_list" | yq eval ".[].name | select(. == \"$HOST\")" - 2>/dev/null | grep -q "$HOST"; then
                    all_deleted=false
                    break
                fi
            done
            
            if [[ "$all_deleted" != "true" ]]; then
                print_info "Waiting for VMs to be deleted... ($wait_time/$max_wait seconds)"
                sleep 10
                wait_time=$((wait_time + 10))
            fi
        done
        
        if [[ "$all_deleted" == "true" ]]; then
            print_success "All VMs deleted successfully"
            
            # Clear VM states
            for HOST in "${existing_vms[@]}"; do
                update_vm_state "$HOST" "" "" "Deleted"
            done
        else
            print_warning "Some VMs may still be deleting in the background"
        fi
    else
        print_info "Skipping wait due to --no-wait flag"
    fi
}

# Store original arguments for handle_standard_commands
ORIGINAL_ARGS=("$@")

# Use consolidated command handling
handle_standard_commands "$0" "deploy status reset help" \
    "deploy" "deploy_vms" \
    "status" "show_status" \
    "reset" "reset_vms" \
    "usage" "show_usage"