# YAML Configuration Implementation Plan

**Date**: January 6, 2025  
**Status**: ✅ **COMPLETED** - June 2025  
**Priority**: Phase 3 - Configuration Modernization ✅ **COMPLETED**  

## Overview

Implement a YAML-based configuration system to replace the current shell variable configuration, providing better user experience, validation, and maintainability while preserving backwards compatibility.

## Current Configuration Analysis

**Current Structure:**
- `etc/config-user.sh` (49 lines) - User-editable settings
- `etc/config-internal.sh` (106 lines) - Computed variables and validation  
- `etc/k0rdent-config.sh` (56 lines) - Legacy mappings and main loader

**Key Configuration Categories:**
1. Azure infrastructure settings (location, VM image, priority)
2. VM sizing (controller vs worker sizes)
3. Cluster topology (node counts, zone distribution)
4. SSH configuration (username, key comment)
5. Software versions (k0s, k0rdent)
6. Network configuration (CIDR blocks, WireGuard network)
7. Timeouts and intervals

## Implementation Plan

### Phase 0: Legacy Variable Cleanup (Prerequisite)

Before implementing YAML configuration, eliminate redundant legacy variable mappings to create a clean, consistent codebase.

#### Milestone 0.1: Variable Name Standardization
**Objective**: Replace all legacy variable usage with modern variable names

**Current Legacy Mappings to Eliminate:**
```bash
# Primary legacy variables (used extensively):
LOCATION="$AZURE_LOCATION"           # Replace with AZURE_LOCATION directly
ADMIN_USER="$SSH_USERNAME"           # Replace with SSH_USERNAME directly  
VM_SIZE="$AZURE_WORKER_VM_SIZE"      # Not actually used correctly
IMAGE="$AZURE_VM_IMAGE"              # Replace with AZURE_VM_IMAGE directly
PRIORITY="$AZURE_VM_PRIORITY"        # Replace with AZURE_VM_PRIORITY directly
EVICTION_POLICY="$AZURE_EVICTION_POLICY"  # Replace with AZURE_EVICTION_POLICY directly

# Redundant timeout mappings:
VM_WAIT_TIMEOUT_MINUTES="$VM_CREATION_TIMEOUT_MINUTES"  # Use VM_CREATION_TIMEOUT_MINUTES
VM_CHECK_INTERVAL_SECONDS="$VM_WAIT_CHECK_INTERVAL"     # Use VM_WAIT_CHECK_INTERVAL

# Hardcoded values that should be configurable:
SSH_TIMEOUT_SECONDS=10                    # Move to YAML config
CLOUD_INIT_TIMEOUT_MINUTES=10            # Move to YAML config  
CLOUD_INIT_CHECK_INTERVAL_SECONDS=30     # Move to YAML config
VERIFICATION_RETRY_COUNT=3                # Move to YAML config
VERIFICATION_RETRY_DELAY_SECONDS=10      # Move to YAML config

# Legacy directory mappings:
KEYDIR="$WG_KEYDIR"                       # Standardize to WG_DIR
CLOUDINITS="$CLOUD_INIT_DIR"              # Use CLOUD_INIT_DIR directly

# Directory name standardization:
WG_KEYDIR → WG_DIR                        # Simplify WireGuard directory name

# Obsolete script references:
SCRIPT_ORDER=()  # Remove entirely (references old merged scripts)
```

