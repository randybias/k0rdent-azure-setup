#!/usr/bin/env bash

# Script: generate-wg-keys.sh
# Purpose: Generate WireGuard key pairs for each node in the mesh.
#          Output a CSV manifest for use in cloud-init and laptop config.
#          All files and manifest are stored in ./wg-keys
# Usage: bash generate-wg-keys.sh [command] [options]

set -euo pipefail

# Load central configuration and common functions
source ./k0rdent-config.sh
source ./common-functions.sh

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  deploy    Generate new WireGuard keys
  reset     Remove all keys and manifest
  status    Show existing keys
  help      Show this help message" \
        "  -y, --yes        Assume yes to all prompts
  -q, --quiet      Suppress non-error output
  -v, --verbose    Enable verbose output" \
        "  $0 deploy        # Generate keys interactively
  $0 deploy -y     # Generate keys without prompts
  $0 status        # Show current key status
  $0 reset -y      # Remove keys without confirmation"
}

show_status() {
    print_header "WireGuard Keys Status"
    
    if [[ ! -d "$KEYDIR" ]]; then
        print_info "Key directory does not exist: $KEYDIR"
        print_info "No keys have been generated yet."
        return
    fi
    
    if [[ ! -f "$WG_MANIFEST" ]]; then
        print_info "Manifest file does not exist: $WG_MANIFEST"
        print_info "Keys may be incomplete or corrupted."
        return
    fi
    
    # Count keys
    local key_count=$(find "$KEYDIR" -name "*_privkey" | wc -l)
    local expected_count=${#WG_IPS[@]}
    
    print_info "Key directory: $KEYDIR"
    print_info "Manifest file: $WG_MANIFEST"
    print_info "Keys generated: $key_count of $expected_count expected"
    
    # Show which hosts have keys
    echo ""
    echo "Host Key Status:"
    for HOST in "${!WG_IPS[@]}"; do
        PRIV_FILE="$KEYDIR/${HOST}_privkey"
        PUB_FILE="$KEYDIR/${HOST}_pubkey"
        
        if [[ -f "$PRIV_FILE" && -f "$PUB_FILE" ]]; then
            print_success "$HOST: Keys exist"
        else
            print_error "$HOST: Keys missing"
        fi
    done
    
    # Show manifest entries
    if [[ -f "$WG_MANIFEST" ]]; then
        echo ""
        echo "Manifest entries:"
        local count=$(tail -n +2 "$WG_MANIFEST" | wc -l)
        print_info "Total entries: $count"
    fi
}

deploy_keys() {
    # Check if WireGuard tools are installed
    check_wireguard_tools
    
    # Check if keys already exist
    if [[ -f "$WG_MANIFEST" ]]; then
        print_warning "WireGuard keys already exist."
        if ! confirm_action "Do you want to regenerate all keys?"; then
            print_info "Key generation cancelled."
            exit 0
        fi
        # Remove existing keys
        print_info "Removing existing keys..."
        rm -rf "$KEYDIR"
    fi
    
    # Create directory and manifest
    print_info_quiet "Creating key directory: $KEYDIR"
    ensure_directory "$KEYDIR"
    print_info_quiet "Creating new manifest file..."
    echo "hostname,wireguard_ip,private_key,public_key" > "$WG_MANIFEST"
    
    # Generate keys for each host
    for HOST in "${!WG_IPS[@]}"; do
        WG_IP="${WG_IPS[$HOST]}"
        PRIV_FILE="$KEYDIR/${HOST}_privkey"
        PUB_FILE="$KEYDIR/${HOST}_pubkey"
        
        print_info_quiet "Generating keys for $HOST..."
        # Generate keys
        wg genkey | tee "$PRIV_FILE" | wg pubkey > "$PUB_FILE"
        
        PRIV=$(cat "$PRIV_FILE")
        PUB=$(cat "$PUB_FILE")
        
        # Output CSV manifest line
        echo "$HOST,$WG_IP,$PRIV,$PUB" >> "$WG_MANIFEST"
        
        # File permissions
        chmod 600 "$PRIV_FILE"
        chmod 644 "$PUB_FILE"
        
        print_info_verbose "Generated keys for $HOST with IP $WG_IP"
    done
    
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo
        print_success "WireGuard keys stored in $KEYDIR"
        print_success "Manifest file at: $WG_MANIFEST"
        echo
        print_info "Next steps:"
        print_info "  1. Use the manifest to prepare per-VM cloud-init files and the laptop WireGuard config."
        print_info "  2. Proceed with Azure network setup."
        echo
    fi
}

reset_keys() {
    if [[ ! -d "$KEYDIR" ]]; then
        print_info "Key directory does not exist. Nothing to reset."
        exit 0
    fi
    
    if confirm_action "This will remove all WireGuard keys. Are you sure?"; then
        print_info_quiet "Resetting key directory: $KEYDIR"
        rm -rf "$KEYDIR"
        print_success "WireGuard keys removed"
    else
        print_info "Reset cancelled."
    fi
}

# Main execution
# Parse command line arguments
COMMAND="${1:-}"
shift || true

# Parse options
parse_result=0
parse_common_args "$@" || parse_result=$?

if [[ $parse_result -eq 1 ]]; then
    # Help was requested
    show_usage
    exit 0
elif [[ $parse_result -eq 2 ]]; then
    # Unknown option
    show_usage
    exit 1
fi

# Check command support
SUPPORTED_COMMANDS="deploy reset status help"
if [[ -z "$COMMAND" ]]; then
    show_usage
    exit 1
fi

# Handle commands
case "$COMMAND" in
    "deploy")
        deploy_keys
        ;;
    "reset")
        reset_keys
        ;;
    "status")
        show_status
        ;;
    "help")
        show_usage
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac