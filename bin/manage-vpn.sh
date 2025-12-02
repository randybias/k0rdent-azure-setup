#!/usr/bin/env bash

# Script: manage-vpn.sh
# Purpose: Comprehensive WireGuard VPN management for k0rdent cluster
#          Consolidates laptop config generation and connection management
# Usage: bash manage-vpn.sh [command] [options]
# Prerequisites: Full k0rdent deployment must be completed first

set -euo pipefail

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh
source ./etc/state-management.sh

# Get WireGuard quick path once for the entire script
WG_QUICK_PATH=$(get_wg_quick_path)

# Note: Setup completion now tracked in deployment state
# Legacy .vpn-setup-complete file removed in favor of state management

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  setup        Generate and setup VPN configuration (one-time)
  connect      Connect to WireGuard VPN (fast, repeatable)
  disconnect   Safely disconnect WireGuard VPN
  test         Test WireGuard connectivity
  status       Show comprehensive VPN status
  cleanup      Clean up orphaned interfaces (macOS)
  reset        Remove configurations and disconnect
  generate     Alias for setup (backwards compatibility)
  help         Show this help message" \
        "  -y, --yes        Skip confirmation prompts
  --no-wait        Skip waiting for resources/connections
  -h, --help       Show help message" \
        "  $0 setup             # One-time VPN setup
  $0 connect           # Connect to VPN (interactive)
  $0 connect -y        # Connect to VPN (automated)
  $0 disconnect        # Disconnect from VPN
  $0 status            # Show full VPN status
  $0 test              # Test connectivity only
  $0 cleanup           # Clean up orphaned interfaces
  $0 reset -y          # Remove all config and disconnect"
}

