# Design: Canonical Configuration from Deployment State

## Architecture Overview

The current k0rdent configuration architecture suffers from a fundamental inconsistency problem: the deployment script tracks canonical configuration in state files, but all other scripts load configuration from hardcoded default files. This design implements a state-based configuration resolution system where the deployment state becomes the single source of truth for all configuration requirements.

## Problem Deep Dive

### Current Architecture Flow

```
Deployment (deploy-k0rdent.sh):
User: --config config/k0rdent-baseline-southeastasia.yaml
↓
├── Loads from specified config file ← CORRECT
├── Stores canonical config in deployment-state.yaml ← CORRECT
└── Deployment completes with southeastasia settings ← CORRECT

Post-Deployment Scripts (setup-azure-cluster-deployment.sh, etc.):
├── source ./etc/k0rdent-config.sh ← PROBLEM BEGINS HERE
├── CONFIG_YAML="./config/k0rdent.yaml" (hardcoded) ← PROBLEM
├── Loads from ./config/k0rdent.yaml (westus2 default) ← WRONG!
└── Wrong Azure region, VM types, etc. ← CRITICAL ERROR
```

### Configuration Drift Examples

**Scenario 1: Azure Region Mismatch**
- Deployment created VMs in `southeastasia`
- Azure setup script tries to work in `westus2`
- Azure operations fail or work on wrong resource groups

**Scenario 2: VM Size Mismatch**  
- Deployment specified specific VM sizes from custom config
- Child cluster creation uses default VM sizes
- Inconsistent cluster capabilities and pricing

**Scenario 3: Feature Flag Mismatch**
- Deployment disabled certain features (child clusters, KOF, etc.)
- Follow-up scripts operate as if features were enabled
- Configuration inconsistency leads to operational errors

## Solution Architecture

### Canonically Ordered Configuration Resolution

```bash
resolve_canonical_config() {
    # Priority 1: Explicit override (for advanced users/diagnostics)
    if [[ -n "${K0RDENT_CONFIG_FILE:-}" ]]; then
        validate_and_use_file "$K0RDENT_CONFIG_FILE"
        return 0
    fi
    
    # Priority 2: Deployment state (canonical source)
    local state_config=$(load_config_from_deployment_state)
    if [[ -n "$state_config" ]]; then
        load_from_state_config "$state_config"
        return 0
    fi
    
    # Priority 3: Default configuration search (backward compatibility)
    search_default_config_files
    return 0
}
```

### Enhanced Configuration Loading System

**Core Components:**

1. **State Configuration Loader**
   - Reads canonical configuration from deployment-state.yaml
   - Validates configuration completeness
   - Handles missing or corrupted state files

2. **Configuration Priority Manager**
   - Implements the 4-tier resolution order
   - Manages fallback behavior when sources are unavailable
   - Provides clear logging about which source is used

3. **Configuration Validator**
   - Ensures loaded configuration meets script requirements
   - Detects and reports configuration inconsistencies
   - Validates that state-derived config is usable

### State-Based Configuration Extraction

**Deployment State Configuration Structure:**
```yaml
# In deployment-state.yaml
config:
  azure_location: "southeastasia"
  resource_group: "k0rdent-xyoeeex2-resgrp"
  controller_count: 1
  worker_count: 1
  wireguard_network: "192.168.100.0/24"
  resource_deployment:
    controller:
      vm_size: "Standard_D2s_v5"
      spot_enabled: false
    worker:
      vm_size: "Standard_D2s_v5"
      spot_enabled: false
  deployment_flags:
    azure_children: false
    kof: false
```

**State Configuration Loader Implementation:**
```bash
load_config_from_deployment_state() {
    local state_file="${DEPLOYMENT_STATE_FILE:-./state/deployment-state.yaml}"
    
    if [[ ! -f "$state_file" ]]; then
        echo "WARNING: Deployment state file not found: $state_file"
        return 1
    fi
    
    # Extract configuration section from deployment state
    local config_section
    config_section=$(yq eval '.config' "$state_file" 2>/dev/null)
    if [[ "$config_section" == "null" ]] || [[ -z "$config_section" ]]; then
        echo "WARNING: No configuration section in deployment state"
        return 1
    fi
    
    # Convert state configuration to environment variables
    echo "$config_section" | yaml_to_shell_vars
    
    # Store provenance information
    export K0RDENT_CONFIG_SOURCE="deployment-state"
    export K0RDENT_CONFIG_FILE="$state_file"
    export K0RDENT_CONFIG_TIMESTAMP=$(yq eval '.last_updated' "$state_file" 2>/dev/null || echo "unknown")
    
    echo "Using configuration from deployment state (${state_file##*/})"
    return 0
}
```

### Enhanced k0rdent-config.sh Integration

