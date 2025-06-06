#!/usr/bin/env bash

# Script: lockdown-ssh.sh
# Purpose: Manage SSH access to k0rdent VMs via Azure NSG rules
#          Provides optional security lockdown after WireGuard VPN is working
# Usage: bash lockdown-ssh.sh [command] [options]
# Prerequisites: Azure CLI authenticated, existing k0rdent deployment

set -euo pipefail

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh

# Script-specific constants
SSH_RULE_NAME="AllowSSH"

# Default values
SKIP_PROMPTS=false

# Parse standard arguments
PARSED_ARGS=$(parse_standard_args "$@")
eval "$PARSED_ARGS"

# Get the command from positional arguments
COMMAND="${POSITIONAL_ARGS[0]:-}"

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  lockdown     Remove SSH (port 22) access from internet
  unlock       Restore SSH (port 22) access from internet  
  status       Show current SSH access configuration
  help         Show this help message" \
        "  -y, --yes        Skip confirmation prompts
  -h, --help       Show help message" \
        "  $0 lockdown      # Remove SSH access from 0.0.0.0/0
  $0 unlock        # Restore SSH access from 0.0.0.0/0
  $0 status        # Show current SSH rule status"
}

# Check prerequisites
validate_prerequisites() {
    if ! check_prerequisites "lockdown-ssh" \
        "azure_cli:Azure CLI not available or not logged in:Run 'az login'"; then
        exit 1
    fi
    
    # Check if resource group exists
    if ! check_azure_resource_exists "group" "$RG"; then
        print_error "Resource group '$RG' does not exist."
        print_info "Deploy Azure resources first with: bash bin/setup-azure-network.sh deploy"
        exit 1
    fi
    
    # Check if NSG exists
    if ! check_azure_resource_exists "nsg" "$NSG_NAME" "$RG"; then
        print_error "Network Security Group '$NSG_NAME' does not exist in resource group '$RG'."
        print_info "Deploy Azure network first with: bash bin/setup-azure-network.sh deploy"
        exit 1
    fi
}

# Find SSH rule that allows port 22 from internet
find_ssh_rule() {
    # Get all NSG rules and find one that allows TCP 22 from 0.0.0.0/0 or *
    az network nsg rule list \
        --resource-group "$RG" \
        --nsg-name "$NSG_NAME" \
        --query "[?protocol=='Tcp' && access=='Allow' && direction=='Inbound' && destinationPortRange=='22' && (sourceAddressPrefix=='0.0.0.0/0' || sourceAddressPrefix=='*')].{name:name,priority:priority,sourceAddressPrefix:sourceAddressPrefix}" \
        --output json 2>/dev/null || echo "[]"
}

# Check if SSH is open to internet
is_ssh_open_to_internet() {
    local ssh_rules=$(find_ssh_rule)
    [[ "$ssh_rules" != "[]" ]]
}

# Show SSH access status
show_ssh_status() {
    print_header "SSH Access Status"
    
    validate_prerequisites
    
    echo
    print_info "Network Security Group: $NSG_NAME"
    
    local ssh_rules=$(find_ssh_rule)
    
    if is_ssh_open_to_internet; then
        print_warning "🔓 SSH is OPEN to internet access"
        
        # Show details of SSH rule(s)
        echo
        print_info "SSH Rules Found:"
        echo "$ssh_rules" | jq -r '.[] | "  Rule: \(.name) (Priority: \(.priority), Source: \(.sourceAddressPrefix))"'
        
        echo
        print_info "Run '$0 lockdown' to restrict SSH access after setting up WireGuard VPN."
    else
        print_success "🔒 SSH access is RESTRICTED from internet"
        print_info "No rules found allowing TCP port 22 from 0.0.0.0/0"
        
        echo
        print_info "Run '$0 unlock' to restore internet SSH access if needed."
    fi
    
    return 0
}


