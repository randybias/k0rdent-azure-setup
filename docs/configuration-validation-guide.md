# Configuration Validation and Drift Detection Guide

**Part of OpenSpec change:** canonical-config-from-state
**Task:** 0010 - Configuration Validation and Inconsistency Detection

## Overview

This guide documents the configuration validation and drift detection system for k0rdent deployments. These features help detect and prevent configuration inconsistencies that can cause operational problems.

## Key Features

### 1. Configuration Drift Detection
Detects when deployment state differs from default configuration files.

### 2. Configuration Completeness Validation
Ensures state-based configuration has all required fields.

### 3. Automated Consistency Checks
Validates common configuration parameters (region, VM sizes, versions, network).

### 4. Operation Validation
Validates configuration before critical operations.

### 5. Value Comparison
Compares specific configuration values between state and files.

## Functions Reference

### compare_config_values()

**Purpose:** Compare configuration values between deployment state and config file

**Usage:**
```bash
if ! compare_config_values "$state_file" "$config_file"; then
    echo "Configuration drift detected!"
fi
```

**Parameters:**
- `$1` - Path to deployment state file
- `$2` - Path to configuration file

**Returns:**
- `0` - Configurations match (no drift)
- `1` - Configurations differ (drift detected)

**Fields Compared:**
- Azure Location
- Azure Subscription ID
- Controller VM Size
- Worker VM Size
- Controller Count
- Worker Count
- WireGuard Network
- K0s Version
- K0rdent Version

### detect_configuration_drift()

**Purpose:** Detect and report configuration drift with actionable guidance

**Usage:**
```bash
detect_configuration_drift
drift_status=$?

case $drift_status in
    0) echo "No drift detected" ;;
    1) echo "Drift detected - review differences" ;;
    2) echo "Cannot determine drift" ;;
esac
```

**Parameters:** None (uses environment variables)

**Returns:**
- `0` - No drift detected or using state-based config
- `1` - Configuration drift detected
- `2` - Cannot determine drift (missing files/tools)

**Example Output:**
```
=== Configuration Drift Detection ===
==> Comparing deployment state with current configuration
==> State file:  deployment-state.yaml
==> Config file: k0rdent.yaml

WARNING: Azure Location differs:
  State:  southeastasia
  Config: westus2

WARNING: Configuration drift detected!

The deployment was created with different configuration than the current default.
Scripts may operate with incorrect parameters.

Recommended actions:
  1. Use state-based configuration (automatic in enhanced scripts)
  2. Explicitly set K0RDENT_CONFIG_FILE to match deployment
  3. Review differences above and update default config if needed
```

### validate_state_config_completeness()

**Purpose:** Ensure state configuration has all required fields

**Usage:**
```bash
if ! validate_state_config_completeness "$state_file"; then
    echo "State configuration is incomplete"
    exit 1
fi
```

**Parameters:**
- `$1` - Path to deployment state file

**Returns:**
- `0` - Configuration is complete
- `1` - Configuration missing required fields

**Validation Levels:**
- **Critical:** Must be present (failure if missing)
  - Azure Location
  - Azure Subscription ID
  - Resource Group
  - Controller Count
  - Worker Count

- **Important:** Should be present (warning if missing)
  - Controller VM Size
  - Worker VM Size
  - WireGuard Network
  - K0s Version
  - K0rdent Version
  - SSH Username

**Example Output:**
```
ERROR: State configuration missing CRITICAL fields:
  - Azure Location
  - Resource Group

ERROR: State configuration is incomplete and cannot be used reliably

Possible causes:
  - Deployment state file is from an older version
  - State file was manually edited and corrupted
  - Deployment did not complete successfully

Recommended actions:
  1. Re-run deployment to regenerate complete state
  2. Use default configuration files instead
  3. Manually repair state file based on deployment parameters
```

### check_configuration_consistency()

**Purpose:** Run automated checks for common configuration mismatches

**Usage:**
```bash
if ! check_configuration_consistency; then
    echo "Configuration inconsistencies detected"
fi
```

**Parameters:** None (uses environment variables and state files)

**Returns:**
- `0` - All consistency checks passed
- `1` - One or more checks failed
- `2` - Cannot perform checks (missing tools/files)

**Checks Performed:**

1. **Azure Region Consistency**
   - Compares `AZURE_LOCATION` env var with state
   - Critical error if mismatch (wrong region operations)

2. **VM Size Consistency**
   - Compares controller/worker VM sizes
   - Warning if mismatch (inconsistent resource sizing)

3. **K0rdent Version Consistency**
   - Compares K0rdent versions
   - Warning if mismatch (compatibility issues)

