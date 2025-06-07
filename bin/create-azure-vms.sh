#!/usr/bin/env bash

# Script: create-azure-vms.sh
# Purpose: Create 5 ARM64 Debian 12 VMs with WireGuard configuration and verification
# Usage: bash create-azure-vms.sh [command] [options]
# Prereq: Run setup-azure-network.sh and generate-cloud-init.sh first.

set -euo pipefail

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh
source ./etc/state-management.sh

# Script-specific functions
verify_vm_connectivity() {
    # ---- VM Verification ----
    
    print_header "Verifying VM Configuration"
    
    # Get VM public IP addresses from state (with single refresh if needed)
    declare -A VM_PUBLIC_IPS
    print_info_quiet "Retrieving VM public IP addresses..."
    
    # Single bulk refresh if state is missing or empty
    if ! state_file_exists || [[ $(get_state "vm_states" | yq eval '. | length' 2>/dev/null || echo "0") -eq 0 ]]; then
        print_info_quiet "Refreshing VM data from Azure..."
        refresh_all_vm_data
    fi
    
    # Get IPs from cached state (empty/null is OK for VMs still provisioning)
    for HOST in "${VM_HOSTS[@]}"; do
        PUBLIC_IP=$(get_vm_info "$HOST" "public_ip")
        if [[ "$PUBLIC_IP" == "null" ]]; then
            PUBLIC_IP=""  # Convert null to empty string
        fi
        VM_PUBLIC_IPS["$HOST"]="$PUBLIC_IP"
        if [[ -n "$PUBLIC_IP" ]]; then
            print_info_quiet "  $HOST: $PUBLIC_IP"
        else
            print_info_quiet "  $HOST: (no public IP yet)"
        fi
    done
    
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo
        print_info "Starting VM verification process..."
        print_info "This will test SSH connectivity, wait for cloud-init completion, and verify WireGuard configuration."
    fi
    
    # Verification tracking
    declare -A SSH_VERIFIED
    declare -A CLOUD_INIT_VERIFIED  
    declare -A WIREGUARD_VERIFIED
    
    ALL_VERIFIED=false
    VERIFICATION_ATTEMPTS=0
    
    while [[ "$ALL_VERIFIED" != "true" && $VERIFICATION_ATTEMPTS -lt $VERIFICATION_RETRIES ]]; do
        VERIFICATION_ATTEMPTS=$((VERIFICATION_ATTEMPTS + 1))
        
        if [[ $VERIFICATION_ATTEMPTS -gt 1 ]]; then
            print_info_verbose "Verification attempt $VERIFICATION_ATTEMPTS of $VERIFICATION_RETRIES"
            print_info_verbose "Waiting ${VERIFICATION_RETRY_DELAY}s before retry..."
            sleep $VERIFICATION_RETRY_DELAY
        fi
        
        # Test SSH connectivity for all VMs
        if [[ "$QUIET_MODE" != "true" ]]; then
            print_header "Testing SSH Connectivity (Attempt $VERIFICATION_ATTEMPTS)"
        fi
        
        for HOST in "${VM_HOSTS[@]}"; do
            if [[ "${SSH_VERIFIED[$HOST]:-false}" == "false" ]]; then
                if test_ssh_connectivity "$HOST" "${VM_PUBLIC_IPS[$HOST]}" "$SSH_PRIVATE_KEY" "$SSH_USERNAME" "$SSH_CONNECT_TIMEOUT"; then
                    SSH_VERIFIED["$HOST"]="true"
                fi
            fi
        done
        
        # Wait for cloud-init completion for VMs with SSH access
        if [[ "$QUIET_MODE" != "true" ]]; then
            print_header "Waiting for Cloud-Init Completion (Attempt $VERIFICATION_ATTEMPTS)"
        fi
        
        for HOST in "${VM_HOSTS[@]}"; do
            if [[ "${SSH_VERIFIED[$HOST]:-false}" == "true" && "${CLOUD_INIT_VERIFIED[$HOST]:-false}" == "false" ]]; then
                if wait_for_cloud_init "$HOST" "${VM_PUBLIC_IPS[$HOST]}" "$SSH_PRIVATE_KEY" "$SSH_USERNAME" "$CLOUD_INIT_TIMEOUT" "$CLOUD_INIT_CHECK_INTERVAL"; then
                    CLOUD_INIT_VERIFIED["$HOST"]="true"
                fi
            fi
        done
        
        # Verify WireGuard configuration for VMs with completed cloud-init
        if [[ "$QUIET_MODE" != "true" ]]; then
            print_header "Verifying WireGuard Configuration (Attempt $VERIFICATION_ATTEMPTS)"
        fi
        
        for HOST in "${VM_HOSTS[@]}"; do
            if [[ "${CLOUD_INIT_VERIFIED[$HOST]:-false}" == "true" && "${WIREGUARD_VERIFIED[$HOST]:-false}" == "false" ]]; then
                if verify_wireguard_config "$HOST" "${VM_PUBLIC_IPS[$HOST]}" "$SSH_PRIVATE_KEY" "$SSH_USERNAME" "$SSH_CONNECT_TIMEOUT"; then
                    WIREGUARD_VERIFIED["$HOST"]="true"
                fi
            fi
        done
        
        # Check if all VMs are fully verified
        ALL_VERIFIED=true
        for HOST in "${VM_HOSTS[@]}"; do
            if [[ "${SSH_VERIFIED[$HOST]:-false}" != "true" ]] || \
               [[ "${CLOUD_INIT_VERIFIED[$HOST]:-false}" != "true" ]] || \
               [[ "${WIREGUARD_VERIFIED[$HOST]:-false}" != "true" ]]; then
                ALL_VERIFIED=false
                break
            fi
        done
        
        if [[ "$ALL_VERIFIED" == "true" ]]; then
            break
        fi
    done
    
    # ---- Verification Results ----
    
    if [[ "$QUIET_MODE" != "true" ]]; then
        print_header "Verification Results"
        
        echo
        print_info "SSH Connectivity:"
        for HOST in "${VM_HOSTS[@]}"; do
            if [[ "${SSH_VERIFIED[$HOST]:-false}" == "true" ]]; then
                print_success "  $HOST: SSH accessible"
            else
                print_error "  $HOST: SSH failed"
            fi
        done
        
        echo
        print_info "Cloud-Init Status:"
        for HOST in "${VM_HOSTS[@]}"; do
            if [[ "${CLOUD_INIT_VERIFIED[$HOST]:-false}" == "true" ]]; then
                print_success "  $HOST: Cloud-init completed"
            else
                print_error "  $HOST: Cloud-init incomplete or failed"
            fi
        done
        
        echo
        print_info "WireGuard Configuration:"
        for HOST in "${VM_HOSTS[@]}"; do
            if [[ "${WIREGUARD_VERIFIED[$HOST]:-false}" == "true" ]]; then
                print_success "  $HOST: WireGuard configured and active"
            else
                print_error "  $HOST: WireGuard configuration failed"
            fi
        done
    fi
    
    # ---- Final Status ----
    
    print_header "Deployment Complete"
    
    if [[ "$ALL_VERIFIED" == "true" ]]; then
        print_success "All VMs are fully deployed and verified!"
        if [[ "$QUIET_MODE" != "true" ]]; then
            echo
            print_success "✓ SSH connectivity confirmed"
            print_success "✓ Cloud-init completed successfully"  
            print_success "✓ WireGuard configured and active"
        fi
    else
        print_warning "Some VMs failed verification. See results above for details."
        if [[ "$QUIET_MODE" != "true" ]]; then
            echo
            print_info "Troubleshooting:"
            print_info "  1. Check VM status: $0 status"
            print_info "  2. Check Azure NSG rules and VM network settings"
            print_info "  3. Review cloud-init logs on the VMs"
        fi
    fi
}

