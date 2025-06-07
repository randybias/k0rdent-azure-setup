#!/usr/bin/env bash

# State Management Functions for k0rdent Deployment
# Provides simple YAML-based state tracking to reduce Azure API calls

# Global state file location
DEPLOYMENT_STATE_FILE="./deployment-state.yaml"

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

# Events log
events: []
EOF
    
    print_info "Initialized deployment state: $DEPLOYMENT_STATE_FILE"
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
    
    # Update the key and timestamp
    yq eval ".${key} = \"${value}\"" -i "$DEPLOYMENT_STATE_FILE"
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
    
    # Add event to events array
    yq eval ".events += [{\"timestamp\": \"${timestamp}\", \"action\": \"${action}\", \"message\": \"${message}\"}]" -i "$DEPLOYMENT_STATE_FILE"
    yq eval ".last_updated = \"${timestamp}\"" -i "$DEPLOYMENT_STATE_FILE"
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