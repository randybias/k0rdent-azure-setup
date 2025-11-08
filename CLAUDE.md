<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# CLAUDE.md - Development Guidelines

This file documents the established patterns, conventions, and best practices for the k0rdent Azure setup project. Use this as a reference when making changes or extending functionality.

## Important Technical Notes

### Kubeconfig Retrieval from k0rdent
When k0rdent creates managed clusters, it stores their kubeconfigs as Secrets in the `kcm-system` namespace. To retrieve:
```bash
kubectl get secret <cluster-name>-kubeconfig -n kcm-system -o jsonpath='{.data.value}' | base64 -d > ./k0sctl-config/<cluster-name>-kubeconfig
```

### macOS WireGuard Interface Naming
On macOS, WireGuard interfaces are always named utun0 through utun9 (dynamically assigned), not by the configuration name. When using `wg show` on macOS, you must use the actual utun interface name, not the configuration name like "wgk0r5jkseel". The configuration name is only used by wg-quick to track which utun interface belongs to which configuration.

# DEVELOPER DIRECTIVES

- Do NOT run tests without confirmation
- Ask before using git commit -A as frequently in this directory there are transient files we do NOT want to commit
- When planning infrastructure, follow the pets vs cattle methodology and consider most cloud instances as cattle who can be easily replaced and that is the better solution than trying to spending excessive amounts of time troubleshooting transient problems

## Development Environment

### Unbound Variable Prevention (CRITICAL)

**THIS IS NON-NEGOTIABLE: Follow these patterns to prevent unbound variable errors forever.**

#### The Problem
Scripts fail with "unbound variable" errors when using `set -u` or when variables are not initialized. This happens repeatedly across the codebase and MUST BE PREVENTED.

#### The Standard Pattern

**1. ALWAYS Use Safe Variable Access**
```bash
# WRONG - will fail if VAR is unset
if [[ $VAR -eq 1 ]]; then

# CORRECT - safe with default value
if [[ ${VAR:-1} -eq 1 ]]; then

# CORRECT - initialize first
VAR=${VAR:-1}
if [[ ${VAR} -eq 1 ]]; then
```

**2. ALWAYS Filter Null Values from YAML**
```bash
# WRONG - exports null as literal string
eval "$(yq eval '.config | to_entries | .[] | "export " + (.key | upcase) + "=" + .value' file.yaml)"

# CORRECT - filters out null values
eval "$(yq eval '.config | to_entries | .[] | select(.value != null) | "export " + (.key | upcase) + "=" + .value' file.yaml)"
```

**3. ALWAYS Use Helper Functions for YAML Export**
See `bin/configure.sh` for `safe_export()` and `safe_export_num()` helpers that automatically filter null values.

**4. ALWAYS Initialize Variables with Defaults**
```bash
# At the top of any script using configuration variables:
K0S_CONTROLLER_COUNT=${K0S_CONTROLLER_COUNT:-1}
K0S_WORKER_COUNT=${K0S_WORKER_COUNT:-1}
CONTROLLER_ZONES=("${CONTROLLER_ZONES[@]:-1}")
WORKER_ZONES=("${WORKER_ZONES[@]:-1}")
```

**5. NEVER Access Variables Directly in Conditionals**
```bash
# WRONG
if [[ $COUNT -gt 0 ]]; then

# CORRECT
COUNT=${COUNT:-0}
if [[ ${COUNT} -gt 0 ]]; then
```

#### Reference Implementations
- **etc/config-internal.sh**: All variables initialized with defaults before use
- **bin/configure.sh**: `safe_export()` and `safe_export_num()` helpers
- **etc/k0rdent-config.sh**: Null filtering in YAML loading

#### Testing Requirement
Before claiming any implementation is complete:
1. Test with `set -u` enabled
2. Test with missing/null YAML values
3. Test with deployment state loading
4. Verify no "unbound variable" errors in ANY scenario

**If you encounter an unbound variable error, FIX THE PATTERN EVERYWHERE, not just the one location.**

### Script Execution Timeouts

**Azure VM Creation Requirements**:
- When executing `create-azure-vms.sh` or any script that creates Azure VMs, use an extended timeout
- Allow at least 5 minutes per VM for creation (25-30 minutes for 5 VMs)
- Use `timeout` parameter of at least 1800000ms (30 minutes) when running these scripts
- VM provisioning on Azure can be slow and should not be prematurely terminated
- **New Async Implementation**: VMs are now created in parallel background processes with automatic failure recovery
- **Timeout Handling**: Individual VM creation timeouts are managed via `VM_CREATION_TIMEOUT_MINUTES` from YAML config
- **Monitoring Loop**: Single monitoring process checks all VM states every 30 seconds using bulk Azure API calls

