#!/usr/bin/env bash

# Script: generate-cloud-init.sh
# Purpose: Generate per-VM cloud-init YAMLs for ARM64 Debian 12 with WireGuard, using pre-generated keys.
# Usage: bash generate-cloud-init.sh [reset]
# Expects: wg-key-manifest.csv and all key files in ./wg-keys
#          wireguard-port.txt from azure network setup

set -euo pipefail

# Load central configuration and common functions
source ./k0rdent-config.sh
source ./common-functions.sh

# Handle reset argument
if [[ "${1:-}" == "reset" ]]; then
    print_info "Resetting cloud-init directory: $CLOUDINITS"
    rm -rf "$CLOUDINITS"
    exit
fi

# Check for required files
if ! check_file_exists "$WG_MANIFEST" "WireGuard manifest"; then
    print_error "Run generate-wg-keys.sh first."
    exit 1
fi

if ! check_file_exists "$WG_PORT_FILE" "WireGuard port file"; then
    print_error "Run setup-azure-network.sh first."
    exit 1
fi

# Read the WireGuard port
WIREGUARD_PORT=$(cat "$WG_PORT_FILE")
print_info "Using WireGuard port: $WIREGUARD_PORT"

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

for HOST in "${VM_HOSTS[@]}"; do

  WG_PRIVKEY="${PRIVKEYS[$HOST]}"
  WG_PUBKEY="${PUBKEYS[$HOST]}"
  WG_IP="${WGIPS[$HOST]}"

  CLOUDINIT="$CLOUDINITS/${HOST}-cloud-init.yaml"

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

      # This is your laptop as the hub. 
      [Peer]
      PublicKey = $LAPTOP_PUBKEY
      AllowedIPs = $LAPTOP_WGIP/32
      # Endpoint = <LAPTOP_PUBLIC_IP>:$WIREGUARD_PORT  # Not set here; hub initiates connection

runcmd:
  - [ systemctl, enable, wg-quick@wg0 ]
  - [ systemctl, start, wg-quick@wg0 ]

final_message: "Cloud-init finished for $HOST. WireGuard is configured (waiting for laptop/hub to connect)."
EOF

  print_success "Wrote $CLOUDINIT"
done

echo
print_success "All per-node cloud-init YAMLs written to: $CLOUDINITS/"
print_info "Using WireGuard port: $WIREGUARD_PORT"
print_info "You can now use these with Azure VM creation."
