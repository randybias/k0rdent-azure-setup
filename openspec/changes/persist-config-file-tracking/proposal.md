# Change Proposal: Persist Configuration File Tracking for Deployment Operations

**Created**: 2025-11-07  
**Author**: Droid (droid@factory.ai)  
**Status:** Draft  

## Summary

When users deploy k0rdent with a custom configuration file using `--config <file>`, the deployment state tracking system does not persist the configuration file path. Subsequent operations like reset, status, or cleanup default to using `./config/k0rdent.yaml`, which can lead to configuration mismatches or errors. This change ensures that the originally specified configuration file path is tracked and used consistently across all deployment operations.

## Problem Statement

Currently, when a deployment is initiated with:

```bash
./deploy-k0rdent.sh deploy --config config/k0rdent-baseline-westeu.yaml
```

The deployment completes successfully, but during reset:

1. **Lost Configuration Context**: The reset operation doesn't know which config file was originally used
2. **Wrong Configuration Loading**: Reset defaults to `./config/k0rdent.yaml` instead of the original file
3. **Potential Configuration Mismatch**: The default config may have different settings or may not exist at all
4. **Inconsistent Behavior**: Different deployment operations may use different configuration files

This affects not just reset operations, but any subsequent deployment-related operations that rely on configuration context.

## Proposed Solution

Enhance the deployment state tracking system to persist the configuration file path and ensure all deployment operations respect the originally specified configuration:

1. **Add configuration file tracking** to the deployment state file
2. **Update all deployment operations** to read and use the tracked configuration path
3. **Implement fallback logic** when the original config file is missing
4. **Add validation** to detect configuration file changes between operations

## Scope

**In Scope:**
- Configuration file path tracking in deployment-state.yaml
- Update all deployment operations to use tracked config file
- Fallback handling for missing configuration files
- Configuration change detection and warnings
- Backward compatibility for deployments without tracked config

**Out of Scope:**
- Multi-environment configuration management
- Configuration versioning or migration
- Dynamic configuration switching during operations
- Configuration file format changes

## Success Criteria

1. Deployments with custom configuration files persist the config path for later operations
2. Reset operations use the same configuration file as the original deployment
3. Clear warnings are provided when the original config file cannot be found
4. Backward compatibility is maintained for existing deployments
5. All deployment operations consistently use the tracked configuration

## Impact Analysis

- **User Experience**: More predictable and reliable deployment operations
- **Configuration Consistency**: Eliminates configuration mismatches between operations
- **Debugging Improves**: Easier to reproduce deployment issues with consistent configs
- **Risk**: Low - additive changes with robust fallback behavior

## Dependencies

- Existing deployment state tracking system (deployment-state.yaml)
- Configuration loading mechanism in etc/k0rdent-config.sh
- All deployment operations that currently use configuration files

## Considerations

- **Configuration File Movement**: Handle cases where original config file is moved or renamed
- **Configuration File Changes**: Detect when the config content differs from original deployment
- **Multiple Config Files**: Clear precedence when multiple config files exist
- **Development vs Production**: Support configuration file sharing between environments

## Use Cases

### Primary Use Case
```bash
# Initial deployment with custom config
./deploy-k0rdent.sh deploy --config config/k0rdent-baseline-westeu.yaml

# Reset automatically uses the same config
./deploy-k0rdent.sh reset
```

### Edge Cases
- Original configuration file moved to different location
- Configuration file content changed between deployment and reset
- Multiple configuration files with conflicting settings
