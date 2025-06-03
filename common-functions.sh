#!/usr/bin/env bash

# common-functions.sh
# Shared functions for k0rdent Azure setup scripts
# Source this file: source ./common-functions.sh

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo "==> $1"
}

# Error handling function
handle_error() {
    local line_number="$1"
    local command="$2"
    print_error "Command failed at line $line_number"
    echo "Last command: $command"
    exit 1
}

# Azure CLI validation
check_azure_cli() {
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI (az) is not installed. Please install it first."
        echo "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi

    print_success "Azure CLI is installed and user is authenticated"
}

# WireGuard tools validation
check_wireguard_tools() {
    if ! command -v wg &> /dev/null; then
        print_error "WireGuard tools (wg) not found. Please install WireGuard tools first."
        echo "On Ubuntu/Debian: sudo apt install wireguard"
        echo "On CentOS/RHEL: sudo yum install wireguard-tools"
        echo "On macOS: brew install wireguard-tools"
        exit 1
    fi
}

# File existence validation
check_file_exists() {
    local file_path="$1"
    local description="$2"
    
    if [[ ! -f "$file_path" ]]; then
        print_error "$description not found at: $file_path"
        return 1
    fi
    return 0
}

# Directory creation with validation
ensure_directory() {
    local dir_path="$1"
    
    if [[ ! -d "$dir_path" ]]; then
        print_info "Creating directory: $dir_path"
        mkdir -p "$dir_path"
    fi
}

# Manifest operations
add_to_manifest() {
    local manifest_file="$1"
    local resource_type="$2"
    local resource_name="$3"
    local resource_group="$4"
    local location="$5"
    local additional_info="${6:-}"
    
    echo "$resource_type,$resource_name,$resource_group,$location,$additional_info" >> "$manifest_file"
}

# Initialize manifest file
init_manifest() {
    local manifest_file="$1"
    local manifest_dir=$(dirname "$manifest_file")
    
    ensure_directory "$manifest_dir"
    echo "resource_type,resource_name,resource_group,location,additional_info" > "$manifest_file"
    print_info "Created new resource manifest: $manifest_file"
}

