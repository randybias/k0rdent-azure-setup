# Implementation Tasks

## 1. Module Foundation (Azure)
- [ ] 1.1 Create terraform/modules/azure/network module (RG, VNet, subnet, NSG, SSH key)
- [ ] 1.2 Create terraform/modules/azure/compute module (VMs with cloud-init, zones, spot support)
- [ ] 1.3 Define module outputs (IPs, resource names, WireGuard port passthrough)
- [ ] 1.4 Write module variables with defaults matching current k0rdent.yaml schema
- [ ] 1.5 Add validation rules (VM sizes, regions, zone availability)

## 2. Module Foundation (AWS - Framework)
- [ ] 2.1 Create terraform/modules/aws/network module (VPC, subnets, IGW, security groups)
- [ ] 2.2 Create terraform/modules/aws/compute module (EC2 instances with user-data, AZ placement)
- [ ] 2.3 Define AWS module outputs (instance IPs, IDs, security group IDs)
- [ ] 2.4 Write module variables matching AWS child cluster patterns
- [ ] 2.5 Add AWS-specific validation (instance types, regions, AZs)

## 3. Root Module and Provider Selection
- [ ] 3.1 Create terraform/main.tf with provider selection logic (var.cloud_provider)
- [ ] 3.2 Configure Azure provider with credentials from config/azure-credentials.yaml
- [ ] 3.3 Configure AWS provider with credentials from config/aws-credentials.yaml
- [ ] 3.4 Set up backend configuration for remote state (Azure Storage + S3 options)
- [ ] 3.5 Create terraform/versions.tf with required provider versions

## 4. Configuration Integration
- [ ] 4.1 Extend bin/configure.sh to generate terraform.tfvars.json from k0rdent.yaml
- [ ] 4.2 Map YAML sections to Terraform variables (azure, network, vm_sizing, cluster, timeouts)
- [ ] 4.3 Handle WireGuard port from state or generate new random port
- [ ] 4.4 Generate separate tfvars for Azure vs AWS deployments
- [ ] 4.5 Validate generated tfvars against module variable definitions

## 5. Terraform Wrapper Script
- [ ] 5.1 Create bin/terraform-wrapper.sh with init/plan/apply/destroy commands
- [ ] 5.2 Implement --cloud-provider flag (azure|aws) for provider selection
- [ ] 5.3 Add --backend-config for remote state initialization
- [ ] 5.4 Parse Terraform outputs and store in deployment-state.yaml
- [ ] 5.5 Add --legacy flag to skip Terraform and use bash scripts

## 6. State Management Integration
- [ ] 6.1 Add terraform_state_available() function to etc/state-management.sh
- [ ] 6.2 Implement get_terraform_output() to read Terraform outputs
- [ ] 6.3 Update update_vm_state() to prefer Terraform outputs over Azure CLI
- [ ] 6.4 Add terraform state file path tracking in deployment-state.yaml
- [ ] 6.5 Create terraform_reconcile_state() to sync Terraform → YAML state

## 7. Bash Script Updates
- [ ] 7.1 Update deploy-k0rdent.sh to call terraform-wrapper.sh before orchestration
- [ ] 7.2 Modify bin/prepare-deployment.sh to pass cloud-init files to Terraform
- [ ] 7.3 Update bin/manage-vpn.sh to read VM IPs from Terraform outputs
- [ ] 7.4 Modify bin/install-k0s.sh to use Terraform-provided inventory
- [ ] 7.5 Add Terraform validation to bin/check-prerequisites.sh

## 8. Testing and Validation
- [ ] 8.1 Test Azure deployment end-to-end with Terraform modules
- [ ] 8.2 Test AWS framework with sample EC2 deployment
- [ ] 8.3 Verify cloud-init/user-data injection works correctly
- [ ] 8.4 Test spot instance handling and failure recovery
- [ ] 8.5 Validate multi-zone deployments for both clouds
- [ ] 8.6 Test Terraform state import for existing bash-created resources
- [ ] 8.7 Verify --legacy flag maintains bash-only path

## 9. Documentation
- [ ] 9.1 Create docs/terraform-usage.md with workflow examples
- [ ] 9.2 Document remote state setup for Azure Storage and S3
- [ ] 9.3 Write migration guide for existing deployments
- [ ] 9.4 Document tfvars generation from k0rdent.yaml
- [ ] 9.5 Add troubleshooting section for common Terraform issues
- [ ] 9.6 Update README.md with new Terraform-based workflow
- [ ] 9.7 Create terraform/README.md explaining module structure

## 10. Migration and Cleanup
- [ ] 10.1 Add terraform import commands for existing Azure resources
- [ ] 10.2 Create migration script to transition active deployments
- [ ] 10.3 Deprecate bin/setup-azure-network.sh with warning message
- [ ] 10.4 Deprecate bin/create-azure-vms.sh with warning message
- [ ] 10.5 Archive deprecated scripts to old_scripts/ directory
