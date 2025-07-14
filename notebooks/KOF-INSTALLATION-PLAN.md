# KOF (k0rdent Operations Framework) Installation Plan

## Current Status Assessment (2025-07-14)

### ✅ Completed Components

1. **KOF Mothership Installation** (`bin/install-kof-mothership.sh`)
   - Fully implemented with Istio service mesh installation
   - KOF operators deployment working
   - State tracking integrated
   - Uninstall functionality tested

2. **KOF Regional Cluster Deployment** (`bin/install-kof-regional.sh`)
   - Creates new k0rdent-managed Azure cluster
   - Applies KOF ClusterProfiles automatically
   - Kubeconfig retrieval automated
   - Monitoring and observability configured

3. **Azure Child Cluster Capability** (`bin/setup-azure-cluster-deployment.sh`)
   - Azure credentials configuration complete
   - ClusterDeployment CRDs working
   - Resource templates configured
   - Integration with k0rdent cluster management

4. **Child Cluster Integration** (`bin/create-child.sh`)
   - `--with-kof` flag implemented
   - Automatic ClusterProfile application for KOF-enabled children
   - Proper labeling for Istio integration

5. **Supporting Infrastructure**
   - Azure Disk CSI Driver installation (`bin/install-k0s-azure-csi.sh`)
   - KOF configuration in YAML files
   - State management integration
   - Common KOF functions library (`etc/kof-functions.sh`)

### ⏳ In Progress

1. **Documentation**
   - Need comprehensive KOF deployment guide
   - Update main README with KOF examples
   - Create troubleshooting guide for KOF issues

2. **Testing and Validation**
   - End-to-end deployment validation
   - Multi-child cluster testing
   - Observability data flow verification

### 🔲 Not Yet Implemented

1. **Orchestration Script** (`bin/deploy-kof-stack.sh`)
   - Would provide single command to deploy entire KOF stack
   - Include rollback capabilities
   - Support partial deployments

2. **Advanced Features**
   - Custom collector configurations
   - Multi-regional deployment support
   - Backup and restore capabilities

### Key Achievements

The core objective of having a working KOF installation system is **complete**. The system now supports:
- Installing KOF mothership on the management cluster
- Deploying a separate KOF regional cluster via k0rdent
- Creating child clusters with KOF functionality as an option
- Proper state tracking throughout the deployment lifecycle
- Clean uninstall/rollback capabilities

The implementation successfully follows the key principles:
- Maximum reuse of existing k0rdent infrastructure
- Modular, script-based approach
- Optional component model (KOF remains opt-in)
- Istio-based deployment for cloud agnosticity

## Overview

This plan outlines the implementation of KOF installation scripts for the k0rdent-azure-setup project. KOF will be an optional component that can be installed after k0rdent is deployed. The implementation will follow existing patterns and maintain separation between k0rdent and KOF.

The original installation instructions for KOF can be found at https://docs.k0rdent.io/latest/admin/kof/kof-install/

IMPORTANT: We are not using AWS or Azure for KOF.  We are ONLY using the Istio installation methodology.

## Key Implementation Principles - MAXIMUM REUSE

1. **Configuration Reuse**: KOF configuration will be added to existing k0rdent YAML files. NO separate KOF configuration files.
2. **Code Reuse**: All general functions come from existing common-functions.sh. Only KOF-specific functions go in kof-functions.sh.
3. **Infrastructure Reuse**: Use existing k0rdent-config.sh, state-management.sh, and all k0rdent variables without modification.
4. **Pattern Reuse**: Follow exact same script patterns as k0rdent scripts - no new patterns needed.
5. **No Duplication**: If a function exists in common-functions.sh, use it. Don't recreate it.

## IMPORTANT Istio Model Clarification

In the Istio deployment model, the `kof-istio` chart (installed on the management cluster) replaces the need for separate `kof-regional` and `kof-child` charts that are used in AWS/Azure models. However, we maintain separate scripts for regional and child installations to:
- Provide clear deployment stages and rollback points
- Manage ClusterProfiles for each cluster type
- Configure cluster-specific settings and labels
- Maintain consistency with the project's modular approach

 Note: Both regional and child clusters use the same label `k0rdent.mirantis.com/istio-role: child`. This is intentional per the KOF documentation - "child" is a generic term in the Istio deployment model that applies to all non-mothership clusters.

