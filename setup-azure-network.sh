#!/usr/bin/env bash

# Script: setup-azure-network.sh
# Purpose: Create Azure resource group, VNet, subnet, and NSG
#          Allow SSH (22/tcp) and WireGuard (UDP/<RANDOM_PORT>) to VMs.
#          Prepares environment for ARM64 spot VMs in supported zones.
#          Tracks all created resources in a manifest for cleanup.
# Usage: bash setup-azure-network.sh [command] [options]

set -euo pipefail

# Load central configuration and common functions
source ./k0rdent-config.sh
source ./common-functions.sh

# Script-specific variables
MANIFEST="$AZURE_MANIFEST"
WIREGUARD_PORT=$((RANDOM % 34001 + 30000))

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
    print_header "Azure Network Resources Status"
    
    # Check manifest
    if [[ ! -f "$AZURE_MANIFEST" ]]; then
        print_info "Manifest file does not exist: $AZURE_MANIFEST"
        print_info "No Azure resources have been created yet."
        return
    fi
    
    print_info "Manifest file: $AZURE_MANIFEST"
    
    # Check resource group
    if check_resource_group_exists "$RG"; then
        print_success "Resource group exists: $RG"
        
        # Show resource details
        print_info_verbose "Fetching resource details..."
        
        # VNet status
        if az network vnet show --resource-group "$RG" --name "$VNET_NAME" &>/dev/null; then
            print_success "Virtual Network exists: $VNET_NAME ($VNET_PREFIX)"
        else
            print_error "Virtual Network missing: $VNET_NAME"
        fi
        
        # NSG status
        if az network nsg show --resource-group "$RG" --name "$NSG_NAME" &>/dev/null; then
            print_success "Network Security Group exists: $NSG_NAME"
            
            # Show NSG rules if verbose
            if [[ "$VERBOSE_MODE" == "true" ]]; then
                echo ""
                echo "NSG Rules:"
                az network nsg rule list --resource-group "$RG" --nsg-name "$NSG_NAME" \
                    --query "[].{Name:name, Port:destinationPortRange, Protocol:protocol, Priority:priority}" \
                    --output table
            fi
        else
            print_error "Network Security Group missing: $NSG_NAME"
        fi
        
        # SSH key status
        if check_ssh_key_exists "$SSH_KEY_NAME" "$RG"; then
            print_success "SSH key exists in Azure: $SSH_KEY_NAME"
        else
            print_error "SSH key missing in Azure: $SSH_KEY_NAME"
        fi
        
        # Local SSH key status
        SSH_PRIVATE_KEY="$MANIFEST_DIR/${K0RDENT_PREFIX}-ssh-key"
        SSH_PUBLIC_KEY="$SSH_PRIVATE_KEY.pub"
        if check_local_ssh_key_exists "$SSH_PRIVATE_KEY" "$SSH_PUBLIC_KEY"; then
            print_success "Local SSH keys exist"
        else
            print_error "Local SSH keys missing"
        fi
        
        # WireGuard port
        if [[ -f "$WG_PORT_FILE" ]]; then
            local port=$(cat "$WG_PORT_FILE")
            print_info "WireGuard port: $port"
        else
            print_warning "WireGuard port file missing"
        fi
        
    else
        print_error "Resource group does not exist: $RG"
        print_info "Resources may have been deleted but manifest still exists."
    fi
    
    # Resource count from manifest
    if [[ -f "$AZURE_MANIFEST" ]]; then
        echo ""
        local count=$(tail -n +2 "$AZURE_MANIFEST" | wc -l)
        print_info "Total resources in manifest: $count"
    fi
}

deploy_resources() {
    # Check Azure CLI prerequisites
    check_azure_cli
    
    # Check if resources already exist
    if [[ -f "$AZURE_MANIFEST" ]]; then
        print_warning "Azure manifest already exists."
        if check_resource_group_exists "$RG"; then
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
    print_info_quiet "Creating resource group: $RG in $LOCATION"
    if ! az group create --name "$RG" --location "$LOCATION"; then
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
    print_info_quiet "Importing SSH public key to Azure: $SSH_KEY_NAME"
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
    print_info_quiet "Creating Virtual Network: $VNET_NAME ($VNET_PREFIX)"
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
    print_info_quiet "Creating Network Security Group: $NSG_NAME"
    if ! az network nsg create \
        --resource-group "$RG" \
        --name "$NSG_NAME" \
        --location "$LOCATION"; then
        handle_error ${LINENO} "az network nsg create"
    fi
    add_resource_to_manifest "network_security_group" "$NSG_NAME" ""
    
    # Add WireGuard NSG rule
    print_info_quiet "Adding NSG rule to allow WireGuard UDP port $WIREGUARD_PORT from anywhere"
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
    print_info_quiet "Adding NSG rule to allow SSH (22/tcp) from anywhere (for troubleshooting)"
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
    print_info_quiet "Associating NSG with subnet"
    if ! az network vnet subnet update \
        --resource-group "$RG" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --network-security-group "$NSG_NAME"; then
        handle_error ${LINENO} "az network vnet subnet update"
    fi
    
    # Save WireGuard port to a separate file for use by VM creation scripts
    echo "$WIREGUARD_PORT" > "$WG_PORT_FILE"
    
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo
        print_success "Network, subnet, NSG, and SSH key are ready."
        print_success "Resource manifest created at: $AZURE_MANIFEST"
        print_success "WireGuard port ($WIREGUARD_PORT) saved to: $WG_PORT_FILE"
        print_success "SSH key '$SSH_KEY_NAME' created for VM access"
        echo
        print_info "Next: Prepare cloud-init YAML for each VM, then deploy the VMs."
    fi
}

uninstall_resources() {
    if [[ ! -f "$AZURE_MANIFEST" ]]; then
        print_info "No manifest found. Nothing to uninstall."
        exit 0
    fi
    
    if ! check_resource_group_exists "$RG"; then
        print_info "Resource group '$RG' does not exist. Nothing to uninstall."
        exit 0
    fi
    
    print_warning "This will delete ALL Azure resources in resource group: $RG"
    print_info "The manifest file will be preserved for reference."
    
    if confirm_action "Are you sure you want to delete all Azure resources?"; then
        print_info_quiet "Deleting resource group: $RG"
        az group delete --name "$RG" --yes --no-wait
        print_success "Resource group deletion initiated (running in background)"
        print_info "You can check deletion status with: az group show --name $RG"
    else
        print_info "Uninstall cancelled."
    fi
}

reset_resources() {
    print_warning "This will delete ALL Azure resources and the manifest!"
    
    if [[ -f "$AZURE_MANIFEST" ]] && check_resource_group_exists "$RG"; then
        print_warning "Resource Group to be deleted: $RG"
    fi
    
    if confirm_action "Are you sure you want to reset everything?"; then
        if check_resource_group_exists "$RG"; then
            print_info_quiet "Deleting resource group: $RG"
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
SUPPORTED_COMMANDS="deploy uninstall reset status help"
if [[ -z "$COMMAND" ]]; then
    show_usage
    exit 1
fi

# Handle commands
case "$COMMAND" in
    "deploy")
        deploy_resources
        ;;
    "uninstall")
        uninstall_resources
        ;;
    "reset")
        reset_resources
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