#!/usr/bin/env bash
# Internal computed variables - DO NOT EDIT

# Note: User configuration now loaded via YAML in k0rdent-config.sh
# Shell-based config-user.sh is no longer used

# ---- Validation ----
# Ensure minimum node counts
if [[ $K0S_CONTROLLER_COUNT -lt 1 ]]; then
    echo "ERROR: K0S_CONTROLLER_COUNT must be at least 1"
    exit 1
fi

if [[ $K0S_WORKER_COUNT -lt 0 ]]; then
    echo "ERROR: K0S_WORKER_COUNT must be 0 or greater"
    exit 1
fi

# If no workers, ensure at least one controller (for workload scheduling)
if [[ $K0S_WORKER_COUNT -eq 0 ]] && [[ $K0S_CONTROLLER_COUNT -lt 1 ]]; then
    echo "ERROR: When K0S_WORKER_COUNT is 0, at least 1 controller is required"
    exit 1
fi

# Warn about worker count of 0
if [[ $K0S_WORKER_COUNT -eq 0 ]]; then
    echo "WARNING: No dedicated worker nodes configured. Controller(s) must be configured to schedule workloads."
fi

# Warn about even number of controllers (not recommended for HA)
if [[ $K0S_CONTROLLER_COUNT -gt 1 ]] && [[ $((K0S_CONTROLLER_COUNT % 2)) -eq 0 ]]; then
    echo "WARNING: Even number of controllers ($K0S_CONTROLLER_COUNT) is not recommended for HA. Use 1, 3, 5, etc."
fi

# ---- Computed Variables ----
# Cluster ID for resource naming
CLUSTERID_FILE="./.clusterid"
if [[ -f "$CLUSTERID_FILE" ]]; then
    K0RDENT_CLUSTERID=$(cat "$CLUSTERID_FILE")
else
    # Generate new cluster ID
    RANDOM_ID=$(head /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 8)
    K0RDENT_CLUSTERID="k0rdent-${RANDOM_ID}"
    echo "$K0RDENT_CLUSTERID" > "$CLUSTERID_FILE"
fi

# Resource naming
RG="${K0RDENT_CLUSTERID}-resgrp"
VNET_NAME="${K0RDENT_CLUSTERID}-vnet"
SUBNET_NAME="${K0RDENT_CLUSTERID}-subnet"
NSG_NAME="${K0RDENT_CLUSTERID}-nsg"
SSH_KEY_NAME="${K0RDENT_CLUSTERID}-admin"

# Directory paths
MANIFEST_DIR="./azure-resources"
WG_DIR="./wireguard"
CLOUD_INIT_DIR="./cloud-init-yaml"

# ---- Generate VM Definitions ----
# Build VM arrays based on counts and zone distribution
VM_HOSTS=()
VM_ZONES=()
VM_TYPES=()  # New array to track if VM is controller or worker
VM_SIZES=()  # New array to track VM size

# Generate controller definitions
for (( i=0; i<$K0S_CONTROLLER_COUNT; i++ )); do
    hostname="k0s-controller-$((i+1))"
    
    # Determine zone (cycle through available zones)
    zone_index=$((i % ${#CONTROLLER_ZONES[@]}))
    zone="${CONTROLLER_ZONES[$zone_index]}"
    
    VM_HOSTS+=("$hostname")
    VM_ZONES+=("$zone")
    VM_TYPES+=("controller")
    VM_SIZES+=("$AZURE_CONTROLLER_VM_SIZE")
done

# Generate worker definitions
for (( i=0; i<$K0S_WORKER_COUNT; i++ )); do
    hostname="k0s-worker-$((i+1))"
    
    # Determine zone (cycle through available zones)
    zone_index=$((i % ${#WORKER_ZONES[@]}))
    zone="${WORKER_ZONES[$zone_index]}"
    
    VM_HOSTS+=("$hostname")
    VM_ZONES+=("$zone")
    VM_TYPES+=("worker")
    VM_SIZES+=("$AZURE_WORKER_VM_SIZE")
done

# ---- WireGuard IP Mapping ----
# WireGuard IPs are now managed in state file
# Initialize the associative array for backwards compatibility
declare -A WG_IPS

# Load state management functions if not already loaded
if ! command -v get_wireguard_ip &> /dev/null; then
    source ./etc/state-management.sh
fi

# If state file exists, populate WG_IPS from state
if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
    populate_wg_ips_array
else
    # Validate WireGuard network is properly configured
    if [[ -z "$WG_NETWORK" ]]; then
        echo "ERROR: WireGuard network (WG_NETWORK) not configured. Check your YAML configuration."
        exit 1
    fi
    
    # Extract network base from WG_NETWORK (e.g., "192.168.100.0/24" -> "192.168.100")
    wg_base=$(echo "$WG_NETWORK" | cut -d'/' -f1 | cut -d'.' -f1-3)
    
    # Fallback: compute IPs temporarily using configured WG_NETWORK
    # This will be replaced by assign_wireguard_ips() call during deployment preparation
    WG_IPS["mylaptop"]="${wg_base}.1"
    ip_counter=1
    for host in "${VM_HOSTS[@]}"; do
        WG_IPS["$host"]="${wg_base}.$((10 + ip_counter))"
        ((ip_counter++))
    done
fi

# ---- Export Arrays for Scripts ----
# Create associative arrays for easy lookup
declare -A VM_ZONE_MAP
declare -A VM_TYPE_MAP
declare -A VM_SIZE_MAP

for (( i=0; i<${#VM_HOSTS[@]}; i++ )); do
    VM_ZONE_MAP["${VM_HOSTS[$i]}"]="${VM_ZONES[$i]}"
    VM_TYPE_MAP["${VM_HOSTS[$i]}"]="${VM_TYPES[$i]}"
    VM_SIZE_MAP["${VM_HOSTS[$i]}"]="${VM_SIZES[$i]}"
done