**Modified Configuration Loading Flow:**
```bash
# In etc/k0rdent-config.sh
# Enhanced configuration loading with state-based resolution

resolve_k0rdent_config() {
    # Try canonical resolution first
    if resolve_canonical_config; then
        return 0
    fi
    
    # Fallback to original logic for backward compatibility
    load_default_configuration_search
    return 0
}

# Original configuration file definitions
CONFIG_YAML="./config/k0rdent.yaml"
CONFIG_DEFAULT_YAML="./config/k0rdent-default.yaml"

# Replace original config loading with enhanced resolution
resolve_k0rdent_config

# Generate shell variables from resolved configuration
if [[ -f "$CONFIG_YAML" ]] || [[ -f "$CONFIG_DEFAULT_YAML" ]]; then
    yaml_to_shell_vars "$CONFIG_YAML"
fi
```

## Integration with Affected Scripts

### Script Integration Strategy

**Phase 1: Central Enhancement**
- Modify `etc/k0rdent-config.sh` to use state-based resolution
- Ensure backward compatibility for existing deployments
- Add configuration source logging

**Phase 2: Script Updates**
- Update all affected scripts to use enhanced config loading
- Add configuration source reporting to script output
- Validate proper configuration loading in each script

**Affected Scripts Mapping:**
```bash
# Core k0rdent scripts
setup-azure-cluster-deployment.sh    ← Updates to ensure correct region/resource group
create-azure-child.sh                ← Uses same VM settings as parent deployment
sync-cluster-state.sh               ← Operates on actual deployment configuration

# Multi-cloud scripts  
create-aws-cluster-deployment.sh     ← Uses same deployment patterns as Azure
setup-aws-cluster-deployment.sh      ← Consistent multi-cloud behavior

# KOF scripts
install-kof-mothership.sh            ← Operates on actual deployment settings
install-kof-regional.sh              ← Uses parent deployment configuration
list-child-clusters.sh               ← Shows correct deployment information

# Utility scripts
azure-configuration-validation.sh    ← Validates actual deployment configuration
```

### Script Integration Example

**Before (Current):**
```bash
# In setup-azure-cluster-deployment.sh
source ./etc/k0rdent-config.sh      # Loads ./config/k0rdent.yaml (wrong!)
echo "==> k0rdent configuration loaded (cluster ID: $K0RDENT_CLUSTERID, region: $AZURE_LOCATION)"
# Shows wrong region from default config file
```

**After (Enhanced):**
```bash
# In setup-azure-cluster-deployment.sh  
source ./etc/k0rdent-config.sh      # Enhanced loading with state resolution
echo "==> k0rdent configuration loaded (cluster ID: $K0RDENT_CLUSTERID, region: $AZURE_LOCATION)"
echo "==> Configuration source: ${K0RDENT_CONFIG_SOURCE:-default}"
# Shows correct region from deployment state
```

## Error Handling and Fallback Strategies

### State File Issues

**Missing State File:**
```bash
if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
    echo "WARNING: Deployment state file not found"
    echo "Falling back to default configuration file search"
    return 1  # Triggers default search fallback
fi
```

**Corrupted State File:**
```bash
if ! validate_deployment_state "$DEPLOYMENT_STATE_FILE"; then
    echo "WARNING: Deployment state file appears corrupted"
    echo "Falling back to default configuration"
    return 1
fi
```

**Missing Configuration Section:**
```bash
local config_section=$(yq eval '.config' "$state_file" 2>/dev/null)
if [[ "$config_section" == "null" ]]; then
    echo "WARNING: No configuration in deployment state"
    echo "This deployment may predate configuration tracking"
    echo "Falling back to default configuration"
    return 1
fi
```

### Configuration Validation

**Required Configuration Elements:**
```bash
validate_state_config_requirements() {
    local required_vars=("AZURE_LOCATION" "AZURE_SUBSCRIPTION_ID" "K0RDENT_CLUSTERID")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            echo "ERROR: Required configuration element missing: $var"
            echo "Deployment state may be incomplete"
            echo "Consider re-initializing deployment or using default configuration"
            return 1
        fi
    done
    
    return 0
}
```

## Multiple Deployments Handling

### Deployment State Resolution

**Single Deployment (Most Common):**
```
./state/deployment-state.yaml ← Use this state file
```

**Multiple Deployments:**
```bash
# Strategy: Most recent deployment state
local latest_state=$(find ./state -name "deployment-state.yaml" -type f -exec stat -f "%m %N" {} \; | sort -rn | head -1 | cut -d' ' -f2-)

if [[ -n "$latest_state" ]]; then
    echo "INFO: Using most recent deployment state: ${latest_state##*/}"
    DEPLOYMENT_STATE_FILE="$latest_state"
else
    echo "WARNING: No deployment state files found"
    fallback_to_default_config
fi
```

### Development Environment Support

**Development Scenarios:**
```bash
# Development mode overrides
if [[ "${K0RDENT_DEVELOPMENT_MODE:-}" == "true" ]]; then
    # In development, prefer default configs for easier iteration
    echo "INFO: Development mode detected, using default configuration"
    disable_state_based_config=true
fi

# Local development with specific state
if [[ -n "${K0RDENT_DEVELOPMENT_STATE:-}" ]]; then
    DEPLOYMENT_STATE_FILE="$K0RDENT_DEVELOPMENT_STATE"
    echo "INFO: Using development state override: $K0RDENT_DEVELOPMENT_STATE"
fi
```

## Performance Considerations

### Configuration Loading Performance

