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
    echo "  validate                  Validate VM availability for current config"
    echo "  export [--file FILE]      Export YAML to shell variables"
    echo "  templates                 List available templates"
    echo "  help                      Show this help message"
    echo
    echo "OPTIONS:"
    echo "  -y, --yes             Skip confirmation prompts"
    echo "  -v, --verbose         Enable verbose output"
    echo "  --skip-validation     Skip automatic validation after init"
    echo
    echo "EXAMPLES:"
    echo "  $0 init                         # Create config from minimal template (default)"
    echo "  $0 init --template production   # Create config from production template"
    echo "  $0 init --skip-validation       # Create config without running validation"
    echo "  $0 show                         # Display current configuration"
    echo "  $0 validate                     # Validate VM availability for current config"
    echo "  $0 export                       # Export current config to shell vars"
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
    local skip_validation="${3:-false}"
    
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
    
    # Run validation check if not skipped and tools are available
    if [[ "$skip_validation" != "true" ]]; then
        if command -v yq &> /dev/null && command -v az &> /dev/null; then
            echo
            print_info "Running configuration validation..."
            if ./bin/azure-configuration-validation.sh; then
                print_success "Configuration validation passed"
            else
                print_warning "Configuration validation found issues - please review and update as needed"
            fi
        else
            print_info "Skipping validation (requires yq and Azure CLI)"
        fi
    else
        print_info "Skipping validation (--skip-validation specified)"
    fi
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


# Main script logic
main() {
    # Check prerequisites
    check_yq
    
    # Parse command line arguments
    local command="${1:-help}"
    local skip_confirm="false"
    local skip_validation="false"
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
            --skip-validation)
                skip_validation="true"
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
            init_config "$template" "$skip_confirm" "$skip_validation"
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
        "validate")
            # Check prerequisites for validation
            if ! command -v yq &> /dev/null; then
                print_error "yq is required for validation but not installed"
                print_info "Install yq: https://github.com/mikefarah/yq"
                exit 1
            fi
            
            if ! command -v az &> /dev/null; then
                print_error "Azure CLI is required for validation but not installed"
                print_info "Install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
                exit 1
            fi
            
            # Ensure configuration exists
            if [[ ! -f "$CONFIG_YAML" ]] && [[ ! -f "$CONFIG_DEFAULT_YAML" ]]; then
                print_error "No configuration found to validate"
                print_info "Initialize configuration with: $0 init"
                exit 1
            fi
            
            # Run validation
            print_info "Running configuration validation..."
            if ./bin/azure-configuration-validation.sh; then
                print_success "Configuration validation passed"
            else
                print_error "Configuration validation failed"
                exit 1
            fi
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