# Enhancement Plan: Interactive YAML Configuration

**Date**: December 5, 2024  
**Status**: Planning Phase  
**Priority**: Medium  

## Overview

Create an interactive configuration system that uses YAML files instead of shell variables, making configuration more user-friendly and portable. This enhancement will provide a cleaner interface for customizing deployments while maintaining backwards compatibility.

---

## Current Configuration System

### Issues with Current Approach
- **Shell-based configuration**: Variables scattered in bash files
- **Limited validation**: No type checking or value validation
- **Not portable**: Configuration tied to shell environment
- **Hard to template**: Difficult to create configuration templates
- **No versioning**: No way to track configuration schema changes

### Current File Structure
```
etc/config-user.sh    # User-editable configuration variables
etc/config-internal.sh # Computed/derived variables  
etc/k0rdent-config.sh  # Main config that sources both
```

---

## Proposed YAML Configuration System

### New Configuration Architecture

```
config/
├── k0rdent.yaml           # Main YAML configuration file
├── k0rdent-default.yaml   # Default configuration template
└── k0rdent-examples/      # Example configurations
    ├── minimal.yaml       # Minimal single-node setup
    ├── production.yaml    # Production multi-zone setup
    └── spot-instances.yaml # Cost-optimized with spot VMs
```

### Default YAML Configuration

#### k0rdent-default.yaml
```yaml
# k0rdent Azure Deployment Configuration
# This file contains all configurable settings for k0rdent deployment

metadata:
  version: "1.0"
  schema: "k0rdent-config"
  description: "Default k0rdent Azure deployment configuration"

# Azure Settings
azure:
  location: "southeastasia"
  vm_image: "Debian:debian-12:12-arm64:latest"
  vm_priority: "Regular"  # Options: Regular, Spot
  eviction_policy: "Deallocate"  # For Spot VMs: Deallocate, Delete

# VM Sizing
vm_sizing:
  controller:
    size: "Standard_D2pls_v6"
    description: "Size for k0s controller nodes"
  worker:
    size: "Standard_D8pls_v6" 
    description: "Size for k0s worker nodes"

# Cluster Topology
cluster:
  controllers:
    count: 3
    description: "Number of k0s controllers (minimum 1, odd number recommended for HA)"
  workers:
    count: 2
    description: "Number of k0s workers (minimum 1)"

# Zone Distribution
zones:
  controllers: [2, 3, 2]
  workers: [3, 2, 3, 2]
  description: "Availability zones for node distribution (will cycle if more nodes than zones)"

# SSH Settings
ssh:
  username: "k0rdent"
  key_comment: "k0rdent-azure-key"

# Software Versions
software:
  k0s:
    version: "v1.33.1+k0s.0"
  k0rdent:
    version: "1.0.0"
    registry: "oci://ghcr.io/k0rdent/kcm/charts/kcm"
    namespace: "kcm-system"

# Network Configuration
network:
  vnet_prefix: "10.240.0.0/16"
  subnet_prefix: "10.240.1.0/24"
  wireguard_network: "172.24.24.0/24"

# Timeouts and Intervals (seconds/minutes)
timeouts:
  ssh_connect: 30
  ssh_command: 300
  k0s_install_wait: 60
  k0rdent_install_wait: 30
  wireguard_connect_wait: 5
  vm_creation_minutes: 15
  vm_wait_check_interval: 30
```

---

## Implementation Plan

### Phase 1: YAML Configuration Parser

#### New Script: `bin/configure.sh`
```bash
#!/usr/bin/env bash
# Interactive configuration script for k0rdent deployment

# Usage:
./bin/configure.sh init              # Create initial config from defaults
./bin/configure.sh edit              # Interactive configuration editor  
./bin/configure.sh validate          # Validate current configuration
./bin/configure.sh show              # Display current configuration
./bin/configure.sh export            # Export to shell variables (backwards compatibility)
```

#### Configuration Functions
```bash
# Parse YAML and export shell variables
parse_yaml_config() {
    local yaml_file="$1"
    # Convert YAML to shell variables
    # Export variables with same names as current system
}

# Validate configuration values
validate_config() {
    # Check required fields
    # Validate VM sizes exist in Azure
    # Validate network CIDR blocks
    # Validate zone numbers
    # Check software version formats
}

# Interactive configuration editor
interactive_config() {
    # Guided prompts for each configuration section
    # Provide defaults and validation
    # Save to k0rdent.yaml
}
```

### Phase 2: Integration with Existing Scripts

#### Modified config loading in `etc/k0rdent-config.sh`
```bash
#!/usr/bin/env bash

# Load YAML configuration if it exists, otherwise fall back to shell config
if [[ -f "./config/k0rdent.yaml" ]]; then
    # Parse YAML and export variables
    source <(./bin/configure.sh export)
else
    # Fall back to existing shell configuration
    source ./etc/config-user.sh
fi

# Load computed variables (unchanged)
source ./etc/config-internal.sh
```

### Phase 3: Enhanced User Experience

#### Configuration Templates
```yaml
# config/k0rdent-examples/minimal.yaml
# Minimal single-node development setup
cluster:
  controllers:
    count: 1
  workers:
    count: 1
vm_sizing:
  controller:
    size: "Standard_B2s"
  worker:
    size: "Standard_B2s"
```

```yaml
# config/k0rdent-examples/production.yaml  
# Production multi-zone setup
cluster:
  controllers:
    count: 3
  workers:
    count: 5
zones:
  controllers: [1, 2, 3]
  workers: [1, 2, 3, 1, 2]
vm_sizing:
  controller:
    size: "Standard_D4s_v5"
  worker:
    size: "Standard_D16s_v5"
```

#### Interactive Setup Workflow
```bash
# First-time setup
./bin/configure.sh init --template minimal     # Start with minimal config
./bin/configure.sh init --template production  # Start with production config
./bin/configure.sh init --interactive          # Guided setup

# Configuration management
./bin/configure.sh edit                         # Interactive editor
./bin/configure.sh validate                     # Check configuration
./deploy-k0rdent.sh config                     # Show final computed config
```

---

## Benefits

### User Experience
- **Easier configuration**: YAML is more readable than shell variables
- **Validation**: Built-in validation prevents common configuration errors
- **Templates**: Pre-built configurations for common scenarios
- **Documentation**: Self-documenting with inline comments and descriptions

### Maintainability  
- **Schema versioning**: Track configuration format changes
- **Type safety**: Validate data types and ranges
- **Portability**: Configuration files can be shared and version-controlled
- **Backwards compatibility**: Existing shell-based configs continue to work

### Operational
- **Template library**: Easy to create and share configuration templates
- **Environment-specific configs**: Different configs for dev/staging/production
- **Configuration as code**: YAML configs can be managed in git
- **Validation early**: Catch configuration errors before deployment starts

---

## Implementation Details

### Prerequisites
- **yq tool**: For YAML parsing and manipulation
  ```bash
  # macOS
  brew install yq
  
  # Linux
  wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
  chmod +x /usr/local/bin/yq
  ```

### YAML to Shell Variable Mapping
```bash
# YAML path -> Shell variable mapping
azure.location -> AZURE_LOCATION
azure.vm_image -> AZURE_VM_IMAGE
vm_sizing.controller.size -> AZURE_CONTROLLER_VM_SIZE
vm_sizing.worker.size -> AZURE_WORKER_VM_SIZE
cluster.controllers.count -> K0S_CONTROLLER_COUNT
# ... etc
```

### Configuration File Discovery
```bash
# Configuration file precedence (first found wins):
1. ./config/k0rdent.yaml           # Local project config
2. ./config/k0rdent-default.yaml   # Default template
3. ./etc/config-user.sh            # Legacy shell config
```

### Validation Rules
```yaml
# Example validation schema
validation:
  azure.location:
    type: string
    required: true
    values: ["eastus", "westus2", "southeastasia", "westeurope", ...]
  
  cluster.controllers.count:
    type: integer
    minimum: 1
    recommended_odd: true
    
  vm_sizing.controller.size:
    type: string
    pattern: "^Standard_[A-Z][0-9]+.*"
    azure_vm_size: true  # Validate against Azure API
```

---

## Migration Strategy

### Phase 1: Parallel System
- Keep existing shell configuration system
- Add YAML configuration as optional alternative
- Users can choose either approach

### Phase 2: Migration Tools
```bash
# Convert existing shell config to YAML
./bin/configure.sh migrate-from-shell

# Convert YAML back to shell (for backwards compatibility)
./bin/configure.sh export-to-shell
```