**Optimizations:**
- **Lazy State Loading**: Only load state when default config is unavailable
- **State File Caching**: Cache extracted configuration for repeated use
- **YAML Parsing Optimization**: Use efficient YAML extraction (yq eval '.config')
- **Fallback Efficiency**: Fast default search when state is not available

**Expected Performance Impact:**
- **Deployments With State**: +~50ms for state file parsing (negligible)
- **Deployments Without State**: Same performance as before
- **Repeated Script Calls**: Cached configuration reuse for subsequent calls

### Memory Usage

**Additional Memory Requirements:**
- **Configuration Section**: ~2-5KB in memory
- **YAML Parser Overhead**: Negligible with yq
- **State File Metadata**: <1KB for provenance information

## Testing Strategy

### Configuration Resolution Testing

**State-Based Loading:**
```bash
# Test with valid deployment state
./bin/setup-azure-cluster-deployment.sh status
# Should show: "Using configuration from deployment state"

# Test with missing state file  
rm ./state/deployment-state.yaml
./bin/setup-azure-cluster-deployment.sh status
# Should show: "WARNING: Deployment state file not found"

# Test with corrupted state file
echo "invalid yaml" > ./state/deployment-state.yaml
./bin/setup-azure-cluster-deployment.sh status  
# Should show: "WARNING: Deployment state file appears corrupted"
```

**Configuration Consistency:**
```bash
# Deploy with custom config
./deploy-k0rdent.sh deploy --config config/special-azure.yaml

# Verify all scripts use same configuration
./bin/setup-azure-cluster-deployment.sh status | grep azure_location
./bin/create-azure-child.sh --dry-run | grep azure_location
./bin/setup-azure-cluster-deployment.sh setup --dry-run | grep azure_location
# All should show the same azure_location value
```

### Backward Compatibility Testing

**Existing Deployments:**
```bash
# Deployments without state tracking should work unchanged
./deploy-k0rdent.sh deploy  # Uses default config, creates state
./bin/setup-azure-cluster-deployment.sh status  # Should work with new resolution
```

## Migration Strategy

**Phased Implementation:**

### Phase 1: Foundation
- Enhance `etc/k0rdent-config.sh` with state-based resolution
- Add comprehensive fallback logic
- Ensure zero breaking changes for existing deployments

### Phase 2: Script Updates  
- Update all affected scripts to use enhanced config loading
- Add configuration source reporting to script output
- Validate each script's behavior with state-based config

### Phase 3: Validation
- Comprehensive testing across deployment lifecycle
- Performance validation and optimization
- Documentation updates and user guidance

## User Experience Improvements

### Clear Configuration Messaging

**Enhanced Script Output:**
```bash
$ ./bin/setup-azure-cluster-deployment.sh status
==> Loading YAML configuration: ./state/deployment-state.yaml
==> Using configuration from deployment state (deployment-state.yaml)
==> k0rdent configuration loaded (cluster ID: k0rdent-xyoeeex2, region: southeastasia)
==> Configuration source: deployment-state (last updated: 2025-11-07T14:23:07Z)
```

**Configuration Source Tracking:**
```bash
$ ./bin/create-azure-child.sh --dry-run
==> Configuration source: deployment-state
==> Parent deployment: k0rdent-xyoeeex2 (southeastasia)
==> Child VM sizing: controller=Standard_D2s_v5, worker=Standard_D2s_v5
==> Using consistent configuration from parent deployment
```

## Security Considerations

### State File Access

**Path Validation:**
```bash
# Ensure state file is within expected project directory
validate_state_file_path() {
    local state_file="$1"
    local project_root="$(pwd)"
    
    if [[ ! "$state_file" =~ ^"$project_root"/ ]]; then
        echo "ERROR: State file outside project directory: $state_file"
        return 1
    fi
    
    if [[ -L "$state_file" ]]; then
        echo "ERROR: State file is symbolic link (potential security risk)"
        return 1
    fi
    
    return 0
}
```

**Permission Checking:**
```bash
validate_state_file_permissions() {
    local state_file="$1"
    
    if [[ ! -r "$state_file" ]]; then
        echo "ERROR: Cannot read state file (permissions): $state_file"
        return 1
    fi
    
    # Validate ownership (should be owned by current user)
    local owner=$(stat -f "%Su" "$state_file" 2>/dev/null || stat -c "%U" "$state_file" 2>/dev/null)
    if [[ "$owner" != "$(whoami)" ]]; then
        echo "WARNING: State file owned by different user: $owner"
        echo "This may indicate a security concern"
    fi
}
```

## Future Enhancements

### Advanced Configuration Management

**Configuration Versioning:**
- Track configuration changes over deployment lifecycle
- Support for configuration rollbacks
- Configuration change detection and alerts

**Multi-Environment Support:**
- Environment-specific configuration overlays
- Development vs production configuration patterns
- Shared configuration across multiple deployments

**Configuration Validation:**
- Cross-validation of configuration consistency
- Automated configuration conflict detection
- Schema validation for configuration completeness

This design provides a comprehensive solution to ensure all k0rdent scripts operate with the same configuration as the actual deployment, eliminating configuration drift and improving operational reliability.