**Azure VM Validation Requirements**:
- VM availability validation requires both `yq` and Azure CLI (`az`)
- Validation makes Azure API calls and can take 30-60 seconds per unique VM size
- Use `--skip-validation` flag when working offline or to speed up configuration creation
- Validation automatically runs after `configure.sh init` unless skipped

### Editor Configuration

**Always use vim editing mode** for consistency across development sessions:

```
vim
```

This ensures:
- Consistent editing experience across team members
- Familiar modal editing for efficient code manipulation
- Standardized keybindings and commands
- Better handling of shell script syntax and indentation

## Desktop Notifications (macOS)

### Overview
Desktop notifications provide real-time deployment status updates on macOS using native notifications.

### Usage
```bash
# Deploy with desktop notifications
./deploy-k0rdent.sh deploy --with-desktop-notifications
```

### Features
- **Real-time notifications**: Major deployment milestones trigger desktop alerts
- **Multi-instance support**: Separate notifiers for k0rdent, KOF, and child clusters
- **Grouped notifications**: Each deployment type has its own notification group
- **Duration tracking**: Completion notification shows total deployment time

### Architecture
- **Notifier daemon**: `bin/utils/desktop-notifier.sh` monitors event files
- **Event monitoring**: Polls YAML event files every 2 seconds
- **Instance isolation**: Each notifier has its own PID, log, and state files
- **Notification technology**: Uses `terminal-notifier` with `osascript` fallback

## KOF (K0rdent Operations Framework) Integration

### Overview
KOF is an optional component that can be installed after k0rdent deployment. The implementation follows the principle of maximum reuse - leveraging existing k0rdent infrastructure, configurations, and functions.

### Key Design Principles
1. **Configuration Reuse**: KOF configuration is part of existing k0rdent YAML files (no separate KOF config)
2. **Code Reuse**: All general functions come from `common-functions.sh` (only KOF-specific in `kof-functions.sh`)
3. **Pattern Reuse**: KOF scripts follow exact same patterns as k0rdent scripts
4. **No Duplication**: If it exists in k0rdent, reuse it

### KOF Functions (etc/kof-functions.sh)
Only KOF-specific functions are included:
- `check_kof_enabled()` - Check if KOF is enabled in configuration
- `get_kof_config()` - Get KOF configuration values from existing YAML
- `check_istio_installed()` - Check if Istio is installed
- `install_istio_for_kof()` - Install Istio for KOF
- `prepare_kof_namespace()` - Create and label KOF namespace
- `check_kof_mothership_installed()` - Check mothership installation
- `check_kof_operators_installed()` - Check operators installation

### Configuration Structure
KOF configuration is added to existing k0rdent YAML files:
```yaml
kof:
  enabled: false  # Disabled by default
  version: "1.1.0"
  istio:
    version: "1.1.0"
    namespace: "istio-system"
  # ... additional KOF settings
```

### Implementation Pattern
All KOF scripts follow the standard k0rdent pattern:
```bash
source ./etc/k0rdent-config.sh      # Loads everything including KOF config
source ./etc/common-functions.sh     # All common functionality
source ./etc/state-management.sh     # State tracking
source ./etc/kof-functions.sh        # Only KOF-specific additions
```

## Naming Conventions

### Cluster ID Pattern
- All resources use a consistent `K0RDENT_CLUSTERID` pattern (e.g., `k0rdent-abc123de`)
- The cluster ID is stored in `.clusterid` file
- WireGuard config files use pattern `wgk0${suffix}.conf` where suffix is extracted from cluster ID
- No more mixed PREFIX/SUFFIX terminology - everything is CLUSTERID now

## Configuration Management

### State-Based Configuration Resolution

All k0rdent scripts use a consistent, priority-based configuration resolution system that ensures configuration consistency across the entire deployment lifecycle.

#### Configuration Priority Order

Scripts resolve configuration in the following priority (highest to lowest):

1. **Explicit Override**: `K0RDENT_CONFIG_FILE` environment variable
   - For manual overrides and debugging
   - Example: `export K0RDENT_CONFIG_FILE="./config/test-config.yaml"`

2. **State-Based**: Configuration from `./state/deployment-state.yaml`
   - Canonical source of truth for deployed systems
   - Automatically used when available
   - Guarantees consistency with actual deployment

3. **Default Search**: `./config/k0rdent.yaml`
   - Fallback for backward compatibility
   - Used when state-based config is not available

4. **Template Fallback**: `./config/k0rdent-default.yaml`
   - Ultimate fallback for first-time setup

#### Configuration Transparency

Every script reports which configuration source is being used:

```bash
./bin/setup-azure-cluster-deployment.sh status
# Output: ==> Configuration source: deployment-state
```

Possible values:
- `deployment-state`: Using canonical state (recommended)
- `override`: Using K0RDENT_CONFIG_FILE override
- `default`: Using fallback config file
- `template`: Using template fallback

