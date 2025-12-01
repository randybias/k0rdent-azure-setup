#!/usr/bin/env bash

# State Management Functions for k0rdent Deployment
# Provides simple YAML-based state tracking to reduce Azure API calls

# State directory
STATE_DIR="./state"

# Global state file locations
DEPLOYMENT_STATE_FILE="$STATE_DIR/deployment-state.yaml"
DEPLOYMENT_EVENTS_FILE="$STATE_DIR/deployment-events.yaml"
KOF_STATE_FILE="$STATE_DIR/kof-state.yaml"
KOF_EVENTS_FILE="$STATE_DIR/kof-events.yaml"
AZURE_STATE_FILE="$STATE_DIR/azure-state.yaml"
AZURE_EVENTS_FILE="$STATE_DIR/azure-events.yaml"

# Deployment phase order (must remain in execution order)
PHASE_SEQUENCE=(
    "prepare_deployment"
    "setup_network"
    "create_vms"
    "setup_vpn"
    "connect_vpn"
    "install_k0s"
    "install_k0rdent"
    "setup_azure_children"
    "install_azure_csi"
    "install_kof_mothership"
    "install_kof_regional"
)

# Archive existing state files to old_deployments
archive_existing_state() {
    local reason="${1:-deployment}"  # Default reason is "deployment"
    local timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    local old_deployments_dir="./old_deployments"
    
    # Check if there are any state files to archive
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]] && [[ ! -f "$DEPLOYMENT_EVENTS_FILE" ]]; then
        return 0  # Nothing to archive
    fi
    
    # Get deployment ID from existing state if available
    local deployment_id=""
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        deployment_id=$(yq eval '.deployment_id' "$DEPLOYMENT_STATE_FILE" 2>/dev/null || echo "unknown")
    fi
    
    # Create archive directory name
    local archive_dir="${old_deployments_dir}/${deployment_id}_${timestamp}_${reason}"
    
    # Create archive directory
    mkdir -p "$archive_dir"
    
    # Move existing state files to archive
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        mv "$DEPLOYMENT_STATE_FILE" "$archive_dir/"
        print_info "Archived deployment-state.yaml to $archive_dir/"
    fi
    
    if [[ -f "$DEPLOYMENT_EVENTS_FILE" ]]; then
        mv "$DEPLOYMENT_EVENTS_FILE" "$archive_dir/"
        print_info "Archived deployment-events.yaml to $archive_dir/"
    fi
    
    # Archive any other state files
    for state_file in "$KOF_STATE_FILE" "$KOF_EVENTS_FILE" "$AZURE_STATE_FILE" "$AZURE_EVENTS_FILE"; do
        if [[ -f "$state_file" ]]; then
            mv "$state_file" "$archive_dir/"
            local filename=$(basename "$state_file")
            print_info "Archived $filename to $archive_dir/"
        fi
    done
    
    print_success "State files archived to $archive_dir/"
}