# Comprehensive status function (combines both scripts)
show_comprehensive_status() {
    print_header "Comprehensive VPN Status"
    
    # Configuration Status (from generate-laptop-wg-config.sh)
    echo
    print_info "=== Configuration Status ==="
    
    if [[ ! -f "$WG_CONFIG_FILE" ]]; then
        print_error "No laptop WireGuard configuration found."
        print_info "Run '$0 generate' to create configuration."
        echo
        print_info "=== Connection Status ==="
        print_error "Cannot check connection status without configuration."
        return 1
    fi
    
    print_success "Configuration file: $WG_CONFIG_FILE"
    print_info "File created: $(stat -f '%Sm' "$WG_CONFIG_FILE" 2>/dev/null || stat -c '%y' "$WG_CONFIG_FILE" 2>/dev/null | cut -d' ' -f1,2)"
    
    # Extract configuration details
    local laptop_ip=$(grep "^Address" "$WG_CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
    local peer_count=$(grep -c "^\[Peer\]" "$WG_CONFIG_FILE" || echo "0")
    local endpoint_port=$(grep "^Endpoint" "$WG_CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ' | cut -d':' -f2)
    
    print_info "Laptop WireGuard IP: $laptop_ip"
    print_info "WireGuard port: $endpoint_port"
    print_info "Configured peers: $peer_count"
    
    # Connection Status (from connect-laptop-wireguard.sh)
    echo
    print_info "=== Connection Status ==="
    
    # Check if WireGuard interface is active
    local interface_name=$(basename "$WG_CONFIG_FILE" .conf)
    local interface_active=false
    
    # Check if interface is active using wg show
    if [[ "$(uname)" == "Darwin" ]]; then
        # On macOS, check if any WireGuard interface exists with actual output
        local wg_output=$(run_wg_command wg-show 2>/dev/null)
        if [[ -n "$wg_output" ]]; then
            interface_active=true
            # Get the interface name from wg show
            local utun_name=$(echo "$wg_output" | grep "interface:" | awk '{print $2}')
            if [[ -n "$utun_name" ]]; then
                print_success "WireGuard interface active: $interface_name ($utun_name)"
            else
                print_success "WireGuard interface active: $interface_name"
            fi
        fi
    else
        # Linux: check specific interface
        if run_wg_command wg-show "$interface_name" &>/dev/null; then
            interface_active=true
            print_success "WireGuard interface active: $interface_name"
        fi
    fi
    
    if [[ "$interface_active" == "false" ]]; then
        print_error "WireGuard interface not active: $interface_name"
        print_info "Run '$0 connect' to establish connection."
        return 0
    fi
    
    # Show peer information if interface is active
    echo
    print_info "=== Peer Status ==="
    
    # Show configured endpoints
    grep -A 1 "^\[Peer\]" "$WG_CONFIG_FILE" | grep "^Endpoint" | while read -r line; do
        local endpoint=$(echo "$line" | cut -d'=' -f2 | tr -d ' ')
        print_info "Peer endpoint: $endpoint"
    done
    
    return 0
}

validate_vpn_setup_state() {
    local setup_flag=$(get_state "wg_laptop_config_created" 2>/dev/null || echo "false")
    if [[ "$setup_flag" != "true" ]]; then
        return 1
    fi

    [[ -f "$WG_CONFIG_FILE" ]]
}

validate_vpn_connection_state() {
    local connected=$(get_state "wg_vpn_connected" 2>/dev/null || echo "false")
    if [[ "$connected" != "true" ]]; then
        return 1
    fi

    if command -v wg >/dev/null 2>&1; then
        if [[ "$(uname)" == "Darwin" ]]; then
            if ! run_wg_command wg-show >/dev/null 2>&1; then
                return 1
            fi
        else
            local iface=$(basename "$WG_CONFIG_FILE" .conf)
            if ! run_wg_command wg-show "$iface" >/dev/null 2>&1; then
                return 1
            fi
        fi
    fi

    return 0
}

# Check if setup is complete
check_setup_complete() {
    local setup_status=$(get_state "wg_laptop_config_created" 2>/dev/null || echo "false")
    [[ "$setup_status" == "true" ]]
}

# Get setup method (gui or cli)
get_setup_method() {
    local setup_method=$(get_state "wg_setup_method" 2>/dev/null || echo "")
    echo "$setup_method"
}

# Mark setup as complete
mark_setup_complete() {
    local method="$1"
    # Update state instead of creating file
    update_state "wg_setup_method" "$method"
    update_state "wg_laptop_config_created" "true"
}

# Script-specific prerequisite validation
validate_full_prerequisites() {
    # Note: WireGuard tools are checked in bin/check-prerequisites.sh
    # This function now only validates script-specific prerequisites
    return 0
}

# One-time VPN setup (combines config generation and setup)
setup_vpn() {
    print_header "Setting Up WireGuard VPN (One-Time Setup)"

    # Check WireGuard wrapper status early - offer to build if needed
    # This provides a better first-run experience by handling wrapper setup upfront
    # Use if/else to capture status without triggering set -e on non-zero return
    local wrapper_status
    if check_wg_wrapper_status; then
        wrapper_status=0
    else
        wrapper_status=$?
    fi

    if [[ $wrapper_status -ne 0 ]]; then
        print_info "Checking WireGuard wrapper before VPN setup..."
        if ! offer_to_build_wg_wrapper; then
            print_error "WireGuard wrapper is required for VPN operations."
            print_info "Please build the wrapper and try again."
            return 1
        fi
    fi

    if state_file_exists && phase_is_completed "setup_vpn"; then
        if validate_vpn_setup_state; then
            print_success "WireGuard VPN setup already complete. Nothing to do."
            return 0
        fi
        print_warning "VPN setup recorded as complete but validation failed. Regenerating configuration."
        phase_reset_from "setup_vpn"
    fi

    local existing_setup=false
    if check_setup_complete; then
        existing_setup=true
        local method=$(get_setup_method)
        print_info "VPN setup already complete using method: $method"
        print_info "Configuration file: $WG_CONFIG_FILE"
        
        if [[ "$SKIP_PROMPTS" == "false" ]]; then
            read -p "Do you want to regenerate the setup? (yes/no): " -r
            if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                print_info "Setup unchanged. Use '$0 connect' to connect."
                phase_mark_completed "setup_vpn"
                return 0
            fi
        fi
    fi
    
    phase_mark_in_progress "setup_vpn"
    
    # Generate configuration first
    generate_laptop_config_internal
    
    # Now setup the connection method
    if [[ "$SKIP_PROMPTS" == "true" ]]; then
        # Non-interactive mode: CLI setup only
        print_info "Non-interactive mode: Setting up CLI connection..."
        setup_wireguard_cli_for_setup
        mark_setup_complete "cli"
        print_success "VPN setup complete! Use '$0 connect' to connect."
    else
        # Interactive mode: ask user preference
        echo
        print_info "Choose setup method:"
        echo "  1. CLI (command line with wg-quick)"
        echo "  2. GUI (import config file into WireGuard app)"
        echo
        
        while true; do
            read -p "Enter choice (1 or 2): " -r choice
            case $choice in
                1)
                    setup_wireguard_cli_for_setup
                    mark_setup_complete "cli"
                    print_success "CLI setup complete! Use '$0 connect' to connect."
                    break
                    ;;
                2)
                    setup_wireguard_gui
                    mark_setup_complete "gui"
                    print_success "GUI setup complete! Activate tunnel in WireGuard app."
                    print_info "To connect via CLI instead, use '$0 connect'."
                    break
                    ;;
                *)
                    print_error "Invalid choice. Please enter 1 or 2."
                    ;;
            esac
        done
    fi

    if [[ -f "$WG_CONFIG_FILE" ]]; then
        record_artifact "wireguard_laptop_config" "$WG_CONFIG_FILE"
    fi
    phase_mark_completed "setup_vpn"
    
    return 0
}