#### Configuration Tracking Variables

When configuration is loaded, these environment variables are set:

- `K0RDENT_CONFIG_SOURCE`: Which configuration source is being used
- `K0RDENT_CONFIG_FILE`: Path to the configuration file
- `K0RDENT_CONFIG_TIMESTAMP`: When configuration was last updated

#### When State-Based Config is Used

**Automatically Used**:
- All post-deployment scripts (setup, create-child, sync-state, etc.)
- When deployment state file exists with config section
- Ensures all operations use the same config as original deployment

**Not Used (Falls Back)**:
- Old deployments without config in state
- When deployment state file is missing or corrupted
- When K0RDENT_DEVELOPMENT_MODE is enabled

#### Development Mode

For development and testing workflows:

```bash
# Disable state-based configuration (use defaults)
export K0RDENT_DEVELOPMENT_MODE=true
./bin/setup-azure-cluster-deployment.sh status
# Uses default config files instead of state

# Force specific state file
export K0RDENT_DEVELOPMENT_STATE="./state/test-deployment-state.yaml"
./bin/setup-azure-cluster-deployment.sh status
# Uses specified state file

# Clear development overrides
unset K0RDENT_DEVELOPMENT_MODE
unset K0RDENT_DEVELOPMENT_STATE
```

#### Troubleshooting Configuration Issues

**Check Configuration Source**:
```bash
# Any script will report its configuration source
./bin/setup-azure-cluster-deployment.sh status | grep "Configuration source"

# Check deployment state config
yq eval '.config' ./state/deployment-state.yaml

# Verify configuration consistency
source ./etc/k0rdent-config.sh
echo "Source: $K0RDENT_CONFIG_SOURCE"
echo "Location: $AZURE_LOCATION"
```

**Common Issues**:

1. **Wrong Azure Region**: Check if script is using state-based config
   - Solution: Verify state file exists and has config section

2. **VM Size Mismatch**: Scripts using different sizes than deployment
   - Solution: Verify scripts report "deployment-state" as config source

3. **Feature Flag Issues**: Scripts assume features are enabled/disabled incorrectly
   - Solution: Check deployment_flags in state file

**Force Configuration Override** (Advanced):
```bash
# Temporarily override configuration for debugging
export K0RDENT_CONFIG_FILE="./config/correct-config.yaml"
./bin/setup-azure-cluster-deployment.sh setup
unset K0RDENT_CONFIG_FILE
```

#### Migration to State-Based Configuration

**New Deployments**: State-based configuration is automatically enabled

**Existing Deployments**: Continue working with default configuration (backward compatible)

Key points:
- 100% backward compatible with existing deployments
- New deployments automatically use state-based config
- No breaking changes to existing workflows
- Scripts gracefully fall back if state is not available

#### Related Documentation

- **OpenSpec Change**: `openspec/changes/canonical-config-from-state/`
  - Complete design documentation
  - Implementation tasks and status
  - Technical architecture details

## Azure Credential Cleanup and Reset Operations

### Azure Credentials Cleanup
The Azure credential cleanup system automatically detects and removes Service Principals during both full and fast reset operations:

```bash
# Automatic cleanup during deployment reset
./deploy-k0rdent.sh reset              # Cleans up SP + Kubernetes resources
./deploy-k0rdent.sh reset --fast          # Cleans up only Service Principal (no clusters to delete)
```

### Fast Reset Optimization
When using `--fast` reset, the cleanup system:
- ✅ **Skips Kubernetes operations** (cluster deleted with resource group)
- ✅ **Only cleans Azure Service Principal** (the only orphaned Azure resource)
- ✅ **Eliminates connection timeouts** (no "Unable to connect to server" errors)
- ✅ **Provides clear messaging** about what's being cleaned up

### Azure-Only Manual Cleanup
For troubleshooting specific Azure credential issues:

```bash
# Clean up only Azure Service Principal (skip Kubernetes)
./bin/setup-azure-cluster-deployment.sh cleanup --azure-only
```

### Service Principal Authentication Issues
If Service Principal authentication fails due to Azure propagation delays:

```bash
# Current implementation (5s wait, single attempt)
./bin/setup-azure-cluster-deployment.sh setup
# May fail: "Service Principal may need more time to propagate"

# Future improvement (retry logic - see OpenSpec proposal)
# Will retry with exponential backoff for up to 5 minutes
```

### Reset Integration
Both `deploy-k0rdent.sh reset` and `deploy-k0rdent.sh reset --fast` automatically integrate Azure credential cleanup:
- Detects when Azure credentials were configured
- Calls appropriate cleanup strategy based on reset type
- Provides clear status reporting and error handling
- Continues even if cleanup encounters issues
