# Design: k0rdent 1.5.0 Regional Management Cluster Support

## Context

k0rdent 1.5.0 introduces the Region CRD and enhanced regional cluster capabilities, building on the foundation established in 1.4.0. This project currently uses k0rdent 1.1.1 and includes KOF regional cluster support for observability workloads. The upgrade to 1.5.0 enables a new architectural pattern: **k0rdent regional management clusters** for infrastructure segregation.

### Key Distinctions

This implementation supports TWO distinct regional cluster types:

1. **k0rdent Regional Clusters** (NEW in this change)
   - Purpose: Segregate CAPI provider infrastructure and user ClusterDeployments
   - Components: Cert Manager, Velero, CAPI providers/operator, ClusterIdentity resources
   - Managed by: Region CRD in management cluster
   - Use case: Geographic distribution of infrastructure, security isolation

2. **KOF Regional Clusters** (EXISTING, separate feature)
   - Purpose: Observability and FinOps workloads
   - Components: KOF, Istio, monitoring, metrics collection
   - Managed by: KOF mothership
   - Use case: Multi-region observability aggregation

These are **independent features** that can be deployed separately or together.

## Goals / Non-Goals

### Goals
- Support k0rdent 1.5.0 regional management cluster architecture
- Enable deployment of multiple k0rdent regional clusters across Azure regions
- Maintain clear separation between k0rdent regional and KOF regional features
- Provide configuration-driven regional cluster deployment
- Support both k0rdent-managed and external clusters as regional targets
- Implement credential and certificate propagation to regional clusters

### Non-Goals
- Backward compatibility with k0rdent 1.1.1 (breaking changes allowed)
- Automatic migration of existing deployments to regional architecture
- Combined k0rdent/KOF regional cluster management (they remain separate)
- Multi-cloud regional support in initial implementation (Azure only)
- Regional cluster failover or disaster recovery automation

## Architecture Overview

### Current Architecture (k0rdent 1.1.1)
```
┌─────────────────────────────────────────┐
│   Management Cluster (k0rdent 1.1.1)    │
│                                         │
│  ┌──────────┐  ┌────────────────────┐ │
│  │   KCM    │  │  CAPI Providers    │ │
│  │   KSM    │  │  ClusterDeployments│ │
│  │   Flux   │  │  User Workloads    │ │
│  └──────────┘  └────────────────────┘ │
└─────────────────────────────────────────┘

Optional KOF Regional (separate):
┌─────────────────────────────────────────┐
│   KOF Regional Cluster                  │
│   (Observability workloads)             │
└─────────────────────────────────────────┘
```

### Target Architecture (k0rdent 1.5.0)
```
┌──────────────────────────────────────────────────┐
│      Management Cluster (k0rdent 1.5.0)          │
│                                                  │
│  ┌──────────┐  ┌─────────────┐  ┌───────────┐ │
│  │   KCM    │  │    KSM      │  │   Flux    │ │
│  │  Region  │  │ Credentials │  │ Templates │ │
│  │   CRD    │  │  Templates  │  │           │ │
│  └──────────┘  └─────────────┘  └───────────┘ │
│                                                  │
│  Manages Regional Clusters via Region CRD       │
└──────────────────────────────────────────────────┘
            │                        │
            ▼                        ▼
┌────────────────────────┐  ┌────────────────────────┐
│  k0rdent Regional      │  │  k0rdent Regional      │
│  Cluster (US East)     │  │  Cluster (West EU)     │
│                        │  │                        │
│  ┌─────────────────┐  │  │  ┌─────────────────┐  │
│  │ CAPI Providers  │  │  │  │ CAPI Providers  │  │
│  │ ClusterIdentity │  │  │  │ ClusterIdentity │  │
│  │ Cert Manager    │  │  │  │ Cert Manager    │  │
│  │ Velero          │  │  │  │ Velero          │  │
│  └─────────────────┘  │  │  └─────────────────┘  │
│                        │  │                        │
│  User ClusterDeployments│  │ User ClusterDeployments│
└────────────────────────┘  └────────────────────────┘

Optional KOF Regional (independent):
┌────────────────────────┐  ┌────────────────────────┐
│  KOF Regional          │  │  KOF Regional          │
│  Cluster (US East)     │  │  Cluster (West EU)     │
│  (Observability)       │  │  (Observability)       │
└────────────────────────┘  └────────────────────────┘
```