## Key Design Principles

1. **Optional Component**: KOF is optional - k0rdent must not depend on KOF
2. **Modular Scripts**: Separate scripts for each KOF installation type (mothership, regional, child)
3. **Consistent Patterns**: Follow existing script patterns from the project
4. **State Management**: Integrate with existing state management system
5. **Reversibility**: Each script must support install/uninstall operations
6. **Istio-based**: Use Istio deployment model (infrastructure-agnostic)
7. **Maximum Reuse**: Reuse all existing k0rdent configurations, functions, and infrastructure
8. **No Duplication**: KOF depends on k0rdent and reuses its code rather than duplicating

## Script Architecture

### 1. Primary Scripts (in `bin/` directory)

#### `bin/install-kof-mothership.sh` ✅ **IMPLEMENTED**
- Installs KOF on the k0rdent management cluster
- Commands: `deploy`, `uninstall`, `status`, `help`
- Prerequisites: k0rdent installed, VPN connected, Azure Disk CSI installed
- State tracking: Updates deployment-state.yaml with kof_mothership_installed
- Key features:
  - Installs Istio service mesh
  - Deploys KOF operators
  - Configures KOF mothership in `kof` namespace

#### `bin/install-kof-regional.sh` ✅ **IMPLEMENTED**
- Creates a new k0rdent-managed Azure cluster and installs KOF on it
- Commands: `deploy`, `uninstall`, `status`, `help`
- Prerequisites: KOF mothership installed, Azure child cluster capability configured
- State tracking: Updates deployment-state.yaml with kof_regional_deployed
- Key features:
  - Creates ClusterDeployment for new Azure cluster
  - Monitors cluster provisioning
  - Applies ClusterProfiles for KOF installation
  - Retrieves and saves kubeconfig
  - Configures observability/FinOps collection

#### KOF on Child Clusters (via `bin/create-child.sh`)
- KOF functionality for child clusters is integrated into the create-child.sh script
- Use `--with-kof` flag when creating child clusters to enable KOF
- Prerequisites: KOF regional deployed
- Automatically applies appropriate ClusterProfiles for KOF-enabled child clusters

### 2. Configuration Extension

KOF configuration will be added to existing k0rdent YAML files (k0rdent.yaml, k0rdent-default.yaml, and example configurations) rather than creating a separate file. This ensures KOF reuses the existing configuration loading mechanism.

#### Extension to existing k0rdent YAML files:
```yaml
# Added to existing k0rdent configuration files
# KOF section is optional and disabled by default
kof:
  enabled: false  # KOF is opt-in
  version: "1.1.0"

  # Istio configuration
  istio:
    version: "1.1.0"
    namespace: "istio-system"

  # Mothership configuration
  mothership:
    namespace: "kof"
    storage_class: "default"  # Can be customized
    collectors:
      global: {}  # Custom global collectors

  # Regional configuration
  regional:
    namespace: "kof"
    cluster_label: "k0rdent.mirantis.com/istio-role=child"  # Same label for both regional and child
    collectors: {}  # Custom regional collectors

  # Child configuration
  child:
    namespace: "kof"
    cluster_label: "k0rdent.mirantis.com/istio-role=child"  # Intentionally same as regional
    regional_cluster: ""  # Optional regional cluster connection
```

**Important**: No changes needed to `etc/k0rdent-config.sh` - it already loads the YAML configuration that will contain KOF settings.

### 3. Shared Functions Extension

