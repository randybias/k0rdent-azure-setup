# Change Proposal: Implement Canonical Configuration from Deployment State

**Created**: 2025-11-07  
**Author**: Droid (droid@factory.ai)  
**Status:** Draft  

## Summary

All k0rdent scripts outside of the main deployment should derive their configuration from the canonical deployment state rather than loading from default configuration files. Currently, scripts like `setup-azure-cluster-deployment.sh` load configuration from `./config/k0rdent.yaml` (default file) which may not match the deployment's actual configuration, leading to inconsistencies like using the wrong Azure region or other parameters.

## Why

Configuration inconsistency between deployment and post-deployment operations causes operational errors and user confusion. When users deploy k0rdent with a custom configuration file, all subsequent scripts must use that same configuration to ensure consistent Azure regions, VM sizes, and settings. Currently, post-deployment scripts load from default configuration files, leading to mismatches that can cause deployment failures or incorrect resource provisioning.

## What Changes

Implement a canonical configuration resolution system in `etc/k0rdent-config.sh` that prioritizes deployment state configuration over default files. All scripts will automatically use the deployment's actual configuration, with graceful fallback to default files when state is unavailable. This ensures configuration consistency across the entire k0rdent ecosystem while maintaining backward compatibility with existing deployments.

## Problem Statement

### Current Issue: Configuration Inconsistency Across Scripts

**Deployment Scenario:**
```bash
./deploy-k0rdent.sh deploy --config config/k0rdent-baseline-westeu.yaml
# Deployment completes successfully in Southeast Asia
```

**Post-Deployment Scenario:**
```bash
./bin/setup-azure-cluster-deployment.sh setup
# Script shows: ==> k0rdent configuration loaded (cluster ID: k0s-xyz, region: westus2)
# But deployment state shows: azure_location: "southeastasia"  ← MISMATCH!
```

**Root Cause:**
1. **Deployment Script**: Uses specified `--config` file and stores canonical config in state
2. **Support Scripts**: Load from hardcoded `./config/k0rdent.yaml` (default)
3. **Configuration Drift**: Scripts operate with different configuration than actual deployment
4. **Operational Errors**: Wrong Azure regions, different VM sizes, mismatched settings

### Affected Scripts Identified
- `setup-azure-cluster-deployment.sh`
- `create-azure-child.sh`  
- `create-aws-cluster-deployment.sh`
- `setup-aws-cluster-deployment.sh`
- `sync-cluster-state.sh`
- `install-kof-mothership.sh`
- `install-kof-regional.sh`
- `list-child-clusters.sh`
- `azure-configuration-validation.sh`

## Proposed Solution

Implement a canonical configuration resolution system where all scripts derive the definitive configuration from the deployment state, ensuring consistency across the entire k0rdent ecosystem.

### Key Components

1. **Canonical Configuration Resolver**: Central function to read configuration from deployment state first
2. **State-Based Configuration Loading**: Enhance k0rdent-config.sh to prioritize deployment state over default files
3. **Fallback Logic**: Graceful degradation when deployment state is unavailable
4. **Configuration Validation**: Ensure state-derived configuration matches script expectations

## Scope

**In Scope:**
- All scripts that currently load configuration via `etc/k0rdent-config.sh`
- State-based configuration resolution for post-deployment operations
- Backward compatibility for deployments without state tracking
- Configuration validation and error handling

**Out of Scope:**
- Changes to the main deployment script's configuration loading
- Multi-environment configuration management
- Configuration file format changes
- Dynamic configuration switching during operations

## Success Criteria

1. All post-deployment scripts use the same configuration as the original deployment
2. Configuration resolution falls back gracefully when deployment state is not available
3. Existing deployments continue working without breaking changes
4. Scripts provide clear messaging about configuration source and any discrepancies
5. No performance degradation in configuration loading

## Impact Analysis

- **Consistency**: Eliminates configuration drift between deployment and post-deployment operations
- **Reliability**: Ensures all operations use the actual deployment parameters
- **Debugging**: Reduces confusion about which configuration is being used
- **User Experience**: Predictable behavior across all k0rdent operations
- **Risk**: Low - enhancements with robust fallback mechanisms

## Dependencies

- Existing deployment state tracking system (deployment-state.yaml)
- Current configuration loading mechanism in etc/k0rdent-config.sh
- All affected scripts that source configuration from environment variables

## Considerations

- **State File Access**: Scripts must be able to locate and read deployment state files
- **Multiple Deployments**: Clear behavior when multiple deployment states exist
- **State Corruption**: Graceful handling when state files are damaged or missing
- **Development vs Production**: Different behavior in development environments

## Implementation Approach

### Phase 1: Core Configuration Resolver
- Create canonical configuration resolution functions
- Enhance k0rdent-config.sh with state-based loading
- Implement fallback logic for missing state files

### Phase 2: Script Integration
- Update all affected scripts to use enhanced configuration loading
- Ensure backward compatibility with existing deployments
- Add configuration source reporting to script output

### Phase 3: Validation and Testing
- Test configuration consistency across deployment lifecycle
- Validate fallback behavior in various scenarios
- Performance testing to ensure no regression

## Technical Requirements

### Configuration Resolution Order
1. **Explicit Override**: Environment variable `K0RDENT_CONFIG_FILE` (for manual overrides)
2. **State-Based**: Configuration from deployment-state.yaml (canonical source)
3. **Default Search**: Existing `./config/k0rdent.yaml` fallback
4. **Template Fallback**: `./config/k0rdent-default.yaml` ultimate fallback

### State Integration Points
- **Deployment State File**: Primary source of canonical configuration
- **Configuration Metadata**: Track config file path, checksum, and last modified
- **Script Logging**: Log configuration source for debugging
- **Error Reporting**: Clear messages about configuration discrepancies

### Error Handling
- **Missing State**: Continue with default configuration search with warning
- **State Corruption**: Graceful fallback to default configuration with error
- **Configuration Mismatch**: Warnings when derived config differs from expectations
- **Multiple Deployments**: Clear rules for which deployment state to use

## Use Cases

### Primary Use Case: Post-Deployment Scripts
```bash
# Deployment
./deploy-k0rdent.sh deploy --config config/k0rdent-baseline-westeu.yaml
# Deployment state contains: azure_location: "westeurope"

# Later operations
./bin/setup-azure-cluster-deployment.sh setup
# Script reads from state and uses westeurope configuration
# Output: "Using configuration from deployment state (westeurope)"
```

### Edge Cases
- **No State File**: Existing deployments continue working with default config
- **Corrupted State**: Fallback to default configuration with error message
- **Multiple Deployments**: Scripts use most recent deployment state
- **Development Environment**: Configurable behavior for development scenarios
