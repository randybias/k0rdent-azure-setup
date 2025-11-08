# Azure Infrastructure Management Specification

## MODIFIED Requirements

### Requirement: Azure Infrastructure Provisioning
The system SHALL provision Azure infrastructure using Terraform declarative modules instead of imperative bash scripts with Azure CLI.

#### Scenario: Resource group creation via Terraform
- **WHEN** infrastructure deployment is initiated
- **THEN** Terraform module creates resource group in specified location
- **AND** resource group name follows ${cluster_id}-resgrp pattern
- **AND** Terraform state tracks resource group lifecycle

#### Scenario: Network infrastructure deployment
- **WHEN** network module is applied
- **THEN** VNet and subnet are created with CIDR blocks from configuration
- **AND** NSG with WireGuard and SSH rules is attached to subnet
- **AND** network resources are tagged with cluster_id and deployment metadata

#### Scenario: VM provisioning with cloud-init
- **WHEN** compute module is applied with cloud-init file paths
- **THEN** VMs are created with cloud-init content from specified files
- **AND** VMs use SSH key imported as Azure SSH Key resource
- **AND** public and private IPs are allocated and tracked in Terraform state

### Requirement: Infrastructure State Management
The system SHALL use Terraform state as authoritative source for infrastructure facts, replacing Azure CLI queries in bash scripts.

#### Scenario: Infrastructure facts from Terraform outputs
- **WHEN** bash scripts need VM IP addresses or resource identifiers
- **THEN** scripts read from Terraform outputs stored in deployment-state.yaml
- **AND** outputs are refreshed via terraform-wrapper.sh after apply/refresh operations
- **AND** scripts fall back to Azure CLI queries only if Terraform outputs unavailable

#### Scenario: Drift detection and reconciliation
- **WHEN** terraform plan is executed on existing infrastructure
- **THEN** Terraform detects changes made outside Terraform (drift)
- **AND** plan output shows difference between desired and actual state
- **AND** user can choose to import, update, or recreate resources

### Requirement: Spot Instance Lifecycle Management
The system SHALL handle Azure Spot VM evictions and failures via Terraform lifecycle configuration, replacing bash retry logic.

#### Scenario: Spot VM creation with automatic retry
- **WHEN** Spot VM creation fails due to capacity or price constraints
- **THEN** Terraform retries creation according to lifecycle configuration
- **AND** create_before_destroy ensures new VM is healthy before destroying old VM
- **AND** failure is logged in Terraform state with detailed error message

#### Scenario: Eviction policy enforcement
- **WHEN** vm_priority is "Spot" in configuration
- **THEN** eviction_policy (Deallocate or Delete) is applied to VM resource
- **AND** policy is validated against Azure constraints at plan time

## REMOVED Requirements

### Requirement: Direct Azure CLI Resource Creation in Bash
**Reason**: Terraform modules replace imperative Azure CLI calls for infrastructure provisioning.

**Migration**: Legacy bash scripts (setup-azure-network.sh, create-azure-vms.sh) are deprecated in favor of terraform-wrapper.sh. A `--legacy` flag maintains bash-only path during transition.

#### Scenario: Sequential VM creation with background processes
- **Previous behavior**: bash script launched az vm create in background with PID tracking
- **New behavior**: Terraform manages VM creation in parallel via Azure Resource Manager; bash monitors Terraform state

### Requirement: CSV Manifest for Azure Resource Tracking
**Reason**: Terraform state file replaces custom CSV-based resource tracking.

**Migration**: Existing deployment-state.yaml is updated to reference Terraform state file location instead of storing infrastructure facts directly.

## ADDED Requirements

### Requirement: Terraform Wrapper Script
The system SHALL provide a bash wrapper script that invokes Terraform with configuration from k0rdent.yaml and integrates outputs with existing state management.

#### Scenario: Terraform initialization with backend configuration
- **WHEN** bin/terraform-wrapper.sh init is executed
- **THEN** wrapper configures Azure Storage backend with cluster_id-based state key
- **AND** Terraform providers are downloaded and initialized
- **AND** backend configuration is stored in deployment-state.yaml

#### Scenario: Infrastructure application and output extraction
- **WHEN** bin/terraform-wrapper.sh apply is executed
- **THEN** wrapper runs terraform apply with auto-approve based on flags
- **AND** Terraform outputs (JSON) are parsed and stored in deployment-state.yaml
- **AND** VM IPs, resource names, and identifiers are available to subsequent bash scripts

#### Scenario: Infrastructure destruction with state cleanup
- **WHEN** bin/terraform-wrapper.sh destroy is executed
- **THEN** wrapper runs terraform destroy after confirmation
- **AND** Terraform state is archived to old_deployments/ directory
- **AND** infrastructure-related keys in deployment-state.yaml are marked as deleted

### Requirement: Configuration Translation from YAML to Terraform Variables
The system SHALL generate Terraform tfvars from k0rdent.yaml configuration to maintain single source of truth.

#### Scenario: Azure tfvars generation
- **WHEN** bin/configure.sh export --format terraform is executed
- **THEN** terraform.tfvars.json is created with Azure provider variables
- **AND** YAML sections (azure, network, vm_sizing, cluster) map to Terraform variable names
- **AND** WireGuard port from state or random generation is included

#### Scenario: AWS tfvars generation
- **WHEN** bin/configure.sh export --format terraform --provider aws is executed
- **THEN** terraform.tfvars.json is created with AWS provider variables
- **AND** YAML sections (aws, network, vm_sizing, cluster) map to AWS module variables
- **AND** availability zones replace Azure zones in configuration

#### Scenario: Validation of generated tfvars
- **WHEN** tfvars file is generated
- **THEN** wrapper validates against Terraform module variable definitions
- **AND** errors are reported for missing required variables or invalid values
- **AND** defaults are applied for optional variables per module specification

### Requirement: Legacy Bash Script Support
The system SHALL maintain backward compatibility with pure bash workflow via --legacy flag during transition period.

#### Scenario: Legacy deployment without Terraform
- **WHEN** deploy-k0rdent.sh is executed with --legacy flag
- **THEN** traditional bash scripts (setup-azure-network.sh, create-azure-vms.sh) are invoked
- **AND** Terraform modules are not used
- **AND** deployment-state.yaml tracks infrastructure facts from Azure CLI queries

#### Scenario: Migration from legacy to Terraform
- **WHEN** existing bash deployment is migrated to Terraform
- **THEN** terraform import commands are provided for resource adoption
- **AND** imported resources are validated against configuration
- **AND** deployment-state.yaml is updated to reference Terraform state

### Requirement: Multi-Cloud Credential Management
The system SHALL support provider-specific credentials from separate YAML files for Azure and AWS.

#### Scenario: Azure provider authentication
- **WHEN** Terraform Azure modules are used
- **THEN** credentials from config/azure-credentials.yaml are loaded
- **AND** subscription_id, tenant_id, client_id, client_secret are exported as environment variables
- **AND** Terraform Azure provider uses environment variable authentication

#### Scenario: AWS provider authentication
- **WHEN** Terraform AWS modules are used
- **THEN** credentials from config/aws-credentials.yaml are loaded
- **AND** aws_access_key_id and aws_secret_access_key are exported as environment variables
- **AND** Terraform AWS provider uses environment variable or profile authentication