#### `etc/kof-functions.sh` (new minimal file)
```bash
# KOF-specific shared functions
# This file contains ONLY functions specific to KOF that don't exist in common-functions.sh
# All general functions (error handling, logging, etc.) are reused from common-functions.sh

# Check if KOF is enabled in configuration
# Uses existing CONFIG_YAML loaded by k0rdent-config.sh
check_kof_enabled() {
    local kof_enabled
    kof_enabled=$(yq '.kof.enabled // false' "$CONFIG_YAML" 2>/dev/null || echo "false")
    [[ "$kof_enabled" == "true" ]]
}

# Get KOF configuration value
# Reuses existing CONFIG_YAML variable
get_kof_config() {
    local key="$1"
    local default="${2:-}"
    yq ".kof.$key // \"$default\"" "$CONFIG_YAML" 2>/dev/null || echo "$default"
}

# Check Istio installation
check_istio_installed() {
    kubectl get namespace istio-system &>/dev/null
}

# Install Istio for KOF
# Uses existing error handling from common-functions.sh
install_istio_for_kof() {
    local istio_version=$(get_kof_config "istio.version" "1.1.0")
    local istio_namespace=$(get_kof_config "istio.namespace" "istio-system")

    print_info "Installing Istio for KOF (version: $istio_version)"
    
    if helm upgrade -i --reset-values --wait \
        --create-namespace -n "$istio_namespace" kof-istio \
        oci://ghcr.io/k0rdent/kof/charts/kof-istio --version "$istio_version"; then
        print_success "Istio installed successfully"
        return 0
    else
        print_error "Failed to install Istio"
        return 1
    fi
}

# Create and label KOF namespace
# Reuses print functions from common-functions.sh
prepare_kof_namespace() {
    local namespace="${1:-kof}"
    print_info "Preparing KOF namespace: $namespace"
    
    if kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - && \
       kubectl label namespace "$namespace" istio-injection=enabled --overwrite; then
        print_success "KOF namespace prepared and labeled"
        return 0
    else
        print_error "Failed to prepare KOF namespace"
        return 1
    fi
}

# All other functions (check_vpn_connectivity, execute_remote_command, etc.) 
# are already available from common-functions.sh
```

## Implementation Plan

### Phase 1: Foundation (Week 1)

1. **Create minimal KOF functions library**
   - File: `etc/kof-functions.sh`
   - Include ONLY KOF-specific functions (Istio checks, namespace preparation)
   - Reuse all general functions from `common-functions.sh`
   - Add to CLAUDE.md for documentation

2. **Extend existing configuration files**
   - Add KOF section to `config/k0rdent-default.yaml` (disabled by default)
   - Add KOF examples to existing example configurations
   - NO changes to `etc/k0rdent-config.sh` - it already loads everything needed
   - NO separate KOF configuration file

3. **Use existing state management**
   - Use existing `update_state()` function to add KOF state fields
   - Track: kof_mothership_installed, kof_regional_installed, kof_child_installed
   - Use existing `add_event()` function for KOF events
   - NO new state management code needed

### Phase 2: Mothership Script (Week 2)

1. **Implement `bin/install-kof-mothership.sh`**
   ```bash
   #!/usr/bin/env bash

   # Script: install-kof-mothership.sh
   # Purpose: Install KOF mothership on k0rdent management cluster
   # Usage: bash install-kof-mothership.sh [deploy|uninstall|status|help]

   set -euo pipefail

   # Load ALL existing k0rdent infrastructure
   source ./etc/k0rdent-config.sh      # Loads CONFIG_YAML automatically
   source ./etc/common-functions.sh     # All common functionality
   source ./etc/state-management.sh     # State tracking
   source ./etc/kof-functions.sh        # ONLY KOF-specific additions

   # Reuse existing patterns:
   # - Use existing KUBECONFIG_FILE variable from k0rdent-config.sh
   # - Use existing argument parsing with parse_standard_args
   # - Use existing VPN connectivity check with check_vpn_connectivity
   # - Use existing print functions for output
   # - Use existing state management functions

   # Main functions:
   # - deploy_kof_mothership()
   # - uninstall_kof_mothership()
   # - show_kof_mothership_status()
   ```

2. **Deploy function logic**
   - Use existing `check_vpn_connectivity()` for VPN check
   - Use new `check_kof_enabled()` to verify KOF is enabled
   - Check k0rdent installation using existing state
   - Install Istio using `install_istio_for_kof()`
   - Create namespace using `prepare_kof_namespace()`
   - Install helm charts using existing patterns
   - Use `update_state()` and `add_event()` for state tracking

3. **Uninstall function logic**
   - Reuse existing prerequisite checks
   - Standard helm uninstall commands
   - Use existing confirmation prompts pattern
   - Update state using existing functions
   - Follow existing cleanup patterns

### Phase 3: Regional Script (Week 3)

1. **Implement `bin/install-kof-regional.sh`**
   - Similar structure to mothership script
   - Additional logic for cluster targeting
   - Support for multiple regional clusters
   - Cluster labeling with istio-role