**Files Modified:**
- `bin/setup-azure-network.sh` - Replace `LOCATION` with `AZURE_LOCATION` (4 instances)
- `bin/install-k0rdent.sh` - Replace `ADMIN_USER` with `SSH_USERNAME` (9 instances)
- `bin/install-k0s.sh` - Replace `ADMIN_USER` with `SSH_USERNAME` (6 instances)
- `bin/create-azure-vms.sh` - Replace all legacy variables:
  - `ADMIN_USER` → `SSH_USERNAME` (4 instances)
  - `IMAGE` → `AZURE_VM_IMAGE` (1 instance)
  - `PRIORITY` → `AZURE_VM_PRIORITY` (2 instances)
  - `EVICTION_POLICY` → `AZURE_EVICTION_POLICY` (1 instance)
  - `VM_WAIT_TIMEOUT_MINUTES` → `VM_CREATION_TIMEOUT_MINUTES` (3 instances)
  - `VM_CHECK_INTERVAL_SECONDS` → `VM_WAIT_CHECK_INTERVAL` (3 instances)
  - `SSH_TIMEOUT_SECONDS` → `SSH_CONNECT_TIMEOUT` (2 instances)
  - `CLOUD_INIT_TIMEOUT_MINUTES` → `CLOUD_INIT_TIMEOUT` (1 instance)
  - `CLOUD_INIT_CHECK_INTERVAL_SECONDS` → `CLOUD_INIT_CHECK_INTERVAL` (1 instance)
  - `VERIFICATION_RETRY_COUNT` → `VERIFICATION_RETRIES` (2 instances)
  - `VERIFICATION_RETRY_DELAY_SECONDS` → `VERIFICATION_RETRY_DELAY` (2 instances)
- `bin/prepare-deployment.sh` - Replace directory variables:
  - `KEYDIR` → `WG_DIR` (19 instances)
  - `CLOUDINITS` → `CLOUD_INIT_DIR` (16 instances)
- `deploy-k0rdent.sh` - Replace directory variables:
  - `KEYDIR` → `WG_DIR` (1 instance)
  - `CLOUDINITS` → `CLOUD_INIT_DIR` (1 instance)
- `etc/config-internal.sh` - Standardize directory name:
  - `WG_KEYDIR` → `WG_DIR` (3 instances)
- `etc/common-functions.sh` - Replace `ADMIN_USER` default with `SSH_USERNAME` (2 instances)
- `etc/k0rdent-config.sh` - Remove all legacy variable mappings, update final echo

**Testing**: Run full deployment to ensure no regressions after variable name changes

#### Milestone 0.2: Configuration Display Cleanup
**Files Modified:**
- `etc/k0rdent-config.sh` - Update final echo to use `AZURE_LOCATION`
- `deploy-k0rdent.sh` - Ensure show_config uses modern variable names

### Phase 1: YAML Infrastructure and Basic Support

#### Milestone 1.1: Prerequisites and YAML Parser
**Files Created:**
- `bin/configure.sh` - Configuration management script

**Files Modified:**
- `etc/common-functions.sh` - Add yq prerequisite check

**Prerequisites Check Addition:**
```bash
# Add to etc/common-functions.sh
check_yq() {
    if ! command -v yq &> /dev/null; then
        print_error "yq is not installed. Please install it first."
        echo "macOS: brew install yq"
        echo "Linux: wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
        exit 1
    fi
    print_success "yq is installed"
}
```

#### Milestone 1.2: Default YAML Configuration
**Files Created:**
- `config/k0rdent-default.yaml` - Default configuration template
- `config/examples/` directory structure

**YAML Schema Structure:**
```yaml
metadata:
  version: "1.0"
  schema: "k0rdent-config"

azure:
  location: "southeastasia"
  vm_image: "Debian:debian-12:12-arm64:latest"
  vm_priority: "Regular"  # Regular | Spot
  eviction_policy: "Deallocate"  # Deallocate | Delete

vm_sizing:
  controller:
    size: "Standard_D2pls_v6"
  worker:
    size: "Standard_D8pls_v6"

cluster:
  controllers:
    count: 3
    zones: [2, 3]
  workers:
    count: 2
    zones: [3, 2]

ssh:
  username: "k0rdent"
  key_comment: "k0rdent-azure-key"

software:
  k0s:
    version: "v1.33.1+k0s.0"
  k0rdent:
    version: "1.0.0"
    registry: "oci://ghcr.io/k0rdent/kcm/charts/kcm"
    namespace: "kcm-system"

network:
  vnet_prefix: "10.240.0.0/16"
  subnet_prefix: "10.240.1.0/24"
  wireguard_network: "172.24.24.0/24"

timeouts:
  ssh_connect: 30
  ssh_command: 300
  k0s_install_wait: 60
  k0rdent_install_wait: 30
  wireguard_connect_wait: 5
  vm_creation_minutes: 15
  vm_wait_check_interval: 30
  
  # Additional timeouts moved from hardcoded values:
  cloud_init_timeout: 10           # CLOUD_INIT_TIMEOUT_MINUTES  
  cloud_init_check_interval: 30    # CLOUD_INIT_CHECK_INTERVAL_SECONDS
  verification_retries: 3          # VERIFICATION_RETRY_COUNT
  verification_retry_delay: 10     # VERIFICATION_RETRY_DELAY_SECONDS
```