show_usage() {
    print_usage "$0" \
        "  deploy    Create Azure VMs with cloud-init
  status    Show VM deployment status
  help      Show this help message" \
        "  -y, --yes        Assume yes to all prompts
  -q, --quiet      Suppress non-error output
  -v, --verbose    Enable verbose output" \
        "  $0 deploy        # Create VMs interactively
  $0 deploy -y     # Create VMs without prompts
  $0 status        # Show current VM status
  $0 status -v     # Show detailed VM status"
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
            print_error "Run: ./generate-cloud-init.sh deploy"
            exit 1
        fi
    done
    
    # Check for existing VMs
    local existing_vms=()
    local vms_to_create=()
    for HOST in "${VM_HOSTS[@]}"; do
        if az vm show --resource-group "$RG" --name "$HOST" &>/dev/null; then
            existing_vms+=("$HOST")
        else
            vms_to_create+=("$HOST")
        fi
    done
    
    if [[ ${#existing_vms[@]} -gt 0 ]]; then
        print_warning "The following VMs already exist and will be skipped: ${existing_vms[*]}"
    fi
    
    if [[ ${#vms_to_create[@]} -eq 0 ]]; then
        print_success "All VMs already exist. Nothing to create."
        # Still perform verification steps
        verify_vm_connectivity
        return
    fi
    
    print_success "Prerequisites validated successfully"
    
    # Confirm deployment
    if ! confirm_action "Create ${#vms_to_create[@]} VMs in Azure?"; then
        print_info "VM creation cancelled."
        exit 0
    fi
    
    # ---- Parallel VM Creation ----
    
    print_header "Creating VMs in parallel"
    
    # Start all VM creations in parallel (only for VMs that don't exist)
    for HOST in "${vms_to_create[@]}"; do
        ZONE="${VM_ZONE_MAP[$HOST]}"
        VM_SIZE="${VM_SIZE_MAP[$HOST]}"
        CLOUD_INIT="$CLOUD_INIT_DIR/${HOST}-cloud-init.yaml"
        
        print_info_quiet "Starting VM creation: $HOST (zone $ZONE, size $VM_SIZE)"
        
        # Build VM creation command based on priority type
        VM_CREATE_CMD="az vm create \
            --resource-group $RG \
            --name $HOST \
            --image $AZURE_VM_IMAGE \
            --size $VM_SIZE \
            --priority $AZURE_VM_PRIORITY \
            --zone $ZONE \
            --admin-username $SSH_USERNAME \
            --ssh-key-name $SSH_KEY_NAME \
            --vnet-name $VNET_NAME \
            --subnet $SUBNET_NAME \
            --nsg $NSG_NAME \
            --public-ip-sku Standard \
            --custom-data $CLOUD_INIT \
            --os-disk-size-gb 64 \
            --no-wait"
        
        # Add eviction policy only for Spot instances
        if [[ "$AZURE_VM_PRIORITY" == "Spot" ]]; then
            VM_CREATE_CMD="$VM_CREATE_CMD --eviction-policy $AZURE_EVICTION_POLICY"
        fi
        
        # Execute the VM creation command (non-blocking)
        eval "$VM_CREATE_CMD"
        
        # Record VM creation in state
        update_vm_state "$HOST" "" "" "Creating"
        add_event "vm_creation_started" "Started creating VM: $HOST"
    done
    
    print_success "All VM creation jobs started in parallel"
    
    # ---- Wait for VMs to be ready ----
    
    # If we created any VMs, wait for them
    if [[ ${#vms_to_create[@]} -gt 0 ]]; then
        print_header "Waiting for new VMs to become ready"
        print_info_quiet "Timeout: $VM_CREATION_TIMEOUT_MINUTES minutes, Check interval: $VM_WAIT_CHECK_INTERVAL seconds"
        
        TIMEOUT_SECONDS=$((VM_CREATION_TIMEOUT_MINUTES * 60))
        ELAPSED_SECONDS=0
        
        while [[ $ELAPSED_SECONDS -lt $TIMEOUT_SECONDS ]]; do
        if [[ "$QUIET_MODE" != "true" ]]; then
            echo
            print_info "Checking VM status... (elapsed: ${ELAPSED_SECONDS}s / ${TIMEOUT_SECONDS}s)"
        fi
        
        ALL_READY=true
        VM_STATUS_OUTPUT=""
        
        # Single bulk refresh of all VM states
        refresh_all_vm_data
        
        # Check status of VMs we're creating from cached state
        for HOST in "${vms_to_create[@]}"; do
            VM_STATE=$(get_vm_info "$HOST" "state")
            if [[ "$VM_STATE" == "null" ]]; then
                VM_STATE="NotFound"
            fi
            
            VM_STATUS_OUTPUT="$VM_STATUS_OUTPUT\n  $HOST: $VM_STATE"
            
            if [[ "$VM_STATE" != "Succeeded" ]]; then
                ALL_READY=false
            fi
        done
        
        if [[ "$QUIET_MODE" != "true" ]]; then
            echo -e "$VM_STATUS_OUTPUT"
        fi
        
        if [[ "$ALL_READY" == "true" ]]; then
            echo
            print_success "All VMs are ready and running!"
            update_state "phase" "vms_ready"
            add_event "vm_deployment_completed" "All VMs successfully deployed and running"
            break
        fi
        
        if [[ $ELAPSED_SECONDS -lt $TIMEOUT_SECONDS ]]; then
            print_info_verbose "Waiting $VM_WAIT_CHECK_INTERVAL seconds before next check..."
            sleep $VM_WAIT_CHECK_INTERVAL
            ELAPSED_SECONDS=$((ELAPSED_SECONDS + VM_WAIT_CHECK_INTERVAL))
        fi
    done
    
    if [[ "$ALL_READY" != "true" ]]; then
        print_error "Timeout reached! Not all VMs are ready after $VM_CREATION_TIMEOUT_MINUTES minutes."
        print_info "You can check VM status with: $0 status"
        exit 1
    fi
    fi  # End of if vms_to_create > 0
    
    # Call the verification function
    verify_vm_connectivity
}

# Store original arguments for handle_standard_commands
ORIGINAL_ARGS=("$@")

# Use consolidated command handling
handle_standard_commands "$0" "deploy status help" \
    "deploy" "deploy_vms" \
    "status" "show_status" \
    "usage" "show_usage"