4. **Network Configuration Consistency**
   - Compares WireGuard network settings
   - Critical error if mismatch (connectivity issues)

**Example Output:**
```
=== Configuration Consistency Checks ===

ERROR: Azure region mismatch detected!
  Current environment: westus2
  Deployment state:    southeastasia
  This will cause operations to target wrong region

SUCCESS: Controller VM size consistency: OK (Standard_D2s_v5)
SUCCESS: K0rdent version consistency: OK (0.0.1-dev)
SUCCESS: WireGuard network consistency: OK (192.168.100.0/24)

ERROR: Configuration consistency checks FAILED

To resolve configuration inconsistencies:
  1. Use state-based configuration (automatic in enhanced scripts)
  2. Source configuration from deployment state before operations
  3. Review and update environment variables to match deployment
```

### validate_config_for_operation()

**Purpose:** Validate configuration before critical operations

**Usage:**
```bash
# For critical operations (blocks on validation failure)
if ! validate_config_for_operation "Azure VM creation" "required"; then
    echo "Cannot proceed with VM creation"
    exit 1
fi

# For recommended validation (warnings only)
if ! validate_config_for_operation "cluster info query" "recommended"; then
    validation_result=$?
    if [[ $validation_result -eq 2 ]]; then
        echo "Warnings present but proceeding..."
    fi
fi
```

**Parameters:**
- `$1` - Operation name (for error messages)
- `$2` - Criticality: "required" or "recommended" (default: recommended)

**Returns:**
- `0` - Configuration valid for operation
- `1` - Validation failed (should not proceed)
- `2` - Validation warnings (can proceed with caution)

**Validation Checks:**
1. Configuration source is known
2. State-based config is complete (if using state)
3. No critical inconsistencies detected
4. Required tools are available (yq)

**Example Output:**
```
=== Configuration Validation for: Azure VM creation ===

SUCCESS: Configuration source: deployment-state
SUCCESS: State configuration is complete and valid
SUCCESS: All configuration consistency checks passed
SUCCESS: yq available for validation

SUCCESS: Configuration validation passed for Azure VM creation
```

## Common Use Cases

### Use Case 1: Pre-Deployment Validation

Before running a critical operation like VM creation:

```bash
#!/usr/bin/env bash

source ./etc/config-resolution-functions.sh

# Validate configuration before creating VMs
if ! validate_config_for_operation "Azure VM creation" "required"; then
    echo "ERROR: Configuration validation failed"
    echo "Fix issues before proceeding"
    exit 1
fi

# Proceed with VM creation
./create-azure-vms.sh
```

### Use Case 2: Detecting Configuration Drift

Check if deployment state differs from default configuration:

```bash
#!/usr/bin/env bash

source ./etc/config-resolution-functions.sh

# Check for configuration drift
detect_configuration_drift
drift_status=$?

if [[ $drift_status -eq 1 ]]; then
    echo ""
    echo "WARNING: Configuration drift detected!"
    echo "Your deployment may be using different settings than expected."
    echo ""
    read -p "Continue anyway? (y/N): " confirm
    if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
        exit 1
    fi
fi
```

### Use Case 3: Automated Consistency Checks

Run consistency checks before operations:

```bash
#!/usr/bin/env bash

source ./etc/config-resolution-functions.sh

# Run automated consistency checks
if ! check_configuration_consistency; then
    consistency_result=$?

    if [[ $consistency_result -eq 1 ]]; then
        echo "ERROR: Critical configuration mismatches detected"
        echo "Review errors above and fix configuration"
        exit 1
    fi
fi

# Proceed with operation
echo "Configuration checks passed, proceeding..."
```

### Use Case 4: Validating State Completeness

Ensure deployment state is complete before using it:

```bash
#!/usr/bin/env bash

source ./etc/config-resolution-functions.sh

# Find deployment state
state_file=$(select_deployment_state)

if [[ $? -ne 0 ]]; then
    echo "ERROR: No deployment state found"
    exit 1
fi

# Validate state completeness
if ! validate_state_config_completeness "$state_file"; then
    echo "ERROR: Deployment state is incomplete"
    echo "Consider re-running deployment or using default config"
    exit 1
fi

# Use state-based configuration
export K0RDENT_DEPLOYMENT_STATE="$state_file"
```

### Use Case 5: Script with Optional Validation

Add optional validation flag to scripts:

```bash
#!/usr/bin/env bash

source ./etc/config-resolution-functions.sh

# Parse arguments
VALIDATE_CONFIG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --validate)
            VALIDATE_CONFIG=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Optional configuration validation
if [[ "$VALIDATE_CONFIG" == "true" ]]; then
    echo "==> Running configuration validation..."

    if ! validate_config_for_operation "script operation" "recommended"; then
        validation_result=$?
        if [[ $validation_result -eq 1 ]]; then
            echo "ERROR: Configuration validation failed"
            exit 1
        fi
    fi

    echo ""
fi

# Proceed with script operations
echo "==> Proceeding with operations..."
```

## Integration with Scripts

### Adding Validation to Existing Scripts

1. **Source the functions:**
   ```bash
   source ./etc/config-resolution-functions.sh
   ```

2. **Add validation before critical operations:**
   ```bash
   validate_config_for_operation "operation name" "required"
   ```

3. **Handle validation results:**
   ```bash
   if ! validate_config_for_operation "operation" "required"; then
       echo "Cannot proceed"
       exit 1
   fi
   ```

### Recommended Validation Points

- **Before VM Creation:** Required validation
- **Before Resource Deletion:** Recommended validation
- **Before Configuration Changes:** Recommended validation
- **Before Cluster Operations:** Optional validation
- **Before Status Queries:** Optional validation

## Exit Codes

All validation functions use consistent exit codes:

- `0` - Success (validation passed)
- `1` - Failure (validation failed, should not proceed)
- `2` - Warning (validation completed with warnings)

## Environment Variables

### K0RDENT_CONFIG_SOURCE
Current configuration source (set by config resolution)
- `deployment-state` - Using deployment state
- `explicit-override` - Using K0RDENT_CONFIG_FILE
- `default` - Using default configuration
- `unknown` - Configuration source unknown

### K0RDENT_CONFIG_FILE
Path to current configuration file

### K0RDENT_DEPLOYMENT_STATE
Override deployment state file path

### AZURE_LOCATION
Azure region (validated against state)

### AZURE_CONTROLLER_VM_SIZE
Controller VM size (validated against state)

### K0RDENT_VERSION
K0rdent version (validated against state)

### WG_NETWORK
WireGuard network (validated against state)

## Error Messages

### Configuration Drift
**Message:** "Configuration drift detected!"
**Cause:** Deployment state differs from default config
**Fix:** Use state-based configuration or update default config

### Missing Critical Fields
**Message:** "State configuration missing CRITICAL fields"
**Cause:** Deployment state incomplete
**Fix:** Re-run deployment or repair state file manually

### Region Mismatch
**Message:** "Azure region mismatch detected!"
**Cause:** AZURE_LOCATION doesn't match state
**Fix:** Use state-based config or set correct AZURE_LOCATION

### Network Mismatch
**Message:** "WireGuard network mismatch detected!"
**Cause:** WG_NETWORK doesn't match state
**Fix:** Use state-based config or set correct WG_NETWORK

## Best Practices

1. **Always validate before critical operations**
   - Use "required" criticality for destructive operations
   - Use "recommended" criticality for read operations

2. **Handle validation results appropriately**
   - Exit on critical failures
   - Warn and continue on recommendations

3. **Use state-based configuration**
   - Let enhanced scripts load from state automatically
   - Eliminates most drift scenarios

4. **Check for drift periodically**
   - Run drift detection after configuration changes
   - Compare state with default configs regularly

5. **Keep deployment state up to date**
   - Don't manually edit state files
   - Re-run deployment if state becomes corrupted

## Troubleshooting

### yq not available
**Symptom:** "yq is required for configuration validation"
**Solution:** Install yq: `brew install yq` (macOS)

### No deployment state found
**Symptom:** "No deployment state found, drift detection skipped"
**Solution:** Run initial deployment or set K0RDENT_DEPLOYMENT_STATE

### State file corrupted
**Symptom:** "State file contains invalid YAML syntax"
**Solution:** Re-run deployment or restore from backup

### Multiple deployment states
**Symptom:** "Multiple deployment states found, using most recent"
**Solution:** Set K0RDENT_DEPLOYMENT_STATE to specify which one

## Examples

See the comprehensive example script:
```bash
./examples/validate-configuration-example.sh
```

Run all examples non-interactively:
```bash
./examples/validate-configuration-example.sh --all
```

## Related Documentation

- [Configuration Resolution Design](../openspec/changes/canonical-config-from-state/design.md)
- [Configuration Resolution Tasks](../openspec/changes/canonical-config-from-state/tasks.md)
- [State Management Guide](state-management-guide.md)

## Support

For issues or questions about configuration validation:
1. Review this guide and examples
2. Check OpenSpec design documentation
3. Review recent changes in git history
4. Contact development team