#### Milestone 1.3: YAML to Shell Variable Export
**Core Function in `bin/configure.sh`:**
```bash
yaml_to_shell_vars() {
    local yaml_file="$1"
    
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
    
    # Export additional timeouts (previously hardcoded)
    echo "export CLOUD_INIT_TIMEOUT=$(yq '.timeouts.cloud_init_timeout' "$yaml_file")"
    echo "export CLOUD_INIT_CHECK_INTERVAL=$(yq '.timeouts.cloud_init_check_interval' "$yaml_file")"
    echo "export VERIFICATION_RETRIES=$(yq '.timeouts.verification_retries' "$yaml_file")"
    echo "export VERIFICATION_RETRY_DELAY=$(yq '.timeouts.verification_retry_delay' "$yaml_file")"
}
```

#### Milestone 1.4: Configuration Loading Integration
**Files Modified:**
- `etc/k0rdent-config.sh` - Enhanced configuration loading

**New Configuration Loading Logic:**
```bash
#!/usr/bin/env bash

# Configuration loading with YAML support and backwards compatibility
CONFIG_YAML="./config/k0rdent.yaml"
CONFIG_DEFAULT_YAML="./config/k0rdent-default.yaml"
CONFIG_USER_SH="./etc/config-user.sh"

# Load configuration in priority order
if [[ -f "$CONFIG_YAML" ]]; then
    echo "==> Loading YAML configuration: $CONFIG_YAML"
    source <(./bin/configure.sh export --file "$CONFIG_YAML")
elif [[ -f "$CONFIG_DEFAULT_YAML" ]]; then
    echo "==> Loading default YAML configuration: $CONFIG_DEFAULT_YAML"
    source <(./bin/configure.sh export --file "$CONFIG_DEFAULT_YAML")
elif [[ -f "$CONFIG_USER_SH" ]]; then
    echo "==> Loading legacy shell configuration: $CONFIG_USER_SH"
    source "$CONFIG_USER_SH"
else
    echo "ERROR: No configuration found. Run: ./bin/configure.sh init"
    exit 1
fi

# Load computed variables (unchanged)
source ./etc/config-internal.sh

# Note: Legacy variable mappings removed in Phase 0
# All scripts now use modern variable names directly:
# - AZURE_LOCATION (not LOCATION)
# - SSH_USERNAME (not ADMIN_USER)  
# - AZURE_VM_IMAGE (not IMAGE)
# - AZURE_VM_PRIORITY (not PRIORITY)
# - AZURE_EVICTION_POLICY (not EVICTION_POLICY)
```

### Phase 2: Configuration Management Tools

#### Milestone 2.1: Basic Configuration Commands
**`bin/configure.sh` Commands:**
```bash
#!/usr/bin/env bash

# Interactive configuration management for k0rdent

show_usage() {
    print_usage "$0" \
        "  init [--template NAME]    Create initial configuration from template
  show                      Display current configuration
  export [--file FILE]      Export YAML to shell variables
  templates                 List available templates  
  migrate                   Convert shell config to YAML
  help                      Show this help message" \
        "  -y, --yes        Skip confirmation prompts
  -v, --verbose    Enable verbose output" \
        "  $0 init                    # Create config from default template
  $0 init --template minimal # Create config from minimal template
  $0 show                    # Display current configuration
  $0 export                  # Export current config to shell vars
  $0 migrate                 # Convert etc/config-user.sh to YAML"
}

# Command implementations
init_config() { ... }
show_config() { ... }
export_config() { ... }
list_templates() { ... }
migrate_shell_to_yaml() { ... }
```