## Decisions

### Decision 1: Separate k0rdent and KOF Regional Implementations

**Rationale**: k0rdent regional and KOF regional serve fundamentally different purposes and have different lifecycles. Keeping them separate provides:
- Clear separation of concerns (infrastructure vs observability)
- Independent deployment and upgrade paths
- Flexibility to deploy one without the other
- Reduced complexity in configuration and state management

**Implementation**:
- Create `bin/install-k0rdent-regional.sh` for k0rdent regional clusters
- Keep existing `bin/install-kof-regional.sh` unchanged (with documentation clarifications)
- Add separate configuration sections in YAML for each type
- Maintain independent state tracking for each regional type

**Alternatives Considered**:
- **Combined Regional Cluster**: Deploy both k0rdent and KOF components to same regional cluster
  - Rejected: Reduces flexibility, couples unrelated concerns, complicates configuration
- **Unified Regional Script**: Single script handling both types
  - Rejected: Violates separation of concerns, harder to maintain, confusing for users

### Decision 2: Configuration-Driven Regional Cluster Deployment

**Rationale**: Regional cluster configuration should be declarative, version-controlled, and support multiple regions without code changes.

**Implementation**:
```yaml
software:
  k0rdent:
    version: "1.5.0"
    regional:
      enabled: false  # Opt-in
      clusters:
        - name: "regional-useast"
          location: "eastus"
          cluster_deployment_ref: "regional-cluster-useast"
          credential_propagation: true
          components:
            cert_manager: true
            velero: true
            capi_providers: true

        - name: "regional-westeu"
          location: "westeu"
          kubeconfig_secret: "external-westeu-cluster"
          credential_propagation: true
          components:
            cert_manager: true
            velero: true
            capi_providers: true
```

**Alternatives Considered**:
- **Script Arguments**: Pass regional configuration via command-line flags
  - Rejected: Not version-controlled, hard to manage multiple regions, error-prone
- **Separate YAML per Region**: One configuration file per regional cluster
  - Rejected: Harder to maintain consistency, no single source of truth

### Decision 3: Support Both k0rdent-Managed and External Regional Clusters

**Rationale**: k0rdent 1.5.0 supports both scenarios - regional clusters can be ClusterDeployments managed by k0rdent, or external clusters accessed via kubeconfig. Supporting both provides maximum flexibility.

**Implementation**:
- `cluster_deployment_ref`: Reference to k0rdent ClusterDeployment (preferred for new deployments)
- `kubeconfig_secret`: Reference to secret containing kubeconfig for external cluster
- Validation ensures only one is specified per regional cluster
- State management tracks which type is used

**Alternatives Considered**:
- **k0rdent-Managed Only**: Only support ClusterDeployments
  - Rejected: Limits integration with existing infrastructure
- **External Only**: Only support external clusters via kubeconfig
  - Rejected: Misses k0rdent's native cluster management capabilities

### Decision 4: Reuse Maximum Code from Existing Infrastructure

**Rationale**: This project follows a "maximum reuse" principle. Regional cluster deployment should leverage existing k0rdent infrastructure, common functions, and deployment patterns.

**Implementation**:
- Regional cluster deployment uses existing `create-child.sh` script
- Common functions from `common-functions.sh` for all operations
- State management via existing `state-management.sh` patterns
- Configuration parsing through `config-resolution-functions.sh`
- Only k0rdent-regional-specific logic in new files

**Example**:
```bash
#!/usr/bin/env bash
# bin/install-k0rdent-regional.sh

# Load ALL existing k0rdent infrastructure (maximum reuse)
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh
source ./etc/state-management.sh
source ./etc/k0rdent-regional-functions.sh  # ONLY regional-specific functions
```

### Decision 5: Phased Deployment with State Tracking

**Rationale**: Regional cluster deployment involves multiple phases (create cluster, install components, configure credentials). State tracking enables resume-on-failure and provides clear progress visibility.

**Implementation**:
```yaml
phases:
  - install_k0rdent_regional_useast
  - install_k0rdent_regional_westeu
  - configure_regional_credentials
  - deploy_regional_components

state:
  k0rdent_regional_clusters:
    - name: "regional-useast"
      deployed: true
      kubeconfig: "./k0sctl-config/regional-useast-kubeconfig"
      components:
        cert_manager: true
        velero: true
    - name: "regional-westeu"
      deployed: false
```

