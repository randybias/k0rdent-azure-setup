# Specification: KOF Istio Integration

## Purpose
Define how KOF (K0rdent Operations Framework) discovers, validates, and uses Istio service mesh provided by k0rdent 1.5.0 management cluster, eliminating the need for KOF to manage its own Istio installation.

## ADDED Requirements

### Requirement: Istio Discovery
KOF SHALL discover and validate k0rdent-managed Istio before proceeding with installation.

#### Scenario: k0rdent Istio fully deployed
**Given** k0rdent 1.5.0 has deployed Istio to the management cluster
**And** Istio namespace `istio-system` exists
**And** istiod deployment is ready with replicas >= 1
**When** KOF installation begins
**Then** KOF SHALL detect the existing Istio installation
**And** SHALL validate Istio is ready for use
**And** SHALL proceed with KOF deployment using k0rdent's Istio

#### Scenario: k0rdent Istio not ready
**Given** k0rdent 1.5.0 is deployed
**But** Istio namespace does not exist OR istiod is not ready
**When** KOF installation begins
**Then** KOF SHALL detect missing or not-ready Istio
**And** SHALL fail installation with clear error message
**And** error message SHALL specify which Istio component is missing/not-ready
**And** error message SHALL provide remediation steps

#### Scenario: k0rdent not deployed
**Given** k0rdent has not been deployed to the cluster
**When** KOF installation begins
**Then** KOF SHALL detect absence of k0rdent infrastructure
**And** SHALL fail installation with error indicating k0rdent prerequisite
**And** error message SHALL specify k0rdent 1.5.0+ is required

### Requirement: Istio Validation Logic
KOF SHALL implement comprehensive validation of k0rdent's Istio installation before using it.

#### Scenario: Complete Istio validation
**Given** KOF is validating k0rdent's Istio
**When** validation executes
**Then** KOF SHALL check namespace `istio-system` exists
**And** SHALL check deployment `istiod` exists in `istio-system`
**And** SHALL check istiod has at least 1 ready replica
**And** SHALL check service `istio-ingressgateway` exists in `istio-system`
**And** SHALL complete validation within 60 seconds
**And** SHALL return validation status with specific component results

#### Scenario: Validation timeout handling
**Given** KOF is validating k0rdent's Istio
**And** some Istio component is slow to become ready
**When** validation exceeds 60 second timeout
**Then** KOF SHALL fail validation with timeout error
**And** error message SHALL indicate which component timed out
**And** SHALL suggest checking k0rdent deployment status

### Requirement: No Istio Installation by KOF
KOF SHALL NOT install, configure, or manage Istio lifecycle.

#### Scenario: KOF installation without Istio management
**Given** k0rdent 1.5.0 Istio is validated and ready
**When** KOF installation proceeds
**Then** KOF SHALL NOT execute Istio Helm chart installation
**And** SHALL NOT create or modify Istio namespace
**And** SHALL NOT configure Istio components
**And** SHALL only use existing Istio resources

#### Scenario: KOF uninstallation preserves Istio
**Given** KOF is installed and using k0rdent's Istio
**When** KOF uninstallation executes
**Then** KOF SHALL remove its own resources
**And** SHALL NOT remove Istio namespace
**And** SHALL NOT uninstall Istio Helm releases
**And** SHALL NOT delete Istio deployments or services
**And** SHALL log that Istio is managed by k0rdent and preserved

### Requirement: Istio Namespace Labeling
KOF SHALL enable Istio injection for its namespace to integrate with the service mesh.

#### Scenario: KOF namespace prepared for Istio
**Given** k0rdent Istio is validated
**When** KOF prepares its namespace (default: `kof`)
**Then** KOF SHALL create namespace if not exists
**And** SHALL apply label `istio-injection=enabled` to the namespace
**And** SHALL verify label is set correctly
**And** SHALL fail if namespace labeling fails with clear error

#### Scenario: Existing KOF namespace with Istio injection
**Given** KOF namespace already exists
**And** namespace already has `istio-injection=enabled` label
**When** KOF prepares its namespace
**Then** KOF SHALL detect existing label
**And** SHALL not fail or overwrite
**And** SHALL proceed with installation

### Requirement: Clear Error Messaging
KOF SHALL provide actionable error messages when Istio validation fails.

#### Scenario: Missing Istio namespace error
**Given** `istio-system` namespace does not exist
**When** KOF validates Istio
**Then** error message SHALL state "Istio not found in istio-system namespace"
**And** SHALL state "k0rdent 1.5.0 Istio not deployed or not ready"
**And** SHALL provide action "Verify k0rdent deployment completed successfully"
**And** SHALL provide check command "kubectl get namespace istio-system"

