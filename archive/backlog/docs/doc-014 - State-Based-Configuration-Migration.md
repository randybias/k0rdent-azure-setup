---
id: doc-014
title: State-Based-Configuration-Migration
type: guide
created_date: '2025-11-08 07:31'
---

# State-Based Configuration Migration Guide

This guide explains how to migrate to the enhanced state-based configuration system in k0rdent Azure setup, including what changes, backward compatibility guarantees, and how to test the new system.

## Table of Contents
1. [Overview](#overview)
2. [What's New](#whats-new)
3. [Backward Compatibility](#backward-compatibility)
4. [Migration Scenarios](#migration-scenarios)
5. [Testing the New System](#testing-the-new-system)
6. [Rollback Procedures](#rollback-procedures)

## Overview

The state-based configuration enhancement ensures all k0rdent scripts use the same configuration as your actual deployment, eliminating configuration drift and operational errors.

### Key Benefits

**Before (Old System)**:
- Deployment uses `--config custom-config.yaml`
- Support scripts load from hardcoded `./config/k0rdent.yaml`
- Configuration mismatch leads to wrong Azure regions, VM sizes, etc.

**After (New System)**:
- Deployment stores canonical configuration in deployment state
- All scripts read configuration from deployment state
- Guaranteed configuration consistency across all operations

## What's New

### Enhanced Configuration Resolution

The new system uses a priority-based resolution order:

1. **Explicit Override**: `K0RDENT_CONFIG_FILE` environment variable
2. **State-Based**: Configuration from `./state/deployment-state.yaml`
3. **Default Search**: `./config/k0rdent.yaml` (backward compatibility)
4. **Template Fallback**: `./config/k0rdent-default.yaml`

### Configuration Transparency

All scripts now report which configuration source they're using:

```bash
./bin/setup-azure-cluster-deployment.sh status
# Output includes:
# ==> Configuration source: deployment-state
```

### New Environment Variables

**Configuration Tracking**:
- `K0RDENT_CONFIG_SOURCE`: Which configuration source is being used
- `K0RDENT_CONFIG_FILE`: Path to the configuration file
- `K0RDENT_CONFIG_TIMESTAMP`: When configuration was last updated

**Development Overrides**:
- `K0RDENT_DEVELOPMENT_MODE`: Disable state-based config for development
- `K0RDENT_DEVELOPMENT_STATE`: Use specific state file for testing

### Enhanced Deployment State

The deployment state file now includes a complete `config` section:

```yaml
# ./state/deployment-state.yaml
config:
  azure_location: "southeastasia"
  resource_group: "k0rdent-xyz-resgrp"
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

## Backward Compatibility

### Guaranteed Compatibility

The new system provides **100% backward compatibility** with existing deployments:

1. **Old deployments without state tracking continue working**
   - Scripts fall back to default configuration search
   - No breaking changes to existing workflows
   - Same behavior as before for deployments without state files

2. **Existing script interfaces unchanged**
   - All scripts work exactly as before
   - No command-line argument changes
   - No required configuration file modifications

3. **Gradual adoption supported**
   - New deployments automatically use state-based config
   - Old deployments continue using default config files
   - Mixed environments work correctly

### What Doesn't Change

- **Script commands**: All commands remain the same
- **Configuration file format**: YAML structure unchanged
- **Deployment workflow**: Same deployment process
- **Directory structure**: Same file locations

### What Gets Better

- **Configuration consistency**: Scripts use correct configuration
- **Transparency**: Clear reporting of configuration source
- **Debugging**: Better visibility into configuration issues
- **Reliability**: Eliminates configuration drift problems

## Migration Scenarios

### Scenario 1: Fresh Deployment (Automatic)

**When**: Starting a new k0rdent deployment

**What Happens**: State-based configuration is automatically enabled

**Steps**:
```bash
# 1. Deploy as usual (with or without custom config)
./deploy-k0rdent.sh deploy --config config/k0rdent-baseline-southeastasia.yaml

# 2. Deployment automatically creates state with config section
# File created: ./state/deployment-state.yaml with config section

# 3. All subsequent scripts automatically use state-based config
./bin/setup-azure-cluster-deployment.sh setup
# Output: ==> Configuration source: deployment-state

# 4. Verify configuration consistency
./bin/setup-azure-cluster-deployment.sh status
# Shows correct region from your custom config
```

**Result**: You're automatically using state-based configuration!

### Scenario 2: Existing Deployment (No Changes Required)

**When**: You have an existing k0rdent deployment from before the enhancement

**What Happens**: Scripts continue using default configuration (backward compatible)

**Steps**:
```bash
# 1. Check your deployment state file
ls -la ./state/deployment-state.yaml

# If it exists but predates the enhancement:
yq eval '.config' ./state/deployment-state.yaml
# Output: null (no config section)

# 2. Scripts continue working with default config
./bin/setup-azure-cluster-deployment.sh status
# Output: ==> Configuration source: default

# 3. No action required - everything works as before
```

**Result**: Your existing deployment continues working unchanged!

**Optional Enhancement**:
To enable state-based config for existing deployment:

```bash
# Option A: Re-deploy (creates new state with config section)
./deploy-k0rdent.sh reset
./deploy-k0rdent.sh deploy --config config/your-config.yaml

# Option B: Continue using current deployment without state-based config
# (No changes needed, scripts use default configuration)
```

### Scenario 3: Upgrading from Old to New

**When**: You want to enable state-based config for existing deployment

**What Happens**: You choose when to migrate by redeploying

**Steps**:
```bash
# 1. Back up current deployment info
./bin/sync-cluster-state.sh backup
kubectl get all -A > cluster-backup.yaml

# 2. Note your current configuration
source ./etc/k0rdent-config.sh
echo "Current Azure Location: $AZURE_LOCATION"
echo "Current Resource Group: $AZURE_RESOURCE_GROUP"

# 3. Reset and redeploy with same configuration
./deploy-k0rdent.sh reset
./deploy-k0rdent.sh deploy --config config/your-config.yaml

# 4. Verify state-based config is enabled
yq eval '.config' ./state/deployment-state.yaml
# Should show complete config section

# 5. Verify all scripts use state-based config
./bin/setup-azure-cluster-deployment.sh status
# Output: ==> Configuration source: deployment-state
```

**Result**: You're now using state-based configuration with guaranteed consistency!

### Scenario 4: Multiple Environments

**When**: You manage multiple k0rdent deployments

**What Happens**: Each deployment has its own state-based configuration

**Steps**:
```bash
# Environment 1: Development
cd ~/k0rdent-dev
./deploy-k0rdent.sh deploy --config config/dev-config.yaml
# Creates: ./state/deployment-state.yaml with dev configuration

# Environment 2: Staging
cd ~/k0rdent-staging
./deploy-k0rdent.sh deploy --config config/staging-config.yaml
# Creates: ./state/deployment-state.yaml with staging configuration

# Environment 3: Production
cd ~/k0rdent-prod
./deploy-k0rdent.sh deploy --config config/prod-config.yaml
# Creates: ./state/deployment-state.yaml with production configuration

# Each environment's scripts automatically use their own state
cd ~/k0rdent-dev && ./bin/setup-azure-cluster-deployment.sh status
# Uses dev configuration

cd ~/k0rdent-prod && ./bin/setup-azure-cluster-deployment.sh status
# Uses production configuration
```

**Result**: Each environment maintains its own configuration consistency!

## Testing the New System

### Test 1: Verify Configuration Source

**Purpose**: Confirm scripts are using state-based configuration

```bash
# Deploy with custom config
./deploy-k0rdent.sh deploy --config config/k0rdent-baseline-southeastasia.yaml

# Check configuration source in any script
./bin/setup-azure-cluster-deployment.sh status | grep "Configuration source"
# Expected: ==> Configuration source: deployment-state

# If shows "default" instead, check state file:
yq eval '.config' ./state/deployment-state.yaml
```

### Test 2: Verify Configuration Consistency

**Purpose**: Ensure all scripts use the same configuration

```bash
# Deploy with known configuration
./deploy-k0rdent.sh deploy --config config/k0rdent-baseline-southeastasia.yaml

# Check multiple scripts report same configuration
echo "=== Script 1: setup-azure-cluster-deployment.sh ==="
./bin/setup-azure-cluster-deployment.sh status | grep -E "(Configuration source|azure_location|region)"

echo "=== Script 2: create-azure-child.sh ==="
./bin/create-azure-child.sh --dry-run | grep -E "(Configuration source|azure_location|region)"

echo "=== Script 3: sync-cluster-state.sh ==="
./bin/sync-cluster-state.sh status | grep -E "(Configuration source|azure_location|region)"

# All should show:
# - Same configuration source (deployment-state)
# - Same Azure region (southeastasia)
```

### Test 3: Verify Deployment State Contents

**Purpose**: Confirm deployment state contains complete configuration

```bash
# Deploy
./deploy-k0rdent.sh deploy --config config/your-config.yaml

# Check state file exists and has config section
ls -la ./state/deployment-state.yaml
yq eval '.config' ./state/deployment-state.yaml

# Should show complete configuration including:
# - azure_location
# - resource_group
# - controller_count, worker_count
# - resource_deployment (VM sizes, spot settings)
# - deployment_flags
```

### Test 4: Test Fallback Behavior

**Purpose**: Verify backward compatibility for deployments without state

```bash
# Simulate old deployment by removing config from state
cp ./state/deployment-state.yaml ./state/deployment-state.yaml.backup
yq eval -i 'del(.config)' ./state/deployment-state.yaml

# Scripts should fall back to default configuration
./bin/setup-azure-cluster-deployment.sh status | grep "Configuration source"
# Expected: ==> Configuration source: default

# Restore state
cp ./state/deployment-state.yaml.backup ./state/deployment-state.yaml

# Verify state-based config restored
./bin/setup-azure-cluster-deployment.sh status | grep "Configuration source"
# Expected: ==> Configuration source: deployment-state
```

### Test 5: Test Configuration Override

**Purpose**: Verify manual override capability for debugging

```bash
# Deploy normally
./deploy-k0rdent.sh deploy --config config/southeastasia-config.yaml
./bin/setup-azure-cluster-deployment.sh status | grep "azure_location"
# Shows: southeastasia

# Override with different config
export K0RDENT_CONFIG_FILE="./config/k0rdent-baseline-westeu.yaml"
./bin/setup-azure-cluster-deployment.sh status | grep "azure_location"
# Shows: westeurope (overridden)

# Clear override
unset K0RDENT_CONFIG_FILE
./bin/setup-azure-cluster-deployment.sh status | grep "azure_location"
# Shows: southeastasia (back to state-based)
```

### Test 6: Test Development Mode

**Purpose**: Verify development mode overrides

```bash
# Normal mode - uses deployment state
./bin/setup-azure-cluster-deployment.sh status
# Configuration source: deployment-state

# Enable development mode - uses default config
export K0RDENT_DEVELOPMENT_MODE=true
./bin/setup-azure-cluster-deployment.sh status
# Configuration source: default

# Force specific state file in development
export K0RDENT_DEVELOPMENT_STATE="./state/test-deployment-state.yaml"
./bin/setup-azure-cluster-deployment.sh status
# Uses specified state file

# Clear development overrides
unset K0RDENT_DEVELOPMENT_MODE
unset K0RDENT_DEVELOPMENT_STATE
```

## Rollback Procedures

### If Issues Arise

The state-based configuration system is designed with robust fallback mechanisms, but if you encounter problems:

### Rollback Option 1: Disable State-Based Config Temporarily

```bash
# Force using default configuration
export K0RDENT_DEVELOPMENT_MODE=true

# Run your operations
./bin/setup-azure-cluster-deployment.sh setup
./bin/create-azure-child.sh child-1

# Clear override when issue is resolved
unset K0RDENT_DEVELOPMENT_MODE
```

### Rollback Option 2: Use Explicit Configuration File

```bash
# Force specific configuration file
export K0RDENT_CONFIG_FILE="./config/k0rdent.yaml"

# Run operations with explicit config
./bin/setup-azure-cluster-deployment.sh setup

# Clear when done
unset K0RDENT_CONFIG_FILE
```

### Rollback Option 3: Fix Deployment State

```bash
# If deployment state is corrupted, restore from backup
cp ./state/deployment-state.yaml.backup ./state/deployment-state.yaml

# Or restore from git history
git log --oneline -- state/deployment-state.yaml
git checkout <commit> -- state/deployment-state.yaml
```

### Rollback Option 4: Complete Rollback to Old Behavior

If you need to completely disable state-based configuration:

```bash
# 1. Edit k0rdent-config.sh and comment out state resolution
vim ./etc/k0rdent-config.sh
# Comment out the resolve_canonical_config() calls
# Scripts will fall back to original default config loading

# 2. Or set permanent development mode override
echo 'export K0RDENT_DEVELOPMENT_MODE=true' >> ~/.bashrc
source ~/.bashrc
```

## Common Questions

### Q: Do I need to do anything to enable state-based configuration?

**A**: No! If you deploy with the updated code, it's automatically enabled. Existing deployments continue working with default configuration (backward compatible).

### Q: Will my existing deployments break?

**A**: No. The system has robust fallback mechanisms. If deployment state is not available, scripts fall back to default configuration exactly as before.

### Q: Can I use a custom configuration file like before?

**A**: Yes! The deployment process is unchanged:

```bash
./deploy-k0rdent.sh deploy --config config/your-custom-config.yaml
```

The difference is that now all subsequent scripts will also use this configuration (via deployment state) instead of falling back to default.

### Q: How do I know if I'm using state-based configuration?

**A**: Check the configuration source reported by any script:

```bash
./bin/setup-azure-cluster-deployment.sh status
# Look for: ==> Configuration source: deployment-state
```

### Q: What if I want to test with a different configuration?

**A**: Use the configuration override:

```bash
export K0RDENT_CONFIG_FILE="./config/test-config.yaml"
./bin/your-script.sh
unset K0RDENT_CONFIG_FILE
```

### Q: Can I migrate my existing deployment to use state-based config?

**A**: The easiest way is to redeploy. Your existing deployment will continue working with default configuration, which may be sufficient for your needs.

### Q: What happens if I have multiple deployments in the same directory?

**A**: The system uses the most recent deployment state by default. For advanced scenarios, you can specify which state file to use:

```bash
export K0RDENT_DEVELOPMENT_STATE="./state/specific-deployment-state.yaml"
```

### Q: How do I troubleshoot configuration issues?

**A**: See the comprehensive troubleshooting guide:
- `backlog/docs/doc-013 - Configuration-Resolution-Troubleshooting.md`

## Getting Help

If you encounter issues during migration:

1. **Check configuration source**: All scripts report their config source
2. **Verify deployment state**: Use `yq eval '.config' ./state/deployment-state.yaml`
3. **Review troubleshooting guide**: `doc-013 - Configuration-Resolution-Troubleshooting.md`
4. **Use fallback mechanisms**: Development mode or explicit config override
5. **Report issues**: Include configuration source and deployment state info

## Summary

The state-based configuration enhancement provides:

- **Automatic adoption**: New deployments automatically get it
- **Zero breaking changes**: Existing deployments continue working
- **Configuration consistency**: All scripts use same configuration
- **Full transparency**: Clear reporting of configuration source
- **Easy migration**: Optional upgrade path via redeployment
- **Robust fallbacks**: Multiple safety mechanisms
- **Development support**: Flexible overrides for testing

You can adopt this enhancement at your own pace, and it will make your k0rdent operations more reliable and consistent.
