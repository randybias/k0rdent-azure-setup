# Spec: Azure Resource Tagging and Deployment History

## ADDED Requirements

### Requirement: Resource Group Ownership Tags

Azure resource groups created by this tool MUST include metadata tags to identify ownership and origin.

#### Scenario: Creating a new resource group with auto-detected deployer

**Given** no `metadata.owner` is configured in the YAML file
**When** the tool creates an Azure resource group
**Then** the resource group MUST have tag `owner` set to the auto-detected deployer identity
**And** the resource group MUST have tag `created-by` set to "k0rdent-azure-setup"
**And** the resource group MUST have tag `cluster-id` set to the K0RDENT_CLUSTERID value
**And** the resource group MUST have tag `created` set to an ISO 8601 UTC timestamp

#### Scenario: Creating a resource group with configured owner

**Given** `metadata.owner` is set to "alice@company.com" in the YAML file
**When** the tool creates an Azure resource group
**Then** the resource group MUST have tag `owner` set to "alice@company.com"
**And** all other standard tags MUST be present

#### Scenario: Viewing resources in Azure portal

**Given** a resource group was created with ownership tags
**When** a team member views the resource group in Azure portal
**Then** they MUST be able to see the `owner` tag value
**And** they MUST be able to filter resources by the `owner` tag

### Requirement: Deployer Identity Detection

The system MUST auto-detect deployer identity using a defined fallback chain.

#### Scenario: Detection with git email available

**Given** no `metadata.owner` is configured
**And** git is configured with user.email "randy@example.com"
**When** the deployer identity is detected
**Then** the identity MUST be "randy@example.com"

#### Scenario: Detection without git, with USER and hostname

**Given** no `metadata.owner` is configured
**And** git is not configured or unavailable
**And** $USER is "rbias" and hostname is "macbook.local"
**When** the deployer identity is detected
**Then** the identity MUST be "rbias@macbook" (short hostname, no domain)

#### Scenario: Detection fallback to whoami

**Given** no `metadata.owner` is configured
**And** git is not available
**And** $USER is unset
**And** `whoami` returns "admin"
**And** hostname is "server1"
**When** the deployer identity is detected
**Then** the identity MUST be "admin@server1"

#### Scenario: Final fallback to unknown

**Given** no `metadata.owner` is configured
**And** all detection methods fail
**When** the deployer identity is detected
**Then** the identity MUST be "unknown"

### Requirement: Tag Format Compliance

Tags applied to Azure resources MUST comply with Azure tag naming and value restrictions.

#### Scenario: Tag values with special characters

**Given** deployer identity contains special characters
**When** the owner tag is applied
**Then** the tag value MUST be properly escaped for Azure CLI
**And** tag values MUST not exceed 256 characters (truncated if needed)

### Requirement: Deployment History Tracking

The system MUST maintain a simple history of all deployments in `old_deployments/deployment-history.yaml`.

#### Scenario: Recording a new deployment

**Given** a deployment is starting
**When** the deployment begins
**Then** an entry MUST be appended to `old_deployments/deployment-history.yaml`
**And** the entry MUST include `cluster_id`, `deployed_at`, `config_file`, and `deployer`

#### Scenario: History file format

**Given** multiple deployments have been recorded
**When** viewing `deployment-history.yaml`
**Then** it MUST be valid YAML with a `deployments` array
**And** each entry MUST have exactly: `cluster_id`, `deployed_at`, `config_file`, `deployer`
**And** `deployed_at` MUST be ISO 8601 UTC format

### Requirement: Organized Old Deployments Directory

Old deployment files MUST be organized into per-cluster subdirectories.

#### Scenario: Archiving deployment on reset

**Given** a deployment is being reset or archived
**When** state files are moved to old_deployments
**Then** files MUST be placed in `old_deployments/<cluster-id>/` subdirectory
**And** all related state files MUST be in the same subdirectory

#### Scenario: Finding old deployment files

**Given** a user wants to find files for cluster "k0rdent-abc123"
**When** they look in old_deployments
**Then** all files MUST be in `old_deployments/k0rdent-abc123/`

### Requirement: Migration of Existing Flat Files

Existing flat files in old_deployments MUST be migrated to the new structure.

#### Scenario: One-time migration

**Given** old_deployments contains flat files like `k0rdent-abc123_20251201_completed.yaml`
**When** the migration runs
**Then** files MUST be moved to `old_deployments/k0rdent-abc123/`
**And** original file names MUST be preserved within the subdirectory

## MODIFIED Requirements

None - this is a new capability.

## REMOVED Requirements

None - no existing requirements are being removed.
