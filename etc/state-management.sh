#!/usr/bin/env bash

# State Management Functions for k0rdent Deployment
# Provides simple YAML-based state tracking to reduce Azure API calls

# Global state file locations
DEPLOYMENT_STATE_FILE="./deployment-state.yaml"
DEPLOYMENT_EVENTS_FILE="./deployment-events.yaml"

# Initialize new deployment state file
init_deployment_state() {
    local deployment_id="$1"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
# k0rdent Deployment State
# Auto-generated on $timestamp

# Basic deployment info
deployment_id: "$deployment_id"
created_at: "$timestamp"
last_updated: "$timestamp"
phase: "preparation"
status: "in_progress"

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
    [[ -f "$DEPLOYMENT_STATE_FILE" ]] && yq eval '.deployment_id' "$DEPLOYMENT_STATE_FILE" &>/dev/null
}

# Show simple state summary
show_state_summary() {
    if ! state_file_exists; then
        print_error "No deployment state found"
        return 1
    fi
    
    local deployment_id=$(get_state "deployment_id")
    local phase=$(get_state "phase")
    local status=$(get_state "status")
    local created=$(get_state "created_at")
    
    echo
    print_info "=== Deployment State Summary ==="
    echo "  Deployment ID: $deployment_id"
    echo "  Phase: $phase"
    echo "  Status: $status"
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

# Check if we need prerequisites before using yq
check_yq_available() {
    if ! command -v yq &> /dev/null; then
        print_error "yq is required for state management but not installed"
        echo "Install with: brew install yq (macOS) or see https://github.com/mikefarah/yq#install"
        return 1
    fi
}

# Backup completed deployment to old_deployments directory
backup_completed_deployment() {
    local reason="${1:-completed}"
    
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        print_warning "No deployment state file to backup"
        return 0
    fi
    
    local deployment_id=$(get_state "deployment_id")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="old_deployments"
    
    # Ensure backup directory exists
    mkdir -p "$backup_dir"
    
    # Backup state file
    cp "$DEPLOYMENT_STATE_FILE" "${backup_dir}/${deployment_id}_${timestamp}_${reason}.yaml"
    print_info "Backed up deployment state: ${backup_dir}/${deployment_id}_${timestamp}_${reason}.yaml"
    
    # Backup events file if it exists
    if [[ -f "$DEPLOYMENT_EVENTS_FILE" ]]; then
        cp "$DEPLOYMENT_EVENTS_FILE" "${backup_dir}/${deployment_id}_${timestamp}_${reason}_events.yaml"
        print_info "Backed up deployment events: ${backup_dir}/${deployment_id}_${timestamp}_${reason}_events.yaml"
    fi
}

# Mark deployment as completed and backup
complete_deployment() {
    local final_phase="${1:-completed}"
    
    # Update final state
    update_state "status" "completed"
    update_state "phase" "$final_phase"
    add_event "deployment_completed" "Full k0rdent deployment completed successfully"
    
    # Backup the completed deployment
    backup_completed_deployment "completed"
}

# Clean up deployment state files (backup first)
cleanup_deployment_state() {
    local reason="${1:-cleanup}"
    
    # Backup before cleanup
    backup_completed_deployment "$reason"
    
    # Remove state files
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
        print_info "Removed deployment state file"
    fi
    
    if [[ -f "$DEPLOYMENT_EVENTS_FILE" ]]; then
        rm -f "$DEPLOYMENT_EVENTS_FILE" 
        print_info "Removed deployment events file"
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
    
    # Get all peer names and their IPs
    local peers
    peers=$(yq eval '.wireguard_peers | keys | .[]' "$DEPLOYMENT_STATE_FILE" 2>/dev/null)
    
    while IFS= read -r peer; do
        if [[ -n "$peer" && "$peer" != "null" ]]; then
            local ip=$(yq eval ".wireguard_peers.${peer}.ip" "$DEPLOYMENT_STATE_FILE" 2>/dev/null)
            if [[ "$ip" != "null" ]]; then
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