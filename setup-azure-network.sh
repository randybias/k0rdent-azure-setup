#!/usr/bin/env bash

# Script: setup-azure-network.sh
# Purpose: Create Azure resource group, VNet, subnet, and NSG
#          Allow SSH (22/tcp) and WireGuard (UDP/<RANDOM_PORT>) to VMs.
#          Prepares environment for ARM64 spot VMs in supported zones.
#          Tracks all created resources in a manifest for cleanup.
# Usage: bash setup-azure-network.sh [reset]

set -euo pipefail

# Load central configuration and common functions
source ./k0rdent-config.sh
source ./common-functions.sh

# Check Azure CLI prerequisites
check_azure_cli

# ---- Configuration ----
# Note: Using centralized configuration from k0rdent-config.sh
# Use manifest path from config
MANIFEST="$AZURE_MANIFEST"

# Generate random WireGuard port
WIREGUARD_PORT=$((RANDOM % 34001 + 30000))

# Handle reset argument
if [[ "${1:-}" == "reset" ]]; then
    echo "==> Resetting Azure resources and manifest..."
    if [[ -f "$AZURE_MANIFEST" ]]; then
        echo "==> WARNING: This will delete ALL Azure resources tracked in the manifest!"
        echo "==> Resource Group to be deleted: $RG"
        read -p "Are you sure? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            echo "==> Deleting resource group: $RG"
            az group delete --name "$RG" --yes --no-wait
            echo "==> Deletion initiated (running in background)"
        else
            echo "==> Reset cancelled"
            exit 0
        fi
    fi
    rm -rf "$(dirname "$AZURE_MANIFEST")"
    print_info "Manifest directory reset"
    exit 0
fi

# Only create new manifest if it doesn't exist
if [[ ! -f "$AZURE_MANIFEST" ]]; then
    init_manifest "$AZURE_MANIFEST"
else
    print_info "Manifest file already exists, checking for existing resource group..."
    if check_resource_group_exists "$RG"; then
        print_error "Resource group '$RG' already exists. Use 'reset' to clean up first."
        exit 1
    fi
fi

# Wrapper function for manifest operations
add_resource_to_manifest() {
    local resource_type="$1"
    local resource_name="$2"
    local additional_info="${3:-}"
    add_to_manifest "$AZURE_MANIFEST" "$resource_type" "$resource_name" "$RG" "$LOCATION" "$additional_info"
}

# ---- Script Start ----

# Error handling is now provided by common-functions.sh

# Create resource group
echo "==> Creating resource group: $RG in $LOCATION"
if ! az group create --name "$RG" --location "$LOCATION"; then
    handle_error ${LINENO} "az group create"
fi
add_resource_to_manifest "resource_group" "$RG" "primary_resource_group"

# Generate local SSH key pair
SSH_PRIVATE_KEY="$MANIFEST_DIR/${K0RDENT_PREFIX}-ssh-key"
SSH_PUBLIC_KEY="$SSH_PRIVATE_KEY.pub"

print_info "Generating local SSH key pair: $SSH_PRIVATE_KEY"
if [[ ! -f "$SSH_PRIVATE_KEY" ]]; then
    ssh-keygen -t rsa -b 4096 -f "$SSH_PRIVATE_KEY" -N "" -C "k0rdent-${K0RDENT_PREFIX}"
    print_success "SSH key pair generated locally"
else
    print_info "SSH key pair already exists locally"
fi

# Import public key to Azure
print_info "Importing SSH public key to Azure: $SSH_KEY_NAME"
if ! az sshkey create \
    --name "$SSH_KEY_NAME" \
    --resource-group "$RG" \
    --location "$LOCATION" \
    --public-key "@$SSH_PUBLIC_KEY"; then
    handle_error ${LINENO} "az sshkey create"
fi
add_resource_to_manifest "ssh_key" "$SSH_KEY_NAME" "vm_access_key"
add_resource_to_manifest "local_ssh_private_key" "$SSH_PRIVATE_KEY" "local_private_key_file"
add_resource_to_manifest "local_ssh_public_key" "$SSH_PUBLIC_KEY" "local_public_key_file"

# Create Virtual Network
echo "==> Creating Virtual Network: $VNET_NAME ($VNET_PREFIX)"
if ! az network vnet create \
    --resource-group "$RG" \
    --name "$VNET_NAME" \
    --address-prefix "$VNET_PREFIX" \
    --subnet-name "$SUBNET_NAME" \
    --subnet-prefix "$SUBNET_PREFIX"; then
    handle_error ${LINENO} "az network vnet create"
fi
add_resource_to_manifest "virtual_network" "$VNET_NAME" "$VNET_PREFIX"
add_resource_to_manifest "subnet" "$SUBNET_NAME" "$SUBNET_PREFIX"

# Create Network Security Group
echo "==> Creating Network Security Group: $NSG_NAME"
if ! az network nsg create \
    --resource-group "$RG" \
    --name "$NSG_NAME" \
    --location "$LOCATION"; then
    handle_error ${LINENO} "az network nsg create"
fi
add_resource_to_manifest "network_security_group" "$NSG_NAME" ""

# Add WireGuard NSG rule
echo "==> Adding NSG rule to allow WireGuard UDP port $WIREGUARD_PORT from anywhere"
if ! az network nsg rule create \
    --resource-group "$RG" \
    --nsg-name "$NSG_NAME" \
    --name "AllowWireGuard" \
    --priority 1000 \
    --access Allow \
    --protocol Udp \
    --direction Inbound \
    --source-address-prefixes "*" \
    --source-port-ranges "*" \
    --destination-address-prefixes "*" \
    --destination-port-ranges "$WIREGUARD_PORT"; then
    handle_error ${LINENO} "az network nsg rule create (WireGuard)"
fi
add_resource_to_manifest "nsg_rule" "AllowWireGuard" "UDP_port_$WIREGUARD_PORT"

# Add SSH NSG rule
echo "==> Adding NSG rule to allow SSH (22/tcp) from anywhere (for troubleshooting)"
if ! az network nsg rule create \
    --resource-group "$RG" \
    --nsg-name "$NSG_NAME" \
    --name "AllowSSH" \
    --priority 1010 \
    --access Allow \
    --protocol Tcp \
    --direction Inbound \
    --source-address-prefixes "*" \
    --source-port-ranges "*" \
    --destination-address-prefixes "*" \
    --destination-port-ranges 22; then
    handle_error ${LINENO} "az network nsg rule create (SSH)"
fi
add_resource_to_manifest "nsg_rule" "AllowSSH" "TCP_port_22"

# Associate NSG with subnet
echo "==> Associating NSG with subnet"
if ! az network vnet subnet update \
    --resource-group "$RG" \
    --vnet-name "$VNET_NAME" \
    --name "$SUBNET_NAME" \
    --network-security-group "$NSG_NAME"; then
    handle_error ${LINENO} "az network vnet subnet update"
fi

# Save WireGuard port to a separate file for use by VM creation scripts
echo "$WIREGUARD_PORT" > "$WG_PORT_FILE"

echo
echo "==> Network, subnet, NSG, and SSH key are ready."
echo "==> Resource manifest created at: $AZURE_MANIFEST"
echo "==> WireGuard port ($WIREGUARD_PORT) saved to: $WG_PORT_FILE"
echo "==> SSH key '$SSH_KEY_NAME' created for VM access"
echo "==> Next: Prepare cloud-init YAML for each VM, then deploy the VMs."
echo
echo "Cleanup command:"
echo "  bash setup-azure-network.sh reset"