### Phase 3: Default to YAML
- New deployments use YAML by default
- Shell configuration becomes legacy option
- Documentation emphasizes YAML approach

---

## File Structure Changes

### New Files
```
bin/configure.sh                    # Interactive configuration script
config/k0rdent-default.yaml        # Default configuration template
config/k0rdent-examples/           # Example configurations
├── minimal.yaml
├── production.yaml
└── spot-instances.yaml
```

### Modified Files
```
etc/k0rdent-config.sh              # Enhanced to load YAML configs
deploy-k0rdent.sh                  # Add configure command
README.md                          # Document YAML configuration
```

### Prerequisites Addition
```bash
# Add yq to prerequisites checking
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

---

## Future Enhancements

### Advanced Features
- **Configuration profiles**: Multiple named configurations per project
- **Environment variables**: Override YAML values with environment variables
- **Remote configurations**: Load configurations from URLs or git repositories
- **Configuration inheritance**: Extend base configurations with overrides
- **GUI configuration**: Web-based configuration editor

### Integration Options
- **IDE support**: YAML schema for autocomplete and validation
- **CI/CD integration**: Validate configurations in pipelines
- **Terraform integration**: Generate Terraform configs from YAML
- **Monitoring integration**: Configuration-driven monitoring setup

---

## Testing Strategy

### Configuration Validation
- Test all example configurations deploy successfully
- Validate error handling for invalid configurations
- Test backwards compatibility with shell configs

### Migration Testing  
- Test conversion from shell to YAML
- Verify identical deployments with both systems
- Test configuration file discovery precedence

### User Experience Testing
- Test interactive configuration flow
- Validate error messages are helpful
- Test configuration templates work correctly

---

## Risk Assessment

### Low Risk
- YAML configuration is additive and optional
- Existing shell configuration continues to work
- Easy to revert if issues arise

### Mitigation
- Maintain backwards compatibility throughout
- Extensive testing of configuration parsing
- Clear migration documentation and tooling
- Gradual rollout with user feedback

---

# Additional Enhancements

## User Experience Enhancements

### Graceful Interrupt Handling
**Priority**: High
**Description**: Allow users to interrupt the deployment process with Control-C (^C) and handle it gracefully, cleaning up any partial resources and providing clear status information.

**Current issues**:
- Scripts may leave resources in inconsistent state if interrupted
- No cleanup on user interruption
- No clear feedback about what was interrupted
- Difficult to resume or restart after interruption

**Proposed improvements**:
- Implement trap handlers for SIGINT/SIGTERM in all long-running scripts
- Provide clear status of what was completed before interruption
- Offer cleanup options or instructions for resuming
- Save state information to allow graceful resume
- Ensure all background processes are properly terminated

**Example implementation**:
```bash
# Trap handler for graceful shutdown
cleanup_on_interrupt() {
    print_warning "\nInterrupted! Cleaning up..."
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null
    # Save current state
    echo "$CURRENT_PHASE" > .deployment-state
    print_info "Current state saved. Run with --resume to continue."
    exit 130
}

trap cleanup_on_interrupt SIGINT SIGTERM
```

**Expected benefits**:
- Better user experience with safe interruption
- Ability to stop and resume deployments
- No orphaned resources from interrupted runs
- Clear understanding of deployment state

## Performance and Optimization Enhancements

### Optimize Azure API Calls
**Priority**: High
**Description**: The current implementation makes individual Azure API calls for each VM instance, which is extremely wasteful and slow. Need to optimize to batch operations and retrieve more data in single calls.

**Current issues**:
- Individual calls per VM for status checks
- Separate calls for each property (IP address, status, etc.)
- No use of Azure's batch query capabilities
- Contributing to slow deployment and validation times

**Proposed improvements**:
- Use `az vm list` with proper queries to get all VM data at once
- Batch status checks for multiple VMs in single API calls
- Cache results where appropriate to avoid repeated calls
- Use `--show-details` flag to get comprehensive data in one call
- Implement parallel processing where individual calls are necessary

**Example optimization**:
```bash
# Instead of:
for vm in vms; do
  az vm show --name $vm ...
done

# Use:
az vm list --resource-group $RG --query "[].{name:name, publicIps:publicIps, powerState:powerState}" -o json
```

**Expected benefits**:
- Significantly faster deployment times
- Reduced API rate limiting issues
- Better user experience with less waiting
- Lower Azure API usage costs