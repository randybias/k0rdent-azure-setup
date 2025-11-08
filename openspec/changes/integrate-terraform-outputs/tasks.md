# Implementation Tasks

## 1. State Management Terraform Integration
- [ ] 1.1 Add terraform_state_exists() function to check for .terraform directory and tfstate
- [ ] 1.2 Implement get_terraform_output(key) to read terraform output -json
- [ ] 1.3 Create get_terraform_output_vm_ips() to parse controller/worker IP arrays
- [ ] 1.4 Implement sync_terraform_to_state() to copy Terraform outputs → deployment-state.yaml
- [ ] 1.5 Update get_vm_info() to try Terraform outputs first, then state, then API

## 2. Terraform Wrapper Output Handling
- [ ] 2.1 Add output extraction logic to terraform-wrapper.sh after apply/refresh
- [ ] 2.2 Parse terraform output -json and store in deployment-state.yaml terraform_outputs section
- [ ] 2.3 Add timestamp tracking for output freshness
- [ ] 2.4 Implement error handling for missing expected outputs
- [ ] 2.5 Add --refresh-outputs flag to re-sync without full apply

## 3. Deployment Preparation Script Updates
- [ ] 3.1 Update bin/prepare-deployment.sh to validate Terraform state if present
- [ ] 3.2 Check that required Terraform outputs exist before generating cloud-init
- [ ] 3.3 Add warning if Terraform state stale (timestamp check)
- [ ] 3.4 Generate cloud-init files compatible with Terraform custom_data format
- [ ] 3.5 Add --skip-terraform-check flag for legacy deployments

## 4. VPN Management Script Updates
- [ ] 4.1 Update bin/manage-vpn.sh to use get_vm_info() for IP retrieval
- [ ] 4.2 Add fallback logic if Terraform outputs unavailable (use Azure CLI)
- [ ] 4.3 Validate WireGuard port from Terraform output matches configuration
- [ ] 4.4 Update connection verification to work with Terraform-provisioned infrastructure
- [ ] 4.5 Add diagnostics for Terraform vs legacy infrastructure detection

## 5. K0s Installation Script Updates
- [ ] 5.1 Update bin/install-k0s.sh inventory generation to use Terraform outputs
- [ ] 5.2 Build k0sctl hosts array from controller_ips and worker_ips outputs
- [ ] 5.3 Validate SSH connectivity using IPs from Terraform
- [ ] 5.4 Add error handling for missing Terraform controller/worker output keys
- [ ] 5.5 Maintain backward compatibility with state-only deployments

## 6. Main Deployment Script Orchestration
- [ ] 6.1 Update deploy-k0rdent.sh to call terraform-wrapper.sh apply before orchestration
- [ ] 6.2 Add --skip-terraform flag to bypass infrastructure provisioning
- [ ] 6.3 Add --terraform-only flag to stop after infrastructure creation
- [ ] 6.4 Implement phase detection: if Terraform state exists, skip legacy scripts
- [ ] 6.5 Add --force-legacy flag to use bash scripts even if Terraform available

## 7. Output Schema Validation
- [ ] 7.1 Define expected Terraform output structure in JSON schema
- [ ] 7.2 Create validate_terraform_outputs() function in state-management.sh
- [ ] 7.3 Check for required keys: controller_ips, worker_ips, resource_group/vpc_id
- [ ] 7.4 Validate IP address formats and reachability
- [ ] 7.5 Add descriptive error messages for missing or malformed outputs

## 8. Multi-Cloud Output Handling
- [ ] 8.1 Abstract provider-specific output keys (resource_group vs vpc_id)
- [ ] 8.2 Create get_cloud_provider() function to detect Azure vs AWS from state
- [ ] 8.3 Implement provider-specific output mapping in get_terraform_output()
- [ ] 8.4 Update scripts to handle both Azure and AWS output structures
- [ ] 8.5 Test output consumption with AWS module outputs (when available)

## 9. Testing and Validation
- [ ] 9.1 Test Terraform → bash workflow with Azure module
- [ ] 9.2 Test legacy bash workflow (no Terraform) still works
- [ ] 9.3 Test fallback from Terraform to API queries when outputs missing
- [ ] 9.4 Verify spot instance replacement updates Terraform outputs correctly
- [ ] 9.5 Test --skip-terraform and --terraform-only flags
- [ ] 9.6 Validate error handling for corrupted Terraform state

## 10. Documentation
- [ ] 10.1 Document Terraform output schema in docs/terraform-outputs.md
- [ ] 10.2 Add troubleshooting section for output sync issues
- [ ] 10.3 Update deployment workflow diagrams with Terraform integration
- [ ] 10.4 Document fallback behavior and detection logic
- [ ] 10.5 Create examples of manual output refresh procedures