#### Milestone 2.2: Configuration Templates
**Files Created:**
- `config/examples/minimal.yaml` - Single node development setup
- `config/examples/production.yaml` - Multi-zone HA setup  
- `config/examples/development.yaml` - Development environment

**Minimal Template Example:**
```yaml
# Minimal single-node development setup
metadata:
  version: "1.0"
  schema: "k0rdent-config"
  description: "Minimal development setup with single controller+worker"

cluster:
  controllers:
    count: 1
    zones: [1]
  workers:
    count: 1 
    zones: [1]

vm_sizing:
  controller:
    size: "Standard_B2s"
  worker:
    size: "Standard_B2s"

# ... rest inherits from default
```

#### Milestone 2.3: Shell to YAML Migration Tool
**Migration Function:**
```bash
migrate_shell_to_yaml() {
    local shell_config="./etc/config-user.sh"
    local output_yaml="./config/k0rdent.yaml"
    
    if [[ ! -f "$shell_config" ]]; then
        print_error "Shell configuration not found: $shell_config"
        exit 1
    fi
    
    print_info "Converting shell configuration to YAML..."
    
    # Source the shell config to get variables
    source "$shell_config"
    
    # Generate YAML from shell variables
    cat > "$output_yaml" << EOF
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

# ... continue mapping all variables
EOF
    
    print_success "YAML configuration created: $output_yaml"
    print_info "You can now remove the old shell configuration files if desired"
}
```

### Phase 3: Integration and Polish

#### Milestone 3.1: Deploy Script Integration
**Files Modified:**
- `deploy-k0rdent.sh` - Add configuration commands

**New Deploy Commands:**
```bash
case "${POSITIONAL_ARGS[0]:-deploy}" in
    "configure")
        ./bin/configure.sh "${POSITIONAL_ARGS[@]:1}"
        ;;
    "config"|"show-config")
        show_config
        ;;
    # ... existing commands
esac
```

#### Milestone 3.2: Enhanced Configuration Display
**Show Configuration with YAML Info:**
```bash
show_config() {
    print_header "k0rdent Deployment Configuration"
    
    # Show configuration source
    if [[ -f "./config/k0rdent.yaml" ]]; then
        echo "Configuration Source: ./config/k0rdent.yaml (YAML)"
    elif [[ -f "./config/k0rdent-default.yaml" ]]; then
        echo "Configuration Source: ./config/k0rdent-default.yaml (Default YAML)"
    else
        echo "Configuration Source: ./etc/config-user.sh (Legacy Shell)"
    fi
    
    # ... rest of existing show_config function
    
    echo
    echo "Configuration Management:"
    echo "  View config:    ./bin/configure.sh show"
    echo "  Edit config:    ./bin/configure.sh edit"  # Future enhancement
    echo "  Use template:   ./bin/configure.sh init --template minimal"
}
```

#### Milestone 3.3: Documentation Updates
**Files Modified:**
- `README.md` - Add YAML configuration documentation

**New README Section:**
```markdown
## Configuration

k0rdent supports both YAML and shell-based configuration.

### YAML Configuration (Recommended)

Create a configuration file:
```bash
./bin/configure.sh init                    # Use default template
./bin/configure.sh init --template minimal # Use minimal template
```

Edit the configuration:
```bash
# Edit config/k0rdent.yaml manually, or
./bin/configure.sh show                    # View current config
```

### Available Templates

- `default`: Full-featured 3 controller + 2 worker setup
- `minimal`: Single controller+worker for development  
- `production`: Multi-zone HA setup for production

### Legacy Shell Configuration

The original shell-based configuration (`etc/config-user.sh`) is still supported for backwards compatibility.

Migrate to YAML:
```bash
./bin/configure.sh migrate
```
```

## Testing Strategy

### Phase 1 Testing
1. **Prerequisites**: Verify yq installation check works
2. **YAML Export**: Test YAML to shell variable conversion
3. **Configuration Loading**: Verify YAML configs load correctly
4. **Backwards Compatibility**: Ensure shell configs still work