# Initialize new deployment state file
init_deployment_state() {
    local deployment_id="$1"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Ensure state directory exists
    mkdir -p "$STATE_DIR"
    
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
# k0rdent Deployment State
# Auto-generated on $timestamp

# Basic deployment info
deployment_id: "$deployment_id"
created_at: "$timestamp"
last_updated: "$timestamp"
phase: "preparation"
status: "in_progress"
deployment_flags:
  azure_children: false
  kof: false

# Source configuration file (for proper variable expansion)
source_config_file: "${CONFIG_YAML:-}"

# Configuration snapshot
config:
  azure_location: "$AZURE_LOCATION"
  resource_group: "${deployment_id}-resgrp"
  controller_count: $K0S_CONTROLLER_COUNT
  worker_count: $K0S_WORKER_COUNT
  wireguard_network: "$WG_NETWORK"
  wireguard_port: null

# Azure resources
azure_rg_status: "not_created"
azure_network_status: "not_created"
azure_ssh_key_status: "not_created"

# VM states (will be populated as VMs are created)
vm_states: {}

# WireGuard setup
wg_keys_generated: false
wg_laptop_config_created: false
wg_vpn_connected: false

# Cluster setup
k0s_config_generated: false
k0s_cluster_deployed: false
k0rdent_installed: false

# Deployment phase tracking
phases:
EOF

    for phase in "${PHASE_SEQUENCE[@]}"; do
        cat >> "$DEPLOYMENT_STATE_FILE" << EOF
  ${phase}:
    status: "pending"
    updated_at: "$timestamp"
EOF
    done

    cat >> "$DEPLOYMENT_STATE_FILE" << EOF

# Artifact registry (generated files/scripts)
artifacts: {}
EOF
    
    # Create separate events file
    cat > "$DEPLOYMENT_EVENTS_FILE" << EOF
# k0rdent Deployment Events Log
# Auto-generated on $timestamp

deployment_id: "$deployment_id"
created_at: "$timestamp"
last_updated: "$timestamp"

# Events log
events:
  - timestamp: "$timestamp"
    action: deployment_initialized
    message: Deployment state tracking initialized
EOF
    
    print_info "Initialized deployment state: $DEPLOYMENT_STATE_FILE"
    print_info "Initialized deployment events: $DEPLOYMENT_EVENTS_FILE"
}

# Phase helpers --------------------------------------------------------------

phase_status() {
    local phase="${1//-/_}"

    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        echo "pending"
        return 0
    fi

    local phase_status
    phase_status=$(yq eval ".phases.${phase}.status" "$DEPLOYMENT_STATE_FILE" 2>/dev/null)
    if [[ "$phase_status" == "null" ]]; then
        echo "pending"
    else
        echo "$phase_status"
    fi
}

phase_is_completed() {
    local current_status
    current_status=$(phase_status "$1")
    [[ "$current_status" == "completed" ]]
}

phase_mark_in_progress() {
    local phase="$1"
    local phase_normalized="${phase//-/_}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        yq eval ".phases.${phase_normalized}.status = \"in_progress\"" -i "$DEPLOYMENT_STATE_FILE"
        yq eval ".phases.${phase_normalized}.updated_at = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
        yq eval ".last_updated = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
    fi
    update_state "phase" "$phase_normalized"
}

phase_mark_completed() {
    local phase="$1"
    local phase_normalized="${phase//-/_}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        yq eval ".phases.${phase_normalized}.status = \"completed\"" -i "$DEPLOYMENT_STATE_FILE"
        yq eval ".phases.${phase_normalized}.updated_at = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
        yq eval ".last_updated = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
    fi
    update_state "phase" "$phase_normalized"
    add_event "phase_completed" "Phase completed: $phase_normalized"
}

phase_mark_pending() {
    local phase="$1"
    local phase_normalized="${phase//-/_}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        yq eval ".phases.${phase_normalized}.status = \"pending\"" -i "$DEPLOYMENT_STATE_FILE"
        yq eval ".phases.${phase_normalized}.updated_at = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
        yq eval ".last_updated = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
    fi
}

