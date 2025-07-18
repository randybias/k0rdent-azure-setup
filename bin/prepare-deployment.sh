#!/usr/bin/env bash

# Script: prepare-deployment.sh
# Purpose: Comprehensive deployment preparation - WireGuard keys and cloud-init files
#          Consolidates functionality from generate-wg-keys.sh and generate-cloud-init.sh
# Usage: bash prepare-deployment.sh [command] [options]
# Prerequisites: Azure network setup must be completed first

set -euo pipefail

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh
source ./etc/state-management.sh

# Script-specific functions
# Note: Global prerequisites are now checked by bin/check-prerequisites.sh
# This function is kept for backward compatibility but just shows a message
check_global_prerequisites() {
    print_info "Prerequisites should be checked using:"
    print_info "  ./bin/check-prerequisites.sh"
    print_info ""
    print_info "Or via the main deployment script:"
    print_info "  ./deploy-k0rdent.sh check"
    return 0
}

show_usage() {
    print_usage "$0" \
        "  keys         Generate WireGuard keys only
  cloudinit    Generate cloud-init files only (requires keys)
  deploy       Generate both keys and cloud-init files
  reset        Remove all generated files
  status       Show generation status
  help         Show this help message" \
        "  -y, --yes        Skip confirmation prompts
  -q, --quiet      Suppress non-error output
  -v, --verbose    Enable verbose output" \
        "  $0 deploy        # Generate keys and cloud-init files
  $0 keys          # Generate WireGuard keys only
  $0 cloudinit     # Generate cloud-init files only
  $0 status        # Show current status
  $0 reset -y      # Remove all files without confirmation"
}