2. **Key differences**
   - Requires mothership to be installed first
   - May target external clusters (not just management cluster)
   - Different helm charts or configurations
   - Regional-specific collectors

### Phase 4: Child Script (Week 3)

1. **Implement `bin/install-kof-child.sh`**
   - Similar structure to regional script
   - Support for connecting to specific regional cluster
   - Child-specific configuration

2. **Key features**
   - Can optionally specify regional cluster connection
   - Minimal installation footprint
   - Child-specific collectors

### Phase 5: Integration (Week 4)

1. **Create orchestration script (optional)**
   - `bin/deploy-kof-stack.sh` - deploys all KOF components in sequence
   - Support for partial deployments
   - Rollback capability

2. **Update documentation**
   - Add KOF section to README.md
   - Create `docs/KOF-DEPLOYMENT.md` guide
   - Update CLAUDE.md with KOF patterns

3. **Testing scripts**
   - `test/test-kof-deployment.sh`
   - Automated validation of KOF installation
   - Integration with existing test framework

## Script Patterns to Follow

### Standard Script Structure (Reusing k0rdent Patterns)
```bash
#!/usr/bin/env bash

# Script header with purpose and usage
set -euo pipefail

# Load ALL k0rdent infrastructure (exactly like k0rdent scripts)
source ./etc/k0rdent-config.sh      # This loads CONFIG_YAML automatically
source ./etc/common-functions.sh     # All error handling, printing, etc.
source ./etc/state-management.sh     # State tracking functions
source ./etc/kof-functions.sh        # ONLY KOF-specific additions

# Use existing variables from k0rdent-config.sh:
# - K0RDENT_PREFIX (deployment prefix)
# - KUBECONFIG_FILE (path to kubeconfig)
# - CONFIG_YAML (loaded configuration)
# - All other k0rdent variables

# Parse arguments using EXISTING function
PARSED_ARGS=$(parse_standard_args "$@")
eval "$PARSED_ARGS"

# Show usage function (uses existing print_usage)
show_usage() {
    print_usage "$0" \
        "  deploy     Install KOF component
  uninstall  Remove KOF component
  status     Show installation status
  help       Show this help message" \
        "  -y, --yes        Skip confirmation prompts
  --no-wait        Skip waiting for resources" \
        "  $0 deploy        # Install KOF
  $0 status        # Check status
  $0 uninstall     # Remove KOF"
}

# Use existing command handling pattern
handle_standard_commands "$0" "deploy uninstall status help" \
    "deploy" "deploy_kof_component" \
    "uninstall" "uninstall_kof_component" \
    "status" "show_kof_status" \
    "usage" "show_usage"
```

### State Management Integration (Using Existing Functions)
```bash
# All state management uses existing functions from state-management.sh
# No new state management code needed

# Update state after successful deployment
update_state "kof_mothership_installed" "true"
update_state "kof_mothership_version" "$KOF_VERSION"
add_event "kof_mothership_deployed" "KOF mothership v$KOF_VERSION deployed successfully"

# Update state after uninstall
update_state "kof_mothership_installed" "false"
remove_state_key "kof_mothership_version"
add_event "kof_mothership_uninstalled" "KOF mothership removed from cluster"

# Check state (using existing functions)
if [[ "$(get_state "k0rdent_installed")" != "true" ]]; then
    print_error "k0rdent must be installed first"
    exit 1
fi
```

### Error Handling Pattern (Using Existing Functions)
```bash
# All error handling uses existing functions and patterns

# Check prerequisites using existing functions
if [[ "$(get_state "k0rdent_installed")" != "true" ]]; then
    print_error "k0rdent must be installed before deploying KOF"
    print_info "Run: ./bin/install-k0rdent.sh deploy"
    exit 1
fi

# Use existing VPN connectivity check
if ! check_vpn_connectivity; then
    print_error "VPN connectivity required for KOF operations"
    print_info "Connect to VPN: ./bin/manage-vpn.sh connect"
    exit 1
fi

# Check KOF enabled (new KOF-specific check)
if ! check_kof_enabled; then
    print_error "KOF is not enabled in configuration"
    print_info "Set 'kof.enabled: true' in your k0rdent.yaml"
    exit 1
fi

# Error handling follows existing patterns from k0rdent scripts
```

## Configuration Management