# Lockdown SSH access
lockdown_ssh() {
    print_header "Locking Down SSH Access"
    
    validate_prerequisites
    
    # Check current status
    if ! is_ssh_open_to_internet; then
        print_info "SSH access is already restricted from internet."
        return 0
    fi
    
    # Confirm action
    if [[ "$SKIP_PROMPTS" == "false" ]]; then
        echo
        print_warning "⚠️  This will REMOVE SSH access from the internet (0.0.0.0/0)"
        print_info "After lockdown, you can only SSH via WireGuard VPN."
        echo
        print_info "Make sure WireGuard VPN is working before proceeding!"
        echo
        read -p "Continue with SSH lockdown? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "SSH lockdown cancelled."
            return 0
        fi
    fi
    
    # Find and remove SSH rules
    local ssh_rules=$(find_ssh_rule)
    local rule_names=$(echo "$ssh_rules" | jq -r '.[].name')
    
    if [[ -z "$rule_names" ]]; then
        print_info "No SSH rules found to remove."
        return 0
    fi
    
    print_info "Removing SSH access rules from internet..."
    
    local success=true
    while IFS= read -r rule_name; do
        [[ -z "$rule_name" ]] && continue
        
        print_info "Removing rule: $rule_name"
        if az network nsg rule delete \
            --resource-group "$RG" \
            --nsg-name "$NSG_NAME" \
            --name "$rule_name" \
            --output none; then
            print_success "✓ Removed rule: $rule_name"
        else
            print_error "✗ Failed to remove rule: $rule_name"
            success=false
        fi
    done <<< "$rule_names"
    
    if [[ "$success" == "true" ]]; then
        print_success "🔒 SSH access locked down successfully!"
        echo
        print_info "SSH is now blocked from internet access."
        print_info "You can still SSH via WireGuard VPN using VM's WireGuard IP addresses."
        echo
        print_info "To restore SSH access: $0 unlock"
        return 0
    else
        print_error "Some SSH rules could not be removed."
        return 1
    fi
}

# Unlock SSH access
unlock_ssh() {
    print_header "Unlocking SSH Access"
    
    validate_prerequisites
    
    # Check if already open
    if is_ssh_open_to_internet; then
        print_info "SSH access is already open to internet."
        return 0
    fi
    
    # Confirm action
    if [[ "$SKIP_PROMPTS" == "false" ]]; then
        echo
        print_info "This will add an SSH rule allowing access from internet (0.0.0.0/0)."
        read -p "Continue with SSH unlock? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "SSH unlock cancelled."
            return 0
        fi
    fi
    
    # Find a safe priority (higher number = lower priority)
    # Get existing priorities and find a safe one
    local existing_priorities=$(az network nsg rule list \
        --resource-group "$RG" \
        --nsg-name "$NSG_NAME" \
        --query '[].priority' \
        --output tsv 2>/dev/null | sort -n)
    
    local new_priority=1100
    while echo "$existing_priorities" | grep -q "^${new_priority}$"; do
        ((new_priority += 10))
        if [[ $new_priority -gt 4000 ]]; then
            print_error "Cannot find available priority for SSH rule"
            return 1
        fi
    done
    
    print_info "Creating SSH access rule with priority $new_priority..."
    
    if az network nsg rule create \
        --resource-group "$RG" \
        --nsg-name "$NSG_NAME" \
        --name "$SSH_RULE_NAME" \
        --protocol tcp \
        --priority "$new_priority" \
        --destination-port-range 22 \
        --source-address-prefix "0.0.0.0/0" \
        --access allow \
        --output none; then
        
        print_success "🔓 SSH access unlocked successfully!"
        echo
        print_info "SSH is now accessible from internet on port 22."
        print_warning "Consider using WireGuard VPN for secure access."
        
        return 0
    else
        print_error "Failed to create SSH access rule"
        return 1
    fi
}

# Main execution
# Store original arguments for handle_standard_commands
ORIGINAL_ARGS=("$@")

# Handle standard commands and dispatch
handle_standard_commands "$0" "lockdown unlock status help" \
    "lockdown" "lockdown_ssh" \
    "unlock" "unlock_ssh" \
    "status" "show_ssh_status" \
    "help" "show_usage" \
    "usage" "show_usage"