#!/usr/bin/env bash

# configure.sh
# Configuration management script for k0rdent Azure deployment
# Handles YAML configuration creation, validation, and export to shell variables

set -euo pipefail

# Load common functions
source ./etc/common-functions.sh

# Configuration file paths
CONFIG_YAML="./config/k0rdent.yaml"
CONFIG_DEFAULT_YAML="./config/k0rdent-default.yaml"
CONFIG_USER_SH="./etc/config-user.sh"

# Show usage information
show_usage() {
    echo "k0rdent Configuration Management"
    echo
    echo "USAGE:"
    echo "  $0 COMMAND [OPTIONS]"
    echo
    echo "COMMANDS:"
    echo "  init [--template NAME]    Create initial configuration from template"
    echo "  show                      Display current configuration"
    echo "  export [--file FILE]      Export YAML to shell variables"
    echo "  templates                 List available templates"
    echo "  migrate                   Convert shell config to YAML"
    echo "  help                      Show this help message"
    echo
    echo "OPTIONS:"
    echo "  -y, --yes        Skip confirmation prompts"
    echo "  -v, --verbose    Enable verbose output"
    echo
    echo "EXAMPLES:"
    echo "  $0 init                         # Create config from minimal template (default)"
    echo "  $0 init --template production   # Create config from production template"
    echo "  $0 init --template development  # Create config from development template"
    echo "  $0 show                         # Display current configuration"
    echo "  $0 export                       # Export current config to shell vars"
    echo "  $0 migrate                      # Convert etc/config-user.sh to YAML"
}

# Check if yq is available
check_yq() {
    if ! command -v yq &> /dev/null; then
        print_error "yq is required for YAML configuration but not installed"
        echo "Install with:"
        echo "  macOS: brew install yq"
        echo "  Linux: wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
        exit 1
    fi
}

# Convert YAML configuration to shell variable exports
yaml_to_shell_vars() {
    local yaml_file="$1"
    
    if [[ ! -f "$yaml_file" ]]; then
        print_error "YAML configuration file not found: $yaml_file"
        exit 1
    fi
    
    # Export Azure settings
    echo "export AZURE_LOCATION='$(yq '.azure.location' "$yaml_file")'"
    echo "export AZURE_VM_IMAGE='$(yq '.azure.vm_image' "$yaml_file")'"
    echo "export AZURE_VM_PRIORITY='$(yq '.azure.vm_priority' "$yaml_file")'"
    echo "export AZURE_EVICTION_POLICY='$(yq '.azure.eviction_policy' "$yaml_file")'"
    
    # Export VM sizing
    echo "export AZURE_CONTROLLER_VM_SIZE='$(yq '.vm_sizing.controller.size' "$yaml_file")'"
    echo "export AZURE_WORKER_VM_SIZE='$(yq '.vm_sizing.worker.size' "$yaml_file")'"
    
    # Export cluster topology
    echo "export K0S_CONTROLLER_COUNT=$(yq '.cluster.controllers.count' "$yaml_file")"
    echo "export K0S_WORKER_COUNT=$(yq '.cluster.workers.count' "$yaml_file")"
    
    # Export zone arrays
    local controller_zones=($(yq '.cluster.controllers.zones[]' "$yaml_file"))
    local worker_zones=($(yq '.cluster.workers.zones[]' "$yaml_file"))
    echo "export CONTROLLER_ZONES=(${controller_zones[*]})"
    echo "export WORKER_ZONES=(${worker_zones[*]})"
    
    # Export SSH settings
    echo "export SSH_USERNAME='$(yq '.ssh.username' "$yaml_file")'"
    echo "export SSH_KEY_COMMENT='$(yq '.ssh.key_comment' "$yaml_file")'"
    
    # Export software versions
    echo "export K0S_VERSION='$(yq '.software.k0s.version' "$yaml_file")'"
    echo "export K0RDENT_VERSION='$(yq '.software.k0rdent.version' "$yaml_file")'"
    echo "export K0RDENT_OCI_REGISTRY='$(yq '.software.k0rdent.registry' "$yaml_file")'"
    echo "export K0RDENT_NAMESPACE='$(yq '.software.k0rdent.namespace' "$yaml_file")'"
    
    # Export network configuration
    echo "export VNET_PREFIX='$(yq '.network.vnet_prefix' "$yaml_file")'"
    echo "export SUBNET_PREFIX='$(yq '.network.subnet_prefix' "$yaml_file")'"
    echo "export WG_NETWORK='$(yq '.network.wireguard_network' "$yaml_file")'"
    
    # Export timeouts
    echo "export SSH_CONNECT_TIMEOUT=$(yq '.timeouts.ssh_connect' "$yaml_file")"
    echo "export SSH_COMMAND_TIMEOUT=$(yq '.timeouts.ssh_command' "$yaml_file")"
    echo "export K0S_INSTALL_WAIT=$(yq '.timeouts.k0s_install_wait' "$yaml_file")"
    echo "export K0RDENT_INSTALL_WAIT=$(yq '.timeouts.k0rdent_install_wait' "$yaml_file")"
    echo "export WIREGUARD_CONNECT_WAIT=$(yq '.timeouts.wireguard_connect_wait' "$yaml_file")"
    echo "export VM_CREATION_TIMEOUT_MINUTES=$(yq '.timeouts.vm_creation_minutes' "$yaml_file")"
    echo "export VM_WAIT_CHECK_INTERVAL=$(yq '.timeouts.vm_wait_check_interval' "$yaml_file")"
    echo "export CLOUD_INIT_TIMEOUT=$(yq '.timeouts.cloud_init_timeout' "$yaml_file")"
    echo "export CLOUD_INIT_CHECK_INTERVAL=$(yq '.timeouts.cloud_init_check_interval' "$yaml_file")"
    echo "export VERIFICATION_RETRIES=$(yq '.timeouts.verification_retries' "$yaml_file")"
    echo "export VERIFICATION_RETRY_DELAY=$(yq '.timeouts.verification_retry_delay' "$yaml_file")"
}

