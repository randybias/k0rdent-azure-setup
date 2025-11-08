# Script Integration with Terraform Specification

## ADDED Requirements

### Requirement: Terraform State Presence Detection
The system SHALL provide functions to detect Terraform state and validate its completeness before bash script execution.

#### Scenario: Terraform state file existence check
- **WHEN** terraform_state_exists() is called
- **THEN** function checks for terraform/ directory with .terraform subdirectory
- **AND** checks for terraform.tfstate file (local) or backend configuration
- **AND** returns true only if state is accessible and valid

#### Scenario: Terraform output availability validation
- **WHEN** validate_terraform_outputs() is called
- **THEN** function runs terraform output -json in terraform/ directory
- **AND** validates presence of required keys (controller_ips, worker_ips, resource_group_or_vpc)
- **AND** returns error with missing key list if validation fails

#### Scenario: Terraform state staleness check
- **WHEN** Terraform state exists but outputs timestamp is older than threshold
- **THEN** warning is logged with last update time
- **AND** user is advised to run terraform refresh
- **AND** scripts proceed with cached data unless --require-fresh-state flag set

### Requirement: Terraform Output Retrieval Functions
The system SHALL provide bash functions to extract and parse Terraform outputs into usable data structures.

#### Scenario: Single output value extraction
- **WHEN** get_terraform_output("wireguard_port") is called
- **THEN** function runs terraform output -json wireguard_port
- **AND** parses JSON value and returns as string
- **AND** handles null/missing output with descriptive error

#### Scenario: Array output parsing
- **WHEN** get_terraform_output("controller_ips") is called
- **THEN** function parses JSON array into bash array
- **AND** returns IP addresses as space-separated string or bash array variable
- **AND** validates each IP address format before returning

#### Scenario: Map output navigation
- **WHEN** get_terraform_output("vm_details.vm-ctrl0.public_ip") is called with dot notation
- **THEN** function navigates nested JSON structure using jq
- **AND** returns specific nested value
- **AND** handles missing keys gracefully with null return

### Requirement: VM Information Abstraction Layer
The system SHALL provide unified get_vm_info() function that works with Terraform, state, or API data sources.

#### Scenario: Terraform-first IP retrieval
- **WHEN** get_vm_info("vm-ctrl0", "public_ip") is called and Terraform state exists
- **THEN** function queries Terraform output for vm-ctrl0 public IP
- **AND** returns IP address if found
- **AND** caches result in deployment-state.yaml for future lookups

#### Scenario: State fallback for offline operations
- **WHEN** get_vm_info() is called but Terraform command unavailable (offline)
- **THEN** function reads from cached terraform_outputs in deployment-state.yaml
- **AND** returns cached value with staleness warning if older than 1 day
- **AND** suggests running terraform refresh when online

#### Scenario: API fallback for legacy deployments
- **WHEN** get_vm_info() is called and no Terraform state exists
- **THEN** function falls back to Azure CLI or AWS CLI query
- **AND** queries VM/instance by name in resource group/VPC
- **AND** stores result in deployment-state.yaml for consistency

### Requirement: Infrastructure Data Synchronization
The system SHALL sync Terraform outputs to deployment-state.yaml for offline access and caching.

#### Scenario: Post-apply output sync
- **WHEN** terraform-wrapper.sh apply completes successfully
- **THEN** sync_terraform_to_state() is automatically called
- **AND** all Terraform outputs are copied to deployment-state.yaml terraform_outputs section
- **AND** sync timestamp is recorded

#### Scenario: Manual output refresh
- **WHEN** user runs terraform-wrapper.sh refresh-outputs
- **THEN** terraform output -json is executed
- **AND** deployment-state.yaml terraform_outputs section is updated
- **AND** no infrastructure changes are made (read-only refresh)

#### Scenario: Output cache invalidation
- **WHEN** Terraform apply modifies infrastructure
- **THEN** previous terraform_outputs cache is marked stale
- **AND** new outputs replace cached values
- **AND** bash scripts automatically pick up new values on next invocation

### Requirement: Multi-Cloud Provider Abstraction
The system SHALL normalize provider-specific Terraform outputs into consistent bash script interface.

#### Scenario: Resource group vs VPC ID abstraction
- **WHEN** scripts call get_infrastructure_id()
- **THEN** function returns resource_group for Azure deployments
- **AND** returns vpc_id for AWS deployments
- **AND** provider is detected from cloud_provider in deployment-state.yaml

#### Scenario: VM vs instance naming normalization
- **WHEN** scripts iterate over compute resources
- **THEN** get_compute_hosts() returns list of hostnames regardless of provider
- **AND** hostnames follow ${cluster_id}-ctrl${n} / ${cluster_id}-wrk${n} pattern for both Azure and AWS
- **AND** provider-specific details (VM size vs instance type) are accessed via get_vm_info() with normalized keys

#### Scenario: Network identifier abstraction
- **WHEN** scripts need subnet/security group identifiers
- **THEN** get_network_id() returns subnet_id for Azure
- **AND** returns subnet_ids (array) for AWS multi-AZ
- **AND** get_security_group_id() works consistently across providers

### Requirement: Error Handling and Diagnostics
The system SHALL provide clear error messages when Terraform outputs are missing or malformed.

#### Scenario: Missing required Terraform output
- **WHEN** bash script requires controller_ips but output is missing
- **THEN** descriptive error indicates Terraform module may need update
- **AND** error message suggests running terraform plan to check module configuration
- **AND** script exits with non-zero status

#### Scenario: Malformed Terraform output JSON
- **WHEN** terraform output -json returns invalid JSON
- **THEN** parsing error is caught with jq error message
- **AND** user is advised to check Terraform state integrity
- **AND** fallback to cached outputs is attempted if available

#### Scenario: Terraform command unavailable
- **WHEN** get_terraform_output() is called but terraform binary not in PATH
- **THEN** function logs warning about missing Terraform
- **AND** immediately falls back to cached outputs or API queries
- **AND** user is advised to install Terraform or use --legacy flag
