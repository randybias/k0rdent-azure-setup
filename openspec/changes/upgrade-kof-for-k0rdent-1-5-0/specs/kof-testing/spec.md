# Specification: KOF Testing

## Purpose
Define comprehensive testing approach for KOF (K0rdent Operations Framework) with k0rdent 1.5.0 managed Istio, ensuring all KOF functionality works correctly with the new Istio integration model.

## ADDED Requirements

### Requirement: Istio Discovery Testing
KOF tests SHALL verify Istio discovery and validation logic under various conditions.

#### Scenario: Test Istio present and ready
**Given** test environment has k0rdent 1.5.0 with Istio fully deployed
**When** KOF Istio validation runs
**Then** test SHALL verify validation passes
**And** SHALL verify correct Istio namespace detected
**And** SHALL verify istiod deployment status checked
**And** SHALL verify ingress gateway service detected

#### Scenario: Test Istio namespace missing
**Given** test environment has no `istio-system` namespace
**When** KOF Istio validation runs
**Then** test SHALL verify validation fails
**And** SHALL verify error message contains "Istio not found"
**And** SHALL verify error includes remediation steps
**And** SHALL verify KOF installation does not proceed

#### Scenario: Test istiod not ready
**Given** test environment has `istio-system` namespace
**But** istiod deployment has 0 ready replicas
**When** KOF Istio validation runs
**Then** test SHALL verify validation fails
**And** SHALL verify error message contains "istiod not ready"
**And** SHALL verify error shows replica status
**And** SHALL verify KOF installation does not proceed

#### Scenario: Test ingress gateway missing
**Given** test environment has Istio namespace and istiod ready
**But** istio-ingressgateway service is missing
**When** KOF Istio validation runs
**Then** test SHALL verify validation fails with warning or error
**And** SHALL verify error message identifies missing gateway
**And** test SHALL document whether KOF can proceed without gateway

### Requirement: Mothership Installation Testing
KOF tests SHALL verify mothership installation works correctly with k0rdent Istio.

#### Scenario: Test mothership installation success
**Given** k0rdent 1.5.0 with Istio is deployed
**When** KOF mothership installation runs
**Then** test SHALL verify KOF namespace created with Istio injection label
**And** SHALL verify kof-operators Helm release installed
**And** SHALL verify kof-mothership Helm release installed
**And** SHALL verify mothership pods are running
**And** SHALL verify mothership uses Istio sidecar proxies
**And** SHALL verify no Istio installation attempted

#### Scenario: Test mothership installation without k0rdent Istio
**Given** k0rdent is deployed without Istio
**When** KOF mothership installation runs
**Then** test SHALL verify installation fails at Istio validation
**And** SHALL verify error message is clear and actionable
**And** SHALL verify no KOF components are installed

#### Scenario: Test mothership with custom storage class
**Given** k0rdent 1.5.0 with Istio is deployed
**And** custom storage class "fast-ssd" is configured
**When** KOF mothership installation runs
**Then** test SHALL verify mothership installed with custom storage class
**And** SHALL verify PVCs use specified storage class

### Requirement: Regional Cluster Testing
KOF tests SHALL verify regional cluster deployment works with k0rdent Istio.

#### Scenario: Test regional cluster deployment
**Given** KOF mothership is installed
**And** k0rdent Istio is available
**When** KOF regional cluster deployment runs
**Then** test SHALL verify regional cluster labels include Istio role
**And** SHALL verify regional cluster integrates with k0rdent Istio
**And** SHALL verify regional cluster pods have Istio proxies

#### Scenario: Test multiple regional clusters
**Given** KOF mothership is installed
**When** multiple regional clusters are deployed
**Then** test SHALL verify all clusters use same k0rdent Istio
**And** SHALL verify clusters have separate Istio configurations as needed
**And** SHALL verify inter-cluster communication via Istio

### Requirement: Uninstallation Testing
KOF tests SHALL verify uninstallation correctly removes KOF while preserving k0rdent Istio.

#### Scenario: Test KOF mothership uninstallation
**Given** KOF mothership is installed
**And** k0rdent Istio is in use
**When** KOF uninstallation runs
**Then** test SHALL verify kof-mothership Helm release removed
**And** SHALL verify kof-operators Helm release removed
**And** SHALL verify KOF namespace removed
**And** SHALL verify Istio namespace still exists
**And** SHALL verify istiod deployment still running
**And** SHALL verify no Istio resources deleted

#### Scenario: Test uninstallation with regional clusters
**Given** KOF mothership and regional clusters are installed
**When** KOF uninstallation runs
**Then** test SHALL verify all KOF resources removed
**And** SHALL verify regional cluster resources cleaned up
**And** SHALL verify k0rdent Istio unaffected

### Requirement: Configuration Compatibility Testing
KOF tests SHALL verify correct handling of Istio configuration in various scenarios.

#### Scenario: Test clean configuration without Istio section
**Given** KOF configuration has no `istio:` section
**When** KOF reads configuration
**Then** test SHALL verify configuration accepted
**And** SHALL verify KOF uses k0rdent Istio discovery
**And** SHALL verify installation proceeds normally

#### Scenario: Test legacy configuration with Istio section
**Given** KOF configuration includes legacy Istio settings:
```yaml
kof:
  istio:
    version: "1.1.0"
    namespace: "istio-system"
```
**When** KOF reads configuration
**Then** test SHALL verify Istio settings ignored
**And** SHALL verify warning logged about k0rdent-managed Istio
**And** SHALL verify KOF uses k0rdent Istio regardless
**And** SHALL verify installation succeeds