# Initialize configuration from template
init_config() {
    local template="${1:-minimal}"
    local skip_confirm="${2:-false}"
    
    # Map template names to files
    local source_file
    case "$template" in
        "default")
            source_file="$CONFIG_DEFAULT_YAML"
            ;;
        *)
            source_file="./config/examples/${template}.yaml"
            ;;
    esac
    
    if [[ ! -f "$source_file" ]]; then
        print_error "Template not found: $source_file"
        echo "Available templates:"
        list_templates
        exit 1
    fi
    
    if [[ -f "$CONFIG_YAML" ]] && [[ "$skip_confirm" != "true" ]]; then
        print_warning "Configuration file already exists: $CONFIG_YAML"
        read -p "Overwrite? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
            print_info "Configuration initialization cancelled"
            exit 0
        fi
    fi
    
    cp "$source_file" "$CONFIG_YAML"
    print_success "Configuration initialized: $CONFIG_YAML"
    print_info "Template: $template"
    print_info "Edit the file to customize your deployment settings"
}

# Display current configuration
show_config() {
    local config_file
    
    if [[ -f "$CONFIG_YAML" ]]; then
        config_file="$CONFIG_YAML"
        print_info "Using YAML configuration: $CONFIG_YAML"
    elif [[ -f "$CONFIG_DEFAULT_YAML" ]]; then
        config_file="$CONFIG_DEFAULT_YAML"
        print_info "Using default YAML configuration: $CONFIG_DEFAULT_YAML"
    elif [[ -f "$CONFIG_USER_SH" ]]; then
        print_info "Using legacy shell configuration: $CONFIG_USER_SH"
        print_warning "Consider migrating to YAML with: $0 migrate"
        return 0
    else
        print_error "No configuration found"
        print_info "Initialize configuration with: $0 init"
        exit 1
    fi
    
    echo
    print_header "Current Configuration"
    yq '.' "$config_file"
}

# Export configuration as shell variables
export_config() {
    local yaml_file="${1:-}"
    
    if [[ -n "$yaml_file" ]]; then
        yaml_to_shell_vars "$yaml_file"
    elif [[ -f "$CONFIG_YAML" ]]; then
        yaml_to_shell_vars "$CONFIG_YAML"
    elif [[ -f "$CONFIG_DEFAULT_YAML" ]]; then
        yaml_to_shell_vars "$CONFIG_DEFAULT_YAML"
    else
        print_error "No YAML configuration found"
        exit 1
    fi
}