### KOF Configuration Loading (NO CHANGES NEEDED)
```bash
# NO changes needed to etc/k0rdent-config.sh
# It already loads CONFIG_YAML which will contain KOF settings
# KOF scripts access configuration using existing CONFIG_YAML variable

# In KOF scripts, read config using yq from existing CONFIG_YAML:
KOF_ENABLED=$(yq '.kof.enabled // false' "$CONFIG_YAML")
KOF_VERSION=$(yq '.kof.version // "1.1.0"' "$CONFIG_YAML")
KOF_NAMESPACE=$(yq '.kof.mothership.namespace // "kof"' "$CONFIG_YAML")

# Or use the get_kof_config helper function:
KOF_VERSION=$(get_kof_config "version" "1.1.0")
KOF_NAMESPACE=$(get_kof_config "mothership.namespace" "kof")
```

### Environment Variables (Optional)
```bash
# KOF scripts can define local variables as needed
# No need for global exports unless required across scripts
# Use configuration values from YAML as the source of truth

# Example in KOF script:
local kof_namespace=$(get_kof_config "mothership.namespace" "kof")
local istio_namespace=$(get_kof_config "istio.namespace" "istio-system")
local kof_chart="oci://ghcr.io/k0rdent/kof/charts/kof-mothership"
```

## Testing Strategy

### Unit Tests
- Test KOF configuration parsing
- Test prerequisite checking functions
- Test state management integration

### Integration Tests
- Full deployment test (mothership → regional → child)
- Rollback test (child → regional → mothership)
- Failure recovery tests
- Multi-cluster deployment tests

### Validation Tests
- Verify Istio installation and configuration
- Verify KOF namespace labeling
- Verify helm chart deployments
- Check service connectivity

## Rollback Strategy

### Graceful Rollback Order
1. Uninstall child clusters first
2. Uninstall regional clusters
3. Uninstall mothership last
4. Optionally remove Istio (with confirmation)

### Force Rollback Option
- Add `--force` flag to uninstall commands
- Skip connectivity checks during force rollback
- Best-effort cleanup approach
- Log but don't fail on errors

## Future Enhancements

1. **Multi-cluster Management**
   - Support for multiple regional/child clusters
   - Cluster inventory management
   - Batch operations across clusters

2. **Configuration Profiles**
   - Development vs Production KOF profiles
   - Custom collector configurations per profile
   - Profile-based deployment strategies

3. **Monitoring Integration**
   - KOF health checks
   - Prometheus metrics collection
   - Alert configuration

4. **Backup and Restore**
   - KOF configuration backup
   - State backup before major operations
   - Restore capabilities

## Dependencies and Prerequisites

### External Dependencies
- Helm 3.x installed on management cluster
- kubectl with cluster access
- Istio-compatible Kubernetes version
- Network connectivity between clusters

### Internal Dependencies
- k0rdent successfully deployed
- VPN connectivity established
- State management system initialized
- Azure resources available

## Security Considerations

1. **RBAC Configuration**
   - Proper service account setup
   - Minimal required permissions
   - Namespace isolation

2. **Network Security**
   - Istio mTLS configuration
   - Service mesh security policies
   - Inter-cluster communication security

3. **Secret Management**
   - Secure storage of credentials
   - Rotation policies
   - Access controls

## Documentation Requirements

### User Documentation
- Quick start guide for KOF deployment
- Troubleshooting guide
- Configuration reference
- Best practices guide

### Developer Documentation
- Script architecture overview
- Function reference
- State management integration
- Testing procedures

## Success Criteria

1. **Functional Requirements**
   - All three KOF components can be deployed independently
   - Each component can be uninstalled cleanly
   - State is properly tracked throughout lifecycle
   - Errors are handled gracefully

2. **Non-Functional Requirements**
   - Scripts follow existing project patterns
   - KOF remains optional (no k0rdent dependencies)
   - Clear error messages and recovery guidance
   - Consistent user experience

3. **Quality Metrics**
   - All scripts pass shellcheck validation
   - Deployment success rate > 95%
   - Uninstall leaves no orphaned resources
   - Documentation coverage for all features

## Updated Implementation Plan - Azure Cluster Deployment Integration

### New Critical Requirement

Before proceeding with KOF regional deployment, we need to set up the k0rdent management cluster to deploy child clusters on Azure. This is required because:

