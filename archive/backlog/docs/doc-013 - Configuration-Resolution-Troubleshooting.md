---
id: doc-013
title: Configuration-Resolution-Troubleshooting
type: troubleshooting
created_date: '2025-11-08 07:31'
---

# Configuration Resolution Troubleshooting Guide

This guide helps diagnose and resolve configuration inconsistency issues in the k0rdent Azure setup project, particularly issues related to state-based configuration resolution.

## Table of Contents
1. [Understanding Configuration Resolution](#understanding-configuration-resolution)
2. [Common Scenarios](#common-scenarios)
3. [Diagnostic Commands](#diagnostic-commands)
4. [Troubleshooting Steps](#troubleshooting-steps)
5. [Configuration Drift Issues](#configuration-drift-issues)
6. [State File Problems](#state-file-problems)

## Understanding Configuration Resolution

The k0rdent system uses a priority-based configuration resolution system:

**Priority Order** (highest to lowest):
1. **Explicit Override**: `K0RDENT_CONFIG_FILE` environment variable
2. **State-Based**: Configuration from `./state/deployment-state.yaml`
3. **Default Search**: `./config/k0rdent.yaml`
4. **Template Fallback**: `./config/k0rdent-default.yaml`

Every script reports which configuration source is being used via the `K0RDENT_CONFIG_SOURCE` variable.

## Common Scenarios

### Scenario 1: Azure Region Mismatch

**Symptom**: Scripts show wrong Azure region compared to actual deployment

```bash
./deploy-k0rdent.sh deploy --config config/k0rdent-baseline-southeastasia.yaml
# Deployment completes in Southeast Asia

./bin/setup-azure-cluster-deployment.sh status
# Shows: region: westus2  ← WRONG!
```

**Cause**: Script is loading from default config file instead of deployment state

**Fix**:
```bash
# Check configuration source
./bin/setup-azure-cluster-deployment.sh status | grep "Configuration source"

# If showing "default" instead of "deployment-state":
# 1. Verify deployment state file exists
ls -la ./state/deployment-state.yaml

# 2. Check if config section exists in state
yq eval '.config' ./state/deployment-state.yaml

# 3. If state is valid but not being used, check k0rdent-config.sh
# for proper state resolution implementation
```

### Scenario 2: VM Size Inconsistency

**Symptom**: Child clusters created with different VM sizes than parent deployment

```bash
# Parent deployment used Standard_D4s_v5
./deploy-k0rdent.sh deploy --config config/custom-vm-sizes.yaml

# Child cluster shows Standard_D2s_v5 (default)
./bin/create-azure-child.sh --dry-run
```

**Cause**: Child cluster script not reading configuration from deployment state

**Fix**: Verify the script sources configuration correctly:
```bash
# Check what configuration is loaded
head -20 ./bin/create-azure-child.sh

# Should see:
# source ./etc/k0rdent-config.sh
# echo "==> Configuration source: ${K0RDENT_CONFIG_SOURCE:-default}"

# Verify state contains VM sizing
yq eval '.config.resource_deployment' ./state/deployment-state.yaml
```

### Scenario 3: Feature Flag Mismatch

**Symptom**: Scripts assume features are enabled when deployment disabled them

```bash
# Deployment with KOF disabled
./deploy-k0rdent.sh deploy --config config/no-kof.yaml

# KOF script tries to proceed
./bin/install-kof-mothership.sh
# Doesn't detect that KOF was disabled in deployment
```

**Cause**: Feature flags not stored in or read from deployment state

**Fix**:
```bash
# Check deployment flags in state
yq eval '.config.deployment_flags' ./state/deployment-state.yaml

# Should show:
# kof: false
# azure_children: false

# Verify script checks these flags
grep -n "deployment_flags" ./bin/install-kof-mothership.sh
```

## Diagnostic Commands

### Check Configuration Source

Every script using enhanced configuration loading reports its source:

```bash
# Any k0rdent script will show configuration source
./bin/setup-azure-cluster-deployment.sh status
# Output includes: ==> Configuration source: deployment-state

# Possible values:
# - "deployment-state" : Using canonical state (correct)
# - "override"         : Using K0RDENT_CONFIG_FILE override
# - "default"          : Using fallback config file (potential issue)
# - "template"         : Using template fallback (likely problem)
```

### Verify Deployment State

Check that deployment state file exists and is valid:

```bash
# 1. Check file exists
ls -la ./state/deployment-state.yaml

# 2. Verify it's valid YAML
yq eval '.' ./state/deployment-state.yaml > /dev/null && echo "Valid YAML" || echo "Invalid YAML"

# 3. Check config section exists
yq eval '.config' ./state/deployment-state.yaml

# 4. View specific configuration values
yq eval '.config.azure_location' ./state/deployment-state.yaml
yq eval '.config.resource_deployment' ./state/deployment-state.yaml
yq eval '.config.deployment_flags' ./state/deployment-state.yaml
```

### Check Configuration Environment Variables

View what configuration is currently loaded:

```bash
# Source configuration and check variables
source ./etc/k0rdent-config.sh

# Check key variables
echo "Cluster ID: $K0RDENT_CLUSTERID"
echo "Azure Location: $AZURE_LOCATION"
echo "Config Source: $K0RDENT_CONFIG_SOURCE"
echo "Config File: $K0RDENT_CONFIG_FILE"
echo "Config Timestamp: $K0RDENT_CONFIG_TIMESTAMP"

# Check resource sizing
echo "Controller VM: $CONTROLLER_VM_SIZE"
echo "Worker VM: $WORKER_VM_SIZE"
```

### Validate Configuration Consistency

Check if all scripts would use the same configuration:

```bash
# Run multiple scripts and check their config source
for script in setup-azure-cluster-deployment.sh create-azure-child.sh sync-cluster-state.sh; do
  echo "=== $script ==="
  ./bin/$script status 2>&1 | grep "Configuration source" || echo "No status command"
done

# All should show the same source (ideally "deployment-state")
```

## Troubleshooting Steps

### Step 1: Identify Configuration Source

```bash
# Run any script and check configuration source
./bin/setup-azure-cluster-deployment.sh status

# Look for this line near the start:
# ==> Configuration source: [source-type]
```

### Step 2: Verify Expected Configuration

```bash
# If source is "deployment-state", verify state file
yq eval '.config.azure_location' ./state/deployment-state.yaml

# If source is "default" or "template", check why state isn't used
if [[ -f ./state/deployment-state.yaml ]]; then
  echo "State file exists, but not being used - investigate k0rdent-config.sh"
else
  echo "State file missing - this may be an old deployment"
fi
```

### Step 3: Check for Configuration Drift

```bash
# Compare deployment state config with what scripts are using
STATE_LOCATION=$(yq eval '.config.azure_location' ./state/deployment-state.yaml)
source ./etc/k0rdent-config.sh
SCRIPT_LOCATION="$AZURE_LOCATION"

if [[ "$STATE_LOCATION" != "$SCRIPT_LOCATION" ]]; then
  echo "Configuration drift detected!"
  echo "State shows: $STATE_LOCATION"
  echo "Scripts using: $SCRIPT_LOCATION"
fi
```

### Step 4: Force Configuration Source (Advanced)

For debugging, you can force a specific configuration:

```bash
# Force using a specific config file
export K0RDENT_CONFIG_FILE="./config/k0rdent-baseline-southeastasia.yaml"
./bin/setup-azure-cluster-deployment.sh status

# Clear override to return to normal behavior
unset K0RDENT_CONFIG_FILE
```

## Configuration Drift Issues

### Detecting Drift

Configuration drift occurs when scripts use different configuration than the actual deployment:

```bash
# Compare key values between state and loaded config
source ./etc/k0rdent-config.sh

echo "Comparing state vs loaded configuration:"
echo "Azure Location:"
echo "  State:  $(yq eval '.config.azure_location' ./state/deployment-state.yaml)"
echo "  Loaded: $AZURE_LOCATION"

echo "Resource Group:"
echo "  State:  $(yq eval '.config.resource_group' ./state/deployment-state.yaml)"
echo "  Loaded: $AZURE_RESOURCE_GROUP"

echo "Controller VM Size:"
echo "  State:  $(yq eval '.config.resource_deployment.controller.vm_size' ./state/deployment-state.yaml)"
echo "  Loaded: $CONTROLLER_VM_SIZE"
```

### Fixing Drift

If drift is detected:

**Option 1: Fix Configuration Loading** (Preferred)
```bash
# Verify k0rdent-config.sh has state-based resolution
grep -A 10 "resolve_canonical_config" ./etc/k0rdent-config.sh

# If missing, this is a pre-state-resolution version
# Check if updates are available
```

**Option 2: Use Configuration Override** (Temporary)
```bash
# Force scripts to use the correct config file
export K0RDENT_CONFIG_FILE="./config/k0rdent-baseline-southeastasia.yaml"

# Run your operations
./bin/setup-azure-cluster-deployment.sh setup

# Remember to unset when done
unset K0RDENT_CONFIG_FILE
```

**Option 3: Update Deployment State** (If state is wrong)
```bash
# If deployment state is incorrect, update it manually
# (Be very careful with this approach)

# Backup current state
cp ./state/deployment-state.yaml ./state/deployment-state.yaml.backup

# Update specific values
yq eval -i '.config.azure_location = "southeastasia"' ./state/deployment-state.yaml

# Verify changes
yq eval '.config' ./state/deployment-state.yaml
```

## State File Problems

### Missing State File

**Symptom**: `Configuration source: default` instead of `deployment-state`

**Cause**: No deployment state file exists (old deployment or state tracking not enabled)

**Fix**:
```bash
# Check if state directory exists
ls -la ./state/

# If missing, this is a pre-state-tracking deployment
# Scripts will fall back to default configuration automatically

# To enable state tracking for existing deployment:
# 1. Deploy again with current code (will create state)
# 2. Or manually create state file based on current deployment
```

### Corrupted State File

**Symptom**: Warning about corrupted state file, falls back to default

**Cause**: YAML syntax error or incomplete state file

**Fix**:
```bash
# Validate YAML syntax
yq eval '.' ./state/deployment-state.yaml

# If invalid, restore from backup
if [[ -f ./state/deployment-state.yaml.backup ]]; then
  cp ./state/deployment-state.yaml.backup ./state/deployment-state.yaml
  echo "Restored from backup"
fi

# If no backup, check git history
git log --oneline --all -- state/deployment-state.yaml
git show <commit>:state/deployment-state.yaml > ./state/deployment-state.yaml
```

### Missing Configuration Section

**Symptom**: State file exists but has no config section

**Cause**: Old deployment state format

**Fix**:
```bash
# Check if config section exists
yq eval '.config' ./state/deployment-state.yaml

# If returns "null", this is an old state format
# Scripts will fall back to default configuration

# To add config section (advanced):
# 1. Determine actual deployment configuration
# 2. Add config section to state file manually
# 3. Or re-deploy with current code
```

### Multiple State Files

**Symptom**: Uncertain which deployment state is being used

**Cause**: Multiple deployments in same directory

**Fix**:
```bash
# Find all deployment state files
find ./state -name "deployment-state.yaml" -type f

# Check which is most recent
find ./state -name "deployment-state.yaml" -type f -exec stat -f "%m %N" {} \; | sort -rn

# System uses most recent by default
# To use specific state file:
export K0RDENT_DEVELOPMENT_STATE="./state/specific-deployment-state.yaml"
```

## Development Mode

For development and testing, you can control configuration behavior:

```bash
# Disable state-based configuration (use defaults)
export K0RDENT_DEVELOPMENT_MODE=true
./bin/setup-azure-cluster-deployment.sh status
# Will use default config files instead of state

# Force specific state file
export K0RDENT_DEVELOPMENT_STATE="./state/test-deployment-state.yaml"
./bin/setup-azure-cluster-deployment.sh status
# Will use specified state file

# Clear development overrides
unset K0RDENT_DEVELOPMENT_MODE
unset K0RDENT_DEVELOPMENT_STATE
```

## Getting Help

If configuration issues persist:

1. **Check script output**: All scripts report configuration source
2. **Verify state file**: Use diagnostic commands above
3. **Compare configurations**: Look for drift between state and loaded config
4. **Review deployment log**: Check what configuration was used during deployment
5. **Check for updates**: Configuration system may have been enhanced

**Common Resolution Path**:
```bash
# 1. Verify problem
./bin/setup-azure-cluster-deployment.sh status | grep "Configuration source"

# 2. Check state file
yq eval '.config' ./state/deployment-state.yaml

# 3. Validate configuration loading
source ./etc/k0rdent-config.sh && echo "Source: $K0RDENT_CONFIG_SOURCE, Location: $AZURE_LOCATION"

# 4. If mismatch, force correct config temporarily
export K0RDENT_CONFIG_FILE="./config/correct-config.yaml"

# 5. Run operation
./bin/setup-azure-cluster-deployment.sh setup

# 6. Clean up
unset K0RDENT_CONFIG_FILE
```