**Alternatives Considered**:
- **Monolithic Deployment**: Deploy all regional clusters and components in single operation
  - Rejected: No resume capability, poor error handling, hard to debug
- **Manual Phase Management**: Require operator to manually track phases
  - Rejected: Error-prone, inconsistent with existing deployment scripts

## Component Details

### 1. k0rdent 1.5.0 Upgrade Components

**Updated Components** (from k0rdent 1.5.0 release notes):
- Cluster API: v1.9.7 → v1.11.2
- CAPA (Azure): v1.19.4 → v1.21.0
- CAPG (GCP): v1.8.1 → v1.10.0
- CAPV (vSphere): v1.13.0 → v1.14.0
- k0smotron: v1.5.2 → v1.9.0
- Projectsveltos: v0.54.0 → v1.1.1

**New Features** (relevant to this change):
- Region CRD and controller for regional cluster management
- Credential cluster identity distribution to regions
- Certificate secret propagation to regional clusters
- Regional telemetry collection
- ClusterDeployment reference in Region spec

### 2. Regional Cluster Deployment Functions

**Location**: `etc/k0rdent-regional-functions.sh`

**Key Functions**:
```bash
# Check if k0rdent regional is enabled
check_k0rdent_regional_enabled()

# Get regional cluster configuration
get_k0rdent_regional_config()

# Deploy regional cluster (k0rdent-managed or external)
deploy_k0rdent_regional_cluster()

# Install regional components (cert-manager, velero, CAPI)
install_regional_components()

# Propagate credentials to regional cluster
propagate_credentials_to_region()

# Validate regional cluster readiness
validate_regional_cluster_ready()
```

### 3. Regional Cluster State Management

**State Schema**:
```yaml
k0rdent_regional:
  enabled: true
  version: "1.5.0"
  clusters:
    - name: "regional-useast"
      location: "eastus"
      type: "cluster_deployment"  # or "external"
      deployed: true
      region_crd_created: true
      credentials_propagated: true
      components:
        cert_manager: "1.12.0"
        velero: "1.11.0"
        capi_operator: "0.19.0"
      kubeconfig_path: "./k0sctl-config/regional-useast-kubeconfig"
      events:
        - timestamp: "2025-11-10T10:00:00Z"
          event: "regional_cluster_created"
        - timestamp: "2025-11-10T10:05:00Z"
          event: "components_installed"
```

## Risks / Trade-offs

### Risk 1: Breaking Change Impact
**Risk**: k0rdent 1.5.0 upgrade may break existing deployments or require manual intervention.

**Mitigation**:
- Document all breaking changes in proposal
- Provide upgrade checklist and migration steps
- Test upgrade path in development environment
- No backward compatibility requirement per project guidelines

**Impact**: MEDIUM - Breaking changes expected but acceptable per project policy

### Risk 2: Credential Propagation Security
**Risk**: Propagating Azure credentials to multiple regional clusters increases security surface area.

**Mitigation**:
- Use k0rdent's native credential propagation mechanisms
- Support Azure ClusterIdentity for federated credentials
- Encrypt credentials in transit and at rest
- Document security best practices for regional deployments

**Impact**: MEDIUM - Requires careful credential management but follows k0rdent patterns

### Risk 3: Regional Cluster State Synchronization
**Risk**: State inconsistency between management cluster and regional clusters if deployments fail partially.

**Mitigation**:
- Implement robust phase-based deployment with rollback
- Use Region CRD status conditions for source of truth
- Implement validation checks before marking phases complete
- Support manual state reset and recovery operations

**Impact**: MEDIUM - State management complexity increases with regional clusters

### Risk 4: KOF 1.5.0 Dependency
**Risk**: k0rdent 1.5.0 notes indicate waiting for KOF 1.5.0 if using kof-istio, but KOF 1.5.0 may not be released yet.

**Mitigation**:
- Check KOF release status before k0rdent 1.5.0 upgrade
- Document KOF upgrade requirement in implementation plan
- Support independent k0rdent regional deployment (without KOF)
- Provide clear error messages if KOF version incompatibility detected

**Impact**: HIGH - May block k0rdent 1.5.0 upgrade if KOF dependency exists

