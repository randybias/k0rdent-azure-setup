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
    print_success "WireGuard tools are installed"
}

# Check k0sctl installation
check_k0sctl() {
    if ! command -v k0sctl &> /dev/null; then
        print_error "k0sctl is not installed. Please install it first."
        echo "Visit: https://docs.k0sproject.io/stable/k0sctl-install/"
        echo "Or install via:"
        echo "  # macOS:"
        echo "  brew install k0sproject/tap/k0sctl"
        echo "  # Linux:"
        echo "  curl -sSLf https://get.k0s.sh | sudo sh"
        exit 1
    fi
    print_success "k0sctl is installed"
}

# Check netcat installation
check_netcat() {
    if ! command -v nc &> /dev/null; then
        print_error "netcat (nc) not found. Please install netcat first:"
        echo "  # macOS:"
        echo "  brew install netcat"
        echo "  # Ubuntu/Debian:"
        echo "  sudo apt install netcat-openbsd"
        echo "  # CentOS/RHEL:"
        echo "  sudo yum install nmap-ncat"
        exit 1
    fi
    print_success "netcat is installed"
}

# Check VPN connectivity for cluster operations
check_vpn_connectivity() {
    print_header "Verifying VPN Connectivity"
    
    # Check if VPN configuration exists
    if [[ ! -f "$WG_CONFIG_FILE" ]]; then
        print_warning "No VPN configuration found. Cluster operations may fail."
        return 1
    fi
    
    # Test VPN connectivity to at least one VM
    print_info "Testing VPN connectivity to cluster nodes..."
    local connected_count=0
    
    for HOST in "${VM_HOSTS[@]}"; do
        local VM_IP="${WG_IPS[$HOST]}"
        if ping -c 1 -W 2000 "$VM_IP" &>/dev/null; then
            print_success "✓ $HOST ($VM_IP) reachable via VPN"
            ((connected_count++))
            break  # Only need one working connection
        fi
    done
    
    if [[ $connected_count -gt 0 ]]; then
        print_success "VPN connectivity verified"
        return 0
    else
        print_error "No VMs reachable via VPN"
        print_info "Ensure WireGuard VPN is connected before cluster operations"
        return 1
    fi
}