show_status() {
    # Show deployment state summary if available
    if state_file_exists; then
        show_state_summary
    fi
    
    # Count keys and files for status display
    local key_count=0
    local expected_key_count=${#WG_IPS[@]}
    if [[ -d "$WG_DIR" ]]; then
        key_count=$(find "$WG_DIR" -name "*_privkey" 2>/dev/null | wc -l)
    fi
    
    local file_count=0
    local expected_file_count=${#VM_HOSTS[@]}
    if [[ -d "$CLOUD_INIT_DIR" ]]; then
        file_count=$(find "$CLOUD_INIT_DIR" -name "*-cloud-init.yaml" 2>/dev/null | wc -l)
    fi
    
    # Get port from state
    local port_info=""
    local wg_port=$(get_state "config.wireguard_port")
    if [[ "$wg_port" != "null" ]]; then
        port_info="$wg_port"
    fi
    
    # Use generic status display framework
    display_status "Deployment Preparation Status" \
        "dir:$WG_DIR:WireGuard key directory" \
        "state:deployment-state.yaml:WireGuard peer data in state" \
        "count:$key_count=$expected_key_count:WireGuard keys" \
        "dir:$CLOUD_INIT_DIR:Cloud-init directory" \
        "count:$file_count=$expected_file_count:Cloud-init files" \
        ${port_info:+"info:$port_info:WireGuard port configured"}
    
    # Show detailed host status if verbose
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        echo
        print_info "=== Host Key Status ==="
        for HOST in "${!WG_IPS[@]}"; do
            PRIV_FILE="$WG_DIR/${HOST}_privkey"
            PUB_FILE="$WG_DIR/${HOST}_pubkey"
            
            if [[ -f "$PRIV_FILE" && -f "$PUB_FILE" ]]; then
                print_success "  $HOST: Keys exist"
            else
                print_error "  $HOST: Keys missing"
            fi
        done
        
        echo
        print_info "=== Host Cloud-Init Status ==="
        for HOST in "${VM_HOSTS[@]}"; do
            CLOUDINIT="$CLOUD_INIT_DIR/${HOST}-cloud-init.yaml"
            
            if [[ -f "$CLOUDINIT" ]]; then
                print_success "  $HOST: Cloud-init file exists"
            else
                print_error "  $HOST: Cloud-init file missing"
            fi
        done
    fi
    
    # Check all prerequisites for full deployment
    echo
    check_global_prerequisites
}

generate_wireguard_keys() {
    print_header "Generating WireGuard Keys"
    
    # Note: WireGuard tools are checked in bin/check-prerequisites.sh
    
    # Assign WireGuard IPs to all hosts (stores in state)
    print_info_quiet "Assigning WireGuard IP addresses..."
    assign_wireguard_ips "${VM_HOSTS[@]}"
    
    # Check if keys already exist in state
    local existing_keys=false
    for HOST in "${!WG_IPS[@]}"; do
        if [[ "$(get_wireguard_private_key "$HOST")" != "null" ]]; then
            existing_keys=true
            break
        fi
    done
    
    if [[ "$existing_keys" == "true" ]]; then
        print_warning "WireGuard keys already exist in state."
        if ! confirm_action "Do you want to regenerate all keys?"; then
            print_info "Key generation cancelled."
            return 0
        fi
        # Remove existing keys from filesystem (state will be updated)
        print_info "Removing existing key files..."
        rm -rf "$WG_DIR"
    fi
    
    # Create directory for key files (for backwards compatibility)
    print_info_quiet "Creating key directory: $WG_DIR"
    ensure_directory "$WG_DIR"
    
    # Generate WireGuard port if not already in state
    local existing_port=$(get_state "config.wireguard_port")
    if [[ "$existing_port" == "null" ]]; then
        WIREGUARD_PORT=$((RANDOM % 34001 + 30000))
        print_info_quiet "Generated WireGuard port: $WIREGUARD_PORT"
        update_state "config.wireguard_port" "$WIREGUARD_PORT"
    else
        WIREGUARD_PORT="$existing_port"
        print_info_quiet "Using existing WireGuard port: $WIREGUARD_PORT"
    fi
    
    # Generate keys for each host
    for HOST in "${!WG_IPS[@]}"; do
        WG_IP="${WG_IPS[$HOST]}"
        PRIV_FILE="$WG_DIR/${HOST}_privkey"
        PUB_FILE="$WG_DIR/${HOST}_pubkey"
        
        print_info_quiet "Generating keys for $HOST..."
        # Generate keys
        wg genkey | tee "$PRIV_FILE" | wg pubkey > "$PUB_FILE"
        
        PRIV=$(cat "$PRIV_FILE")
        PUB=$(cat "$PUB_FILE")
        
        # Store keys in state (this is the primary storage now)
        update_wireguard_peer "$HOST" "$PRIV" "$PUB"
        
        # File permissions for compatibility files
        chmod 600 "$PRIV_FILE"
        chmod 644 "$PUB_FILE"
        
        print_info_verbose "Generated keys for $HOST with IP $WG_IP"
    done
    
    if [[ "$QUIET_MODE" != "true" ]]; then
        print_success "WireGuard keys stored in deployment state"
        print_success "Compatibility key files in: $WG_DIR"
    fi
    
    return 0
}

generate_cloudinit_files() {
    print_header "Generating Cloud-Init Files"
    
    # Check if WireGuard keys exist in state
    if [[ "$(get_wireguard_private_key "mylaptop")" == "null" ]]; then
        print_error "WireGuard keys must be generated first."
        print_info "Run: $0 keys"
        exit 1
    fi
    
    # Check if WireGuard port exists in state
    WIREGUARD_PORT=$(get_state "config.wireguard_port")
    if [[ "$WIREGUARD_PORT" == "null" ]]; then
        print_error "WireGuard port missing from state. Keys must be generated first."
        print_info "Run: $0 keys"
        exit 1
    fi
    
    # Check if files already exist
    if [[ -d "$CLOUD_INIT_DIR" ]] && [[ -n "$(find "$CLOUD_INIT_DIR" -name "*-cloud-init.yaml" 2>/dev/null)" ]]; then
        print_warning "Cloud-init files already exist."
        if ! confirm_action "Do you want to regenerate all cloud-init files?"; then
            print_info "Cloud-init generation cancelled."
            return 0
        fi
        print_info_quiet "Removing existing cloud-init files..."
        rm -f "$CLOUD_INIT_DIR"/*-cloud-init.yaml
    fi
    
    print_info_quiet "Using WireGuard port: $WIREGUARD_PORT"
    
    ensure_directory "$CLOUD_INIT_DIR"
    
    # Get laptop public key and IP for peer config from state
    LAPTOP_PUBKEY=$(get_wireguard_public_key "mylaptop")
    LAPTOP_WGIP=$(get_wireguard_ip "mylaptop")
    
    # Generate cloud-init for each VM
    for HOST in "${VM_HOSTS[@]}"; do
        WG_PRIVKEY=$(get_wireguard_private_key "$HOST")
        WG_PUBKEY=$(get_wireguard_public_key "$HOST")
        WG_IP=$(get_wireguard_ip "$HOST")
        
        CLOUDINIT="$CLOUD_INIT_DIR/${HOST}-cloud-init.yaml"
        
        print_info_quiet "Generating cloud-init for $HOST..."
        
        cat > "$CLOUDINIT" <<EOF
#cloud-config
#
# Cloud-init for $HOST (Debian 12 ARM64, WireGuard)
#

package_update: true
package_upgrade: true
packages:
  - wireguard

write_files:
  - path: /etc/wireguard/privatekey
    permissions: '0600'
    owner: root:root
    content: |
      $WG_PRIVKEY

  - path: /etc/wireguard/wg0.conf
    permissions: '0600'
    owner: root:root
    content: |
      [Interface]
      PrivateKey = $WG_PRIVKEY
      Address = $WG_IP/32
      ListenPort = $WIREGUARD_PORT

      # This is your laptop as the hub. 
      [Peer]
      PublicKey = $LAPTOP_PUBKEY
      AllowedIPs = $LAPTOP_WGIP/32
      # Endpoint = <LAPTOP_PUBLIC_IP>:$WIREGUARD_PORT  # Not set here; hub initiates connection

runcmd:
  - [ systemctl, enable, wg-quick@wg0 ]
  - [ systemctl, start, wg-quick@wg0 ]
  - [ touch, /var/lib/cloud/instance/locale-check.skip ]
  - [ apt, install, locales-all ]

final_message: "Cloud-init finished for $HOST. WireGuard is configured (waiting for laptop/hub to connect)."
EOF
        
        print_info_verbose "Generated $CLOUDINIT"
    done
    
    if [[ "$QUIET_MODE" != "true" ]]; then
        print_success "All per-node cloud-init YAMLs written to: $CLOUD_INIT_DIR/"
        print_info "Using WireGuard port: $WIREGUARD_PORT"
    fi
    
    return 0
}

deploy_preparation() {
    print_header "Comprehensive Deployment Preparation"
    
    # Initialize deployment state if it doesn't exist
    if ! state_file_exists; then
        print_info "Initializing deployment state tracking..."
        init_deployment_state "$K0RDENT_CLUSTERID"
        add_event "preparation_started" "Beginning deployment preparation"
    else
        print_info "Using existing deployment state"
        update_state "phase" "preparation"
    fi
    
    # Validate Azure configuration before proceeding
    print_info "Validating Azure VM configuration..."
    if ! ./bin/azure-configuration-validation.sh; then
        print_error "Azure configuration validation failed"
        print_info "Please fix the configuration issues before proceeding"
        exit 1
    fi
    echo
    
    # Generate WireGuard keys first
    if ! generate_wireguard_keys; then
        print_error "Failed to generate WireGuard keys"
        exit 1
    fi
    update_state "wg_keys_generated" "true"
    add_event "wireguard_keys_generated" "WireGuard keys generated successfully"
    
    echo
    
    # Generate cloud-init files
    if ! generate_cloudinit_files; then
        print_error "Failed to generate cloud-init files"
        exit 1
    fi
    add_event "cloud_init_generated" "Cloud-init files generated successfully"
    
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo
        print_success "🎉 Deployment preparation completed successfully!"
        echo
        print_info "Generated files:"
        print_info "  • WireGuard keys: stored in deployment state"
        print_info "  • Cloud-init files: $CLOUD_INIT_DIR/"
        print_info "  • Compatibility key files: $WG_DIR/"
        echo
        print_info "Next steps:"
        print_info "  1. Create Azure VMs: bash bin/create-azure-vms.sh deploy"
        print_info "  2. Generate VPN config: bash bin/manage-vpn.sh generate"
        print_info "  3. Connect to VPN: bash bin/manage-vpn.sh connect"
        echo
    fi
}

reset_preparation() {
    print_header "Resetting Deployment Preparation"
    
    local has_files=false
    
    # Check what exists
    if [[ -d "$WG_DIR" ]]; then
        has_files=true
    fi
    
    if [[ -d "$CLOUD_INIT_DIR" ]]; then
        has_files=true
    fi
    
    if [[ "$has_files" == "false" ]]; then
        print_info "No preparation files exist. Nothing to reset."
        return 0
    fi
    
    if [[ "$SKIP_PROMPTS" == "false" ]]; then
        echo "This will remove:"
        [[ -d "$WG_DIR" ]] && echo "  • WireGuard keys directory: $WG_DIR"
        [[ -d "$CLOUD_INIT_DIR" ]] && echo "  • Cloud-init files directory: $CLOUD_INIT_DIR"
        echo
        read -p "Are you sure you want to remove all preparation files? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "Reset cancelled."
            return 0
        fi
    fi
    
    # Remove directories
    if [[ -d "$WG_DIR" ]]; then
        print_info "Removing WireGuard directory: $WG_DIR"
        rm -rf "$WG_DIR"
    fi
    
    if [[ -d "$CLOUD_INIT_DIR" ]]; then
        print_info "Removing cloud-init files directory: $CLOUD_INIT_DIR"
        rm -rf "$CLOUD_INIT_DIR"
    fi
    
    print_success "Deployment preparation files removed"
    
    # Update state
    update_state "wg_keys_generated" "false"
    add_event "preparation_reset" "WireGuard keys and cloud-init files removed"
    
    # Clean up deployment state files (backup and delete)
    cleanup_deployment_state "reset"
}

# Store original arguments for handle_standard_commands
ORIGINAL_ARGS=("$@")

# Use consolidated command handling
handle_standard_commands "$0" "keys cloudinit deploy reset status help" \
    "keys" "generate_wireguard_keys" \
    "cloudinit" "generate_cloudinit_files" \
    "deploy" "deploy_preparation" \
    "reset" "reset_preparation" \
    "status" "show_status" \
    "help" "show_usage" \
    "usage" "show_usage"