# Configuration generation (internal function, from generate-laptop-wg-config.sh)
generate_laptop_config_internal() {
    print_header "Generating Laptop WireGuard Configuration"
    
    # Enhanced prerequisite validation
    validate_full_prerequisites
    
    # Note: Azure CLI is checked in bin/check-prerequisites.sh
    
    # Check if Azure resources exist
    if ! check_azure_resource_exists "group" "$RG"; then
        print_error "Resource group '$RG' does not exist."
        print_info "Deploy Azure resources first with: bash bin/setup-azure-network.sh deploy"
        exit 1
    fi
    
    
    # Check if WireGuard keys exist in state
    if [[ "$(get_wireguard_private_key "mylaptop")" == "null" ]]; then
        print_error "WireGuard keys not found in deployment state"
        print_info "Generate keys first with: bash bin/prepare-deployment.sh keys"
        exit 1
    fi
    
    # Get WireGuard port from state
    WG_PORT=$(get_state "config.wireguard_port")
    if [[ -z "$WG_PORT" || "$WG_PORT" == "null" ]]; then
        print_error "WireGuard port not found in deployment state"
        print_info "This should have been set during deployment preparation."
        exit 1
    fi
    
    print_info "Using WireGuard port: $WG_PORT"
    
    # Check if configuration already exists
    if [[ -f "$WG_CONFIG_FILE" ]]; then
        print_warning "WireGuard configuration already exists: $WG_CONFIG_FILE"
        if [[ "$SKIP_PROMPTS" == "false" ]]; then
            read -p "Do you want to regenerate the configuration? (yes/no): " -r
            if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                print_info "Configuration generation cancelled."
                exit 0
            fi
        fi
    fi
    
    # Create configuration directory
    # WireGuard directory already exists from key generation
    
    # Get VM public IP addresses from state
    print_info "Retrieving VM public IP addresses from state..."
    declare -A VM_PUBLIC_IPS
    
    # Refresh VM data if state doesn't exist or is empty
    if ! state_file_exists || [[ $(get_state "vm_states" | yq eval '. | length' 2>/dev/null || echo "0") -eq 0 ]]; then
        print_info "Refreshing VM data from Azure..."
        refresh_all_vm_data
    fi
    
    for HOST in "${VM_HOSTS[@]}"; do
        print_info "Getting public IP for $HOST..."
        PUBLIC_IP=$(get_vm_info "$HOST" "public_ip")
        
        if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "null" ]]; then
            print_error "Could not retrieve public IP for $HOST from state"
            print_info "Ensure VM is running and has a public IP assigned."
            exit 1
        fi
        
        VM_PUBLIC_IPS["$HOST"]="$PUBLIC_IP"
        print_success "  $HOST: $PUBLIC_IP"
    done
    
    # Get laptop private key from state
    print_info "Reading laptop WireGuard key from state..."
    # Get laptop private key from state
    LAPTOP_PRIVATE_KEY=$(get_wireguard_private_key "mylaptop")
    if [[ "$LAPTOP_PRIVATE_KEY" == "null" ]]; then
        print_error "Laptop private key not found in state"
        exit 1
    fi
    print_success "Retrieved laptop private key from state"
    
    # Start building configuration file
    print_info "Creating WireGuard configuration file: $WG_CONFIG_FILE"
    
    cat > "$WG_CONFIG_FILE" << EOF
