#!/usr/bin/env bash

# Script: create-azure-vms.sh
# Purpose: Create 5 ARM64 Debian 12 VMs with WireGuard configuration and verification
# Usage: bash create-azure-vms.sh [command] [options]
# Prereq: Run setup-azure-network.sh and generate-cloud-init.sh first.

set -euo pipefail

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh

# Script-specific functions
verify_vm_connectivity() {
    # ---- VM Verification ----
    
    print_header "Verifying VM Configuration"
    
    # Get VM public IP addresses
    declare -A VM_PUBLIC_IPS
    print_info_quiet "Retrieving VM public IP addresses..."
    
    for HOST in "${VM_HOSTS[@]}"; do
        PUBLIC_IP=$(az vm show --resource-group "$RG" --name "$HOST" --show-details --query "publicIps" -o tsv 2>/dev/null || echo "")
        if [[ -z "$PUBLIC_IP" ]]; then
            print_error "Could not retrieve public IP for $HOST"
            exit 1
        fi
        VM_PUBLIC_IPS["$HOST"]="$PUBLIC_IP"
        print_info_quiet "  $HOST: $PUBLIC_IP"
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
    
    while [[ "$ALL_VERIFIED" != "true" && $VERIFICATION_ATTEMPTS -lt $VERIFICATION_RETRY_COUNT ]]; do
        VERIFICATION_ATTEMPTS=$((VERIFICATION_ATTEMPTS + 1))
        
        if [[ $VERIFICATION_ATTEMPTS -gt 1 ]]; then
            print_info_verbose "Verification attempt $VERIFICATION_ATTEMPTS of $VERIFICATION_RETRY_COUNT"
            print_info_verbose "Waiting ${VERIFICATION_RETRY_DELAY_SECONDS}s before retry..."
            sleep $VERIFICATION_RETRY_DELAY_SECONDS
        fi
        
        # Test SSH connectivity for all VMs
        if [[ "$QUIET_MODE" != "true" ]]; then
            print_header "Testing SSH Connectivity (Attempt $VERIFICATION_ATTEMPTS)"
        fi
        
        for HOST in "${VM_HOSTS[@]}"; do
            if [[ "${SSH_VERIFIED[$HOST]:-false}" == "false" ]]; then
                if test_ssh_connectivity "$HOST" "${VM_PUBLIC_IPS[$HOST]}" "$SSH_PRIVATE_KEY" "$ADMIN_USER" "$SSH_TIMEOUT_SECONDS"; then
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
                if wait_for_cloud_init "$HOST" "${VM_PUBLIC_IPS[$HOST]}" "$SSH_PRIVATE_KEY" "$ADMIN_USER" "$CLOUD_INIT_TIMEOUT_MINUTES" "$CLOUD_INIT_CHECK_INTERVAL_SECONDS"; then
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
                if verify_wireguard_config "$HOST" "${VM_PUBLIC_IPS[$HOST]}" "$SSH_PRIVATE_KEY" "$ADMIN_USER" "$SSH_TIMEOUT_SECONDS"; then
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
    
    # Check Azure CLI
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
        for HOST in "${VM_HOSTS[@]}"; do
            if az vm show --resource-group "$RG" --name "$HOST" &>/dev/null; then
                print_info "$HOST:"
                
                # Get public IP
                local public_ip=$(az vm show --resource-group "$RG" --name "$HOST" --show-details --query "publicIps" -o tsv 2>/dev/null || echo "N/A")
                print_info_verbose "  Public IP: $public_ip"
                
                # Get private IP
                local private_ip=$(az vm show --resource-group "$RG" --name "$HOST" --show-details --query "privateIps" -o tsv 2>/dev/null || echo "N/A")
                print_info_verbose "  Private IP: $private_ip"
                
                # Get VM size and priority
                local vm_size=$(az vm show --resource-group "$RG" --name "$HOST" --query "hardwareProfile.vmSize" -o tsv 2>/dev/null || echo "N/A")
                local priority=$(az vm show --resource-group "$RG" --name "$HOST" --query "priority" -o tsv 2>/dev/null || echo "Regular")
                print_info_verbose "  Size: $vm_size (Priority: $priority)"
                
                # SSH connectivity test
                if [[ -n "$SSH_PRIVATE_KEY" ]] && [[ "$public_ip" != "N/A" ]]; then
                    if ssh -i "$SSH_PRIVATE_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$ADMIN_USER@$public_ip" "echo 'SSH OK'" &>/dev/null; then
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
        if [[ -f "$CLOUDINITS/${HOST}-cloud-init.yaml" ]]; then
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
    # Check Azure CLI
    check_azure_cli
    
    # Validate prerequisites
    print_header "Validating prerequisites"
    
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
        CLOUD_INIT="$CLOUDINITS/${HOST}-cloud-init.yaml"
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
        CLOUD_INIT="$CLOUDINITS/${HOST}-cloud-init.yaml"
        
        print_info_quiet "Starting VM creation: $HOST (zone $ZONE, size $VM_SIZE)"
        
        # Build VM creation command based on priority type
        VM_CREATE_CMD="az vm create \
            --resource-group $RG \
            --name $HOST \
            --image $IMAGE \
            --size $VM_SIZE \
            --priority $PRIORITY \
            --zone $ZONE \
            --admin-username $ADMIN_USER \
            --ssh-key-name $SSH_KEY_NAME \
            --vnet-name $VNET_NAME \
            --subnet $SUBNET_NAME \
            --nsg $NSG_NAME \
            --public-ip-sku Standard \
            --custom-data $CLOUD_INIT \
            --os-disk-size-gb 64 \
            --no-wait"
        
        # Add eviction policy only for Spot instances
        if [[ "$PRIORITY" == "Spot" ]]; then
            VM_CREATE_CMD="$VM_CREATE_CMD --eviction-policy $EVICTION_POLICY"
        fi
        
        # Execute the VM creation command (non-blocking)
        eval "$VM_CREATE_CMD"
    done
    
    print_success "All VM creation jobs started in parallel"
    
    # ---- Wait for VMs to be ready ----
    
    # If we created any VMs, wait for them
    if [[ ${#vms_to_create[@]} -gt 0 ]]; then
        print_header "Waiting for new VMs to become ready"
        print_info_quiet "Timeout: $VM_WAIT_TIMEOUT_MINUTES minutes, Check interval: $VM_CHECK_INTERVAL_SECONDS seconds"
        
        TIMEOUT_SECONDS=$((VM_WAIT_TIMEOUT_MINUTES * 60))
        ELAPSED_SECONDS=0
        
        while [[ $ELAPSED_SECONDS -lt $TIMEOUT_SECONDS ]]; do
        if [[ "$QUIET_MODE" != "true" ]]; then
            echo
            print_info "Checking VM status... (elapsed: ${ELAPSED_SECONDS}s / ${TIMEOUT_SECONDS}s)"
        fi
        
        ALL_READY=true
        VM_STATUS_OUTPUT=""
        
        # Check status of VMs we're creating
        for HOST in "${vms_to_create[@]}"; do
            VM_STATE=$(az vm show --resource-group "$RG" --name "$HOST" --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
            
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
            break
        fi
        
        if [[ $ELAPSED_SECONDS -lt $TIMEOUT_SECONDS ]]; then
            print_info_verbose "Waiting $VM_CHECK_INTERVAL_SECONDS seconds before next check..."
            sleep $VM_CHECK_INTERVAL_SECONDS
            ELAPSED_SECONDS=$((ELAPSED_SECONDS + VM_CHECK_INTERVAL_SECONDS))
        fi
    done
    
    if [[ "$ALL_READY" != "true" ]]; then
        print_error "Timeout reached! Not all VMs are ready after $VM_WAIT_TIMEOUT_MINUTES minutes."
        print_info "You can check VM status with: $0 status"
        exit 1
    fi
    fi  # End of if vms_to_create > 0
    
    # Call the verification function
    verify_vm_connectivity
}

# Main execution
# Parse command line arguments
COMMAND="${1:-}"
shift || true

# Parse options
parse_result=0
parse_common_args "$@" || parse_result=$?

if [[ $parse_result -eq 1 ]]; then
    # Help was requested
    show_usage
    exit 0
elif [[ $parse_result -eq 2 ]]; then
    # Unknown option
    show_usage
    exit 1
fi

# Check command support
SUPPORTED_COMMANDS="deploy status help"
if [[ -z "$COMMAND" ]]; then
    show_usage
    exit 1
fi

# Handle commands
case "$COMMAND" in
    "deploy")
        deploy_vms
        ;;
    "status")
        show_status
        ;;
    "help")
        show_usage
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac