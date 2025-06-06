#!/usr/bin/env bash

# Script: generate-cloud-init.sh
# Purpose: Generate per-VM cloud-init YAMLs for ARM64 Debian 12 with WireGuard, using pre-generated keys.
# Usage: bash generate-cloud-init.sh [command] [options]
# Expects: wg-key-manifest.csv and all key files in ./wg-keys
#          wireguard-port.txt from azure network setup

set -euo pipefail

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  deploy    Generate cloud-init YAML files
  reset     Remove all cloud-init files
  status    Show cloud-init generation status
  help      Show this help message" \
        "  -y, --yes        Assume yes to all prompts
  -q, --quiet      Suppress non-error output
  -v, --verbose    Enable verbose output" \
        "  $0 deploy        # Generate cloud-init files
  $0 deploy -y     # Generate without prompts
  $0 status        # Show generation status
  $0 reset -y      # Remove files without confirmation"
}

show_status() {
    print_header "Cloud-Init Files Status"
    
    if [[ ! -d "$CLOUDINITS" ]]; then
        print_info "Cloud-init directory does not exist: $CLOUDINITS"
        print_info "No cloud-init files have been generated yet."
        return
    fi
    
    # Count files
    local file_count=$(find "$CLOUDINITS" -name "*-cloud-init.yaml" | wc -l)
    local expected_count=${#VM_HOSTS[@]}
    
    print_info "Cloud-init directory: $CLOUDINITS"
    print_info "Files generated: $file_count of $expected_count expected"
    
    # Check WireGuard port
    if [[ -f "$WG_PORT_FILE" ]]; then
        local port=$(cat "$WG_PORT_FILE")
        print_info "WireGuard port configured: $port"
    else
        print_error "WireGuard port file missing: $WG_PORT_FILE"
    fi
    
    # Show which hosts have cloud-init files
    echo ""
    echo "Host Cloud-Init Status:"
    for HOST in "${VM_HOSTS[@]}"; do
        CLOUDINIT="$CLOUDINITS/${HOST}-cloud-init.yaml"
        
        if [[ -f "$CLOUDINIT" ]]; then
            print_success "$HOST: Cloud-init file exists"
            if [[ "$VERBOSE_MODE" == "true" ]]; then
                print_info_verbose "  File size: $(stat -f%z "$CLOUDINIT" 2>/dev/null || stat -c%s "$CLOUDINIT") bytes"
                print_info_verbose "  Modified: $(stat -f "%Sm" "$CLOUDINIT" 2>/dev/null || stat -c "%y" "$CLOUDINIT" | cut -d' ' -f1-2)"
            fi
        else
            print_error "$HOST: Cloud-init file missing"
        fi
    done
    
    # Check dependencies
    echo ""
    echo "Dependencies:"
    if [[ -f "$WG_MANIFEST" ]]; then
        print_success "WireGuard manifest exists"
    else
        print_error "WireGuard manifest missing"
    fi
    
    if [[ -f "$WG_PORT_FILE" ]]; then
        print_success "WireGuard port file exists"
    else
        print_error "WireGuard port file missing"
    fi
}

deploy_cloudinit() {
    # Check for required files
    if ! check_file_exists "$WG_MANIFEST" "WireGuard manifest"; then
        print_error "Run: ./generate-wg-keys.sh deploy"
        exit 1
    fi
    
    if ! check_file_exists "$WG_PORT_FILE" "WireGuard port file"; then
        print_error "Run: ./setup-azure-network.sh deploy"
        exit 1
    fi
    
    # Check if files already exist
    if [[ -d "$CLOUDINITS" ]] && [[ -n "$(find "$CLOUDINITS" -name "*-cloud-init.yaml" 2>/dev/null)" ]]; then
        print_warning "Cloud-init files already exist."
        if ! confirm_action "Do you want to regenerate all cloud-init files?"; then
            print_info "Cloud-init generation cancelled."
            exit 0
        fi
        print_info_quiet "Removing existing cloud-init files..."
        rm -f "$CLOUDINITS"/*-cloud-init.yaml
    fi
    
    # Read the WireGuard port
    WIREGUARD_PORT=$(cat "$WG_PORT_FILE")
    print_info_quiet "Using WireGuard port: $WIREGUARD_PORT"
    
    ensure_directory "$CLOUDINITS"
    
    # Load manifest as associative arrays
    declare -A PRIVKEYS
    declare -A PUBKEYS
    declare -A WGIPS
    
    while IFS=, read -r host wgip priv pub; do
      PRIVKEYS["$host"]="$priv"
      PUBKEYS["$host"]="$pub"
      WGIPS["$host"]="$wgip"
    done < <(tail -n +2 "$WG_MANIFEST")  # Skip header
    
    # Get laptop public key and IP for peer config
    LAPTOP_PUBKEY="${PUBKEYS[mylaptop]}"
    LAPTOP_WGIP="${WGIPS[mylaptop]}"
    
    # Generate cloud-init for each VM
    for HOST in "${VM_HOSTS[@]}"; do
        WG_PRIVKEY="${PRIVKEYS[$HOST]}"
        WG_PUBKEY="${PUBKEYS[$HOST]}"
        WG_IP="${WGIPS[$HOST]}"
        
        CLOUDINIT="$CLOUDINITS/${HOST}-cloud-init.yaml"
        
        print_info_quiet "Generating cloud-init for $HOST..."
        
        cat > "$CLOUDINIT" <<EOF
#cloud-config
#
# Cloud-init for $HOST (Debian 12 ARM64, WireGuard)
#

package_update: true
package_upgrade: true
packages:
  - wireguard

write_files:
  - path: /etc/wireguard/privatekey
    permissions: '0600'
    owner: root:root
    content: |
      $WG_PRIVKEY

  - path: /etc/wireguard/wg0.conf
    permissions: '0600'
    owner: root:root
    content: |
      [Interface]
      PrivateKey = $WG_PRIVKEY
      Address = $WG_IP/32
      ListenPort = $WIREGUARD_PORT

      # This is your laptop as the hub. 
      [Peer]
      PublicKey = $LAPTOP_PUBKEY
      AllowedIPs = $LAPTOP_WGIP/32
      # Endpoint = <LAPTOP_PUBLIC_IP>:$WIREGUARD_PORT  # Not set here; hub initiates connection

runcmd:
  - [ systemctl, enable, wg-quick@wg0 ]
  - [ systemctl, start, wg-quick@wg0 ]
  - [ touch, /var/lib/cloud/instance/locale-check.skip ]
  - [ apt, update ]
  - [ apt, install, locales-all ]

final_message: "Cloud-init finished for $HOST. WireGuard is configured (waiting for laptop/hub to connect)."
EOF
        
        print_info_verbose "Generated $CLOUDINIT"
    done
    
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo
        print_success "All per-node cloud-init YAMLs written to: $CLOUDINITS/"
        print_info "Using WireGuard port: $WIREGUARD_PORT"
        print_info "You can now use these with Azure VM creation."
    fi
}

reset_cloudinit() {
    if [[ ! -d "$CLOUDINITS" ]]; then
        print_info "Cloud-init directory does not exist. Nothing to reset."
        exit 0
    fi
    
    if [[ "$SKIP_PROMPTS" == "false" ]]; then
        read -p "This will remove all cloud-init files. Are you sure? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "Reset cancelled."
            exit 0
        fi
    fi
    
    print_info "Resetting cloud-init directory: $CLOUDINITS"
    rm -rf "$CLOUDINITS"
    print_success "Cloud-init files removed"
}

# Store original arguments for handle_standard_commands
ORIGINAL_ARGS=("$@")

# Use consolidated command handling
handle_standard_commands "$0" "deploy reset status help" \
    "deploy" "deploy_cloudinit" \
    "reset" "reset_cloudinit" \
    "status" "show_status" \
    "usage" "show_usage"