# WireGuard configuration for laptop connection to k0rdent cluster
# Generated: $(date)
# Cluster ID: $K0RDENT_CLUSTERID

[Interface]
PrivateKey = $LAPTOP_PRIVATE_KEY
Address = ${WG_IPS["mylaptop"]}/32
DNS = 8.8.8.8, 1.1.1.1

EOF
    
    # Add peer configuration for each VM
    for HOST in "${VM_HOSTS[@]}"; do
        WG_IP="${WG_IPS[$HOST]}"
        PUBLIC_IP="${VM_PUBLIC_IPS[$HOST]}"
        
        # Get VM's public key from state
        VM_PUBLIC_KEY=$(get_wireguard_public_key "$HOST")
        
        if [[ "$VM_PUBLIC_KEY" == "null" ]]; then
            print_error "Could not find public key for $HOST in state"
            exit 1
        fi
        
        cat >> "$WG_CONFIG_FILE" << EOF
# Peer: $HOST ($WG_IP)
[Peer]
PublicKey = $VM_PUBLIC_KEY
AllowedIPs = $WG_IP/32
Endpoint = $PUBLIC_IP:$WG_PORT
PersistentKeepalive = 25

EOF
    done
    
    # Set proper file permissions
    chmod 600 "$WG_CONFIG_FILE"
    
    print_success "WireGuard configuration generated successfully!"
    print_info "Configuration file: $WG_CONFIG_FILE"
    print_info "Laptop WireGuard IP: ${WG_IPS["mylaptop"]}"
    
    # Update state
    update_state "wg_laptop_config_created" "true"
    add_event "vpn_config_generated" "WireGuard laptop configuration generated"
    
    echo
    print_info "Next steps:"
    print_info "  1. Connect to VPN: $0 connect"
    print_info "  2. Test connectivity: $0 test"
    
    return 0
}

# Generate laptop config (backwards compatibility)
generate_laptop_config() {
    setup_vpn
}

# WireGuard connection setup (from connect-laptop-wireguard.sh)
validate_connection_prerequisites() {
    # Check if configuration file exists
    if ! check_file_exists "$WG_CONFIG_FILE" "WireGuard configuration"; then
        print_error "WireGuard configuration not found. Run '$0 generate' first."
        exit 1
    fi

    # Note: netcat is checked in bin/check-prerequisites.sh

    # Note: wg-quick is checked in bin/check-prerequisites.sh
}

