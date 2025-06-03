#!/usr/bin/env bash

# Script: generate-laptop-wg-config.sh
# Purpose: Generate WireGuard configuration file for laptop to connect to k0rdent VMs
# Usage: bash generate-laptop-wg-config.sh [command] [options]
# Prerequisites: Run full deployment first (VMs must be created and running)

set -euo pipefail

# Load central configuration and common functions
source ./k0rdent-config.sh
source ./common-functions.sh

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  deploy    Generate laptop WireGuard configuration
  reset     Remove laptop WireGuard configuration
  status    Show configuration status
  help      Show this help message" \
        "  -y, --yes        Assume yes to all prompts
  -q, --quiet      Suppress non-error output
  -v, --verbose    Enable verbose output" \
        "  $0 deploy        # Generate laptop WireGuard config
  $0 status        # Check configuration status
  $0 reset -y      # Remove configuration without confirmation"
}

show_status() {
    print_header "Laptop WireGuard Configuration Status"
    
    CONFIG_DIR="./laptop-wg-config"
    CONFIG_FILE="$CONFIG_DIR/k0rdent-cluster.conf"
    
    if [[ ! -d "$CONFIG_DIR" || ! -f "$CONFIG_FILE" ]]; then
        print_info "No laptop WireGuard configuration found."
        print_info "Run '$0 deploy' to generate configuration."
        return
    fi
    
    print_info "Configuration file: $CONFIG_FILE"
    print_info "File created: $(stat -f '%Sm' "$CONFIG_FILE" 2>/dev/null || stat -c '%y' "$CONFIG_FILE" 2>/dev/null | cut -d' ' -f1,2)"
    
    # Extract configuration details
    local laptop_ip=$(grep "^Address" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
    local peer_count=$(grep -c "^\[Peer\]" "$CONFIG_FILE" || echo "0")
    local endpoint=$(grep "^Endpoint" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ' | cut -d':' -f2)
    
    print_info "Laptop WireGuard IP: $laptop_ip"
    print_info "WireGuard port: $endpoint"
    print_info "Configured peers: $peer_count"
    
    if [[ $VERBOSE == true ]]; then
        echo
        print_info "Peer endpoints:"
        grep "^Endpoint" "$CONFIG_FILE" | while read -r line; do
            echo "  - ${line#*= }"
        done
    fi
}

reset_laptop_config() {
    CONFIG_DIR="./laptop-wg-config"
    
    if [[ $YES != true ]]; then
        read -p "Are you sure you want to remove the laptop WireGuard configuration? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Reset cancelled."
            return
        fi
    fi
    
    print_info "Resetting laptop WireGuard configuration..."
    if [[ -d "$CONFIG_DIR" ]]; then
        rm -rf "$CONFIG_DIR"
        print_success "Laptop WireGuard configuration directory removed: $CONFIG_DIR"
    else
        print_info "No laptop WireGuard configuration directory found"
    fi
}

deploy_laptop_config() {
    # Check if Azure CLI is installed and user is authenticated
    check_azure_cli

print_header "Generating Laptop WireGuard Configuration"

# Validate prerequisites
print_info "Validating prerequisites..."

# Check if WireGuard keys exist
if ! check_file_exists "$WG_MANIFEST" "WireGuard key manifest"; then
    print_error "WireGuard keys not found. Run generate-wg-keys.sh first."
    exit 1
fi

# Check if WireGuard port file exists
if ! check_file_exists "$WG_PORT_FILE" "WireGuard port file"; then
    print_error "WireGuard port not found. Run setup-azure-network.sh first."
    exit 1
fi

# Check if VMs exist and get their public IPs
print_info "Checking VM deployment status..."

VM_DEPLOYED=true
declare -A VM_PUBLIC_IPS

for HOST in "${VM_HOSTS[@]}"; do
    # Try to get VM public IP
    PUBLIC_IP=$(az vm show --resource-group "$RG" --name "$HOST" --show-details --query "publicIps" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$PUBLIC_IP" ]]; then
        print_error "VM $HOST is not deployed or has no public IP"
        VM_DEPLOYED=false
    else
        VM_PUBLIC_IPS["$HOST"]="$PUBLIC_IP"
        print_info "  $HOST: $PUBLIC_IP"
    fi
done

if [[ "$VM_DEPLOYED" != "true" ]]; then
    print_error "Not all VMs are deployed. Run create-azure-vms.sh first."
    exit 1
fi

print_success "All VMs found with public IPs"

# Read WireGuard port
WG_PORT=$(cat "$WG_PORT_FILE")
print_info "WireGuard port: $WG_PORT"

# Read laptop private key from manifest
LAPTOP_PRIVATE_KEY=""
while IFS=',' read -r hostname wg_ip private_key public_key; do
    # Skip header line
    if [[ "$hostname" == "hostname" ]]; then
        continue
    fi
    
    if [[ "$hostname" == "mylaptop" ]]; then
        LAPTOP_PRIVATE_KEY="$private_key"
        print_info "Found laptop private key"
        break
    fi
done < "$WG_MANIFEST"

if [[ -z "$LAPTOP_PRIVATE_KEY" ]]; then
    print_error "Laptop private key not found in manifest"
    exit 1
fi

# Generate WireGuard configuration
CONFIG_DIR="./laptop-wg-config"
CONFIG_FILE="$CONFIG_DIR/k0rdent-cluster.conf"

ensure_directory "$CONFIG_DIR"

print_info "Generating WireGuard configuration: $CONFIG_FILE"

cat > "$CONFIG_FILE" << EOF
# k0rdent Cluster WireGuard Configuration
# Generated: $(date)
# Cluster: ${K0RDENT_PREFIX}

[Interface]
PrivateKey = $LAPTOP_PRIVATE_KEY
Address = ${WG_IPS["mylaptop"]}/32

EOF

# Add peer configuration for each VM
while IFS=',' read -r hostname wg_ip private_key public_key; do
    # Skip header line and laptop entry
    if [[ "$hostname" == "hostname" || "$hostname" == "mylaptop" ]]; then
        continue
    fi
    
    # Check if this is one of our VM hosts
    if [[ " ${VM_HOSTS[*]} " =~ " ${hostname} " ]]; then
        VM_PUBLIC_KEY="$public_key"
        VM_PUBLIC_IP="${VM_PUBLIC_IPS[$hostname]}"
        
        cat >> "$CONFIG_FILE" << EOF
# Peer: $hostname (${WG_IPS[$hostname]})
[Peer]
PublicKey = $VM_PUBLIC_KEY
AllowedIPs = ${WG_IPS[$hostname]}/32
Endpoint = $VM_PUBLIC_IP:$WG_PORT
PersistentKeepalive = 25

EOF
        print_info "Added peer: $hostname (${WG_IPS[$hostname]} -> $VM_PUBLIC_IP:$WG_PORT)"
    fi
done < "$WG_MANIFEST"

print_success "WireGuard configuration generated successfully"

echo
print_header "Configuration Summary"
echo "Configuration file: $CONFIG_FILE"
echo "Laptop WireGuard IP: ${WG_IPS["mylaptop"]}"
echo "WireGuard port: $WG_PORT"
echo "VM peers configured: ${#VM_HOSTS[@]}"

echo
print_header "Next Steps"
echo "1. Install the configuration on your laptop:"
echo "   # macOS with WireGuard app:"
echo "   open $CONFIG_FILE"
echo ""
echo "   # Linux with wg-quick:"
echo "   sudo cp $CONFIG_FILE /etc/wireguard/"
echo "   sudo systemctl enable wg-quick@k0rdent-cluster"
echo "   sudo systemctl start wg-quick@k0rdent-cluster"
echo ""
echo "2. Test connectivity to VMs:"
for HOST in "${VM_HOSTS[@]}"; do
    echo "   ping ${WG_IPS[$HOST]}  # $HOST"
done
echo ""
echo "3. Verify WireGuard status:"
echo "   sudo wg show"

echo
print_info "Configuration file contents:"
echo "----------------------------------------"
cat "$CONFIG_FILE"
echo "----------------------------------------"
}

# Parse arguments
parse_common_args "$@" || parse_result=$?

if [[ $parse_result -eq 1 ]]; then
    # Help was requested
    show_usage
    exit 0
elif [[ $parse_result -eq 2 ]]; then
    # Invalid argument
    show_usage
    exit 1
fi

# Execute command
case "$COMMAND" in
    "deploy")
        deploy_laptop_config
        ;;
    "reset")
        reset_laptop_config
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