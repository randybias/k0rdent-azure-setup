# CLAUDE.md - Development Guidelines

This file documents the established patterns, conventions, and best practices for the k0rdent Azure setup project. Use this as a reference when making changes or extending functionality.

# DEVELOPER DIRECTIVES

- Do NOT run tests without confirmation
- Ask before using git commit -A as frequently in this directory there are transient files we do NOT want to commit
- When planning infrastructure, follow the pets vs cattle methodology and consider most cloud instances as cattle who can be easily replaced and that is the better solution than trying to spending excessive amounts of time troubleshooting transient problems

## Development Environment

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