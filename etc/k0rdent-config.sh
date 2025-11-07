#!/usr/bin/env bash

# k0rdent-config.sh
# Central configuration file for k0rdent Azure setup scripts
# Source this file in other scripts: source ./k0rdent-config.sh

# Configuration loading with YAML support
CONFIG_YAML="./config/k0rdent.yaml"
CONFIG_DEFAULT_YAML="./config/k0rdent-default.yaml"

# Allow caller to override the configuration file
if [[ -n "${K0RDENT_CONFIG_FILE:-}" ]]; then
    if [[ ! -f "$K0RDENT_CONFIG_FILE" ]]; then
        echo "ERROR: Custom config file not found: $K0RDENT_CONFIG_FILE"
        exit 1
    fi
    CONFIG_YAML="$K0RDENT_CONFIG_FILE"
fi

# Load configuration in priority order
NOUNSET_WAS_ON=0
if [[ -o nounset ]]; then
    NOUNSET_WAS_ON=1
    set +u
fi

if [[ -f "$CONFIG_YAML" ]]; then
    echo "==> Loading YAML configuration: $CONFIG_YAML"
    eval "$(./bin/configure.sh export --file "$CONFIG_YAML")"
elif [[ -f "$CONFIG_DEFAULT_YAML" ]]; then
    echo "==> Loading default YAML configuration: $CONFIG_DEFAULT_YAML"
    eval "$(./bin/configure.sh export --file "$CONFIG_DEFAULT_YAML")"
else
    echo "ERROR: No configuration found. Run: ./bin/configure.sh init"
    exit 1
fi

if [[ $NOUNSET_WAS_ON -eq 1 ]]; then
    set -u
fi

# Load computed internal variables
source ./etc/config-internal.sh

# ---- Directory Configuration ----

# Note: Azure resource tracking now handled via deployment-state.yaml
# Legacy CSV manifest support removed in favor of state management

# WireGuard laptop configuration
# Extract suffix from cluster ID (everything after "k0rdent-")
CLUSTERID_SUFFIX="${K0RDENT_CLUSTERID#k0rdent-}"
WG_CONFIG_FILE="$WG_DIR/wgk0${CLUSTERID_SUFFIX}.conf"


echo "==> k0rdent configuration loaded (cluster ID: $K0RDENT_CLUSTERID, region: $AZURE_LOCATION)" 
