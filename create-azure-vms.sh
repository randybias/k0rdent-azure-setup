#!/usr/bin/env bash

# Script: create-azure-vms.sh
# Purpose: Create 5 ARM64 Debian 12 Spot VMs in southeastasia (zones 2/3)
#          Each VM is provisioned with its own cloud-init for WireGuard.
# Usage: bash create-azure-vms.sh
# Prereq: Run setup-azure-network.sh and generate-cloud-init.sh first.

set -euo pipefail

# Load central configuration and common functions
source ./k0rdent-config.sh
source ./common-functions.sh

# Check if Azure CLI is installed and user is authenticated
check_azure_cli

# Validate prerequisites
print_header "Validating prerequisites"

# Check if resource group exists
if ! check_resource_group_exists "$RG"; then
    print_error "Resource group '$RG' does not exist."
    print_error "Run setup-azure-network.sh first."
    exit 1
fi

# Check if SSH key exists in Azure
if ! check_ssh_key_exists "$SSH_KEY_NAME" "$RG"; then
    print_error "SSH key '$SSH_KEY_NAME' does not exist in resource group '$RG'."
    print_error "Run setup-azure-network.sh first."
    exit 1
fi

# Check if local SSH keys exist
SSH_PRIVATE_KEY="$MANIFEST_DIR/${K0RDENT_PREFIX}-ssh-key"
SSH_PUBLIC_KEY="$SSH_PRIVATE_KEY.pub"
if ! check_local_ssh_key_exists "$SSH_PRIVATE_KEY" "$SSH_PUBLIC_KEY"; then
    print_error "Local SSH keys not found at '$SSH_PRIVATE_KEY' and '$SSH_PUBLIC_KEY'."
    print_error "Run setup-azure-network.sh first."
    exit 1
fi

# Check if cloud-init files exist
for HOST in "${VM_HOSTS[@]}"; do
    CLOUD_INIT="$CLOUDINITS/${HOST}-cloud-init.yaml"
    if ! check_file_exists "$CLOUD_INIT" "Cloud-init file for $HOST"; then
        print_error "Run generate-cloud-init.sh first."
        exit 1
    fi
done

print_success "Prerequisites validated successfully"

# ---- Parallel VM Creation ----

print_header "Creating VMs in parallel"

# Start all VM creations in parallel
for HOST in "${VM_HOSTS[@]}"; do
  ZONE="${VM_ZONES[$HOST]}"
  CLOUD_INIT="$CLOUDINITS/${HOST}-cloud-init.yaml"

  print_info "Starting VM creation: $HOST (zone $ZONE)"

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

print_header "Waiting for VMs to become ready"
print_info "Timeout: $VM_WAIT_TIMEOUT_MINUTES minutes, Check interval: $VM_CHECK_INTERVAL_SECONDS seconds"

TIMEOUT_SECONDS=$((VM_WAIT_TIMEOUT_MINUTES * 60))
ELAPSED_SECONDS=0

while [[ $ELAPSED_SECONDS -lt $TIMEOUT_SECONDS ]]; do
    echo
    print_info "Checking VM status... (elapsed: ${ELAPSED_SECONDS}s / ${TIMEOUT_SECONDS}s)"
    
    ALL_READY=true
    VM_STATUS_OUTPUT=""
    
    # Check each VM status
    for HOST in "${VM_HOSTS[@]}"; do
        VM_STATE=$(az vm show --resource-group "$RG" --name "$HOST" --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
        POWER_STATE=$(az vm show --resource-group "$RG" --name "$HOST" --query "instanceView.statuses[1].displayStatus" -o tsv 2>/dev/null || echo "Unknown")
        
        VM_STATUS_OUTPUT="$VM_STATUS_OUTPUT\n  $HOST: $VM_STATE / $POWER_STATE"
        
        if [[ "$VM_STATE" != "Succeeded" ]] || [[ "$POWER_STATE" != "VM running" ]]; then
            ALL_READY=false
        fi
    done
    
    echo -e "$VM_STATUS_OUTPUT"
    
    if [[ "$ALL_READY" == "true" ]]; then
        echo
        print_success "All VMs are ready and running!"
        break
    fi
    
    if [[ $ELAPSED_SECONDS -lt $TIMEOUT_SECONDS ]]; then
        print_info "Waiting $VM_CHECK_INTERVAL_SECONDS seconds before next check..."
        sleep $VM_CHECK_INTERVAL_SECONDS
        ELAPSED_SECONDS=$((ELAPSED_SECONDS + VM_CHECK_INTERVAL_SECONDS))
    fi
done

if [[ "$ALL_READY" != "true" ]]; then
    print_error "Timeout reached! Not all VMs are ready after $VM_WAIT_TIMEOUT_MINUTES minutes."
    print_info "You can check VM status manually with: az vm list --resource-group $RG --query '[].{Name:name, ProvisioningState:provisioningState, PowerState:instanceView.statuses[1].displayStatus}' -o table"
    exit 1
fi

# ---- Final Status ----

print_header "Deployment Complete"

if [[ "$PRIORITY" == "Spot" ]]; then
    print_success "All VMs successfully launched as Spot instances."
else
    print_success "All VMs successfully launched as Regular instances."
fi

echo
print_info "VM Public IP Addresses:"
az vm list-ip-addresses --resource-group "$RG" --query "[].{Name:virtualMachine.name, PublicIP:virtualMachine.network.publicIpAddresses[0].ipAddress, PrivateIP:virtualMachine.network.privateIpAddresses[0]}" -o table

echo
print_info "Cloud-init may still be running on the VMs. You can monitor progress by:"
print_info "  1. SSH to each VM: ssh -i ./azure-resources/${K0RDENT_PREFIX}-ssh-key $ADMIN_USER@<PUBLIC_IP>"
print_info "  2. Check cloud-init status: sudo cloud-init status"
print_info "  3. View cloud-init logs: sudo journalctl -u cloud-init-final"

echo
print_info "Next steps:"
print_info "  1. Wait for cloud-init to complete WireGuard setup"
print_info "  2. Configure your laptop WireGuard client with the generated configs"
print_info "  3. Install and configure k0rdent on the VMs"
