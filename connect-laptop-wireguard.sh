#!/usr/bin/env bash

# Script: connect-laptop-wireguard.sh
# Purpose: Set up and test WireGuard VPN connection to k0rdent cluster
# Usage: bash connect-laptop-wireguard.sh
# Prerequisites: WireGuard configuration must be generated first

set -euo pipefail

# Load central configuration and common functions
source ./k0rdent-config.sh
source ./common-functions.sh

print_header "k0rdent WireGuard VPN Setup"

# Configuration file path
CONFIG_DIR="./laptop-wg-config"
CONFIG_FILE="$CONFIG_DIR/k0rdent-cluster.conf"

# Check if configuration file exists
if ! check_file_exists "$CONFIG_FILE" "WireGuard configuration"; then
    print_error "WireGuard configuration not found. Run ./generate-laptop-wg-config.sh first."
    exit 1
fi

# Check if netcat is installed (needed for connectivity testing)
if ! command -v nc &> /dev/null; then
    print_error "netcat (nc) not found. Please install netcat first:"
    echo "  brew install netcat"
    exit 1
fi

print_success "WireGuard configuration found: $CONFIG_FILE"

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

# Check current VPN status
print_info "Checking current VPN connectivity..."
if WORKING_COUNT=$(test_wireguard_connectivity); then
    print_success "WireGuard VPN is already active ($WORKING_COUNT/${#VM_HOSTS[@]} VMs reachable)"
    print_info "Skipping setup - proceeding to final connectivity test..."
else
    print_info "WireGuard VPN not detected ($WORKING_COUNT/${#VM_HOSTS[@]} VMs reachable)"
    
    # Provide setup options
    if [[ $YES == true ]]; then
        # Non-interactive mode: use CLI tools
        print_info "Non-interactive mode: using wg-quick..."
        
        # Check if WireGuard tools are installed
        if ! command -v wg &> /dev/null; then
            print_error "WireGuard tools not found. Please install first:"
            echo "  brew install wireguard-tools"
            exit 1
        fi
        
        # Start the interface directly from local config file
        print_info "Starting WireGuard interface from: $CONFIG_FILE"
        if sudo wg-quick up "$CONFIG_FILE"; then
            print_success "WireGuard interface started successfully"
        else
            print_error "Failed to start WireGuard interface"
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
                print_header "WireGuard GUI Setup"
                echo "Steps to import configuration:"
                echo "1. Open the WireGuard app (install from Mac App Store if needed)"
                echo "2. Click 'Import Tunnel(s) from File...'"
                echo "3. Select the configuration file: $CONFIG_FILE"
                echo "4. Activate the tunnel in the WireGuard app"
                echo ""
                read -p "Press Enter after you've imported and activated the tunnel in WireGuard app..."
                break
                ;;
            2)
                print_header "Command-line wg-quick Setup"
                
                # Check if WireGuard tools are installed
                if ! command -v wg &> /dev/null; then
                    print_error "WireGuard tools not found. Please install first:"
                    echo "  brew install wireguard-tools"
                    exit 1
                fi
                
                # Start the interface directly from local config file
                print_info "Starting WireGuard interface from: $CONFIG_FILE"
                if sudo wg-quick up "$CONFIG_FILE"; then
                    print_success "WireGuard interface started successfully"
                else
                    print_error "Failed to start WireGuard interface"
                    exit 1
                fi
                break
                ;;
            3)
                print_header "Detailed Connectivity Test"
                
                # Run detailed connectivity test
                declare -A PING_RESULTS
                declare -A SSH_RESULTS
                ALL_REACHABLE=true
                SSH_KEY="./azure-resources/${K0RDENT_PREFIX}-ssh-key"
                
                for HOST in "${VM_HOSTS[@]}"; do
                    VM_IP="${WG_IPS[$HOST]}"
                    print_info "Testing connectivity to $HOST ($VM_IP)..."
                    
                    # Test ping connectivity
                    if ping -c 3 -W 5000 "$VM_IP" >/dev/null 2>&1; then
                        print_success "  ✓ Ping to $HOST successful"
                        PING_RESULTS["$HOST"]="success"
                        
                        # Test SSH connectivity if ping works
                        if [[ -f "$SSH_KEY" ]]; then
                            if ssh -i "$SSH_KEY" \
                                   -o ConnectTimeout=10 \
                                   -o StrictHostKeyChecking=no \
                                   -o UserKnownHostsFile=/dev/null \
                                   -o LogLevel=ERROR \
                                   "k0rdent@$VM_IP" \
                                   "echo 'SSH via WireGuard successful'" >/dev/null 2>&1; then
                                print_success "  ✓ SSH to $HOST via WireGuard successful"
                                SSH_RESULTS["$HOST"]="success"
                            else
                                print_warning "  ⚠ SSH to $HOST failed (ping works, check SSH keys)"
                                SSH_RESULTS["$HOST"]="failed"
                            fi
                        else
                            print_warning "  ⚠ SSH key not found, skipping SSH test for $HOST"
                            SSH_RESULTS["$HOST"]="no_key"
                        fi
                    else
                        print_error "  ✗ Ping to $HOST failed"
                        PING_RESULTS["$HOST"]="failed"
                        SSH_RESULTS["$HOST"]="no_ping"
                        ALL_REACHABLE=false
                    fi
                done
                
                # Detailed summary
                print_header "Detailed Test Results"
                
                for HOST in "${VM_HOSTS[@]}"; do
                    VM_IP="${WG_IPS[$HOST]}"
                    PING_STATUS="${PING_RESULTS[$HOST]}"
                    SSH_STATUS="${SSH_RESULTS[$HOST]}"
                    
                    if [[ "$PING_STATUS" == "success" && "$SSH_STATUS" == "success" ]]; then
                        print_success "  ✓ $HOST ($VM_IP) - Ping & SSH working"
                    elif [[ "$PING_STATUS" == "success" && "$SSH_STATUS" == "failed" ]]; then
                        print_warning "  ⚠ $HOST ($VM_IP) - Ping works, SSH failed"
                    elif [[ "$PING_STATUS" == "success" && "$SSH_STATUS" == "no_key" ]]; then
                        print_warning "  ⚠ $HOST ($VM_IP) - Ping works, SSH not tested (no key)"
                    else
                        print_error "  ✗ $HOST ($VM_IP) - Ping failed"
                    fi
                done
                
                if [[ "$ALL_REACHABLE" == "true" ]]; then
                    print_success "🎉 All detailed tests passed!"
                else
                    print_warning "Some detailed connectivity issues detected."
                fi
                
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
fi

# Final verification
print_header "Verifying WireGuard Connection"

print_info "Testing VPN connectivity..."
if WORKING_COUNT=$(test_wireguard_connectivity); then
    print_success "🎉 WireGuard VPN is working correctly ($WORKING_COUNT/${#VM_HOSTS[@]} VMs reachable)"
    echo
    print_info "You can now:"
    echo "  • SSH to VMs: ssh -i ./azure-resources/${K0RDENT_PREFIX}-ssh-key k0rdent@<VM_WIREGUARD_IP>"
    echo "  • Deploy k0rdent cluster using the WireGuard network"
    echo "  • Access services running on the VMs via their internal IPs"
else
    print_error "WireGuard VPN is not working ($WORKING_COUNT/${#VM_HOSTS[@]} VMs reachable)"
    print_info "Please check your WireGuard configuration and try again"
    exit 1
fi

echo
print_info "To disconnect WireGuard:"
echo "  • GUI: Deactivate tunnel in WireGuard app"
echo "  • CLI: sudo wg-quick down $CONFIG_FILE"
