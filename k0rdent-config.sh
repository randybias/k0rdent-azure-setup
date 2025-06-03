#!/usr/bin/env bash

# k0rdent-config.sh
# Central configuration file for k0rdent Azure setup scripts
# Source this file in other scripts: source ./k0rdent-config.sh

# Load user configuration and computed internal variables
source ./config-user.sh
source ./config-internal.sh

# ---- Legacy Variable Mappings ----
# Map new variable names to legacy names for backward compatibility
LOCATION="$AZURE_LOCATION"
ADMIN_USER="$SSH_USERNAME"
VM_SIZE="$AZURE_WORKER_VM_SIZE"  # Default to worker size for compatibility
IMAGE="$AZURE_VM_IMAGE"
PRIORITY="$AZURE_VM_PRIORITY"
EVICTION_POLICY="$AZURE_EVICTION_POLICY"

# Map timeout variables
VM_WAIT_TIMEOUT_MINUTES="$VM_CREATION_TIMEOUT_MINUTES"
VM_CHECK_INTERVAL_SECONDS="$VM_WAIT_CHECK_INTERVAL"

# Additional legacy variables not in user config
SSH_TIMEOUT_SECONDS=10
CLOUD_INIT_TIMEOUT_MINUTES=10
CLOUD_INIT_CHECK_INTERVAL_SECONDS=30
VERIFICATION_RETRY_COUNT=3
VERIFICATION_RETRY_DELAY_SECONDS=10

# ---- Directory Configuration ----
# Legacy directory names
KEYDIR="$WG_KEYDIR"
CLOUDINITS="$CLOUD_INIT_DIR"

# File paths
WG_MANIFEST="$KEYDIR/wg-key-manifest.csv"
AZURE_MANIFEST="$MANIFEST_DIR/azure-resource-manifest.csv"
WG_PORT_FILE="$MANIFEST_DIR/wireguard-port.txt"

# ---- Script Dependencies ----

# Script execution order for reference
SCRIPT_ORDER=(
    "generate-wg-keys.sh"
    "setup-azure-network.sh" 
    "generate-cloud-init.sh"
    "create-azure-vms.sh"
)

echo "==> k0rdent configuration loaded (prefix: $K0RDENT_PREFIX, region: $LOCATION)" 
