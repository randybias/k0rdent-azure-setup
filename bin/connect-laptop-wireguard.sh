#!/usr/bin/env bash

# Script: connect-laptop-wireguard.sh
# Purpose: Set up and test WireGuard VPN connection to k0rdent cluster
# Usage: bash connect-laptop-wireguard.sh [command] [options]
# Prerequisites: WireGuard configuration must be generated first

set -euo pipefail

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh

# Get WireGuard quick path once for the entire script
WG_QUICK_PATH=$(get_wg_quick_path)

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  connect    Set up WireGuard VPN connection
  disconnect Safely shut down WireGuard VPN connection
  test       Test existing WireGuard connectivity
  status     Show VPN connection status
  cleanup    Clean up orphaned WireGuard interfaces (macOS)
  help       Show this help message" \
        "  -y, --yes        Skip confirmation prompts (use CLI tools)
  --no-wait        Skip waiting for connection establishment" \
        "  $0 connect       # Interactive WireGuard setup
  $0 connect -y    # Automated setup with CLI tools
  $0 disconnect    # Safely disconnect WireGuard
  $0 test          # Test connectivity only
  $0 status        # Check current VPN status
  $0 cleanup       # Clean up orphaned interfaces"
}

# Configuration file path (now defined in global config)

# Validation functions
validate_prerequisites() {
    # Check if configuration file exists
    if ! check_file_exists "$WG_CONFIG_FILE" "WireGuard configuration"; then
        print_error "WireGuard configuration not found. Run ./generate-laptop-wg-config.sh first."
        exit 1
    fi

    # Check if netcat is installed (needed for connectivity testing)
    if ! command -v nc &> /dev/null; then
        print_error "netcat (nc) not found. Please install netcat first:"
        echo "  brew install netcat"
        exit 1
    fi

    print_success "WireGuard configuration found: $WG_CONFIG_FILE"
}

# Setup WireGuard using GUI method
setup_wireguard_gui() {
    print_header "WireGuard GUI Setup"
    echo "Steps to import configuration:"
    echo "1. Open the WireGuard app (install from Mac App Store if needed)"
    echo "2. Click 'Import Tunnel(s) from File...'"
    echo "3. Select the configuration file: $WG_CONFIG_FILE"
    echo "4. Activate the tunnel in the WireGuard app"
    echo ""
    read -p "Press Enter after you've imported and activated the tunnel in WireGuard app..."
}

# Setup WireGuard using CLI method
setup_wireguard_cli() {
    print_header "Command-line wg-quick Setup"
    
    # Start the interface directly from local config file
    print_info "Starting WireGuard interface from: $WG_CONFIG_FILE"
    if sudo "$WG_QUICK_PATH" up "$WG_CONFIG_FILE"; then
        print_success "WireGuard interface started successfully"
        return 0
    else
        print_error "Failed to start WireGuard interface"
        return 1
    fi
}

# Verify connection and show info
verify_and_show_connection_info() {
    print_header "Verifying WireGuard Connection"
    
    print_info "Testing VPN connectivity..."
    if WORKING_COUNT=$(test_wireguard_connectivity); then
        print_success "🎉 WireGuard VPN is working correctly ($WORKING_COUNT/${#VM_HOSTS[@]} VMs reachable)"
        echo
        print_info "You can now:"
        echo "  • SSH to VMs: ssh -i ./azure-resources/${K0RDENT_PREFIX}-ssh-key k0rdent@<VM_WIREGUARD_IP>"
        echo "  • Deploy k0rdent cluster using the WireGuard network"
        echo "  • Access services running on the VMs via their internal IPs"
        echo
        print_info "To disconnect WireGuard:"
        echo "  • GUI: Deactivate tunnel in WireGuard app"
        echo "  • CLI: sudo ${WG_QUICK_PATH} down ${WG_CONFIG_FILE}"
    else
        print_error "WireGuard VPN is not working ($WORKING_COUNT/${#VM_HOSTS[@]} VMs reachable)"
        print_info "Please check your WireGuard configuration and try again"
        exit 1
    fi
}

# Function to test if WireGuard VPN is actually working
test_wireguard_connectivity() {
    local working_count=0
    local total_hosts=${#VM_HOSTS[@]}

    for HOST in "${VM_HOSTS[@]}"; do
        local vm_ip="${WG_IPS[$HOST]}"

        # Test ping connectivity (quick test)
        if ping -c 1 -W 2000 "$vm_ip" >/dev/null 2>&1; then
            # Test SSH port connectivity using netcat
            if nc -z -w 3 "$vm_ip" 22 2>/dev/null; then
                ((working_count++))
            fi
        fi
    done

    # Return success if more than half the hosts are reachable
    if [[ $working_count -gt $((total_hosts / 2)) ]]; then
        echo "$working_count"
        return 0
    else
        echo "$working_count"
        return 1
    fi
}

# Main connection function - simplified to only handle connection
connect_wireguard() {
    print_header "k0rdent WireGuard VPN Setup"
    validate_prerequisites

    # Check current VPN status
    print_info "Checking current VPN connectivity..."
    if WORKING_COUNT=$(test_wireguard_connectivity); then
        print_success "WireGuard VPN is already active ($WORKING_COUNT/${#VM_HOSTS[@]} VMs reachable)"
        verify_and_show_connection_info
        return 0
    fi
    
    print_info "WireGuard VPN not detected ($WORKING_COUNT/${#VM_HOSTS[@]} VMs reachable)"

    # Connect based on mode
    if [[ "$SKIP_PROMPTS" == "true" ]]; then
        # Non-interactive mode: use CLI tools
        print_info "Non-interactive mode: using wg-quick..."
        if ! setup_wireguard_cli; then
            exit 1
        fi
    else
        # Interactive mode: show options
        print_header "WireGuard Setup Options"
        echo "Choose how you want to set up the WireGuard connection:"
        echo ""
        echo "1) Import into WireGuard GUI app (recommended for macOS)"
        echo "2) Use command-line wg-quick (requires sudo)"
        echo "3) Run detailed connectivity test"
        echo ""

        while true; do
            read -p "Enter your choice (1-3): " choice
            case $choice in
                1)
                    setup_wireguard_gui
                    break
                    ;;
                2)
                    if ! setup_wireguard_cli; then
                        exit 1
                    fi
                    break
                    ;;
                3)
                    # Run detailed connectivity test using common function
                    run_detailed_wireguard_connectivity_test "$K0RDENT_PREFIX"
                    exit 0
                    ;;
                *)
                    print_error "Invalid choice. Please enter 1, 2, or 3."
                    ;;
            esac
        done
    fi

    # Wait a moment for connection to establish
    print_info "Waiting 5 seconds for connection to establish..."
    sleep 5
    
    # Final verification
    verify_and_show_connection_info
}