# List available templates
list_templates() {
    echo "Available templates:"
    
    if [[ -d "./config/examples" ]]; then
        for template in ./config/examples/*.yaml; do
            if [[ -f "$template" ]]; then
                local name=$(basename "$template" .yaml)
                local description=$(yq '.metadata.description' "$template" 2>/dev/null || echo "No description")
                if [[ "$name" == "minimal" ]]; then
                    echo "  $name - $description (default)"
                else
                    echo "  $name - $description"
                fi
            fi
        done
    fi
    
    echo "  default      - Full-featured 3 controller + 2 worker setup (k0rdent-default.yaml)"
}

# Migrate shell configuration to YAML
migrate_shell_to_yaml() {
    if [[ ! -f "$CONFIG_USER_SH" ]]; then
        print_error "Shell configuration not found: $CONFIG_USER_SH"
        exit 1
    fi
    
    if [[ -f "$CONFIG_YAML" ]]; then
        print_warning "YAML configuration already exists: $CONFIG_YAML"
        read -p "Overwrite with migrated configuration? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
            print_info "Migration cancelled"
            exit 0
        fi
    fi
    
    print_info "Migrating shell configuration to YAML..."
    
    # Source the shell config to get variables
    source "$CONFIG_USER_SH"
    
    # Generate YAML from shell variables
    cat > "$CONFIG_YAML" << EOF
# Migrated from etc/config-user.sh
metadata:
  version: "1.0"
  schema: "k0rdent-config"
  description: "Migrated from shell configuration"

azure:
  location: "$AZURE_LOCATION"
  vm_image: "$AZURE_VM_IMAGE"
  vm_priority: "$AZURE_VM_PRIORITY"
  eviction_policy: "$AZURE_EVICTION_POLICY"

vm_sizing:
  controller:
    size: "$AZURE_CONTROLLER_VM_SIZE"
  worker:
    size: "$AZURE_WORKER_VM_SIZE"

cluster:
  controllers:
    count: $K0S_CONTROLLER_COUNT
    zones: [$(IFS=,; echo "${CONTROLLER_ZONES[*]/#/}" | sed 's/,/, /g')]
  workers:
    count: $K0S_WORKER_COUNT
    zones: [$(IFS=,; echo "${WORKER_ZONES[*]/#/}" | sed 's/,/, /g')]

ssh:
  username: "$SSH_USERNAME"
  key_comment: "$SSH_KEY_COMMENT"

software:
  k0s:
    version: "$K0S_VERSION"
  k0rdent:
    version: "$K0RDENT_VERSION"
    registry: "$K0RDENT_OCI_REGISTRY"
    namespace: "$K0RDENT_NAMESPACE"

network:
  vnet_prefix: "$VNET_PREFIX"
  subnet_prefix: "$SUBNET_PREFIX"
  wireguard_network: "$WG_NETWORK"

timeouts:
  ssh_connect: $SSH_CONNECT_TIMEOUT
  ssh_command: $SSH_COMMAND_TIMEOUT
  k0s_install_wait: $K0S_INSTALL_WAIT
  k0rdent_install_wait: $K0RDENT_INSTALL_WAIT
  wireguard_connect_wait: $WIREGUARD_CONNECT_WAIT
  vm_creation_minutes: $VM_CREATION_TIMEOUT_MINUTES
  vm_wait_check_interval: $VM_WAIT_CHECK_INTERVAL
  cloud_init_timeout: $CLOUD_INIT_TIMEOUT
  cloud_init_check_interval: $CLOUD_INIT_CHECK_INTERVAL
  verification_retries: $VERIFICATION_RETRIES
  verification_retry_delay: $VERIFICATION_RETRY_DELAY
EOF
    
    print_success "YAML configuration created: $CONFIG_YAML"
    print_info "You can now remove the old shell configuration files if desired"
    print_info "Test the new configuration with: $0 show"
}

# Main script logic
main() {
    # Check prerequisites
    check_yq
    
    # Parse command line arguments
    local command="${1:-help}"
    local skip_confirm="false"
    local template="default"
    local yaml_file=""
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --template)
                template="$2"
                shift 2
                ;;
            --file)
                yaml_file="$2"
                shift 2
                ;;
            -y|--yes)
                skip_confirm="true"
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                if [[ -z "${command_set:-}" ]]; then
                    command="$1"
                    command_set=true
                fi
                shift
                ;;
        esac
    done
    
    # Execute command
    case "$command" in
        "init")
            init_config "$template" "$skip_confirm"
            ;;
        "show")
            show_config
            ;;
        "export")
            export_config "$yaml_file"
            ;;
        "templates")
            list_templates
            ;;
        "migrate")
            migrate_shell_to_yaml
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi