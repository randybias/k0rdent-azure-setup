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