### Phase 2 Testing  
1. **Template Creation**: Test all configuration templates
2. **Migration**: Test shell to YAML conversion
3. **Command Interface**: Test all configure.sh commands

### Phase 3 Testing
1. **Integration**: Test deploy script with YAML configs
2. **End-to-End**: Full deployment with YAML configuration
3. **Documentation**: Verify all examples work

### Phase 4: WireGuard Manifest YAML Conversion ✅ **SUPERSEDED**

#### ✅ **IMPLEMENTATION NOTE**: This phase was superseded during development

**What Actually Happened:**
Instead of creating a separate WireGuard YAML manifest, WireGuard configuration was integrated directly into the unified state management system (`deployment-state.yaml`). This provides better architecture:

**Current Implementation:**
```yaml
# deployment-state.yaml
wireguard_peers:
  mylaptop:
    ip: 172.24.24.1
    role: hub
    private_key: PRIV_KEY_HERE
    public_key: PUB_KEY_HERE
    keys_generated: true
    keys_generated_at: "2025-06-08T08:11:32Z"
  
  k0s-controller:
    ip: 172.24.24.11
    role: controller
    private_key: PRIV_KEY_HERE
    public_key: PUB_KEY_HERE
    keys_generated: true
    keys_generated_at: "2025-06-08T08:11:32Z"
```

**Benefits of Actual Implementation:**
- **Unified state**: All deployment data in single file
- **No data duplication**: WireGuard data integrated with VM states
- **Better consistency**: Single source of truth for deployment state
- **Simplified architecture**: Fewer files to manage
- **State transitions**: Track key generation and setup completion

**Files Actually Modified:**
- `etc/state-management.sh` - WireGuard data management functions
- CSV manifest and port files completely eliminated
- Individual key files removed in favor of state management

**Status**: ✅ **COMPLETED** via better architectural approach (unified state management)

## File Structure After Implementation

```
config/
├── k0rdent-default.yaml        # Default template (created)
└── examples/                   # Example configurations (created)
    ├── minimal.yaml
    ├── production.yaml
    └── development.yaml

bin/
├── configure.sh                # Configuration management (created)
└── ... (existing scripts)

etc/
├── k0rdent-config.sh          # Enhanced with YAML support (modified)
├── config-user.sh             # Legacy (unchanged, optional)
├── config-internal.sh         # Modified (WG_KEYDIR → WG_DIR)
└── common-functions.sh        # Add yq check (modified)

wireguard/                      # Renamed from old inconsistent naming
├── wg-manifest.yaml           # New YAML manifest (replaces CSV + port file)
├── hostname_privkey           # Private key files
└── hostname_pubkey            # Public key files
```

## Benefits

### User Experience
- **Self-documenting**: YAML configs include descriptions and comments
- **Templates**: Quick start with different deployment scenarios
- **Validation**: Basic structure validation through yq
- **Migration**: Easy transition from shell to YAML
- **Consistent variables**: Clean, modern variable names throughout

### Maintainability
- **Schema versioning**: Track configuration format changes
- **Type awareness**: Clear data types in YAML
- **Portability**: Configuration files can be shared and version-controlled
- **Backwards compatibility**: Existing deployments continue working
- **No legacy cruft**: Eliminated redundant variable mappings

### Operational
- **Configuration as code**: YAML configs integrate well with git
- **Environment-specific**: Easy to maintain different configs for different environments
- **Documentation**: Configuration is self-documenting with inline comments
- **Simplified debugging**: One variable name per concept, no aliases

## Risk Mitigation

### Low Risk Implementation
- YAML configuration is completely optional
- Existing shell configurations continue to work unchanged
- Easy rollback if issues arise

### Dependencies
- Requires `yq` tool installation
- Added to prerequisite checks with clear installation instructions
- Graceful fallback to shell configuration if YAML not available

### Migration Path
1. **Phase 1**: Add YAML support as option (shell configs still work)
2. **Phase 2**: Provide migration tools (shell → YAML conversion)
3. **Phase 3**: Document YAML as recommended approach (shell still supported)

---

This plan provides a complete, backwards-compatible YAML configuration system that improves user experience while preserving all existing functionality.