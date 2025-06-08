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
source ./etc/state-management.sh

# Note: Resource tracking now uses deployment-state.yaml instead of CSV manifest

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
    local wg_port=$(get_state "config.wireguard_port" 2>/dev/null || echo "null")
    if [[ "$wg_port" != "null" ]]; then
        port_info="$wg_port"
    fi
    
    local azure_rg_status=$(get_state "azure_rg_status" 2>/dev/null || echo "not_created")
    local azure_network_status=$(get_state "azure_network_status" 2>/dev/null || echo "not_created")
    local azure_ssh_key_status=$(get_state "azure_ssh_key_status" 2>/dev/null || echo "not_created")
    
    # Use generic status display framework
    display_status "Azure Network Resources Status" \
        "info:$azure_rg_status:Resource group status" \
        "info:$azure_network_status:Network status" \
        "info:$azure_ssh_key_status:SSH key status" \
        "file:$SSH_PRIVATE_KEY:SSH private key" \
        "file:$SSH_PUBLIC_KEY:SSH public key" \
        ${port_info:+"info:$port_info:WireGuard port (from state)"}
    
    # Check Azure resources if state exists
    if state_file_exists && check_resource_group_exists "$RG"; then
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
    elif state_file_exists; then
        echo
        print_warning "Deployment state exists but resource group '$RG' not found"
        print_info "Resources may have been deleted externally or deployment may be incomplete"
    fi
}

deploy_resources() {
    # Check prerequisites using generic framework
    if ! check_prerequisites "setup-azure-network" \
        "azure_cli:Azure CLI not available or not logged in:Run 'az login'" \
        "state_file:deployment state required:Run: bash bin/prepare-deployment.sh deploy"; then
        exit 1
    fi
    
    # Get WireGuard port from state
    WIREGUARD_PORT=$(get_state "config.wireguard_port")
    if [[ -z "$WIREGUARD_PORT" || "$WIREGUARD_PORT" == "null" ]]; then
        print_error "WireGuard port not found in deployment state"
        print_info "Run deployment preparation first: bash bin/prepare-deployment.sh deploy"
        exit 1
    fi
    print_info "Using WireGuard port: $WIREGUARD_PORT"
    
    # Check if network setup is already complete
    if state_file_exists; then
        local azure_rg_status=$(get_state "azure_rg_status" 2>/dev/null || echo "not_created")
        local azure_network_status=$(get_state "azure_network_status" 2>/dev/null || echo "not_created")
        local azure_ssh_key_status=$(get_state "azure_ssh_key_status" 2>/dev/null || echo "not_created")
        
        if [[ "$azure_rg_status" == "created" && "$azure_network_status" == "created" && "$azure_ssh_key_status" == "created" ]]; then
            print_error "Azure network setup is already complete. Use 'reset' to clean up first."
            exit 1
        fi
        
        if [[ "$azure_rg_status" == "created" ]] || [[ "$azure_network_status" == "created" ]] || [[ "$azure_ssh_key_status" == "created" ]]; then
            print_warning "Partial Azure setup detected. Completing missing components..."
        fi
    fi
    
    # Create resource group (if not already created)
    if [[ "$(get_state "azure_rg_status" 2>/dev/null)" != "created" ]]; then
        if ! log_azure_command "Creating resource group: $RG in $AZURE_LOCATION" \
            az group create --name "$RG" --location "$AZURE_LOCATION"; then
            handle_error ${LINENO} "az group create"
        fi
        # Update state
        update_state "azure_rg_status" "created"
        add_event "azure_rg_created" "Resource group created: $RG"
    else
        print_info "Resource group already exists: $RG"
    fi
    
    # Generate local SSH key pair
    SSH_PRIVATE_KEY="$MANIFEST_DIR/${K0RDENT_PREFIX}-ssh-key"
    SSH_PUBLIC_KEY="$SSH_PRIVATE_KEY.pub"
    
    # Ensure SSH key directory exists
    ensure_directory "$MANIFEST_DIR"
    
    print_info_quiet "Generating local SSH key pair: $SSH_PRIVATE_KEY"
    if [[ ! -f "$SSH_PRIVATE_KEY" ]]; then
        ssh-keygen -t rsa -b 4096 -f "$SSH_PRIVATE_KEY" -N "" -C "k0rdent-${K0RDENT_PREFIX}"
        print_success "SSH key pair generated locally"
    else
        print_info_verbose "SSH key pair already exists locally"
    fi
    
    # Import public key to Azure (if not already done)
    if [[ "$(get_state "azure_ssh_key_status" 2>/dev/null)" != "created" ]]; then
        if ! log_azure_command "Importing SSH public key to Azure: $SSH_KEY_NAME" \
            az sshkey create \
            --name "$SSH_KEY_NAME" \
            --resource-group "$RG" \
            --location "$AZURE_LOCATION" \
            --public-key "@$SSH_PUBLIC_KEY"; then
            handle_error ${LINENO} "az sshkey create"
        fi
        # Update state
        update_state "azure_ssh_key_status" "created"
        add_event "azure_ssh_key_created" "SSH key imported to Azure: $SSH_KEY_NAME"
    else
        print_info "SSH key already exists in Azure: $SSH_KEY_NAME"
    fi
    
    # Create Virtual Network (if not already created)
    if [[ "$(get_state "azure_network_status" 2>/dev/null)" != "created" ]]; then
        if ! log_azure_command "Creating Virtual Network: $VNET_NAME ($VNET_PREFIX)" \
            az network vnet create \
            --resource-group "$RG" \
            --name "$VNET_NAME" \
            --address-prefix "$VNET_PREFIX" \
            --subnet-name "$SUBNET_NAME" \
            --subnet-prefix "$SUBNET_PREFIX"; then
            handle_error ${LINENO} "az network vnet create"
        fi
        # Update state
        update_state "azure_network_status" "created"
        add_event "azure_network_created" "Virtual network and subnet created: $VNET_NAME"
    else
        print_info "Virtual network already exists: $VNET_NAME"
    fi
    
    # Create Network Security Group
    if ! log_azure_command "Creating Network Security Group: $NSG_NAME" \
        az network nsg create \
        --resource-group "$RG" \
        --name "$NSG_NAME" \
        --location "$AZURE_LOCATION"; then
        handle_error ${LINENO} "az network nsg create"
    fi
    # NSG creation tracked in state management automatically
    
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
    # NSG rules tracked in state management automatically
    
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
    # NSG rules tracked in state management automatically
    
    # Associate NSG with subnet
    if ! log_azure_command "Associating NSG with subnet" \
        az network vnet subnet update \
        --resource-group "$RG" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --network-security-group "$NSG_NAME"; then
        handle_error ${LINENO} "az network vnet subnet update"
    fi
    
    # Update state to mark Azure setup complete
    update_state "phase" "azure_ready"
    add_event "azure_setup_completed" "Azure network infrastructure deployment completed"
    
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo
        print_success "Network, subnet, NSG, and SSH key are ready."
        print_success "Azure resources tracked in deployment state"
        print_success "Using WireGuard port: $WIREGUARD_PORT"
        print_success "SSH key '$SSH_KEY_NAME' created for VM access"
        echo
        print_info "Next: Create Azure VMs with the prepared cloud-init files."
    fi
}

