# Terraform Modules Specification

## ADDED Requirements

### Requirement: Azure Network Module
The system SHALL provide a Terraform module that provisions Azure networking infrastructure matching current bash script behavior.

#### Scenario: Complete network stack creation
- **WHEN** terraform apply is executed with Azure provider
- **THEN** the module creates resource group, VNet, subnet, NSG, and SSH key resource
- **AND** NSG rules allow WireGuard UDP (dynamic port) and SSH TCP (port 22)
- **AND** NSG is associated with the subnet

#### Scenario: WireGuard port configuration
- **WHEN** WireGuard port is provided in tfvars
- **THEN** NSG rule uses the specified port number
- **AND** the port is passed through as module output

#### Scenario: Regional deployment
- **WHEN** azure_location variable specifies a region
- **THEN** all resources are created in that region
- **AND** region is validated against Azure provider availability

### Requirement: Azure Compute Module
The system SHALL provide a Terraform module that provisions Azure VMs with cloud-init support, zone placement, and spot instance handling.

#### Scenario: Multi-node cluster creation
- **WHEN** terraform apply is executed with controller_count and worker_count variables
- **THEN** VMs are created with naming pattern ${cluster_id}-ctrl${index} and ${cluster_id}-wrk${index}
- **AND** each VM is assigned to a zone from the specified zones list (round-robin)
- **AND** cloud-init file content is injected via custom_data

#### Scenario: Spot instance configuration
- **WHEN** vm_priority is set to "Spot"
- **THEN** VMs are created with Spot priority and specified eviction policy
- **AND** lifecycle create_before_destroy is enabled for graceful replacement

#### Scenario: VM outputs for orchestration
- **WHEN** VMs are successfully created
- **THEN** module outputs include public_ips, private_ips, and hostnames as maps keyed by VM name
- **AND** outputs are structured for easy bash script consumption

### Requirement: AWS Network Module
The system SHALL provide a Terraform module that provisions AWS networking infrastructure for future multi-cloud support.

#### Scenario: VPC and subnet creation
- **WHEN** terraform apply is executed with AWS provider
- **THEN** the module creates VPC, public subnets, internet gateway, and route tables
- **AND** security group allows WireGuard UDP and SSH TCP with same rule structure as Azure NSG

#### Scenario: Multi-AZ subnet distribution
- **WHEN** multiple availability zones are specified
- **THEN** subnets are created in each AZ with distinct CIDR blocks
- **AND** subnet IDs are output as a map keyed by AZ

### Requirement: AWS Compute Module
The system SHALL provide a Terraform module that provisions EC2 instances with user-data support and spot instance handling.

#### Scenario: EC2 instance provisioning
- **WHEN** terraform apply is executed with controller_count and worker_count
- **THEN** EC2 instances are created with naming tags matching Azure pattern
- **AND** user-data from generated files is injected via user_data argument
- **AND** instances are distributed across availability zones

#### Scenario: Spot instance request
- **WHEN** instance_market_type is set to "spot"
- **THEN** instances are launched as spot with specified max_price
- **AND** instance interruption handling uses lifecycle policies

### Requirement: Module Variable Validation
The system SHALL validate Terraform module inputs against cloud provider constraints.

#### Scenario: Azure VM size validation
- **WHEN** terraform plan is executed with Azure module
- **THEN** vm_size variables are validated against regex pattern for Azure naming
- **AND** warning is shown if size may not support Gen2 images

#### Scenario: AWS instance type validation
- **WHEN** terraform plan is executed with AWS module
- **THEN** instance_type variables are validated against AWS naming patterns
- **AND** error is raised for invalid instance family combinations

#### Scenario: Zone/AZ availability check
- **WHEN** zones (Azure) or availability_zones (AWS) are specified
- **THEN** validation checks zone format matches provider requirements
- **AND** descriptive error message guides user to correct format

### Requirement: Module Outputs for Bash Integration
The system SHALL expose Terraform outputs in a structure optimized for bash script consumption.

#### Scenario: VM/Instance inventory output
- **WHEN** infrastructure is successfully applied
- **THEN** outputs include controller_ips and worker_ips as JSON arrays
- **AND** outputs include vm_details map with public_ip, private_ip, zone per host
- **AND** outputs include resource_group/vpc_id for cleanup operations

#### Scenario: Network configuration output
- **WHEN** networking module completes
- **THEN** outputs include wireguard_port, subnet_id, security_group_id
- **AND** outputs include ssh_key_name for VM connection

### Requirement: Terraform State Backend Configuration
The system SHALL support remote state storage with locking for both Azure and AWS backends.

#### Scenario: Azure Storage backend initialization
- **WHEN** terraform init is run with azurerm backend configuration
- **THEN** state is stored in Azure Storage container with blob locking
- **AND** state key includes cluster_id for multi-deployment isolation

#### Scenario: AWS S3 backend initialization
- **WHEN** terraform init is run with s3 backend configuration
- **THEN** state is stored in S3 bucket with DynamoDB table locking
- **AND** state key includes cluster_id for multi-deployment isolation

#### Scenario: Local state fallback
- **WHEN** no backend configuration is provided
- **THEN** Terraform uses local state file in terraform/ directory
- **AND** warning is displayed about lack of locking for team deployments

### Requirement: Cloud Provider Selection
The system SHALL allow runtime selection between Azure and AWS providers via configuration variable.

#### Scenario: Azure provider activation
- **WHEN** cloud_provider variable is set to "azure"
- **THEN** only Azure modules are instantiated (count = 1)
- **AND** AWS modules are skipped (count = 0)
- **AND** Azure provider is configured with credentials from azure-credentials.yaml

#### Scenario: AWS provider activation
- **WHEN** cloud_provider variable is set to "aws"
- **THEN** only AWS modules are instantiated (count = 1)
- **AND** Azure modules are skipped (count = 0)
- **AND** AWS provider is configured with credentials from aws-credentials.yaml

#### Scenario: Invalid provider rejection
- **WHEN** cloud_provider variable is set to unsupported value
- **THEN** Terraform plan fails with validation error
- **AND** error message lists supported providers (azure, aws)
