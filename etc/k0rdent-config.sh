#!/usr/bin/env bash

# k0rdent-config.sh
# Central configuration file for k0rdent Azure setup scripts
# Source this file in other scripts: source ./k0rdent-config.sh

# Source configuration resolution functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/config-resolution-functions.sh" ]]; then
    source "$SCRIPT_DIR/config-resolution-functions.sh"
else
    echo "ERROR: config-resolution-functions.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Configuration loading with YAML support
CONFIG_YAML="./config/k0rdent.yaml"
CONFIG_DEFAULT_YAML="./config/k0rdent-default.yaml"

# Deployment state file location
DEPLOYMENT_STATE_FILE="${DEPLOYMENT_STATE_FILE:-./state/deployment-state.yaml}"

# Load configuration in priority order using canonical resolution
NOUNSET_WAS_ON=0
if [[ -o nounset ]]; then
    NOUNSET_WAS_ON=1
    set +u
fi

# Resolve canonical configuration
# This will set K0RDENT_CONFIG_SOURCE, K0RDENT_CONFIG_FILE, and K0RDENT_CONFIG_TIMESTAMP
if ! resolve_canonical_config; then
    echo "ERROR: Failed to resolve configuration"
    exit 1
fi

# Load configuration based on resolved source
case "${K0RDENT_CONFIG_SOURCE:-default}" in
    deployment-state)
        # Configuration loaded from deployment state
        echo "==> Loading YAML configuration from deployment state: ${DEPLOYMENT_STATE_FILE}"

        # Check if state file has a source config file reference
        if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
            SOURCE_CONFIG_FILE=$(yq eval '.source_config_file // ""' "$DEPLOYMENT_STATE_FILE" 2>/dev/null)

            # If we have the source config file, load from it properly
            if [[ -n "$SOURCE_CONFIG_FILE" ]] && [[ -f "$SOURCE_CONFIG_FILE" ]]; then
                echo "==> Loading configuration from original config file: $SOURCE_CONFIG_FILE"
                eval "$(./bin/configure.sh export --file "$SOURCE_CONFIG_FILE")"
                CONFIG_YAML="$SOURCE_CONFIG_FILE"
            else
                # Fallback: Load minimal config from state and set safe defaults for missing variables
                echo "==> Loading minimal configuration from state (some defaults will be applied)"

                # Export the configuration section as environment variables, filtering out null values
                eval "$(yq eval '.config | to_entries | .[] | select(.value != null) | "export " + (.key | upcase | sub("-", "_")) + "=\"" + .value + "\""' "$DEPLOYMENT_STATE_FILE" 2>/dev/null)"

                # Set default zone arrays if not already set (required by config-internal.sh)
                export CONTROLLER_ZONES=(1)
                export WORKER_ZONES=(1)

                # Set default VM sizes if not already set
                export AZURE_CONTROLLER_VM_SIZE="${AZURE_CONTROLLER_VM_SIZE:-Standard_D2s_v5}"
                export AZURE_WORKER_VM_SIZE="${AZURE_WORKER_VM_SIZE:-Standard_D2s_v5}"

                # Set other commonly needed defaults
                export SSH_USERNAME="${SSH_USERNAME:-k0rdent}"
                export SSH_KEY_COMMENT="${SSH_KEY_COMMENT:-k0rdent-azure-key}"
                export AZURE_VM_IMAGE="${AZURE_VM_IMAGE:-Debian:debian-12:12-gen2:latest}"
                export AZURE_VM_PRIORITY="${AZURE_VM_PRIORITY:-Regular}"
                export AZURE_EVICTION_POLICY="${AZURE_EVICTION_POLICY:-Deallocate}"
                export VNET_PREFIX="${VNET_PREFIX:-10.0.0.0/16}"
                export SUBNET_PREFIX="${SUBNET_PREFIX:-10.0.1.0/24}"
                export K0S_VERSION="${K0S_VERSION:-v1.33.2+k0s.0}"
                export K0RDENT_VERSION="${K0RDENT_VERSION:-1.4.0}"
                export K0RDENT_OCI_REGISTRY="${K0RDENT_OCI_REGISTRY:-oci://ghcr.io/k0rdent/kcm/charts/kcm}"
                export K0RDENT_NAMESPACE="${K0RDENT_NAMESPACE:-kcm-system}"

                echo "WARNING: Source config file not available, using defaults for missing variables"
            fi

            # Also need to export the deployment_id as K0RDENT_CLUSTERID if not already set
            if [[ -z "${K0RDENT_CLUSTERID:-}" ]]; then
                export K0RDENT_CLUSTERID=$(yq eval '.deployment_id' "$DEPLOYMENT_STATE_FILE" 2>/dev/null)
            fi
        else
            echo "WARNING: Deployment state file not found, falling back to default configuration"
            K0RDENT_CONFIG_SOURCE="default"
        fi
        ;;

    explicit-override)
        # Use explicitly specified configuration file
        if [[ -n "${K0RDENT_CONFIG_FILE:-}" ]]; then
            if [[ ! -f "$K0RDENT_CONFIG_FILE" ]]; then
                echo "ERROR: Custom config file not found: $K0RDENT_CONFIG_FILE"
                exit 1
            fi
            echo "==> Loading YAML configuration (explicit override): $K0RDENT_CONFIG_FILE"
            eval "$(./bin/configure.sh export --file "$K0RDENT_CONFIG_FILE")"
            CONFIG_YAML="$K0RDENT_CONFIG_FILE"
        fi
        ;;

    default|*)
        # Fall back to default configuration file search (backward compatibility)
        if [[ -f "$CONFIG_YAML" ]]; then
            echo "==> Loading YAML configuration: $CONFIG_YAML"
            eval "$(./bin/configure.sh export --file "$CONFIG_YAML")"
            K0RDENT_CONFIG_FILE="$CONFIG_YAML"
        elif [[ -f "$CONFIG_DEFAULT_YAML" ]]; then
            echo "==> Loading default YAML configuration: $CONFIG_DEFAULT_YAML"
            eval "$(./bin/configure.sh export --file "$CONFIG_DEFAULT_YAML")"
            K0RDENT_CONFIG_FILE="$CONFIG_DEFAULT_YAML"
        else
            echo "ERROR: No configuration found. Run: ./bin/configure.sh init"
            exit 1
        fi
        ;;
esac

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

# Display configuration summary with source information
echo "==> k0rdent configuration loaded (cluster ID: $K0RDENT_CLUSTERID, region: $AZURE_LOCATION)"

# Show configuration source for transparency
show_configuration_source 
