#!/usr/bin/env bash

# Script: generate-wg-keys.sh
# Purpose: Generate WireGuard key pairs for each node in the mesh.
#          Output a CSV manifest for use in cloud-init and laptop config.
#          All files and manifest are stored in ./wg-keys
# Usage: bash generate-wg-keys.sh [reset]

set -euo pipefail

# Load central configuration and common functions
source ./k0rdent-config.sh
source ./common-functions.sh

# Check if WireGuard tools are installed
check_wireguard_tools

# Handle reset argument
if [[ "${1:-}" == "reset" ]]; then
    print_info "Resetting key directory: $KEYDIR"
    rm -rf "$KEYDIR"
    exit
fi

# Only create new manifest if it doesn't exist or we're resetting
if [[ ! -f "$WG_MANIFEST" ]]; then
    print_info "Creating key directory: $KEYDIR"
    ensure_directory "$KEYDIR"
    print_info "Creating new manifest file..."
    echo "hostname,wireguard_ip,private_key,public_key" > "$WG_MANIFEST"
else
    print_info "Manifest file already exists, exiting..."
    exit
fi

# --- Key Generation Loop ---
# For each host in the WG_IPS array:
# 1. Generate WireGuard private and public key pair if they don't exist
# 2. Store keys in separate files with appropriate permissions
# 3. Add entry to CSV manifest with hostname, IP, and keys
for HOST in "${!WG_IPS[@]}"; do
    WG_IP="${WG_IPS[$HOST]}"
    PRIV_FILE="$KEYDIR/${HOST}_privkey"
    PUB_FILE="$KEYDIR/${HOST}_pubkey"

    # Skip if both key files exist
    if [[ -f "$PRIV_FILE" && -f "$PUB_FILE" ]]; then
        print_info "Keys already exist for $HOST, skipping..."
        continue
    fi

    print_info "Generating keys for $HOST..."
    # Generate keys
    wg genkey | tee "$PRIV_FILE" | wg pubkey > "$PUB_FILE"

    PRIV=$(cat "$PRIV_FILE")
    PUB=$(cat "$PUB_FILE")

    # Output CSV manifest line
    echo "$HOST,$WG_IP,$PRIV,$PUB" >> "$WG_MANIFEST"

    # File permissions
    chmod 600 "$PRIV_FILE"
    chmod 644 "$PUB_FILE"
done

echo
print_success "WireGuard keys stored in $KEYDIR"
print_success "Manifest file at: $WG_MANIFEST"
echo
print_info "Next steps:"
print_info "  1. Use the manifest to prepare per-VM cloud-init files and the laptop WireGuard config."
print_info "  2. Proceed with Azure network setup."
echo
