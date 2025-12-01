## ADDED Requirements

### Requirement: k0rdent Regional Cluster Configuration

The system SHALL support configuration of k0rdent regional management clusters through YAML configuration files.

#### Scenario: Regional cluster configuration with k0rdent-managed cluster
- **GIVEN** a k0rdent 1.5.0 deployment configuration file
- **WHEN** the operator adds regional cluster configuration with `cluster_deployment_ref`
- **THEN** the configuration SHALL be validated and parsed successfully
- **AND** the regional cluster SHALL reference a k0rdent-managed ClusterDeployment

#### Scenario: Regional cluster configuration with external cluster
- **GIVEN** a k0rdent 1.5.0 deployment configuration file
- **WHEN** the operator adds regional cluster configuration with `kubeconfig_secret`
- **THEN** the configuration SHALL be validated and parsed successfully
- **AND** the regional cluster SHALL reference an external cluster kubeconfig secret

#### Scenario: Multiple regional clusters configuration
- **GIVEN** a k0rdent 1.5.0 deployment configuration file
- **WHEN** the operator configures multiple regional clusters across different Azure regions
- **THEN** each regional cluster SHALL have unique name and location
- **AND** all regional clusters SHALL be tracked independently in state

#### Scenario: Regional cluster disabled by default
- **GIVEN** a new k0rdent deployment configuration
- **WHEN** no regional cluster configuration is provided
- **THEN** regional cluster support SHALL be disabled by default
- **AND** the deployment SHALL proceed with management cluster only

### Requirement: k0rdent Regional Cluster Deployment

The system SHALL deploy k0rdent regional management clusters using the Region CRD.

#### Scenario: Deploy k0rdent-managed regional cluster
- **GIVEN** regional cluster configuration with `cluster_deployment_ref`
- **WHEN** the operator runs regional cluster deployment command
- **THEN** a ClusterDeployment SHALL be created for the regional cluster
- **AND** a Region CRD SHALL be created referencing the ClusterDeployment
- **AND** the regional cluster SHALL transition to Ready state
- **AND** the regional kubeconfig SHALL be retrieved and stored locally

#### Scenario: Register external regional cluster
- **GIVEN** regional cluster configuration with `kubeconfig_secret`
- **WHEN** the operator runs regional cluster deployment command
- **THEN** the kubeconfig secret SHALL be validated for accessibility
- **AND** a Region CRD SHALL be created referencing the kubeconfig secret
- **AND** the regional cluster SHALL transition to Ready state

#### Scenario: Regional cluster deployment failure handling
- **GIVEN** a regional cluster deployment in progress
- **WHEN** the deployment fails due to infrastructure or network issues
- **THEN** the deployment SHALL record the failure in state
- **AND** the operator SHALL be notified of the specific failure reason
- **AND** the deployment SHALL support retry without recreating successful components

#### Scenario: Regional cluster component installation
- **GIVEN** a regional cluster in Ready state
- **WHEN** component installation is triggered
- **THEN** cert-manager SHALL be installed in the regional cluster
- **AND** Velero SHALL be installed for backup capabilities
- **AND** CAPI providers SHALL be deployed to the regional cluster
- **AND** component versions SHALL be tracked in state

### Requirement: Regional Cluster Credential Propagation

The system SHALL propagate Azure credentials from the management cluster to regional clusters.

#### Scenario: Credential propagation to regional cluster
- **GIVEN** a regional cluster in Ready state
- **AND** Azure credentials configured in the management cluster
- **WHEN** credential propagation is triggered
- **THEN** Azure ClusterIdentity resources SHALL be copied to the regional cluster
- **AND** credential secrets SHALL be securely propagated
- **AND** credential propagation status SHALL be recorded in state

#### Scenario: Multiple regional clusters credential synchronization
- **GIVEN** multiple regional clusters deployed
- **WHEN** credentials are propagated
- **THEN** each regional cluster SHALL receive the same credentials
- **AND** propagation SHALL complete successfully for all regions
- **AND** any propagation failures SHALL be reported per-region

#### Scenario: Credential rotation to regional clusters
- **GIVEN** regional clusters with existing credentials
- **WHEN** Azure credentials are rotated in the management cluster
- **THEN** updated credentials SHALL be propagated to all regional clusters
- **AND** ClusterIdentity resources SHALL be updated in each region
- **AND** credential rotation SHALL not disrupt existing ClusterDeployments

### Requirement: Regional Cluster State Management

The system SHALL track the state of all k0rdent regional clusters.