phase_reset_from() {
    local phase="${1//-/_}"
    local index=0
    local found=0

    # Find index of phase in sequence
    for p in "${PHASE_SEQUENCE[@]}"; do
        if [[ "$p" == "$phase" ]]; then
            found=1
            break
        fi
        ((index++))
    done

    if [[ $found -eq 0 ]]; then
        return 1
    fi

    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local total=${#PHASE_SEQUENCE[@]}

    for ((i=index; i<total; i++)); do
        local target="${PHASE_SEQUENCE[$i]}"
        yq eval ".phases.${target}.status = \"pending\"" -i "$DEPLOYMENT_STATE_FILE"
        yq eval ".phases.${target}.updated_at = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
    done

    yq eval ".last_updated = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
    update_state "phase" "$phase"
    add_event "phase_reset" "Phase reset invoked from: $phase"
}

phase_needs_run() {
    local current_status
    current_status=$(phase_status "$1")
    [[ "$current_status" != "completed" ]]
}

# Check if a phase is completed
# Args: $1 - phase name
# Returns: 0 if completed, 1 if not
check_phase_completion() {
    local phase_name="$1"
    local status
    status=$(phase_status "${phase_name}")
    [[ "${status}" == "completed" ]]
}

# Artifact helpers -----------------------------------------------------------

record_artifact() {
    local name="$1"
    local path="$2"
    local metadata="${3:-}"

    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        return 1
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    yq eval ".artifacts.${name}.path = \"${path}\"" -i "$DEPLOYMENT_STATE_FILE"
    yq eval ".artifacts.${name}.updated_at = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
    if [[ -n "$metadata" ]]; then
        yq eval ".artifacts.${name}.metadata = \"${metadata}\"" -i "$DEPLOYMENT_STATE_FILE"
    fi
    yq eval ".last_updated = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
}

artifact_exists() {
    local name="$1"
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        return 1
    fi

    local path
    path=$(yq eval ".artifacts.${name}.path" "$DEPLOYMENT_STATE_FILE" 2>/dev/null)
    if [[ -z "$path" || "$path" == "null" ]]; then
        return 1
    fi

    [[ -e "$path" ]]
}

# Update a simple key-value in state
update_state() {
    local key="$1"
    local value="$2"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        print_error "State file not found: $DEPLOYMENT_STATE_FILE"
        return 1
    fi
    
    # Handle boolean values properly
    if [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
        # Set as actual boolean, not string
        yq eval ".${key} = ${value}" -i "$DEPLOYMENT_STATE_FILE"
    elif [[ "$value" == "{}" ]]; then
        # Handle empty object
        yq eval ".${key} = {}" -i "$DEPLOYMENT_STATE_FILE"
    else
        # Everything else as string
        yq eval ".${key} = \"${value}\"" -i "$DEPLOYMENT_STATE_FILE"
    fi
    
    yq eval ".last_updated = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
}

# Get value from state
get_state() {
    local key="$1"
    
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        return 1
    fi
    
    yq eval ".${key}" "$DEPLOYMENT_STATE_FILE" 2>/dev/null || echo "null"
}

# Update VM state info
update_vm_state() {
    local vm_name="$1"
    local public_ip="$2"
    local private_ip="$3"
    local state="$4"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Create VM entry if it doesn't exist
    yq eval ".vm_states.${vm_name} = {}" -i "$DEPLOYMENT_STATE_FILE"
    
    # Update VM properties
    yq eval ".vm_states.${vm_name}.public_ip = \"${public_ip}\"" -i "$DEPLOYMENT_STATE_FILE"
    yq eval ".vm_states.${vm_name}.private_ip = \"${private_ip}\"" -i "$DEPLOYMENT_STATE_FILE"
    yq eval ".vm_states.${vm_name}.state = \"${state}\"" -i "$DEPLOYMENT_STATE_FILE"
    yq eval ".vm_states.${vm_name}.last_checked = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
    yq eval ".last_updated = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
}

# Get VM info from state
get_vm_info() {
    local vm_name="$1"
    local property="$2"  # public_ip, private_ip, state, last_checked
    
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        return 1
    fi
    
    yq eval ".vm_states.${vm_name}.${property}" "$DEPLOYMENT_STATE_FILE" 2>/dev/null || echo "null"
}

# Bulk refresh all VM data from Azure
refresh_all_vm_data() {
    local rg=$(get_state "config.resource_group")
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    print_info "Refreshing VM data from Azure..."
    
    # Single API call to get all VM data
    local vm_data
    vm_data=$(az vm list --resource-group "$rg" --show-details \
        --query "[].{name:name, publicIps:publicIps, privateIps:privateIps, state:provisioningState}" \
        -o tsv 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$vm_data" ]]; then
        # Parse and update state for each VM
        while IFS=$'\t' read -r name public_ip private_ip state; do
            if [[ -n "$name" ]]; then
                update_vm_state "$name" "$public_ip" "$private_ip" "$state"
            fi
        done <<< "$vm_data"
        print_info "VM data refreshed from Azure"
    else
        print_warning "Could not refresh VM data from Azure"
    fi
}

# Add event to log
add_event() {
    local action="$1"
    local message="$2"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Add event to events array in separate events file
    if [[ -f "$DEPLOYMENT_EVENTS_FILE" ]]; then
        yq eval ".events += [{\"timestamp\": \"${timestamp}\", \"action\": \"${action}\", \"message\": \"${message}\"}]" -i "$DEPLOYMENT_EVENTS_FILE"
        yq eval ".last_updated = \"${timestamp}\"" -i "$DEPLOYMENT_EVENTS_FILE"
    fi
    
    # Update timestamp in main state file
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        yq eval ".last_updated = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
    fi
    
}

# Check if state file exists and is valid
state_file_exists() {
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]] && yq eval '.deployment_id' "$DEPLOYMENT_STATE_FILE" &>/dev/null; then
        # Ensure deployment_flags exist for older state files
        if [[ "$(yq eval '.deployment_flags' "$DEPLOYMENT_STATE_FILE" 2>/dev/null)" == "null" ]]; then
            yq eval '.deployment_flags = {"azure_children": false, "kof": false}' -i "$DEPLOYMENT_STATE_FILE"
        fi
        return 0
    fi
    return 1
}

# Show simple state summary
show_state_summary() {
    if ! state_file_exists; then
        print_error "No deployment state found"
        return 1
    fi
    
    local deployment_id=$(get_state "deployment_id")
    local phase=$(get_state "phase")
    local deployment_status=$(get_state "status")
    local created=$(get_state "created_at")

    echo
    print_info "=== Deployment State Summary ==="
    echo "  Deployment ID: $deployment_id"
    echo "  Phase: $phase"
    echo "  Status: $deployment_status"
    echo "  Created: $created"
    echo
    
    # Show VM states if any exist
    local vm_count=$(yq eval '.vm_states | length' "$DEPLOYMENT_STATE_FILE" 2>/dev/null || echo "0")
    if [[ "$vm_count" -gt 0 ]]; then
        print_info "=== VM States ==="
        yq eval '.vm_states | to_entries | .[] | .key + ": " + .value.state + " (" + .value.public_ip + ")"' "$DEPLOYMENT_STATE_FILE" 2>/dev/null | while read -r line; do
            echo "  $line"
        done
        echo
    fi
}


# Mark deployment as completed
complete_deployment() {
    local final_phase="${1:-completed}"

    # Update final state
    update_state "status" "completed"
    update_state "phase" "$final_phase"
    add_event "deployment_completed" "Full k0rdent deployment completed successfully"
}

# Clean up deployment state files
cleanup_deployment_state() {
    local reason="${1:-cleanup}"

    # Remove state files
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
        print_info "Removed deployment state file"
    fi

    if [[ -f "$DEPLOYMENT_EVENTS_FILE" ]]; then
        rm -f "$DEPLOYMENT_EVENTS_FILE"
        print_info "Removed deployment events file"
    fi

    # Remove state directory if empty
    if [[ -d "$STATE_DIR" ]] && [[ -z "$(ls -A "$STATE_DIR" 2>/dev/null)" ]]; then
        rmdir "$STATE_DIR"
        print_info "Removed empty state directory"
    fi

    print_success "Deployment state cleanup completed"
}

# ---- WireGuard IP Management ----

# Assign WireGuard IPs to hosts and store in state
assign_wireguard_ips() {
    local vm_hosts=("$@")
    local wg_network=$(get_state "config.wireguard_network" || echo "$WG_NETWORK")
    local base_ip="${wg_network%.*}"  # Extract base (e.g., "172.24.24" from "172.24.24.0/24")
    
    # Initialize wireguard_peers section if it doesn't exist
    yq eval ".wireguard_peers = {}" -i "$DEPLOYMENT_STATE_FILE" 2>/dev/null || true
    
    # Assign laptop IP (always .1)
    yq eval ".wireguard_peers.mylaptop.ip = \"${base_ip}.1\"" -i "$DEPLOYMENT_STATE_FILE"
    yq eval ".wireguard_peers.mylaptop.role = \"hub\"" -i "$DEPLOYMENT_STATE_FILE"
    
    # Assign VM IPs starting from .11
    local ip_counter=1
    for host in "${vm_hosts[@]}"; do
        local wg_ip="${base_ip}.$((10 + ip_counter))"
        yq eval ".wireguard_peers.${host}.ip = \"${wg_ip}\"" -i "$DEPLOYMENT_STATE_FILE"
        
        # Determine role based on hostname
        if [[ "$host" == *"controller"* ]]; then
            yq eval ".wireguard_peers.${host}.role = \"controller\"" -i "$DEPLOYMENT_STATE_FILE"
        else
            yq eval ".wireguard_peers.${host}.role = \"worker\"" -i "$DEPLOYMENT_STATE_FILE"
        fi
        
        ((ip_counter++))
    done
    
    # Update timestamp
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    yq eval ".last_updated = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
    
    add_event "wireguard_ips_assigned" "WireGuard IP addresses assigned to all hosts"
}

# Get WireGuard IP for a specific host
get_wireguard_ip() {
    local host="$1"
    
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        return 1
    fi
    
    yq eval ".wireguard_peers.${host}.ip" "$DEPLOYMENT_STATE_FILE" 2>/dev/null || echo "null"
}

# Update WireGuard peer keys in state
update_wireguard_peer() {
    local host="$1"
    local private_key="$2"
    local public_key="$3"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Ensure peer entry exists
    if [[ $(yq eval ".wireguard_peers.${host}" "$DEPLOYMENT_STATE_FILE" 2>/dev/null) == "null" ]]; then
        print_error "WireGuard peer $host not found in state. Run assign_wireguard_ips first."
        return 1
    fi
    
    # Update keys
    yq eval ".wireguard_peers.${host}.private_key = \"${private_key}\"" -i "$DEPLOYMENT_STATE_FILE"
    yq eval ".wireguard_peers.${host}.public_key = \"${public_key}\"" -i "$DEPLOYMENT_STATE_FILE"
    yq eval ".wireguard_peers.${host}.keys_generated = true" -i "$DEPLOYMENT_STATE_FILE"
    yq eval ".wireguard_peers.${host}.keys_generated_at = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
    yq eval ".last_updated = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
}

# Get all WireGuard peers as associative array
# Usage: declare -A WG_IPS; populate_wg_ips_array
populate_wg_ips_array() {
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        return 1
    fi
    
    # Check if wireguard_peers exists in state file
    local has_peers=$(yq eval 'has("wireguard_peers")' "$DEPLOYMENT_STATE_FILE" 2>/dev/null)
    if [[ "$has_peers" != "true" ]]; then
        # No wireguard peers yet, return silently
        return 0
    fi
    
    # Get all peer names and their IPs
    local peers
    peers=$(yq eval '.wireguard_peers | keys | .[]' "$DEPLOYMENT_STATE_FILE" 2>/dev/null)
    
    # Handle empty or null peers gracefully
    if [[ -z "$peers" || "$peers" == "null" ]]; then
        return 0
    fi
    
    while IFS= read -r peer; do
        if [[ -n "$peer" && "$peer" != "null" ]]; then
            local ip=$(yq eval ".wireguard_peers.${peer}.ip" "$DEPLOYMENT_STATE_FILE" 2>/dev/null)
            if [[ "$ip" != "null" && -n "$ip" ]]; then
                WG_IPS["$peer"]="$ip"
            fi
        fi
    done <<< "$peers"
}

# Get WireGuard peer private key
get_wireguard_private_key() {
    local host="$1"
    yq eval ".wireguard_peers.${host}.private_key" "$DEPLOYMENT_STATE_FILE" 2>/dev/null || echo "null"
}

# Get WireGuard peer public key  
get_wireguard_public_key() {
    local host="$1"
    yq eval ".wireguard_peers.${host}.public_key" "$DEPLOYMENT_STATE_FILE" 2>/dev/null || echo "null"
}

# ---- KOF State Management ----


# ---- Azure State Management ----

# Update Azure state
update_azure_state() {
    local key="$1"
    local value="$2"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Initialize if doesn't exist
    if [[ ! -f "$AZURE_STATE_FILE" ]]; then
        init_azure_state
    fi
    
    # Handle boolean values properly
    if [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
        yq eval ".${key} = ${value}" -i "$AZURE_STATE_FILE"
    else
        yq eval ".${key} = \"${value}\"" -i "$AZURE_STATE_FILE"
    fi
    
    yq eval ".last_updated = \"${timestamp}\"" -i "$AZURE_STATE_FILE"
}

# Get Azure state
get_azure_state() {
    local key="$1"
    
    if [[ ! -f "$AZURE_STATE_FILE" ]]; then
        echo "null"
        return
    fi
    
    yq eval ".${key}" "$AZURE_STATE_FILE" 2>/dev/null || echo "null"
}

# Add Azure event
add_azure_event() {
    local action="$1"
    local message="$2"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Initialize if doesn't exist
    if [[ ! -f "$AZURE_EVENTS_FILE" ]]; then
        init_azure_state
    fi
    
    # Add event to events array
    yq eval ".events += [{\"timestamp\": \"${timestamp}\", \"action\": \"${action}\", \"message\": \"${message}\"}]" -i "$AZURE_EVENTS_FILE"
    yq eval ".last_updated = \"${timestamp}\"" -i "$AZURE_EVENTS_FILE"
    
    # Update timestamp in main Azure state file
    if [[ -f "$AZURE_STATE_FILE" ]]; then
        yq eval ".last_updated = \"${timestamp}\"" -i "$AZURE_STATE_FILE"
    fi
}

# Remove Azure state key
remove_azure_state_key() {
    local key="$1"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    if [[ -f "$AZURE_STATE_FILE" ]]; then
        yq eval "del(.${key})" -i "$AZURE_STATE_FILE"
        yq eval ".last_updated = \"${timestamp}\"" -i "$AZURE_STATE_FILE"
    fi
}

# ---- Individual Cluster State Management ----

# Get cluster state file path
get_cluster_state_file() {
    local cluster_name="$1"
    echo "$STATE_DIR/cluster-${cluster_name}-state.yaml"
}

# Get cluster events file path
get_cluster_events_file() {
    local cluster_name="$1"
    echo "$STATE_DIR/cluster-${cluster_name}-events.yaml"
}

# Initialize cluster events file (state tracking removed - k0rdent is source of truth)
init_cluster_events() {
    local cluster_name="$1"
    local cluster_events_file=$(get_cluster_events_file "$cluster_name")
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Ensure state directory exists
    mkdir -p "$STATE_DIR"
    
    # Only create events file - no local state tracking
    cat > "$cluster_events_file" << EOF
# Cluster Events Log: $cluster_name
# Auto-generated on $timestamp
# Note: Cluster state is tracked in k0rdent - this file only tracks local events

cluster_name: "$cluster_name"
created_at: "$timestamp"
last_updated: "$timestamp"

# Events log (local operations only)
events:
  - timestamp: "$timestamp"
    action: cluster_events_initialized
    message: Local event tracking initialized for $cluster_name
EOF
    
    print_info "Initialized cluster events: $cluster_events_file"
}

# Add cluster event
add_cluster_event() {
    local cluster_name="$1"
    local action="$2"
    local message="$3"
    local cluster_events_file=$(get_cluster_events_file "$cluster_name")
    local cluster_state_file=$(get_cluster_state_file "$cluster_name")
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Initialize if doesn't exist
    if [[ ! -f "$cluster_events_file" ]]; then
        init_cluster_state "$cluster_name"
    fi
    
    # Add event to events array
    yq eval ".events += [{\"timestamp\": \"${timestamp}\", \"action\": \"${action}\", \"message\": \"${message}\"}]" -i "$cluster_events_file"
    yq eval ".last_updated = \"${timestamp}\"" -i "$cluster_events_file"
    
    # Update timestamp in main cluster state file
    if [[ -f "$cluster_state_file" ]]; then
        yq eval ".last_updated = \"${timestamp}\"" -i "$cluster_state_file"
    fi
}
