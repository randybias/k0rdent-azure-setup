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
See `backlog/docs/doc-004 - Kubeconfig-Retrieval.md` for detailed documentation.

### macOS WireGuard Interface Naming
On macOS, WireGuard interfaces are always named utun0 through utun9 (dynamically assigned), not by the configuration name. When using `wg show` on macOS, you must use the actual utun interface name, not the configuration name like "wgk0r5jkseel". The configuration name is only used by wg-quick to track which utun interface belongs to which configuration.

# DEVELOPER DIRECTIVES

- Do NOT run tests without confirmation
- Ask before using git commit -A as frequently in this directory there are transient files we do NOT want to commit
- When planning infrastructure, follow the pets vs cattle methodology and consider most cloud instances as cattle who can be easily replaced and that is the better solution than trying to spending excessive amounts of time troubleshooting transient problems

## Task Management Transition (2025-07-20)

**IMPORTANT**: We have fully migrated to using Backlog.md (https://github.com/MrLesk/Backlog.md) for all task management and documentation.

- **Old System**: Previously used `notebooks/BACKLOG.md` and various subdirectories
- **New System**: Now using the `backlog` CLI tool with structured directories:
  - `backlog/tasks/` - All project tasks (48 migrated)
  - `backlog/docs/` - Design specs, troubleshooting guides, references
  - `backlog/decisions/` - Architecture Decision Records (ADRs)
  - `backlog/completed/` - Historical implementation plans
- **Migration Date**: 2025-07-20
- **Usage**: Use `backlog` CLI commands for all task management (see guidelines below)

### Task Numbering Convention
- Tasks use **3-digit zero-padded integers** (e.g., task-001, task-056, task-100)
- Do NOT use decimal numbering (e.g., task-1.01) - this is reserved for subtasks
- When creating a new task without specifying `-p` (parent), it gets the next available integer
- Only use the `-p` flag when creating actual subtasks of an existing parent task

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

## Documentation and Decision Management

### Documentation (backlog/docs/)
- **Design Documents**: Store all design documents and architectural plans in `backlog/docs/`
- **Troubleshooting Guides**: Create troubleshooting documents with type: troubleshooting
- **Technical References**: API documentation, integration guides, etc.
- **Format**: Use `doc-XXX - Title.md` naming convention
- **Types**: design, troubleshooting, reference, guide, other

### Decisions (backlog/decisions/)
- **Architectural Decisions**: Record all key architectural decisions as ADRs (Architecture Decision Records)
- **Format**: Use `decision-XXX - Title.md` naming convention
- **Structure**: Context, Decision, Consequences
- **Status**: proposed, accepted, rejected, superseded
- **Purpose**: Maintain a history of why certain technical choices were made

### Directory Usage Guidelines
- **Tasks**: Use `backlog task create` for all new tasks and features
- **Troubleshooting**: Create docs in `backlog/docs/` with type: troubleshooting
- **Design Documents**: Create docs in `backlog/docs/` with type: design
- **Technical References**: Create docs in `backlog/docs/` with type: reference
- **Architecture Decisions**: Create ADRs in `backlog/decisions/`
- **DEPRECATED**: The notebooks/ directory has been removed

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