### Requirement: Error Message Testing
KOF tests SHALL verify error messages are clear, accurate, and actionable.

#### Scenario: Test error message for missing Istio namespace
**Given** Istio namespace does not exist
**When** KOF installation fails
**Then** test SHALL verify error message contains "Istio not found in istio-system namespace"
**And** SHALL verify error includes "k0rdent 1.5.0 Istio not deployed"
**And** SHALL verify error provides check command "kubectl get namespace istio-system"

#### Scenario: Test error message for istiod not ready
**Given** istiod has 0 ready replicas
**When** KOF installation fails
**Then** test SHALL verify error message contains "Istio control plane (istiod) not ready"
**And** SHALL verify error shows replica count (e.g., "0/1 ready")
**And** SHALL verify error provides check command "kubectl get deployment -n istio-system istiod"

### Requirement: End-to-End Testing
KOF tests SHALL include complete end-to-end scenarios with k0rdent 1.5.0.

#### Scenario: Test complete KOF deployment lifecycle
**Given** clean test environment
**When** E2E test executes
**Then** test SHALL deploy k0rdent 1.5.0 with Istio
**And** SHALL verify k0rdent Istio ready
**And** SHALL install KOF mothership
**And** SHALL verify KOF mothership operational
**And** SHALL deploy KOF regional cluster
**And** SHALL verify regional cluster operational
**And** SHALL test KOF features (collectors, dashboards, etc.)
**And** SHALL uninstall KOF
**And** SHALL verify k0rdent Istio still operational
**And** SHALL clean up test environment

#### Scenario: Test KOF feature functionality with k0rdent Istio
**Given** KOF is fully deployed with k0rdent 1.5.0 Istio
**When** E2E feature tests run
**Then** test SHALL verify KOF collectors work correctly
**And** SHALL verify Istio ingress routes traffic to KOF services
**And** SHALL verify KOF dashboards accessible via Istio gateway
**And** SHALL verify inter-service communication via Istio mesh
**And** SHALL verify KOF monitoring and observability features

### Requirement: Regression Testing
KOF tests SHALL verify no regression in existing KOF functionality.

#### Scenario: Test existing KOF features work with new Istio model
**Given** KOF deployed with k0rdent 1.5.0 Istio
**When** regression tests run
**Then** test SHALL verify all KOF v1.4.0 features still work
**And** SHALL verify mothership APIs functional
**And** SHALL verify regional cluster management functional
**And** SHALL verify no performance degradation
**And** SHALL verify no new errors or warnings in logs

### Requirement: Test Environment Setup
KOF testing SHALL support reproducible test environments with k0rdent 1.5.0.

#### Scenario: Create minimal k0rdent 1.5.0 test environment
**Given** automated test setup script exists
**When** test environment creation runs
**Then** test SHALL create k0rdent 1.5.0 cluster with Istio
**And** SHALL verify Istio fully deployed and ready
**And** SHALL provide kubeconfig for test access
**And** SHALL complete within reasonable time (< 30 minutes)
**And** SHALL be repeatable for CI/CD integration

#### Scenario: Test environment cleanup
**Given** KOF tests have completed
**When** test cleanup runs
**Then** cleanup SHALL remove all KOF resources
**And** SHALL remove k0rdent cluster
**And** SHALL verify no orphaned resources
**And** SHALL complete within 10 minutes

### Requirement: Performance Testing
KOF tests SHALL verify performance with k0rdent Istio meets expectations.

#### Scenario: Test KOF mothership performance with Istio
**Given** KOF mothership is deployed
**When** performance tests run
**Then** test SHALL measure API response times via Istio ingress
**And** SHALL verify P95 latency < 200ms for typical operations
**And** SHALL measure resource usage (CPU, memory) with Istio sidecars
**And** SHALL verify resource usage within acceptable limits
**And** SHALL compare with baseline (pre-Istio integration)

#### Scenario: Test regional cluster performance
**Given** multiple regional clusters deployed
**When** performance tests run
**Then** test SHALL measure inter-cluster communication latency via Istio
**And** SHALL verify collector data flow performance
**And** SHALL test under load (e.g., 100 managed clusters)

### Requirement: Test Documentation
KOF tests SHALL be documented for maintainability and knowledge transfer.

#### Scenario: Test documentation completeness
**Given** KOF test suite exists
**Then** documentation SHALL describe test environment setup
**And** SHALL document how to run all test categories
**And** SHALL explain each test scenario's purpose
**And** SHALL provide troubleshooting guide for test failures
**And** SHALL include examples of expected test output

## MODIFIED Requirements

### Requirement: Existing KOF Test Suite Update
The existing KOF test suite (e.g., `tests/test-kof-with-default.sh`) SHALL be updated for k0rdent 1.5.0 compatibility.

**Changes**:
- Remove tests for Istio installation by KOF
- Add tests for Istio discovery and validation
- Update expected behavior (no Istio version in config)
- Update assertions for k0rdent-managed Istio
- Add prerequisite checks for k0rdent 1.5.0

#### Scenario: Updated test suite passes with k0rdent 1.5.0
**Given** updated test suite is executed
**And** k0rdent 1.5.0 with Istio is deployed
**When** tests run
**Then** all tests SHALL pass
**And** tests SHALL verify k0rdent Istio is used
**And** tests SHALL not attempt Istio installation
**And** tests SHALL validate new Istio integration behavior
