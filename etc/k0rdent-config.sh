#!/usr/bin/env bash

# k0rdent-config.sh
# Central configuration file for k0rdent Azure setup scripts
# Source this file in other scripts: source ./k0rdent-config.sh

# Load user configuration and computed internal variables
source ./etc/config-user.sh
source ./etc/config-internal.sh

# ---- Directory Configuration ----

# File paths
WG_MANIFEST="$WG_DIR/wg-key-manifest.csv"
AZURE_MANIFEST="$MANIFEST_DIR/azure-resource-manifest.csv"
WG_PORT_FILE="$WG_DIR/wireguard-port.txt"

# WireGuard laptop configuration
WG_CONFIG_DIR="./laptop-wg-config"
WG_CONFIG_FILE="$WG_CONFIG_DIR/wgk0${RANDOM_SUFFIX}.conf"


echo "==> k0rdent configuration loaded (prefix: $K0RDENT_PREFIX, region: $AZURE_LOCATION)" 
