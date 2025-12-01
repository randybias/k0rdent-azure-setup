## MODIFIED Requirements

### Requirement: KOF Regional Cluster Clarification and Independence

The system SHALL support KOF regional clusters as a separate, independent feature from k0rdent regional management clusters.

**NOTE**: This requirement clarifies the distinction between KOF regional clusters (observability) and k0rdent regional clusters (infrastructure segregation). These are independent features that can be deployed separately or together.

#### Scenario: KOF regional cluster independent deployment
- **GIVEN** k0rdent 1.5.0 deployed with k0rdent regional clusters
- **WHEN** the operator deploys KOF regional clusters
- **THEN** KOF regional clusters SHALL be separate from k0rdent regional clusters
- **AND** KOF regional deployment SHALL use existing `install-kof-regional.sh` script
- **AND** KOF regional clusters SHALL not require k0rdent regional clusters
- **AND** KOF can be deployed to management cluster only, k0rdent regional only, or both

#### Scenario: KOF regional cluster for observability
- **GIVEN** k0rdent regional clusters deployed across Azure regions
- **WHEN** KOF regional clusters are deployed for observability
- **THEN** KOF regional clusters SHALL collect metrics from k0rdent regional clusters
- **AND** KOF regional clusters SHALL aggregate observability data
- **AND** KOF regional clusters SHALL operate independently from k0rdent regional infrastructure

#### Scenario: Combined k0rdent and KOF regional deployment
- **GIVEN** configuration for both k0rdent regional and KOF regional clusters
- **WHEN** both are deployed
- **THEN** k0rdent regional clusters SHALL be deployed first
- **AND** KOF regional clusters SHALL be deployed after k0rdent regional
- **AND** both SHALL be tracked separately in state
- **AND** both SHALL have independent lifecycles and upgrade paths

#### Scenario: KOF regional cluster configuration clarity
- **GIVEN** YAML configuration with both k0rdent and KOF regional sections
- **WHEN** operators review configuration
- **THEN** k0rdent regional configuration SHALL be under `software.k0rdent.regional`
- **AND** KOF regional configuration SHALL be under `kof.regional`
- **AND** configuration documentation SHALL clearly explain the difference
- **AND** example configurations SHALL demonstrate both deployment patterns

## ADDED Requirements

### Requirement: KOF Regional Cluster Azure Region Coordination

The system SHALL support coordinating KOF regional clusters with k0rdent regional cluster locations.

#### Scenario: KOF regional cluster co-location
- **GIVEN** k0rdent regional clusters deployed in specific Azure regions
- **WHEN** KOF regional clusters are deployed
- **THEN** KOF regional clusters MAY be deployed in the same Azure regions as k0rdent regional
- **OR** KOF regional clusters MAY be deployed in different Azure regions
- **AND** the configuration SHALL allow independent region specification for each type

#### Scenario: KOF regional observability of k0rdent regional clusters
- **GIVEN** k0rdent regional clusters with workloads
- **AND** KOF regional clusters deployed
- **WHEN** observability is configured
- **THEN** KOF regional clusters SHALL collect metrics from k0rdent regional workloads
- **AND** KOF mothership SHALL aggregate data from all KOF regional clusters
- **AND** observability SHALL span both k0rdent regional and management cluster workloads

### Requirement: KOF Regional and k0rdent Regional State Separation

The system SHALL maintain separate state tracking for KOF regional and k0rdent regional clusters.

#### Scenario: Independent state tracking
- **GIVEN** both KOF regional and k0rdent regional clusters deployed
- **WHEN** state is queried
- **THEN** k0rdent regional state SHALL be under `k0rdent_regional` state key
- **AND** KOF regional state SHALL be under `kof_regional` state key
- **AND** each SHALL have independent deployment phases and status
- **AND** state queries SHALL support filtering by regional cluster type

#### Scenario: KOF regional deployment without k0rdent regional
- **GIVEN** k0rdent 1.5.0 deployed without k0rdent regional clusters
- **WHEN** KOF regional clusters are deployed
- **THEN** KOF regional deployment SHALL succeed independently
- **AND** KOF regional state SHALL not reference k0rdent regional clusters
- **AND** KOF regional observability SHALL monitor management cluster workloads

#### Scenario: k0rdent regional deployment without KOF regional
- **GIVEN** k0rdent 1.5.0 deployed with k0rdent regional clusters
- **WHEN** KOF is not deployed
- **THEN** k0rdent regional clusters SHALL operate without KOF
- **AND** observability SHALL rely on native k0rdent telemetry (introduced in 1.5.0)
- **AND** k0rdent regional state SHALL not reference KOF components