test_connectivity() {
    validate_prerequisites
    print_header "Testing WireGuard Connectivity"

    print_info "Testing VPN connectivity..."
    if WORKING_COUNT=$(test_wireguard_connectivity); then
        print_success "🎉 WireGuard VPN is working correctly ($WORKING_COUNT/${#VM_HOSTS[@]} VMs reachable)"
    else
        print_error "WireGuard VPN is not working ($WORKING_COUNT/${#VM_HOSTS[@]} VMs reachable)"
        return 1
    fi
}

disconnect_wireguard() {
    print_header "Disconnecting WireGuard VPN"

    # First validate the config exists
    if [[ ! -f "$WG_CONFIG_FILE" ]]; then
        print_warning "No WireGuard configuration found at $WG_CONFIG_FILE"
        return 1
    fi

    # Disconnect the interface
    if shutdown_wireguard_interface "$WG_CONFIG_FILE"; then
        print_success "WireGuard VPN disconnected successfully"
    else
        print_error "Failed to disconnect WireGuard VPN"
        print_info "You may need to manually disconnect using:"
        echo "  sudo wg-quick down ${WG_CONFIG_FILE}"
        # Extract interface name from config file path for ip link delete
        local interface_name=$(basename "$WG_CONFIG_FILE" .conf)
        echo "  or"
        echo "  sudo ip link delete ${interface_name}"
        return 1
    fi
}

show_status() {
    validate_prerequisites
    print_header "WireGuard VPN Status"

    print_info "Checking VPN connectivity..."
    if WORKING_COUNT=$(test_wireguard_connectivity); then
        print_success "WireGuard VPN is active ($WORKING_COUNT/${#VM_HOSTS[@]} VMs reachable)"
    else
        print_info "WireGuard VPN not detected ($WORKING_COUNT/${#VM_HOSTS[@]} VMs reachable)"
    fi
}

cleanup_orphaned_interfaces() {
    print_header "Clean Up Orphaned WireGuard Interfaces"
    
    if [[ "$(uname)" != "Darwin" ]]; then
        print_info "This command is only available on macOS"
        return 0
    fi
    
    local orphaned_interfaces=($(list_macos_wireguard_interfaces))
    
    if [[ ${#orphaned_interfaces[@]} -eq 0 ]]; then
        print_success "No orphaned WireGuard interfaces found"
        return 0
    fi
    
    print_warning "Found ${#orphaned_interfaces[@]} orphaned WireGuard interface(s):"
    for i in "${!orphaned_interfaces[@]}"; do
        echo "  $((i+1))) ${orphaned_interfaces[$i]}"
    done
    
    if [[ "$SKIP_PROMPTS" == "true" ]]; then
        # In non-interactive mode, clean up all orphaned interfaces
        print_info "Non-interactive mode: cleaning up all orphaned interfaces..."
        for intf in "${orphaned_interfaces[@]}"; do
            cleanup_macos_wireguard_interface "$intf"
        done
    else
        # Interactive mode: let user choose
        echo ""
        read -p "Enter number to clean up (1-${#orphaned_interfaces[@]}), 'a' for all, or Enter to skip: " -r choice
        
        if [[ "$choice" == "a" ]]; then
            # Use the comprehensive cleanup function for 'all'
            cleanup_all_macos_wireguard_interfaces
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#orphaned_interfaces[@]} ]]; then
            cleanup_macos_wireguard_interface "${orphaned_interfaces[$((choice-1))]}"
        else
            print_info "Skipping cleanup"
        fi
    fi
}

# Default values
SKIP_PROMPTS=false
NO_WAIT=false

# Parse standard arguments
PARSED_ARGS=$(parse_standard_args "$@")
eval "$PARSED_ARGS"

# Get command from positional arguments
COMMAND="${POSITIONAL_ARGS[0]:-connect}"

# Check for help flag
if [[ "$SHOW_HELP" == "true" ]]; then
    show_usage
    exit 0
fi

# Execute command
case "$COMMAND" in
    "connect")
        connect_wireguard
        ;;
    "disconnect")
        disconnect_wireguard
        ;;
    "test")
        test_connectivity
        ;;
    "status")
        show_status
        ;;
    "cleanup")
        cleanup_orphaned_interfaces
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
