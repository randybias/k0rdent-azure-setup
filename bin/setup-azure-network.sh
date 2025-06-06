#!/usr/bin/env bash

# Script: setup-azure-network.sh
# Purpose: Create Azure resource group, VNet, subnet, and NSG
#          Allow SSH (22/tcp) and WireGuard (UDP/<RANDOM_PORT>) to VMs.
#          Prepares environment for ARM64 spot VMs in supported zones.
#          Tracks all created resources in a manifest for cleanup.
# Usage: bash setup-azure-network.sh [command] [options]

set -euo pipefail

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh

# Script-specific variables
MANIFEST="$AZURE_MANIFEST"

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  deploy    Create Azure network resources
  uninstall Delete Azure resources (keep manifest)
  reset     Delete Azure resources and manifest
  status    Show Azure resource status
  help      Show this help message" \
        "  -y, --yes        Assume yes to all prompts
  -q, --quiet      Suppress non-error output
  -v, --verbose    Enable verbose output" \
        "  $0 deploy        # Create resources interactively
  $0 deploy -y     # Create resources without prompts
  $0 status        # Show current resource status
  $0 reset -y      # Delete everything without confirmation"
}

show_status() {
    # Prepare status information
    local SSH_PRIVATE_KEY="$MANIFEST_DIR/${K0RDENT_PREFIX}-ssh-key"
    local SSH_PUBLIC_KEY="$SSH_PRIVATE_KEY.pub"
    local port_info=""
    if [[ -f "$WG_PORT_FILE" ]]; then
        port_info=$(cat "$WG_PORT_FILE")
    fi
    
    local resource_count=0
    if [[ -f "$AZURE_MANIFEST" ]]; then
        resource_count=$(tail -n +2 "$AZURE_MANIFEST" 2>/dev/null | wc -l)
    fi
    
    # Use generic status display framework
    display_status "Azure Network Resources Status" \
        "file:$AZURE_MANIFEST:Azure manifest file" \
        "info:$resource_count:Total Azure resources" \
        "file:$SSH_PRIVATE_KEY:SSH private key" \
        "file:$SSH_PUBLIC_KEY:SSH public key" \
        "file:$WG_PORT_FILE:WireGuard port file" \
        ${port_info:+"info:$port_info:WireGuard port configured"}
    
    # Check Azure resources if manifest exists
    if [[ -f "$AZURE_MANIFEST" ]] && check_resource_group_exists "$RG"; then
        echo
        print_info "=== Azure Resource Details ==="
        
        # Check specific Azure resources
        if check_azure_resource_exists "group" "$RG"; then
            print_success "Resource group: $RG"
        else
            print_error "Resource group missing: $RG"
        fi
        
        if check_azure_resource_exists "vnet" "$VNET_NAME" "$RG"; then
            print_success "Virtual Network: $VNET_NAME ($VNET_PREFIX)"
        else
            print_error "Virtual Network missing: $VNET_NAME"
        fi
        
        if check_azure_resource_exists "nsg" "$NSG_NAME" "$RG"; then
            print_success "Network Security Group: $NSG_NAME"
            
            # Show NSG rules if verbose
            if [[ "$VERBOSE_MODE" == "true" ]]; then
                echo
                print_info "NSG Rules:"
                az network nsg rule list --resource-group "$RG" --nsg-name "$NSG_NAME" \
                    --query "[].{Name:name, Port:destinationPortRange, Protocol:protocol, Priority:priority}" \
                    --output table
            fi
        else
            print_error "Network Security Group missing: $NSG_NAME"
        fi
        
        if check_azure_resource_exists "sshkey" "$SSH_KEY_NAME" "$RG"; then
            print_success "SSH key in Azure: $SSH_KEY_NAME"
        else
            print_error "SSH key missing in Azure: $SSH_KEY_NAME"
        fi
    elif [[ -f "$AZURE_MANIFEST" ]]; then
        echo
        print_warning "Manifest exists but resource group '$RG' not found"
        print_info "Resources may have been deleted externally"
    fi
}

