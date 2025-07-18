#!/usr/bin/env bash

# k0rdent-config.sh
# Central configuration file for k0rdent Azure setup scripts
# Source this file in other scripts: source ./k0rdent-config.sh

# Configuration loading with YAML support
CONFIG_YAML="./config/k0rdent.yaml"
CONFIG_DEFAULT_YAML="./config/k0rdent-default.yaml"

# Load configuration in priority order
if [[ -f "$CONFIG_YAML" ]]; then
    echo "==> Loading YAML configuration: $CONFIG_YAML"
    source <(./bin/configure.sh export --file "$CONFIG_YAML")
elif [[ -f "$CONFIG_DEFAULT_YAML" ]]; then
    echo "==> Loading default YAML configuration: $CONFIG_DEFAULT_YAML"
    source <(./bin/configure.sh export --file "$CONFIG_DEFAULT_YAML")
else
    echo "ERROR: No configuration found. Run: ./bin/configure.sh init"
    exit 1
fi

# Load computed internal variables
source ./etc/config-internal.sh

# ---- Directory Configuration ----

# Note: Azure resource tracking now handled via deployment-state.yaml
# Legacy CSV manifest support removed in favor of state management

# WireGuard laptop configuration
WG_CONFIG_FILE="$WG_DIR/wgk0${RANDOM_SUFFIX}.conf"


echo "==> k0rdent configuration loaded (cluster ID: $K0RDENT_CLUSTERID, region: $AZURE_LOCATION)" 