1. **KOF Regional Clusters**: Need to be deployed as separate k0rdent-managed clusters
2. **k0rdent ClusterDeployment**: Management cluster must be able to spin up new Kubernetes clusters
3. **Azure Integration**: Requires Azure credentials and Service Principal setup

### New Implementation Phase - Azure Cluster Deployment Setup

**Phase 2.5: Azure Cluster Deployment Configuration** (Insert before Regional Script)

1. **Create Azure cluster deployment setup script** (`bin/setup-azure-cluster-deployment.sh`)
   - Configure k0rdent management cluster with Azure credentials
   - Create Azure Service Principal with contributor access
   - Create necessary Kubernetes secrets and resources
   - Setup AzureClusterIdentity and KCM Credential objects
   - Configure resource templates for cluster deployment

2. **Key Components to Implement**:
   - Azure Service Principal creation and management
   - Kubernetes secret creation in `kcm-system` namespace
   - AzureClusterIdentity resource creation
   - KCM Credential object setup
   - Resource template ConfigMap configuration
   - Cluster deployment capability testing

3. **Prerequisites**:
   - Azure CLI installed and authenticated
   - k0rdent management cluster operational
   - Appropriate Azure subscription permissions

### Modified Regional Deployment Approach

**Updated Phase 3: Regional Script** (Revised)

1. **Regional cluster deployment via k0rdent**:
   - Use k0rdent ClusterDeployment to spin up new Azure cluster
   - Deploy regional cluster using k0rdent's cluster management
   - Install KOF on the k0rdent-managed regional cluster
   - Configure regional cluster for KOF operations

2. **Key changes**:
   - Regional deployment now creates a separate k0rdent-managed cluster
   - KOF regional installation targets the new cluster
   - Child clusters can be deployed similarly using k0rdent

### Implementation Timeline (Revised)

- **Week 1**: Foundation and configuration system ✅ **COMPLETED**
- **Week 2**: Mothership script implementation ✅ **COMPLETED**
- **Week 2.5**: Azure cluster deployment setup ✅ **COMPLETED**
- **Week 3**: Regional script ✅ **COMPLETED**, Child cluster integration ✅ **COMPLETED**
- **Week 4**: Integration, testing, and documentation ⏳ **IN PROGRESS**

### New Script: `bin/setup-azure-cluster-deployment.sh`

**Purpose**: Configure k0rdent management cluster to deploy Azure child clusters

**Key Functions**:
- `setup_azure_credentials()` - Create Service Principal and secrets
- `configure_cluster_identity()` - Setup AzureClusterIdentity resources
- `create_resource_templates()` - Configure cluster deployment templates
- `test_cluster_deployment()` - Verify deployment capability
- `cleanup_azure_config()` - Remove Azure configuration

**Integration Points**:
- Reuses existing Azure authentication from k0rdent deployment
- Integrates with existing state management system
- Follows established script patterns and error handling
- Uses existing VPN connectivity for cluster operations

### Configuration Extensions

**Add to existing k0rdent YAML files**:
```yaml
# Azure cluster deployment configuration
cluster_deployment:
  enabled: false  # Opt-in feature
  azure:
    subscription_id: ""  # Will be populated during setup
    service_principal:
      client_id: ""
      client_secret: ""  # Stored in Kubernetes secret
      tenant_id: ""
    default_location: "westus2"
    default_vm_size: "Standard_D2s_v3"
    resource_group_prefix: "k0rdent-child"
```

This approach ensures that:
1. KOF regional clusters are properly managed by k0rdent
2. Child clusters can be deployed using the same mechanism
3. All cluster lifecycle management goes through k0rdent
4. Maintains consistency with k0rdent's cluster management philosophy

## Notes and Considerations

1. **Version Compatibility**
   - Track KOF version compatibility with k0rdent
   - Handle version upgrades gracefully
   - Maintain compatibility matrix

2. **Multi-Cloud Future**
   - Design with cloud abstraction in mind
   - Istio provides cloud-agnostic foundation
   - Consider provider-specific optimizations

3. **Operational Concerns**
   - Log aggregation for troubleshooting
   - Performance impact monitoring
   - Resource utilization tracking

This plan provides a comprehensive approach to implementing KOF installation while maintaining the project's established patterns and principles.