# Detect orphaned WireGuard interfaces on macOS
# Returns: Array of interface names found in /var/run/wireguard/
list_macos_wireguard_interfaces() {
    local wg_run_dir="/var/run/wireguard"
    local interfaces=()
    
    if [[ ! -d "$wg_run_dir" ]]; then
        return 0
    fi
    
    # Find all .name files in the directory
    for name_file in "$wg_run_dir"/*.name; do
        if [[ -f "$name_file" ]]; then
            local interface_name=$(basename "$name_file" .name)
            interfaces+=("$interface_name")
        fi
    done
    
    echo "${interfaces[@]}"
}

# Clean up orphaned WireGuard interface on macOS
# Parameters:
#   $1 - Interface name to clean up
# Returns: 0 on success, 1 on failure
cleanup_macos_wireguard_interface() {
    local interface_name="$1"
    local wg_run_dir="/var/run/wireguard"
    local name_file="$wg_run_dir/${interface_name}.name"
    local socket_file="$wg_run_dir/${interface_name}.sock"
    
    if [[ ! -f "$name_file" ]]; then
        print_error "Interface '$interface_name' not found in $wg_run_dir"
        return 1
    fi
    
    # Read the utun interface name
    local utun_name=$(cat "$name_file" 2>/dev/null)
    
    print_info "Cleaning up WireGuard interface: $interface_name (utun: $utun_name)"
    
    # Remove the socket file
    if [[ -f "$socket_file" ]]; then
        if sudo rm -f "$socket_file"; then
            print_success "Removed socket file: $socket_file"
        else
            print_error "Failed to remove socket file: $socket_file"
            return 1
        fi
    fi
    
    # Remove the name file
    if sudo rm -f "$name_file"; then
        print_success "Removed name file: $name_file"
    else
        print_error "Failed to remove name file: $name_file"
        return 1
    fi
    
    # Try to bring down the utun interface
    if [[ -n "$utun_name" ]]; then
        if sudo ifconfig "$utun_name" down 2>/dev/null; then
            print_success "Brought down interface: $utun_name"
        fi
    fi
    
    print_success "Cleaned up orphaned WireGuard interface: $interface_name"
    return 0
}

# Force cleanup of WireGuard interface on macOS
# Parameters:
#   $1 - Interface name (e.g., wgk0abc123)
# Returns: 0 on success, 1 on failure
force_cleanup_macos_wireguard() {
    local interface_name="$1"
    local wg_run_dir="/var/run/wireguard"
    local name_file="$wg_run_dir/${interface_name}.name"
    
    print_info "Cleaning up WireGuard interface: $interface_name"
    
    # Check if name file exists
    if [[ ! -f "$name_file" ]]; then
        print_info "No name file found, interface appears to be down"
        return 0
    fi
    
    # Read the utun name from the name file
    local utun_name=$(cat "$name_file" 2>/dev/null)
    if [[ -z "$utun_name" ]]; then
        print_error "Unable to read utun name from $name_file"
        # Still try to remove the name file
        sudo rm -f "$name_file"
        return 1
    fi
    
    local utun_socket="$wg_run_dir/${utun_name}.sock"
    
    # Remove socket file first (important!)
    if [[ -f "$utun_socket" ]]; then
        print_info "Removing socket file: $utun_socket"
        if sudo rm -f "$utun_socket"; then
            print_success "Socket file removed"
        else
            print_error "Failed to remove socket file"
            return 1
        fi
    fi
    
    # Remove name file
    print_info "Removing name file: $name_file"
    if sudo rm -f "$name_file"; then
        print_success "Name file removed"
    else
        print_error "Failed to remove name file"
        return 1
    fi
    
    # Try to bring down the utun interface
    print_info "Bringing down interface: $utun_name"
    sudo ifconfig "$utun_name" down 2>/dev/null || true
    
    # Final verification
    if [[ ! -f "$name_file" ]] && [[ ! -f "$utun_socket" ]]; then
        print_success "Interface '$interface_name' cleaned up successfully"
        return 0
    else
        print_error "Cleanup incomplete"
        return 1
    fi
}

# Clean up ALL orphaned WireGuard interfaces on macOS
# This is a destructive operation that removes all WireGuard configurations
# Returns: 0 on success, 1 on failure
cleanup_all_macos_wireguard_interfaces() {
    local wg_run_dir="/var/run/wireguard"
    
    if [[ ! -d "$wg_run_dir" ]]; then
        print_info "No WireGuard runtime directory found"
        return 0
    fi
    
    # Find all .name files
    local name_files=()
    for name_file in "$wg_run_dir"/*.name; do
        if [[ -f "$name_file" ]]; then
            name_files+=("$name_file")
        fi
    done
    
    if [[ ${#name_files[@]} -eq 0 ]]; then
        print_info "No WireGuard interfaces found to clean up"
        return 0
    fi
    
    # Show big warning
    print_warning "⚠️  WARNING: This will DESTROY ALL WireGuard configurations! ⚠️"
    echo ""
    echo "The following WireGuard interfaces will be removed:"
    
    # List all interfaces that will be removed
    for name_file in "${name_files[@]}"; do
        local interface_name=$(basename "$name_file" .name)
        local utun_name=$(cat "$name_file" 2>/dev/null || echo "unknown")
        echo "  - $interface_name (utun: $utun_name)"
    done
    
    echo ""
    
    # Confirm unless in non-interactive mode
    if [[ "${SKIP_PROMPTS:-false}" != "true" ]]; then
        read -p "Are you SURE you want to remove ALL WireGuard interfaces? Type 'yes' to confirm: " -r
        if [[ "$REPLY" != "yes" ]]; then
            print_info "Cleanup cancelled"
            return 1
        fi
    fi
    
    print_info "Cleaning up all WireGuard interfaces..."
    
    # Process each interface
    local failed=false
    for name_file in "${name_files[@]}"; do
        local interface_name=$(basename "$name_file" .name)
        local utun_name=$(cat "$name_file" 2>/dev/null)
        
        if [[ -n "$utun_name" ]]; then
            local utun_socket_file="$wg_run_dir/${utun_name}.sock"
            
            # Remove the utun socket file
            if [[ -f "$utun_socket_file" ]]; then
                if sudo rm -f "$utun_socket_file"; then
                    print_success "Removed socket: $utun_socket_file"
                else
                    print_error "Failed to remove socket: $utun_socket_file"
                    failed=true
                fi
            fi
            
            # Try to bring down the interface
            if sudo ifconfig "$utun_name" down 2>/dev/null; then
                print_success "Brought down interface: $utun_name"
            fi
        fi
        
        # Remove the name file
        if sudo rm -f "$name_file"; then
            print_success "Removed name file: $name_file"
        else
            print_error "Failed to remove name file: $name_file"
            failed=true
        fi
    done
    
    if [[ "$failed" == "true" ]]; then
        print_warning "Some interfaces could not be fully cleaned up"
        return 1
    else
        print_success "Successfully cleaned up all WireGuard interfaces"
        return 0
    fi
}

# Safely shut down WireGuard interface
# Parameters:
#   $1 - Interface name or config file path
# Returns: 0 on success (or if already down), 1 on failure
shutdown_wireguard_interface() {
    local interface_or_config="$1"
    local interface_name=""
    local config_file=""
    
    # Determine interface name and config file
    if [[ -f "$interface_or_config" ]]; then
        # We have a config file path
        config_file="$interface_or_config"
        interface_name=$(basename "$interface_or_config" .conf)
    else
        # We have just an interface name
        interface_name="$interface_or_config"
    fi
    
    print_info "Shutting down WireGuard interface: $interface_name"
    
    # macOS-specific logic
    if [[ "$(uname)" == "Darwin" ]]; then
        local wg_run_dir="/var/run/wireguard"
        local name_file="$wg_run_dir/${interface_name}.name"
        local wg_quick_path=$(get_wg_quick_path)
        
        # Step 1: Try graceful shutdown with wg-quick if config exists
        if [[ -n "$config_file" ]] && [[ -f "$config_file" ]] && [[ -n "$wg_quick_path" ]]; then
            print_info "Attempting graceful shutdown with wg-quick..."
            if sudo "$wg_quick_path" down "$config_file" 2>&1; then
                print_success "wg-quick down completed"
            else
                print_warning "wg-quick down failed (continuing with cleanup)"
            fi
        else
            if [[ ! -f "$config_file" ]]; then
                print_warning "Config file not found, skipping wg-quick down"
            fi
        fi
        
        # Step 2: Verify interface is down by checking /var/run/wireguard
        if [[ ! -f "$name_file" ]]; then
            print_success "WireGuard interface '$interface_name' is down"
            return 0
        fi
        
        # Step 3: Force cleanup if interface is still up
        print_info "Interface still active, performing cleanup..."
        force_cleanup_macos_wireguard "$interface_name"
        return $?
        
    else
        # Linux logic (unchanged)
        # Check if interface exists using wg show
        if ! sudo wg show "$interface_name" &>/dev/null; then
            print_info "WireGuard interface '$interface_name' is not active"
            return 0
        fi
        
        # Try wg-quick first
        local wg_quick_path=$(get_wg_quick_path)
        if [[ -n "$wg_quick_path" ]]; then
            if sudo "$wg_quick_path" down "$interface_name" 2>/dev/null; then
                print_success "WireGuard interface '$interface_name' shut down successfully"
                return 0
            fi
        fi
        
        # Fallback: manual interface shutdown
        print_warning "wg-quick not available, using manual shutdown"
        
        if sudo ip link delete "$interface_name" 2>/dev/null; then
            print_success "WireGuard interface '$interface_name' shut down manually"
            return 0
        fi
        
        print_error "Failed to shut down WireGuard interface '$interface_name'"
        return 1
    fi
}

# Get full path to WireGuard tools for sudo usage
get_wg_path() {
    which wg 2>/dev/null || echo "/usr/bin/wg"
}

get_wg_quick_path() {
    which wg-quick 2>/dev/null || echo "/usr/bin/wg-quick"
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
    
    # Check both legacy and new skip prompts variables
    if [[ "${YES_TO_ALL:-false}" == "true" ]] || [[ "${SKIP_PROMPTS:-false}" == "true" ]]; then
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

# Parse standard arguments for all scripts
parse_standard_args() {
    # Initialize arrays and variables
    POSITIONAL_ARGS=()
    local skip_prompts=false
    local no_wait=false
    local show_help=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                skip_prompts=true
                shift
                ;;
            --no-wait)
                no_wait=true
                shift
                ;;
            -h|--help)
                show_help=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                print_info "Use -h or --help for usage information"
                exit 1
                ;;
            *)
                POSITIONAL_ARGS+=("$1")
                shift
                ;;
        esac
    done
    
    # Export parsed values
    echo "SKIP_PROMPTS=$skip_prompts"
    echo "NO_WAIT=$no_wait"
    echo "SHOW_HELP=$show_help"
    echo "POSITIONAL_ARGS=(${POSITIONAL_ARGS[@]:-})"
}

# ---- Logging Functions ----

# Initialize logging for a script
init_logging() {
    local script_name="$1"
    local log_dir="./logs"
    
    # Ensure logs directory exists
    ensure_directory "$log_dir"
    
    # Create timestamped log file
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local log_file="$log_dir/${script_name}_${timestamp}.log"
    
    # Export for use in script
    export CURRENT_LOG_FILE="$log_file"
    
    # Write header to log
    echo "=== Log started at $(date) ===" > "$log_file"
    echo "Script: $script_name" >> "$log_file"
    echo "============================" >> "$log_file"
    echo "" >> "$log_file"
    
    print_info "Logging to: $log_file"
}

# Log command output while also displaying progress
log_command() {
    local description="$1"
    shift
    
    # Ensure we have a log file
    if [[ -z "${CURRENT_LOG_FILE:-}" ]]; then
        print_error "No log file initialized. Call init_logging first."
        return 1
    fi
    
    # Log the command being run
    echo "==> Running: $description" >> "$CURRENT_LOG_FILE"
    echo "Command: $*" >> "$CURRENT_LOG_FILE"
    echo "Time: $(date)" >> "$CURRENT_LOG_FILE"
    echo "---" >> "$CURRENT_LOG_FILE"
    
    # Run command and capture output
    local output_file=$(mktemp)
    local exit_code=0
    
    # Execute command with output to temp file
    if "$@" > "$output_file" 2>&1; then
        print_success "$description"
        exit_code=0
    else
        exit_code=$?
        print_error "$description failed (exit code: $exit_code)"
    fi
    
    # Append output to log file
    cat "$output_file" >> "$CURRENT_LOG_FILE"
    echo "" >> "$CURRENT_LOG_FILE"
    
    # Clean up temp file
    rm -f "$output_file"
    
    return $exit_code
}

# Log Azure command with reduced console output
log_azure_command() {
    local description="$1"
    shift
    
    print_info "$description..."
    log_command "$description" "$@"
}

# ---- Unified Command Handling Framework ----

# Handle standard script commands with consistent behavior
# Parameters:
#   $1 - Script name (usually $0)
#   $2 - Space-separated list of supported commands
#   $3+ - Pairs of command_name function_name mappings
# Usage:
#   handle_standard_commands "$0" "deploy reset status help" \
#       "deploy" "deploy_function" \
#       "reset" "reset_function" \
#       "status" "show_status" \
#       "usage" "show_usage"
handle_standard_commands() {
    local script_name="$1"
    local supported_commands="$2"
    shift 2
    
    # Build command-to-function mapping
    declare -A command_functions=()
    while [[ $# -gt 0 ]]; do
        command_functions["$1"]="$2"
        shift 2
    done
    
    # Parse standard arguments (assumes ORIGINAL_ARGS is available)
    if [[ -n "${ORIGINAL_ARGS[*]:-}" ]]; then
        PARSED_ARGS=$(parse_standard_args "${ORIGINAL_ARGS[@]}")
    else
        PARSED_ARGS=$(parse_standard_args "$@")
    fi
    eval "$PARSED_ARGS"
    
    # Get command from positional arguments
    local command="${POSITIONAL_ARGS[0]:-}"
    
    # Handle help request
    if [[ "$SHOW_HELP" == "true" ]] || [[ "$command" == "help" ]]; then
        if [[ -n "${command_functions[usage]:-}" ]]; then
            ${command_functions["usage"]}
        else
            print_error "No usage function defined for script: $script_name"
        fi
        exit 0
    fi
    
    # Validate command
    if [[ -z "$command" ]]; then
        print_error "No command specified"
        if [[ -n "${command_functions[usage]:-}" ]]; then
            ${command_functions["usage"]}
        fi
        exit 1
    fi
    
    if [[ ! " $supported_commands " =~ " $command " ]]; then
        print_error "Invalid command: $command"
        print_info "Supported commands: $supported_commands"
        if [[ -n "${command_functions[usage]:-}" ]]; then
            ${command_functions["usage"]}
        fi
        exit 1
    fi
    
    # Execute command function
    if [[ -n "${command_functions[$command]:-}" ]]; then
        ${command_functions["$command"]}
    else
        print_error "No function defined for command: $command"
        exit 1
    fi
}

# ---- SSH Execution Framework ----

# Execute SSH command with standard options and error handling
# Parameters:
#   $1 - Host (hostname or IP)
#   $2 - Command to execute
#   $3 - Description (optional, for logging)
#   $4 - Timeout in seconds (optional, default 30)
#   $5 - SSH key path (optional, uses SSH_PRIVATE_KEY if not provided)
#   $6 - Admin user (optional, uses SSH_USERNAME if not provided)
# Returns: Exit code from SSH command
execute_remote_command() {
    local host="$1"
    local command="$2"
    local description="${3:-Remote command}"
    local timeout="${4:-30}"
    local ssh_key="${5:-${SSH_PRIVATE_KEY:-}}"
    local admin_user="${6:-${SSH_USERNAME:-k0rdent}}"
    
    # Validate parameters
    if [[ -z "$host" ]]; then
        print_error "Host parameter required for execute_remote_command"
        return 1
    fi
    
    if [[ -z "$command" ]]; then
        print_error "Command parameter required for execute_remote_command"
        return 1
    fi
    
    if [[ -z "$ssh_key" ]]; then
        print_error "SSH key not specified and SSH_PRIVATE_KEY not set"
        return 1
    fi
    
    if [[ ! -f "$ssh_key" ]]; then
        print_error "SSH key not found: $ssh_key"
        return 1
    fi
    
    print_info "$description on $host..."
    
    # Execute SSH command with standard options
    if ssh -i "$ssh_key" \
           -o ConnectTimeout="$timeout" \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o LogLevel=ERROR \
           "$admin_user@$host" \
           "$command"; then
        return 0
    else
        local exit_code=$?
        print_error "$description failed on $host (exit code: $exit_code)"
        return $exit_code
    fi
}

# Execute SSH command and capture output
# Parameters: Same as execute_remote_command
# Returns: Sets global variable SSH_OUTPUT with command output
execute_remote_command_with_output() {
    local host="$1"
    local command="$2"
    local description="${3:-Remote command}"
    local timeout="${4:-30}"
    local ssh_key="${5:-${SSH_PRIVATE_KEY:-}}"
    local admin_user="${6:-${SSH_USERNAME:-k0rdent}}"
    
    # Validate parameters (same as execute_remote_command)
    if [[ -z "$host" ]] || [[ -z "$command" ]] || [[ -z "$ssh_key" ]] || [[ ! -f "$ssh_key" ]]; then
        print_error "Invalid parameters for execute_remote_command_with_output"
        return 1
    fi
    
    print_info "$description on $host..."
    
    # Execute and capture output
    SSH_OUTPUT=$(ssh -i "$ssh_key" \
                     -o ConnectTimeout="$timeout" \
                     -o StrictHostKeyChecking=no \
                     -o UserKnownHostsFile=/dev/null \
                     -o LogLevel=ERROR \
                     "$admin_user@$host" \
                     "$command" 2>&1)
    
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        return 0
    else
        print_error "$description failed on $host (exit code: $exit_code)"
        return $exit_code
    fi
}

# ---- Azure Operations Framework ----

# Check if Azure resource exists with error handling
# Parameters:
#   $1 - Resource type (group, vm, vnet, etc.)
#   $2 - Resource name
#   $3 - Resource group (optional for resource group type)
# Returns: 0 if exists, 1 if not exists, 2 if error
check_azure_resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="${3:-}"
    
    case "$resource_type" in
        "group"|"resource-group")
            az group show --name "$resource_name" >/dev/null 2>&1
            ;;
        "vm")
            if [[ -z "$resource_group" ]]; then
                print_error "Resource group required for VM existence check"
                return 2
            fi
            az vm show --name "$resource_name" --resource-group "$resource_group" >/dev/null 2>&1
            ;;
        "vnet")
            if [[ -z "$resource_group" ]]; then
                print_error "Resource group required for VNet existence check"
                return 2
            fi
            az network vnet show --name "$resource_name" --resource-group "$resource_group" >/dev/null 2>&1
            ;;
        "nsg")
            if [[ -z "$resource_group" ]]; then
                print_error "Resource group required for NSG existence check"
                return 2
            fi
            az network nsg show --name "$resource_name" --resource-group "$resource_group" >/dev/null 2>&1
            ;;
        "sshkey")
            if [[ -z "$resource_group" ]]; then
                print_error "Resource group required for SSH key existence check"
                return 2
            fi
            az sshkey show --name "$resource_name" --resource-group "$resource_group" >/dev/null 2>&1
            ;;
        *)
            print_error "Unsupported resource type: $resource_type"
            return 2
            ;;
    esac
}

# Execute Azure CLI command with error handling and logging
# Parameters:
#   $1 - Description of the operation
#   $2+ - Azure CLI command and arguments
# Returns: Exit code from az command
execute_azure_command() {
    local description="$1"
    shift
    
    print_info "$description..."
    
    # Log the command if logging is enabled
    if [[ -n "${CURRENT_LOG_FILE:-}" ]]; then
        echo "==> Azure Command: $description" >> "$CURRENT_LOG_FILE"
        echo "Command: az $*" >> "$CURRENT_LOG_FILE"
        echo "Time: $(date)" >> "$CURRENT_LOG_FILE"
        echo "---" >> "$CURRENT_LOG_FILE"
    fi
    
    # Execute Azure CLI command
    if az "$@"; then
        print_success "$description completed"
        return 0
    else
        local exit_code=$?
        print_error "$description failed (exit code: $exit_code)"
        return $exit_code
    fi
}

# Wait for Azure operation to complete with status checking
# Parameters:
#   $1 - Resource type for status checking
#   $2 - Resource name
#   $3 - Resource group (if needed)
#   $4 - Expected status (optional, default "Succeeded")
#   $5 - Timeout in seconds (optional, default 300)
#   $6 - Check interval in seconds (optional, default 30)
wait_for_azure_operation() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="${3:-}"
    local expected_status="${4:-Succeeded}"
    local timeout="${5:-300}"
    local check_interval="${6:-30}"
    
    print_info "Waiting for Azure operation to complete: $resource_name"
    
    local elapsed_seconds=0
    while [[ $elapsed_seconds -lt $timeout ]]; do
        local current_status=""
        
        case "$resource_type" in
            "vm")
                current_status=$(az vm show --name "$resource_name" --resource-group "$resource_group" \
                    --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
                ;;
            "deployment")
                current_status=$(az deployment group show --name "$resource_name" --resource-group "$resource_group" \
                    --query "properties.provisioningState" -o tsv 2>/dev/null || echo "NotFound")
                ;;
            *)
                print_error "Unsupported resource type for wait operation: $resource_type"
                return 1
                ;;
        esac
        
        if [[ "$current_status" == "$expected_status" ]]; then
            print_success "Azure operation completed: $resource_name ($current_status)"
            return 0
        elif [[ "$current_status" == "Failed" ]]; then
            print_error "Azure operation failed: $resource_name"
            return 1
        fi
        
        print_info "Current status: $current_status (elapsed: ${elapsed_seconds}s)"
        sleep $check_interval
        elapsed_seconds=$((elapsed_seconds + check_interval))
    done
    
    print_error "Timeout waiting for Azure operation: $resource_name (after ${timeout}s)"
    return 1
}

# ---- Resource Verification Framework ----

# Generic resource verification with retry logic
# Parameters:
#   $1 - Resource type description
#   $2 - Check function name
#   $3 - Timeout in seconds (optional, default 300)
#   $4 - Check interval in seconds (optional, default 30)
#   $5+ - Resources to verify
verify_resources() {
    local resource_type="$1"
    local check_function="$2"
    local timeout="${3:-300}"
    local interval="${4:-30}"
    shift 4
    local resources=("$@")
    
    if [[ ${#resources[@]} -eq 0 ]]; then
        print_error "No resources specified for verification"
        return 1
    fi
    
    print_header "Verifying $resource_type"
    
    local elapsed_seconds=0
    local all_ready=false
    
    while [[ $elapsed_seconds -lt $timeout ]]; do
        local ready_count=0
        local total_count=${#resources[@]}
        
        for resource in "${resources[@]}"; do
            if $check_function "$resource"; then
                ((ready_count++))
            fi
        done
        
        print_info "Ready: $ready_count/$total_count $resource_type (elapsed: ${elapsed_seconds}s)"
        
        if [[ $ready_count -eq $total_count ]]; then
            all_ready=true
            break
        fi
        
        if [[ $elapsed_seconds -lt $timeout ]]; then
            sleep $interval
            elapsed_seconds=$((elapsed_seconds + interval))
        fi
    done
    
    if [[ "$all_ready" == "true" ]]; then
        print_success "All $resource_type verified successfully"
        return 0
    else
        print_error "Timeout verifying $resource_type after $((timeout / 60)) minutes"
        return 1
    fi
}

# ---- Status Display Framework ----

# Generic status display for any resource type
# Parameters:
#   $1 - Title for the status section
#   $2 - Function to check if resource exists
#   $3 - Function to get resource details
#   $4+ - Resources to check
display_resource_status() {
    local title="$1"
    local check_exists_func="$2"
    local get_details_func="$3"
    shift 3
    local resources=("$@")
    
    print_header "$title Status"
    
    if [[ ${#resources[@]} -eq 0 ]]; then
        print_info "No resources to check"
        return 0
    fi
    
    for resource in "${resources[@]}"; do
        if $check_exists_func "$resource"; then
            if command -v "$get_details_func" >/dev/null 2>&1; then
                local details
                details=$($get_details_func "$resource" 2>/dev/null || echo "Details unavailable")
                print_success "$resource: $details"
            else
                print_success "$resource: Available"
            fi
        else
            print_error "$resource: Not found"
        fi
    done
}

# ---- Enhanced Prerequisite Checking ----

# Check for k0sctl tool
check_k0sctl() {
    if ! command -v k0sctl &> /dev/null; then
        print_error "k0sctl is not installed. Please install it first."
        echo "Visit: https://github.com/k0sproject/k0sctl/releases"
        return 1
    fi
    print_success "k0sctl is installed"
    return 0
}

# Check for netcat tool  
check_netcat() {
    if ! command -v nc &> /dev/null; then
        print_error "netcat (nc) is not installed. Please install it first."
        echo "On Ubuntu/Debian: sudo apt install netcat"
        echo "On CentOS/RHEL: sudo yum install netcat"
        echo "On macOS: brew install netcat"
        return 1
    fi
    print_success "netcat is installed"
    return 0
}

# Comprehensive prerequisites check
check_all_prerequisites() {
    print_header "Checking Prerequisites"
    
    local failed=false
    
    # Core tools
    if ! check_azure_cli; then
        failed=true
    fi
    
    if ! check_wireguard_tools; then
        failed=true
    fi
    
    # Optional tools (warn but don't fail)
    if ! check_k0sctl; then
        print_warning "k0sctl not found - required for k0s cluster installation"
    fi
    
    if ! check_netcat; then
        print_warning "netcat not found - required for connectivity testing"
    fi
    
    if [[ "$failed" == "true" ]]; then
        print_error "Some prerequisites are missing"
        return 1
    fi
    
    print_success "All prerequisites satisfied"
    return 0
}

# ---- WireGuard Connectivity Testing ----

# Run detailed WireGuard connectivity test
# Parameters:
#   $1 - K0rdent prefix
#   $2 - SSH key path (optional, will construct from prefix if not provided)
# Returns: 0 if test passes, 1 if fails
# Requires: VM_HOSTS and WG_IPS arrays to be defined in k0rdent-config.sh
run_detailed_wireguard_connectivity_test() {
    local k0rdent_prefix="$1"
    local ssh_key="${2:-./azure-resources/${k0rdent_prefix}-ssh-key}"
    
    print_header "Detailed Connectivity Test"
    
    # Validate prerequisites
    if [[ -z "${VM_HOSTS[*]:-}" ]]; then
        print_error "VM_HOSTS array not defined. Source k0rdent-config.sh first."
        return 1
    fi
    
    if [[ -z "${WG_IPS[*]:-}" ]]; then
        print_error "WG_IPS array not defined. Source k0rdent-config.sh first."
        return 1
    fi
    
    # Initialize result tracking
    declare -A PING_RESULTS
    declare -A SSH_RESULTS
    local ALL_REACHABLE=true
    local PING_SUCCESS_COUNT=0
    local SSH_SUCCESS_COUNT=0
    local TOTAL_HOSTS=${#VM_HOSTS[@]}
    
    # Test each host
    for HOST in "${VM_HOSTS[@]}"; do
        local VM_IP="${WG_IPS[$HOST]}"
        print_info "Testing connectivity to $HOST ($VM_IP)..."
        
        # Test ping connectivity
        if ping -c 3 -W 5000 "$VM_IP" >/dev/null 2>&1; then
            print_success "  ✓ Ping to $HOST successful"
            PING_RESULTS["$HOST"]="success"
            ((PING_SUCCESS_COUNT++))
            
            # Test SSH connectivity if ping works
            if [[ -f "$ssh_key" ]]; then
                if ssh -i "$ssh_key" \
                       -o ConnectTimeout=10 \
                       -o StrictHostKeyChecking=no \
                       -o UserKnownHostsFile=/dev/null \
                       -o LogLevel=ERROR \
                       "k0rdent@$VM_IP" \
                       "echo 'SSH via WireGuard successful'" >/dev/null 2>&1; then
                    print_success "  ✓ SSH to $HOST via WireGuard successful"
                    SSH_RESULTS["$HOST"]="success"
                    ((SSH_SUCCESS_COUNT++))
                else
                    print_warning "  ⚠ SSH to $HOST failed (ping works, check SSH keys)"
                    SSH_RESULTS["$HOST"]="failed"
                fi
            else
                print_warning "  ⚠ SSH key not found, skipping SSH test for $HOST"
                SSH_RESULTS["$HOST"]="no_key"
            fi
        else
            print_error "  ✗ Ping to $HOST failed"
            PING_RESULTS["$HOST"]="failed"
            SSH_RESULTS["$HOST"]="no_ping"
            ALL_REACHABLE=false
        fi
    done
    
    # Print summary
    print_header "Detailed Test Results"
    
    for HOST in "${VM_HOSTS[@]}"; do
        local VM_IP="${WG_IPS[$HOST]}"
        local PING_STATUS="${PING_RESULTS[$HOST]}"
        local SSH_STATUS="${SSH_RESULTS[$HOST]}"
        
        if [[ "$PING_STATUS" == "success" && "$SSH_STATUS" == "success" ]]; then
            print_success "  ✓ $HOST ($VM_IP) - Ping & SSH working"
        elif [[ "$PING_STATUS" == "success" && "$SSH_STATUS" == "failed" ]]; then
            print_warning "  ⚠ $HOST ($VM_IP) - Ping works, SSH failed"
        elif [[ "$PING_STATUS" == "success" && "$SSH_STATUS" == "no_key" ]]; then
            print_warning "  ⚠ $HOST ($VM_IP) - Ping works, SSH not tested (no key)"
        else
            print_error "  ✗ $HOST ($VM_IP) - Ping failed"
        fi
    done
    
    # Print final summary
    echo
    print_info "Summary:"
    echo "  • Ping successful: $PING_SUCCESS_COUNT/$TOTAL_HOSTS hosts"
    echo "  • SSH successful: $SSH_SUCCESS_COUNT/$TOTAL_HOSTS hosts"
    
    if [[ "$ALL_REACHABLE" == "true" && "$SSH_SUCCESS_COUNT" -eq "$TOTAL_HOSTS" ]]; then
        print_success "🎉 All detailed tests passed!"
        return 0
    elif [[ "$PING_SUCCESS_COUNT" -gt $(($TOTAL_HOSTS / 2)) ]]; then
        print_warning "Some connectivity issues detected, but majority of hosts are reachable."
        return 0
    else
        print_error "Significant connectivity issues detected."
        return 1
    fi
}
# ---- Generic Resource Verification Framework ----

# Generic prerequisite checker
# Usage: check_prerequisites "script_name" "resource:error_msg:fix_cmd" ...
check_prerequisites() {
    local script_name="$1"
    shift
    
    print_info "Validating prerequisites..."
    local all_ok=true
    
    for check in "$@"; do
        IFS=':' read -r resource error_msg fix_cmd <<< "$check"
        
        case "$resource" in
            azure_cli)
                if ! check_azure_cli_quiet; then
                    print_error "$error_msg"
                    [[ -n "$fix_cmd" ]] && print_info "$fix_cmd"
                    all_ok=false
                fi
                ;;
            wireguard_tools)
                if ! command -v wg &> /dev/null || ! command -v wg-quick &> /dev/null; then
                    print_error "$error_msg"
                    [[ -n "$fix_cmd" ]] && print_info "$fix_cmd"
                    all_ok=false
                fi
                ;;
            resource_group)
                if ! check_resource_group_exists "$RG"; then
                    print_error "$error_msg"
                    [[ -n "$fix_cmd" ]] && print_info "$fix_cmd"
                    all_ok=false
                fi
                ;;
            file:*)
                local file_path="${resource#file:}"
                if ! check_file_exists "$file_path" "$error_msg"; then
                    [[ -n "$fix_cmd" ]] && print_info "$fix_cmd"
                    all_ok=false
                fi
                ;;
            dir:*)
                local dir_path="${resource#dir:}"
                if [[ ! -d "$dir_path" ]]; then
                    print_error "$error_msg"
                    [[ -n "$fix_cmd" ]] && print_info "$fix_cmd"
                    all_ok=false
                fi
                ;;
            manifest:*)
                local manifest_type="${resource#manifest:}"
                case "$manifest_type" in
                    wg_keys)
                        if [[ "$(get_wireguard_private_key "mylaptop" 2>/dev/null || echo "null")" == "null" ]]; then
                            print_error "$error_msg"
                            [[ -n "$fix_cmd" ]] && print_info "$fix_cmd"
                            all_ok=false
                        fi
                        ;;
                    azure)
                        if ! state_file_exists; then
                            print_error "$error_msg"
                            [[ -n "$fix_cmd" ]] && print_info "$fix_cmd"
                            all_ok=false
                        fi
                        ;;
                esac
                ;;
        esac
    done
    
    if [[ "$all_ok" == "true" ]]; then
        print_success "Prerequisites validated"
        return 0
    else
        return 1
    fi
}

# Check Azure CLI quietly (no output)
check_azure_cli_quiet() {
    if ! command -v az &> /dev/null; then
        return 1
    fi
    
    if ! az account show &> /dev/null; then
        return 1
    fi
    
    return 0
}

# Generic status display framework
# Usage: display_status "header" "check:description" ...
display_status() {
    local header="$1"
    shift
    
    print_header "$header"
    
    for item in "$@"; do
        IFS=':' read -r check description <<< "$item"
        
        case "$check" in
            file:*)
                local file_path="${check#file:}"
                if [[ -f "$file_path" ]]; then
                    print_success "$description"
                else
                    print_error "$description (missing)"
                fi
                ;;
            dir:*)
                local dir_path="${check#dir:}"
                if [[ -d "$dir_path" ]]; then
                    print_success "$description"
                else
                    print_error "$description (missing)"
                fi
                ;;
            count:*)
                local count_info="${check#count:}"
                IFS='=' read -r actual expected <<< "$count_info"
                if [[ "$actual" -eq "$expected" ]]; then
                    print_success "$description: $actual of $expected"
                else
                    print_warning "$description: $actual of $expected"
                fi
                ;;
            info:*)
                local info="${check#info:}"
                print_info "$description: $info"
                ;;
            *)
                print_info "$description"
                ;;
        esac
    done
}