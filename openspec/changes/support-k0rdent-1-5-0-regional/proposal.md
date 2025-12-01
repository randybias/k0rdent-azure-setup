# Change: Support k0rdent 1.5.0 Regional Management Clusters

## Why

k0rdent 1.5.0 introduces **regional management clusters** - a critical architectural improvement that allows organizations to distribute workloads and provider infrastructure across geographic regions. The regional cluster feature (introduced in 1.4.0, enhanced in 1.5.0) provides:

1. **Geographic Distribution**: Deploy user workloads and CAPI provider infrastructure in separate regional clusters while maintaining centralized management
2. **Security & Networking Isolation**: Separate hosted control plane pods from the management cluster for improved security posture
3. **Scalability**: Prevent management cluster resource contention by offloading provider-related infrastructure to regional clusters

Currently, this project:
- Uses k0rdent 1.1.1 (released June 2025)
- Has KOF regional cluster support (separate feature for KOF observability)
- Lacks support for k0rdent's native regional management cluster architecture

The upgrade to k0rdent 1.5.0 is essential to leverage these architectural improvements and align with the latest k0rdent capabilities.

## What Changes

### Core Changes
- **BREAKING**: Upgrade k0rdent from 1.1.1 to 1.5.0
  - Update Helm chart references and installation scripts
  - Adapt to CAPI v1.11.2 and updated provider versions
  - Implement Region CRD support for regional cluster management

- **NEW**: k0rdent Regional Management Cluster Support
  - Configure and deploy k0rdent regional clusters (separate from KOF regional)
  - Credential distribution to regional clusters
  - ClusterDeployment regional placement
  - Certificate secret propagation to regions

- **ENHANCED**: Distinguish k0rdent Regional from KOF Regional
  - k0rdent regional: Infrastructure segregation (CAPI providers, ClusterDeployments)
  - KOF regional: Observability and FinOps workloads
  - Support independent or combined deployment of both types

- **NEW**: Multi-Regional Configuration Management
  - YAML configuration for multiple regional clusters
  - Regional cluster deployment automation
  - Credential and certificate management across regions

### Configuration Structure
```yaml
software:
  k0rdent:
    version: "1.5.0"  # BREAKING: Updated from 1.1.1

    # NEW: k0rdent regional management cluster configuration
    regional:
      enabled: false  # Opt-in feature
      clusters:
        - name: "regional-useast"
          location: "eastus"
          cluster_deployment_ref: "regional-cluster-useast"  # Reference to k0rdent-managed cluster
          # OR
          kubeconfig_secret: "external-cluster-kubeconfig"  # Reference to external cluster
          credential_propagation: true
          components:
            cert_manager: true
            velero: true
            capi_providers: true

# KOF regional configuration (separate, existing feature)
kof:
  enabled: false
  regional:
    # Existing KOF regional configuration for observability
```

## Impact

### Affected Specs
- **NEW**: `k0rdent-regional-management` - k0rdent regional cluster deployment and management
- **NEW**: `multi-regional-coordination` - Coordinating multiple regional clusters
- **MODIFIED**: `kof-regional-management` - Clarify distinction from k0rdent regional

### Affected Code
- `etc/config-resolution-functions.sh` - Add k0rdent regional config parsing
- `bin/install-k0rdent.sh` - Update to k0rdent 1.5.0 installation
- `bin/install-k0rdent-regional.sh` - NEW: Deploy k0rdent regional clusters
- `bin/install-kof-regional.sh` - CLARIFY: KOF regional (separate from k0rdent regional)
- `config/k0rdent-default.yaml` - Add k0rdent regional configuration schema
- `etc/state-management.sh` - Add regional cluster state tracking

### Breaking Changes
- **BREAKING**: k0rdent version upgrade 1.1.1 → 1.5.0
  - No backward compatibility required (per project guidelines)
  - May require Helm chart updates for dependent services
  - CAPI provider version changes (v1.9.7 → v1.11.2)

- **BREAKING**: New required KOF dependency
  - v1.5.0 requires waiting for KOF 1.5.0 before upgrading if using kof-istio
  - Coordination needed between k0rdent and KOF upgrades

### Migration Path
1. Review current k0rdent 1.1.1 deployment
2. Upgrade k0rdent to 1.5.0 (mothership cluster)
3. Optionally configure k0rdent regional clusters
4. Optionally configure KOF regional clusters (independent from k0rdent regional)
5. Deploy regional clusters using new installation scripts

### Non-Breaking Enhancements
- k0rdent regional cluster support is opt-in (disabled by default)
- Existing single-management-cluster deployments continue to work
- KOF regional functionality remains independent and optional