#### Scenario: Regional cluster state initialization
- **GIVEN** a new regional cluster deployment starts
- **WHEN** the deployment begins
- **THEN** the regional cluster state SHALL be created with status "deploying"
- **AND** the state SHALL include cluster name, location, and configuration
- **AND** the deployment phase SHALL be marked as in-progress

#### Scenario: Regional cluster state update on success
- **GIVEN** a regional cluster deployment completes successfully
- **WHEN** all components are installed
- **THEN** the regional cluster state SHALL be updated to "deployed"
- **AND** component versions SHALL be recorded
- **AND** the kubeconfig path SHALL be stored
- **AND** the deployment phase SHALL be marked as completed

#### Scenario: Regional cluster state persistence
- **GIVEN** regional clusters in various states
- **WHEN** the deployment script is interrupted or restarted
- **THEN** the state SHALL be loaded from the state file
- **AND** the deployment SHALL resume from the last completed phase
- **AND** already-deployed regional clusters SHALL not be redeployed

#### Scenario: Query regional cluster status
- **GIVEN** one or more regional clusters deployed
- **WHEN** the operator queries regional cluster status
- **THEN** the system SHALL display all regional clusters with their states
- **AND** component installation status SHALL be shown
- **AND** credential propagation status SHALL be indicated
- **AND** Region CRD Ready condition SHALL be displayed

### Requirement: Regional Cluster Validation

The system SHALL validate regional cluster configuration and deployment readiness.

#### Scenario: Validate regional cluster configuration
- **GIVEN** a regional cluster configuration
- **WHEN** configuration validation is triggered
- **THEN** the system SHALL verify exactly one of cluster_deployment_ref or kubeconfig_secret is specified
- **AND** the system SHALL validate Azure location is valid
- **AND** required component flags SHALL be validated
- **AND** validation errors SHALL be reported with specific messages

#### Scenario: Validate k0rdent version compatibility
- **GIVEN** a regional cluster configuration
- **WHEN** deployment is initiated
- **THEN** the system SHALL verify k0rdent version is 1.5.0 or higher
- **AND** the system SHALL check Region CRD availability in the management cluster
- **AND** deployment SHALL be blocked if version requirements not met

#### Scenario: Validate regional cluster readiness
- **GIVEN** a regional cluster deployment
- **WHEN** the deployment completes
- **THEN** the system SHALL verify the Region CRD status is Ready
- **AND** all configured components SHALL be verified as installed
- **AND** credential propagation SHALL be confirmed successful
- **AND** the regional cluster SHALL be accessible via kubeconfig

### Requirement: Regional Cluster Cleanup

The system SHALL support cleanup and removal of k0rdent regional clusters.

#### Scenario: Remove single regional cluster
- **GIVEN** a deployed regional cluster
- **WHEN** the operator requests regional cluster removal
- **THEN** all ClusterDeployments in the regional cluster SHALL be deleted first
- **AND** the Region CRD SHALL be deleted from the management cluster
- **AND** the regional cluster ClusterDeployment SHALL be removed (if k0rdent-managed)
- **AND** the regional cluster state SHALL be updated to "removed"

#### Scenario: Cleanup orphaned regional resources
- **GIVEN** a failed regional cluster deployment
- **WHEN** cleanup is triggered
- **THEN** partially created Azure resources SHALL be identified
- **AND** orphaned Region CRDs SHALL be removed
- **AND** local kubeconfig files SHALL be cleaned up
- **AND** state entries for the failed cluster SHALL be removed

#### Scenario: Regional cluster removal with active workloads
- **GIVEN** a regional cluster with active ClusterDeployments
- **WHEN** removal is attempted
- **THEN** the system SHALL warn about active workloads
- **AND** removal SHALL be blocked unless force flag is provided
- **AND** if forced, all ClusterDeployments SHALL be deleted before region removal

### Requirement: Regional Cluster Certificate Management

The system SHALL propagate TLS certificates to k0rdent regional clusters.

#### Scenario: Certificate secret propagation
- **GIVEN** TLS certificates configured in the management cluster
- **AND** a regional cluster in Ready state
- **WHEN** certificate propagation is triggered
- **THEN** certificate secrets SHALL be copied to the regional cluster
- **AND** certificates SHALL be available for CAPI provider usage
- **AND** certificate propagation status SHALL be tracked in state

#### Scenario: Certificate rotation to regional clusters
- **GIVEN** regional clusters with existing certificates
- **WHEN** certificates are rotated in the management cluster
- **THEN** updated certificates SHALL be propagated to all regional clusters
- **AND** certificate updates SHALL not disrupt running workloads
- **AND** certificate rotation SHALL be logged in events
