# Azure Credential Cleanup Integration

## MODIFIED Requirements

### Requirement: Deployment Reset Integration
The deployment reset workflow SHALL automatically trigger Azure credential cleanup when credentials have been previously configured, ensuring no orphaned service principals remain in the Azure subscription.

#### Scenario: Deployment reset with configured Azure credentials
**Given** Azure credentials have been configured via `setup-azure-cluster-deployment.sh setup`
**When** the user runs `deploy-k0rdent.sh reset`
**Then** the reset process automatically calls Azure credential cleanup
**And** removes the Azure Service Principal from the subscription
**And** removes local credential files
**And** updates state tracking accordingly

#### Scenario: Deployment reset without Azure credentials
**Given** no Azure credentials have been configured
**When** the user runs `deploy-k0rdent.sh reset`
**Then** the reset process continues normally
**And** no Azure cleanup activities are performed
**And** reset logging indicates no credentials to clean up

### Requirement: State-Driven Cleanup Detection
The reset process SHALL use Azure state tracking to detect when credential cleanup is required, cleaning up only when necessary and avoiding unnecessary Azure API calls.

#### Scenario: State file indicates credentials configured
**Given** `azure_credentials_configured` is set to "true" in azure-state.yaml
**When** deployment reset begins
**Then** the system detects credential configuration
**And** triggers automatic cleanup
**And** logs the detection event

#### Scenario: State file indicates no credentials configured
**Given** `azure_credentials_configured` is not set or is "false"
**When** deployment reset begins
**Then** the system skips Azure cleanup
**And** logs that no credentials were found

## ADDED Requirements

### Requirement: Automatic Cleanup Orchestration
The system SHALL orchestrate Azure credential cleanup automatically during deployment reset, handling both online and offline cleanup scenarios with appropriate error handling.

#### Scenario: Cluster is accessible during reset
**Given** the Kubernetes cluster is still accessible during reset
**When** automatic cleanup is triggered
**Then** the system removes Kubernetes resources (secrets, identities, credentials)
**And** deletes the Azure Service Principal
**And** removes local credential files
**And** reports successful cleanup

#### Scenario: Cluster is inaccessible during reset
**Given** the Kubernetes cluster is not accessible during reset
**When** automatic cleanup is triggered
**Then** the system skips Kubernetes resource cleanup
**And** deletes the Azure Service Principal via Azure CLI
**And** removes local credential files
**And** continues with main reset process
**And** logs that cluster cleanup was skipped

### Requirement: Cleanup Resilience and Error Handling
The system SHALL continue the main deployment reset process even if Azure credential cleanup encounters errors, providing clear error reporting and manual cleanup guidance.

#### Scenario: Insufficient Azure permissions for cleanup
**Given** the user lacks sufficient permissions to delete the Service Principal
**When** automatic cleanup attempts Azure SP deletion
**Then** cleanup logs the permission error
**And** provides clear instructions for manual cleanup
**And** continues with the main deployment reset process
**And** does not fail the entire reset operation

#### Scenario: Azure CLI authentication expired during reset
**Given** Azure CLI authentication is not valid during reset
**When** automatic cleanup attempts Azure operations
**Then** cleanup logs the authentication error
**And** provides instructions to re-authenticate manually
**And** cleans up local credential files where possible
**And** continues with main reset process

### Requirement: Cleanup Status Reporting
The system SHALL provide clear status reporting for Azure credential cleanup activities, including what was successfully cleaned up and what may require manual intervention.

#### Scenario: Successful automatic cleanup
**Given** all Azure credential components are successfully cleaned up
**When** automatic cleanup completes
**Then** the system logs successful cleanup events
**And** displays "Azure credentials cleaned up successfully" message
**And** records cleanup completion in deployment events

#### Scenario: Partial cleanup with some failures
**Given** cleanup encounters partial failures (e.g., Azure SP deletion fails but local files removed)
**When** automatic cleanup completes
**Then** the system logs what succeeded and what failed
**And** displays warning messages about partial cleanup
**And** provides instructions for completing manual cleanup
**And** continues with main reset process

### Requirement: Manual Cleanup Compatibility
The system SHALL preserve the existing manual cleanup functionality, allowing users to manually run Azure credential cleanup independently of the deployment reset process.

#### Scenario: User wants to clean up Azure credentials without full reset
**Given** the user wants to clean up Azure credentials but keep the k0rdent cluster
**When** they run `./setup-azure-cluster-deployment.sh cleanup`
**Then** the manual cleanup operates exactly as before
**And** performs complete Azure credential cleanup
**And** respects manual confirmation prompts unless -y flag is used

#### Scenario: User wants to clean up after failed automatic cleanup
**Given** automatic cleanup during reset encountered errors
**When** the user runs `./setup-azure-cluster-deployment.sh cleanup` manually
**Then** manual cleanup can complete the cleanup process
**And** resolve any credential cleanup issues
**And** update state tracking appropriately

## Technical Implementation Notes

### Integration Point
- Automatic cleanup integrated into `deploy-k0rdent.sh reset` workflow
- Existing `cleanup_azure_credentials()` function reused
- State detection uses existing `get_azure_state()` functions

### State Management
- Cleanup events recorded in azure-events.yaml
- Phase reset markers updated via existing phase tracking system
- Azure state file updated to reflect cleanup completion

### Error Handling Strategy
- Non-critical failures do not stop main reset process
- Clear error messages guide users to manual completion if needed
- All cleanup attempts logged for audit trail

### Security Considerations
- Automatic cleanup reduces credential lifetime
- Local credential files always removed regardless of cluster access
- Service principal permissions revoked when possible