# Interactive GUI setup instructions
setup_wireguard_gui() {
    print_header "WireGuard GUI Setup Instructions"
    
    echo
    print_info "To connect using WireGuard GUI application:"
    echo
    echo "1. Open WireGuard application"
    echo "2. Click 'Import tunnel(s) from file'"
    echo "3. Select the configuration file:"
    echo "   $WG_CONFIG_FILE"
    echo "4. Click 'Activate' to connect"
    echo
    print_success "Configuration file is ready for import!"
    echo
    print_info "After connecting, test with: $0 test"
    
    return 0
}

# CLI setup for initial setup (doesn't start connection)
setup_wireguard_cli_for_setup() {
    print_info "CLI setup complete. Configuration ready for connection."
    print_info "Configuration file: $WG_CONFIG_FILE"
    return 0
}

# CLI-based WireGuard setup (for immediate connection)
setup_wireguard_cli() {
    local interface_name=$(basename "$WG_CONFIG_FILE" .conf)
    
    print_header "Setting up WireGuard CLI Connection"
    
    # Check if interface is already active
    local interface_exists=false
    if [[ "$(uname)" == "Darwin" ]]; then
        # On macOS, check if any WireGuard interface exists with actual output
        local wg_output=$(run_wg_command wg-show 2>/dev/null)
        if [[ -n "$wg_output" ]]; then
            interface_exists=true
        fi
    else
        # Linux: check specific interface
        if run_wg_command wg-show "$interface_name" &>/dev/null; then
            interface_exists=true
        fi
    fi
    
    if [[ "$interface_exists" == "true" ]]; then
        print_warning "WireGuard interface '$interface_name' appears to be active"
        if [[ "$SKIP_PROMPTS" == "false" ]]; then
            read -p "Do you want to restart the connection? (yes/no): " -r
            if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                print_info "Shutting down existing connection..."
                shutdown_wireguard_interface "$WG_CONFIG_FILE"
            else
                print_info "Keeping existing connection."
                return 0
            fi
        else
            print_info "Restarting connection..."
            shutdown_wireguard_interface "$WG_CONFIG_FILE"
        fi
    fi
    
    # Start WireGuard interface
    print_info "Starting WireGuard interface: $interface_name"
    
    # Capture output to parse the utun interface name on macOS
    local wg_output
    if wg_output=$(run_wg_command wg-quick-up "$WG_CONFIG_FILE" 2>&1); then
        echo "$wg_output"  # Show the output
        
        # On macOS, parse the utun interface from the output
        if [[ "$(uname)" == "Darwin" ]]; then
            local utun_name=$(echo "$wg_output" | grep -o "Interface for .* is utun[0-9]" | awk '{print $NF}')
            if [[ -n "$utun_name" ]]; then
                # Store the mapping for later use
                export WG_MACOS_INTERFACE="$utun_name"
                # Also store in state for persistence
                update_state "wg_macos_interface" "$utun_name"
            fi
        fi
        
        print_success "WireGuard interface started successfully!"
        update_state "wg_vpn_connected" "true"
        add_event "vpn_connected" "WireGuard VPN connected successfully"
    else
        echo "$wg_output"  # Show error output
        print_error "Failed to start WireGuard interface"
        print_info "Check the configuration file and try again."
        return 1
    fi
    
    # Wait for interface to be ready
    if [[ "$NO_WAIT" != "true" ]]; then
        print_info "Waiting for interface to be ready..."
        sleep 3
    fi
    
    return 0
}