uninstall_resources() {
    if ! state_file_exists; then
        print_info "No deployment state found. Nothing to uninstall."
        exit 0
    fi
    
    if ! check_azure_resource_exists "group" "$RG"; then
        print_info "Resource group '$RG' does not exist. Nothing to uninstall."
        exit 0
    fi
    
    print_warning "This will delete ALL Azure resources in resource group: $RG"
    print_info "The deployment state will be updated to reflect the deletion."
    
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
    
    if state_file_exists && check_azure_resource_exists "group" "$RG"; then
        print_warning "Resource Group to be deleted: $RG"
    fi
    
    if confirm_action "Are you sure you want to reset everything?"; then
        if check_azure_resource_exists "group" "$RG"; then
            log_azure_command "Deleting resource group: $RG" \
                az group delete --name "$RG" --yes --no-wait
            print_success "Resource group deletion initiated (running in background)"
        fi
        
        print_info_quiet "Updating deployment state"
        # Azure resources directory cleanup handled by state management
        
        # Update state
        update_state "azure_rg_status" "deleted"
        update_state "azure_network_status" "deleted" 
        update_state "azure_ssh_key_status" "deleted"
        update_state "vm_states" "{}"
        update_state "phase" "reset"
        add_event "azure_infrastructure_reset" "All Azure resources deleted and cleaned up"
        
        print_success "Azure resources reset complete"
    else
        print_info "Reset cancelled."
    fi
}

# Note: Resource tracking now handled via deployment state management
# Legacy CSV manifest functions removed

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