## Migration Plan

### Phase 1: k0rdent 1.5.0 Upgrade (Without Regional)
1. Review current k0rdent 1.1.1 configuration and state
2. Check KOF version compatibility (if KOF is enabled)
3. Update k0rdent version in configuration: `1.1.1` → `1.5.0`
4. Run `./bin/install-k0rdent.sh deploy` to upgrade management cluster
5. Verify k0rdent 1.5.0 installation and Region CRD availability
6. Test existing ClusterDeployment functionality

**Rollback**: Redeploy management cluster with k0rdent 1.1.1 from backup state

### Phase 2: Configure k0rdent Regional Clusters
1. Add regional cluster configuration to YAML:
   ```yaml
   software.k0rdent.regional.enabled: true
   software.k0rdent.regional.clusters: [...]
   ```
2. Validate configuration: `./bin/configure.sh validate`
3. Review regional cluster placement (Azure regions, VM sizes)
4. Plan credential propagation strategy

**Rollback**: Remove regional configuration, no deployment changes yet

### Phase 3: Deploy First k0rdent Regional Cluster
1. Enable regional deployment for single region (e.g., eastus)
2. Run `./bin/install-k0rdent-regional.sh deploy`
3. Monitor regional cluster creation via Region CRD status
4. Verify component installation (cert-manager, velero, CAPI)
5. Test credential propagation
6. Deploy test ClusterDeployment to regional cluster

**Rollback**: Delete Region CRD, remove regional cluster ClusterDeployment

### Phase 4: Deploy Additional Regional Clusters
1. Add additional regional cluster configurations
2. Deploy each regional cluster sequentially
3. Verify credential propagation to all regions
4. Test ClusterDeployment placement across regions

**Rollback**: Delete specific Region CRDs, preserve others

### Phase 5: (Optional) Deploy KOF Regional Clusters
1. Configure KOF regional clusters (separate from k0rdent regional)
2. Deploy using existing `./bin/install-kof-regional.sh`
3. Verify KOF observability across k0rdent regional clusters

**Rollback**: Uninstall KOF regional using existing uninstall procedure

## Open Questions

1. **KOF 1.5.0 Release Timeline**: When will KOF 1.5.0 be released? Can we proceed with k0rdent 1.5.0 upgrade without it?
   - Resolution: Check GitHub releases, coordinate with KOF team, document wait requirement

2. **Azure Region Limitations**: Are there Azure-specific limitations for regional cluster deployment (quotas, VM sizes, network configuration)?
   - Resolution: Test in target Azure regions, document region-specific requirements

3. **Regional Cluster Sizing**: What VM sizes and node counts should be recommended for regional clusters?
   - Resolution: Provide multiple configuration templates (minimal, production), document scaling considerations

4. **Credential Rotation**: How should credential rotation be handled across multiple regional clusters?
   - Resolution: Document manual rotation procedure, consider automation in future enhancement

5. **Regional Cluster Naming**: Should regional cluster names include location/region suffix? What naming convention?
   - Resolution: Use pattern `k0rdent-regional-{clusterid}-{location}` for consistency

6. **Multi-Region Kubeconfig**: Should we combine multiple regional kubeconfigs or keep separate files?
   - Resolution: Keep separate files for clarity, document kubectl context switching

7. **Regional Cluster Deletion**: What's the proper cleanup order when removing regional clusters?
   - Resolution: Delete ClusterDeployments first, then Region CRD, then cleanup Azure resources

## Implementation Phases

### Phase A: Core k0rdent 1.5.0 Upgrade
- Update k0rdent version configuration
- Modify installation scripts for 1.5.0
- Update Helm chart references
- Test upgrade path

### Phase B: Regional Configuration Support
- Add regional cluster YAML schema
- Implement config parsing functions
- Add state management for regional clusters
- Validation for regional configuration

### Phase C: Regional Cluster Deployment
- Implement regional cluster creation (k0rdent-managed)
- Support external cluster integration
- Component installation automation
- Credential propagation

### Phase D: Multi-Regional Coordination
- Support multiple regional clusters
- Regional cluster status monitoring
- Cross-region credential management
- Documentation and examples

### Phase E: Testing & Documentation
- Create test configurations
- Document upgrade procedures
- Provide regional deployment examples
- Troubleshooting guide