#### Scenario: istiod not ready error
**Given** `istio-system` namespace exists
**But** istiod deployment has 0 ready replicas
**When** KOF validates Istio
**Then** error message SHALL state "Istio control plane (istiod) not ready"
**And** SHALL show current replica status
**And** SHALL provide check command "kubectl get deployment -n istio-system istiod"
**And** SHALL suggest waiting for k0rdent deployment to complete

#### Scenario: Missing ingress gateway error
**Given** istiod is ready
**But** istio-ingressgateway service does not exist
**When** KOF validates Istio
**Then** error message SHALL state "Istio ingress gateway not found"
**And** SHALL provide check command "kubectl get service -n istio-system istio-ingressgateway"
**And** SHALL indicate this may affect KOF external access

### Requirement: Configuration Compatibility
KOF configuration SHALL no longer include Istio version or namespace settings.

#### Scenario: Legacy Istio configuration ignored
**Given** KOF configuration contains legacy Istio section:
```yaml
kof:
  istio:
    version: "1.1.0"
    namespace: "istio-system"
```
**When** KOF reads configuration
**Then** KOF SHALL ignore these Istio settings
**And** SHALL log warning that Istio is managed by k0rdent
**And** SHALL use k0rdent's Istio regardless of config values

#### Scenario: Clean KOF configuration
**Given** KOF configuration has no Istio section:
```yaml
kof:
  enabled: true
  version: "1.5.0"
  mothership:
    namespace: "kof"
```
**When** KOF reads configuration
**Then** KOF SHALL accept configuration without Istio section
**And** SHALL proceed with Istio discovery using k0rdent defaults

### Requirement: Installation Order Enforcement
KOF SHALL enforce that k0rdent 1.5.0+ is fully deployed before KOF installation.

#### Scenario: k0rdent 1.5.0 prerequisite check
**Given** KOF installation is initiated
**When** KOF checks prerequisites
**Then** KOF SHALL verify k0rdent namespace `kcm-system` exists
**And** SHALL verify k0rdent deployment is ready
**And** SHALL verify Istio is deployed and ready
**And** SHALL fail if any prerequisite is missing
**And** error message SHALL list all missing prerequisites

#### Scenario: Successful prerequisite validation
**Given** k0rdent 1.5.0 is fully deployed with Istio
**When** KOF checks prerequisites
**Then** all checks SHALL pass
**And** KOF SHALL log successful prerequisite validation
**And** SHALL proceed with KOF operator installation

## REMOVED Requirements

### Requirement: Istio Installation by KOF
**Removed**: KOF previously installed Istio via `install_istio_for_kof()` function using `oci://ghcr.io/k0rdent/kof/charts/kof-istio` Helm chart.

**Reason**: k0rdent 1.5.0 now manages Istio installation as part of management cluster deployment. KOF no longer needs or should install Istio.

**Migration**: Users must deploy k0rdent 1.5.0 before installing KOF. k0rdent handles Istio installation automatically.

### Requirement: Istio Version Configuration
**Removed**: KOF configuration previously specified Istio version:
```yaml
kof:
  istio:
    version: "1.1.0"
```

**Reason**: k0rdent 1.5.0 controls Istio version. KOF must use whatever version k0rdent provides.

**Migration**: Remove `kof.istio.version` from configuration files. k0rdent version determines Istio version.

### Requirement: Istio Namespace Configuration
**Removed**: KOF configuration previously specified Istio namespace:
```yaml
kof:
  istio:
    namespace: "istio-system"
```

**Reason**: k0rdent 1.5.0 uses standard `istio-system` namespace. No need for configuration.

**Migration**: Remove `kof.istio.namespace` from configuration files. KOF uses standard k0rdent Istio namespace.

### Requirement: Sveltos CRD Waiting
**Removed**: KOF previously waited for Sveltos CRDs before installing Istio, as Istio chart depended on Sveltos.

**Reason**: k0rdent 1.5.0 installs Istio as part of management cluster deployment, handling all dependencies. KOF no longer installs Istio.

**Migration**: KOF still depends on Sveltos for its own operations, but waiting for CRDs before Istio installation is no longer needed.

### Requirement: Istio Uninstallation by KOF
**Removed**: KOF previously uninstalled Istio during cleanup:
```bash
helm uninstall kof-istio -n istio-system --wait
```

**Reason**: k0rdent 1.5.0 manages Istio lifecycle. Removing Istio would break management cluster.

**Migration**: KOF uninstallation skips Istio cleanup. Users must remove Istio via k0rdent if desired.