deploy_resources() {
    # Check prerequisites using generic framework
    if ! check_prerequisites "setup-azure-network" \
        "azure_cli:Azure CLI not available or not logged in:Run 'az login'" \
        "file:$WG_PORT_FILE:WireGuard port file not found:Run: bash bin/prepare-deployment.sh deploy"; then
        exit 1
    fi
    
    # Read WireGuard port
    WIREGUARD_PORT=$(cat "$WG_PORT_FILE")
    print_info "Using WireGuard port: $WIREGUARD_PORT"
    
    # Check if resources already exist
    if [[ -f "$AZURE_MANIFEST" ]]; then
        print_warning "Azure manifest already exists."
        if check_azure_resource_exists "group" "$RG"; then
            print_error "Resource group '$RG' already exists. Use 'reset' to clean up first."
            exit 1
        fi
        print_warning "Manifest exists but resource group is missing. Creating new resources..."
    fi
    
    # Create manifest
    if [[ ! -f "$AZURE_MANIFEST" ]]; then
        init_manifest "$AZURE_MANIFEST"
    fi
    
    # Create resource group
    if ! log_azure_command "Creating resource group: $RG in $LOCATION" \
        az group create --name "$RG" --location "$LOCATION"; then
        handle_error ${LINENO} "az group create"
    fi
    add_resource_to_manifest "resource_group" "$RG" "primary_resource_group"
    
    # Generate local SSH key pair
    SSH_PRIVATE_KEY="$MANIFEST_DIR/${K0RDENT_PREFIX}-ssh-key"
    SSH_PUBLIC_KEY="$SSH_PRIVATE_KEY.pub"
    
    print_info_quiet "Generating local SSH key pair: $SSH_PRIVATE_KEY"
    if [[ ! -f "$SSH_PRIVATE_KEY" ]]; then
        ssh-keygen -t rsa -b 4096 -f "$SSH_PRIVATE_KEY" -N "" -C "k0rdent-${K0RDENT_PREFIX}"
        print_success "SSH key pair generated locally"
    else
        print_info_verbose "SSH key pair already exists locally"
    fi
    
    # Import public key to Azure
    if ! log_azure_command "Importing SSH public key to Azure: $SSH_KEY_NAME" \
        az sshkey create \
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
    if ! log_azure_command "Creating Virtual Network: $VNET_NAME ($VNET_PREFIX)" \
        az network vnet create \
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
    if ! log_azure_command "Creating Network Security Group: $NSG_NAME" \
        az network nsg create \
        --resource-group "$RG" \
        --name "$NSG_NAME" \
        --location "$LOCATION"; then
        handle_error ${LINENO} "az network nsg create"
    fi
    add_resource_to_manifest "network_security_group" "$NSG_NAME" ""
    
    # Add WireGuard NSG rule
    if ! log_azure_command "Adding NSG rule to allow WireGuard UDP port $WIREGUARD_PORT" \
        az network nsg rule create \
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
    if ! log_azure_command "Adding NSG rule to allow SSH (22/tcp)" \
        az network nsg rule create \
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
    if ! log_azure_command "Associating NSG with subnet" \
        az network vnet subnet update \
        --resource-group "$RG" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --network-security-group "$NSG_NAME"; then
        handle_error ${LINENO} "az network vnet subnet update"
    fi
    
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo
        print_success "Network, subnet, NSG, and SSH key are ready."
        print_success "Resource manifest created at: $AZURE_MANIFEST"
        print_success "Using WireGuard port: $WIREGUARD_PORT"
        print_success "SSH key '$SSH_KEY_NAME' created for VM access"
        echo
        print_info "Next: Create Azure VMs with the prepared cloud-init files."
    fi
}

uninstall_resources() {
    if [[ ! -f "$AZURE_MANIFEST" ]]; then
        print_info "No manifest found. Nothing to uninstall."
        exit 0
    fi
    
    if ! check_azure_resource_exists "group" "$RG"; then
        print_info "Resource group '$RG' does not exist. Nothing to uninstall."
        exit 0
    fi
    
    print_warning "This will delete ALL Azure resources in resource group: $RG"
    print_info "The manifest file will be preserved for reference."
    
    if confirm_action "Are you sure you want to delete all Azure resources?"; then
        log_azure_command "Deleting resource group: $RG" \
            az group delete --name "$RG" --yes --no-wait
        print_success "Resource group deletion initiated (running in background)"
        print_info "You can check deletion status with: az group show --name $RG"
    else
        print_info "Uninstall cancelled."
    fi
}

reset_resources() {
    print_warning "This will delete ALL Azure resources and the manifest!"
    
    if [[ -f "$AZURE_MANIFEST" ]] && check_azure_resource_exists "group" "$RG"; then
        print_warning "Resource Group to be deleted: $RG"
    fi
    
    if confirm_action "Are you sure you want to reset everything?"; then
        if check_azure_resource_exists "group" "$RG"; then
            log_azure_command "Deleting resource group: $RG" \
                az group delete --name "$RG" --yes --no-wait
            print_success "Resource group deletion initiated (running in background)"
        fi
        
        print_info_quiet "Removing manifest directory"
        rm -rf "$(dirname "$AZURE_MANIFEST")"
        print_success "Manifest directory removed"
        print_success "Azure resources reset complete"
    else
        print_info "Reset cancelled."
    fi
}

# Wrapper function for manifest operations
add_resource_to_manifest() {
    local resource_type="$1"
    local resource_name="$2"
    local additional_info="${3:-}"
    add_to_manifest "$AZURE_MANIFEST" "$resource_type" "$resource_name" "$RG" "$LOCATION" "$additional_info"
}

# Main execution
# Initialize logging
init_logging "setup-azure-network"

# Store original arguments for handle_standard_commands
ORIGINAL_ARGS=("$@")

# Use consolidated command handling
handle_standard_commands "$0" "deploy uninstall reset status help" \
    "deploy" "deploy_resources" \
    "uninstall" "uninstall_resources" \
    "reset" "reset_resources" \
    "status" "show_status" \
    "usage" "show_usage"