# Connection verification and info display
verify_and_show_connection_info() {
    local interface_name=$(basename "$WG_CONFIG_FILE" .conf)
    
    print_header "Verifying WireGuard Connection"
    
    # Verify interface is active
    local interface_active=false
    
    if [[ "$(uname)" == "Darwin" ]]; then
        # On macOS, use the stored interface name or check if any WireGuard interface exists
        local utun_name="${WG_MACOS_INTERFACE:-}"
        
        # If not in environment, check state file
        if [[ -z "$utun_name" ]]; then
            utun_name=$(get_state "wg_macos_interface" || echo "")
        fi
        
        # If we still don't have the stored name, check for any active WireGuard interface
        if [[ -z "$utun_name" ]] && run_wg_command wg-show &>/dev/null; then
            # Try to find the interface from wg show output
            utun_name=$(run_wg_command wg-show 2>/dev/null | grep "interface:" | awk '{print $2}')
        fi
        
        if [[ -n "$utun_name" ]] && ifconfig "$utun_name" &>/dev/null; then
            interface_active=true
            print_success "WireGuard interface is active: $interface_name ($utun_name)"
            local laptop_ip=$(ifconfig "$utun_name" | grep "inet " | awk '{print $2}')
            if [[ -n "$laptop_ip" ]]; then
                print_info "Laptop IP in VPN: $laptop_ip"
            fi
        fi
    else
        # Linux: interface name works directly
        if run_wg_command wg-show "$interface_name" &>/dev/null; then
            interface_active=true
            print_success "WireGuard interface is active: $interface_name"
            local laptop_ip=$(ip addr show "$interface_name" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
            if [[ -n "$laptop_ip" ]]; then
                print_info "Laptop IP in VPN: $laptop_ip"
            fi
        fi
    fi
    
    if [[ "$interface_active" == "false" ]]; then
        print_error "WireGuard interface is not active"
        return 1
    fi
    
    
    return 0
}

# Comprehensive connectivity test
test_wireguard_connectivity() {
    print_header "Testing WireGuard Connectivity"
    
    # Validate prerequisites
    validate_connection_prerequisites
    
    # Check if interface is active - simplified check
    local interface_active=false
    
    # Just check if any WireGuard interface is up
    if run_wg_command wg-show >/dev/null 2>&1; then
        interface_active=true
        print_success "WireGuard interface is active"
    else
        print_error "No active WireGuard interfaces found"
        print_info "Run '$0 connect' to establish connection first."
        return 1
    fi
    
    # Test connectivity to VMs
    echo
    print_info "Testing connectivity to VMs..."
    
    local success_count=0
    local total_count=${#VM_HOSTS[@]}
    
    for HOST in "${VM_HOSTS[@]}"; do
        local VM_IP="${WG_IPS[$HOST]}"
        print_info "Testing $HOST ($VM_IP)..."
        
        # Test ping connectivity
        if ping -c 3 -W 5000 "$VM_IP" >/dev/null 2>&1; then
            print_success "  ✓ Ping successful"
            ((success_count++))
            
            # Test SSH port if netcat is available
            if command -v nc &> /dev/null; then
                if nc -z -w 5 "$VM_IP" 22 2>/dev/null; then
                    print_success "  ✓ SSH port (22) reachable"
                else
                    print_warning "  ⚠ SSH port (22) not reachable"
                fi
            fi
        else
            print_error "  ✗ Ping failed"
        fi
    done
    
    echo
    print_info "Connectivity test results:"
    print_info "  Successful connections: $success_count/$total_count"
    
    if [[ $success_count -eq $total_count ]]; then
        print_success "🎉 All VMs are reachable via WireGuard!"
        echo
        print_info "You can now:"
        print_info "  • SSH to VMs using their WireGuard IPs"
        print_info "  • Access k0s cluster services"
        print_info "  • Use kubectl with the generated kubeconfig"
        return 0
    elif [[ $success_count -gt 0 ]]; then
        print_warning "Some VMs are not reachable. Check VM status and WireGuard configuration."
        return 1
    else
        print_error "Ping tests failed - no VMs are reachable via WireGuard."
        print_info "This indicates WireGuard connection issues. Check:"
        print_info "  • WireGuard interface status: sudo wg show"
        print_info "  • VM WireGuard services: may need time to start"
        print_info "  • Network connectivity between laptop and VMs"
        return 1
    fi
}

# Main connection function (fast, for repeat connections)
connect_wireguard() {
    print_header "Connecting to WireGuard VPN"

    # Check WireGuard wrapper status early - offer to build if needed
    # Use if/else to capture status without triggering set -e on non-zero return
    local wrapper_status
    if check_wg_wrapper_status; then
        wrapper_status=0
    else
        wrapper_status=$?
    fi

    if [[ $wrapper_status -ne 0 ]]; then
        print_info "Checking WireGuard wrapper before connecting..."
        if ! offer_to_build_wg_wrapper; then
            print_error "WireGuard wrapper is required for VPN operations."
            print_info "Please build the wrapper and try again."
            return 1
        fi
    fi

    if state_file_exists && phase_is_completed "connect_vpn"; then
        if validate_vpn_connection_state; then
            print_success "WireGuard VPN already connected."
            return 0
        fi
        print_warning "VPN connection recorded as active but validation failed. Reconnecting."
        phase_reset_from "connect_vpn"
    fi

    # Check if setup is complete
    if ! check_setup_complete; then
        print_error "VPN setup not complete. Run '$0 setup' first."
        exit 1
    fi

    # Validate prerequisites
    validate_connection_prerequisites
    
    local setup_method=$(get_setup_method)
    
    if [[ "$setup_method" == "gui" ]]; then
        print_info "VPN was set up for GUI use."
        print_info "Please activate the tunnel in your WireGuard application."
        print_info "Or run '$0 setup' to switch to CLI mode."
        phase_mark_pending "connect_vpn"
        return 0
    fi
    
    phase_mark_in_progress "connect_vpn"
    
    # CLI connection (fast path)
    print_info "Connecting via CLI (fast connection)..."
    if setup_wireguard_cli; then
        if verify_and_show_connection_info; then
            phase_mark_completed "connect_vpn"
        else
            phase_reset_from "connect_vpn"
            return 1
        fi
    else
        phase_reset_from "connect_vpn"
        return 1
    fi
    
    return 0
}

# Standalone connectivity test
test_connectivity() {
    test_wireguard_connectivity
}

# Safe disconnection
disconnect_wireguard() {
    print_header "Disconnecting WireGuard VPN"
    
    local interface_name=$(basename "$WG_CONFIG_FILE" .conf)
    
    # Check if configuration file exists
    if [[ ! -f "$WG_CONFIG_FILE" ]]; then
        print_warning "WireGuard configuration not found: $WG_CONFIG_FILE"
        print_info "Nothing to disconnect."
        return 0
    fi
    
    # Check if interface is active
    local interface_active=false
    
    if [[ "$(uname)" == "Darwin" ]]; then
        # On macOS, check if any WireGuard interface exists with actual output
        local wg_output=$(run_wg_command wg-show 2>/dev/null)
        if [[ -n "$wg_output" ]]; then
            interface_active=true
        fi
    else
        # Linux: check specific interface
        if run_wg_command wg-show "$interface_name" &>/dev/null; then
            interface_active=true
        fi
    fi
    
    if [[ "$interface_active" == "false" ]]; then
        print_info "WireGuard interface '$interface_name' is not active."
        print_info "Nothing to disconnect."
        return 0
    fi
    
    # Perform shutdown
    print_info "Shutting down WireGuard interface: $interface_name"
    
    if shutdown_wireguard_interface "$WG_CONFIG_FILE"; then
        print_success "WireGuard VPN disconnected successfully!"
        update_state "wg_vpn_connected" "false"
        # Clear the macOS interface mapping
        if [[ "$(uname)" == "Darwin" ]]; then
            update_state "wg_macos_interface" ""
        fi
        add_event "vpn_disconnected" "WireGuard VPN disconnected"
        phase_mark_pending "connect_vpn"
    else
        print_error "Failed to disconnect WireGuard VPN"
        return 1
    fi

    return 0
}

# Cleanup orphaned interfaces
cleanup_orphaned_interfaces() {
    print_header "Cleaning Up Orphaned WireGuard Interfaces"
    
    if [[ "$(uname)" != "Darwin" ]]; then
        print_info "Cleanup is primarily needed on macOS."
        print_info "On Linux, use standard WireGuard tools to manage interfaces."
        return 0
    fi
    
    # Use the common function for cleanup
    cleanup_all_macos_wireguard_interfaces
}

# Reset configuration and disconnect
reset_and_cleanup() {
    print_header "Resetting WireGuard Configuration"

    if state_file_exists; then
        phase_reset_from "setup_vpn"
    fi
    
    # Determine interface name from config file or from the expected name
    local interface_name=""
    if [[ -f "$WG_CONFIG_FILE" ]]; then
        interface_name=$(basename "$WG_CONFIG_FILE" .conf)
    else
        # Try to determine from the deployment ID
        interface_name="wgk0${K0RDENT_CLUSTERID#k0rdent-}"
    fi
    
    # First disconnect if connected - always attempt shutdown if config file exists
    if [[ -f "$WG_CONFIG_FILE" ]]; then
        print_info "Disconnecting WireGuard VPN..."
        shutdown_wireguard_interface "$WG_CONFIG_FILE"
    else
        # No config file, but check if interface is still active using state
        if [[ "$(uname)" == "Darwin" ]]; then
            local stored_utun=$(get_state "wg_macos_interface" || echo "")
            if [[ -n "$stored_utun" ]] && ifconfig "$stored_utun" &>/dev/null; then
                print_warning "Found active WireGuard interface without config file: $stored_utun"
                print_info "Attempting to shut down orphaned interface..."

                # Try to shut it down using wg-quick with the interface name
                if run_wg_command wg-quick-down "$interface_name" 2>/dev/null; then
                    print_success "Orphaned interface shut down"
                else
                    print_warning "Could not shut down interface automatically"
                fi
            fi
        fi
    fi
    
    # Remove configuration directory
    if [[ -f "$WG_CONFIG_FILE" ]]; then
        if [[ "$SKIP_PROMPTS" == "false" ]]; then
            read -p "This will remove all WireGuard configurations. Are you sure? (yes/no): " -r
            if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                print_info "Reset cancelled."
                return 0
            fi
        fi
        
        print_info "Removing WireGuard laptop configuration: $WG_CONFIG_FILE"
        rm -f "$WG_CONFIG_FILE"
        print_success "WireGuard configuration and setup state removed."
        
        # Update state
        update_state "wg_laptop_config_created" "false"
        update_state "wg_vpn_connected" "false"
        # Clear the macOS interface mapping
        if [[ "$(uname)" == "Darwin" ]]; then
            update_state "wg_macos_interface" ""
        fi
        add_event "vpn_config_reset" "WireGuard laptop configuration removed"
    else
        print_info "No WireGuard configuration directory found."
    fi
    
    # Check if runtime files are still present (wg-quick down should have cleaned them)
    if [[ "$(uname)" == "Darwin" ]] && [[ -n "$interface_name" ]]; then
        if [[ -f "/var/run/wireguard/${interface_name}.name" ]] || ls /var/run/wireguard/*.sock &>/dev/null 2>&1; then
            print_warning "WireGuard runtime files still exist in /var/run/wireguard/"
            print_info "Manual cleanup may be required: sudo rm -f /var/run/wireguard/${interface_name}.name /var/run/wireguard/*.sock"
        fi
    fi
    
    print_success "Reset complete."
    return 0
}

# Main execution
# Store original arguments for handle_standard_commands
ORIGINAL_ARGS=("$@")

# Use consolidated command handling
handle_standard_commands "$0" "setup connect disconnect test status cleanup reset generate help" \
    "setup" "setup_vpn" \
    "connect" "connect_wireguard" \
    "disconnect" "disconnect_wireguard" \
    "test" "test_connectivity" \
    "status" "show_comprehensive_status" \
    "cleanup" "cleanup_orphaned_interfaces" \
    "reset" "reset_and_cleanup" \
    "generate" "generate_laptop_config" \
    "help" "show_usage" \
    "usage" "show_usage"