# Check if resource group exists
check_resource_group_exists() {
    local rg_name="$1"
    
    if az group show --name "$rg_name" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Check if SSH key exists in Azure
check_ssh_key_exists() {
    local ssh_key_name="$1"
    local rg_name="$2"
    
    if az sshkey show --name "$ssh_key_name" --resource-group "$rg_name" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Check if local SSH key exists
check_local_ssh_key_exists() {
    local ssh_private_key="$1"
    local ssh_public_key="$2"
    
    if [[ -f "$ssh_private_key" && -f "$ssh_public_key" ]]; then
        return 0
    else
        return 1
    fi
}

# Test SSH connectivity to a VM
test_ssh_connectivity() {
    local host="$1"
    local public_ip="$2"
    local ssh_key="$3"
    local admin_user="$4"
    local timeout="${5:-10}"
    
    print_info "Testing SSH connectivity to $host ($public_ip)..."
    
    if ssh -i "$ssh_key" \
           -o ConnectTimeout="$timeout" \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o LogLevel=ERROR \
           "$admin_user@$public_ip" \
           "echo 'SSH connection successful'" &> /dev/null; then
        print_success "SSH connectivity to $host verified"
        return 0
    else
        print_error "SSH connectivity to $host failed"
        return 1
    fi
}

# Check WireGuard configuration on VM
verify_wireguard_config() {
    local host="$1"
    local public_ip="$2"
    local ssh_key="$3"
    local admin_user="$4"
    local timeout="${5:-10}"
    
    print_info "Verifying WireGuard configuration on $host..."
    
    # Check if WireGuard interface exists and is configured
    local wg_status
    wg_status=$(ssh -i "$ssh_key" \
                    -o ConnectTimeout="$timeout" \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -o LogLevel=ERROR \
                    "$admin_user@$public_ip" \
                    "sudo wg show wg0 2>/dev/null | head -1" 2>/dev/null || echo "FAILED")
    
    if [[ "$wg_status" == "FAILED" ]] || [[ -z "$wg_status" ]]; then
        print_error "WireGuard interface wg0 not found or not configured on $host"
        return 1
    fi
    
    # Check if WireGuard service is active
    local service_status
    service_status=$(ssh -i "$ssh_key" \
                         -o ConnectTimeout="$timeout" \
                         -o StrictHostKeyChecking=no \
                         -o UserKnownHostsFile=/dev/null \
                         -o LogLevel=ERROR \
                         "$admin_user@$public_ip" \
                         "sudo systemctl is-active wg-quick@wg0" 2>/dev/null || echo "FAILED")
    
    if [[ "$service_status" != "active" ]]; then
        print_error "WireGuard service wg-quick@wg0 is not active on $host (status: $service_status)"
        return 1
    fi
    
    print_success "WireGuard configuration verified on $host"
    return 0
}

# Wait for cloud-init to complete
wait_for_cloud_init() {
    local host="$1"
    local public_ip="$2"
    local ssh_key="$3"
    local admin_user="$4"
    local timeout_minutes="${5:-10}"
    local check_interval="${6:-30}"
    
    print_info "Waiting for cloud-init to complete on $host..."
    
    local timeout_seconds=$((timeout_minutes * 60))
    local elapsed_seconds=0
    
    while [[ $elapsed_seconds -lt $timeout_seconds ]]; do
        local cloud_init_status
        cloud_init_status=$(ssh -i "$ssh_key" \
                                -o ConnectTimeout=10 \
                                -o StrictHostKeyChecking=no \
                                -o UserKnownHostsFile=/dev/null \
                                -o LogLevel=ERROR \
                                "$admin_user@$public_ip" \
                                "sudo cloud-init status --wait" 2>/dev/null || echo "FAILED")
        
        if [[ "$cloud_init_status" == *"done"* ]]; then
            print_success "Cloud-init completed on $host"
            return 0
        elif [[ "$cloud_init_status" == "FAILED" ]]; then
            print_info "Cloud-init still running on $host (elapsed: ${elapsed_seconds}s)"
        else
            print_info "Cloud-init status on $host: $cloud_init_status (elapsed: ${elapsed_seconds}s)"
        fi
        
        if [[ $elapsed_seconds -lt $timeout_seconds ]]; then
            sleep $check_interval
            elapsed_seconds=$((elapsed_seconds + check_interval))
        fi
    done
    
    print_error "Timeout waiting for cloud-init to complete on $host after $timeout_minutes minutes"
    return 1
}

# ---- Standard Argument Handling ----

# Global variables for common options
QUIET_MODE=false
VERBOSE_MODE=false
YES_TO_ALL=false

# Standard usage function
print_usage() {
    local script_name="$1"
    local commands="$2"
    local options="$3"
    local examples="$4"
    
    cat << EOF
Usage: $script_name [command] [options]

Commands:
$commands

Options:
$options

Examples:
$examples
EOF
}

# Parse common arguments
parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                YES_TO_ALL=true
                shift
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE_MODE=true
                shift
                ;;
            -h|--help)
                return 1  # Signal to show help
                ;;
            -*)
                print_error "Unknown option: $1"
                return 2  # Signal unknown option
                ;;
            *)
                # Not an option, return to let script handle
                return 0
                ;;
        esac
    done
    return 0
}

# Enhanced print functions that respect quiet mode
print_info_verbose() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        print_info "$1"
    fi
}

print_info_quiet() {
    if [[ "$QUIET_MODE" != "true" ]]; then
        print_info "$1"
    fi
}

# Confirmation function that respects -y flag
confirm_action() {
    local prompt="$1"
    
    if [[ "$YES_TO_ALL" == "true" ]]; then
        return 0
    fi
    
    read -p "$prompt (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Check if a command is supported
check_command_support() {
    local command="$1"
    local supported_commands="$2"
    
    if [[ " $supported_commands " =~ " $command " ]]; then
        return 0
    else
        print_error "Unknown command: $command"
        print_info "Supported commands: $supported_commands"
        return 1
    fi
}