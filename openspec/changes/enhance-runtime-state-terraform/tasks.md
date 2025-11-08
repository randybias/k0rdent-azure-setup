# Implementation Tasks

## 1. State Structure Redesign
- [ ] 1.1 Design new deployment-state.yaml schema with Terraform and runtime sections
- [ ] 1.2 Create JSON schema for validation of new state structure
- [ ] 1.3 Define deployment_runs array structure with run_id, timestamp, phases, outcome
- [ ] 1.4 Design infrastructure_facts cache section for Terraform output snapshot
- [ ] 1.5 Remove infrastructure-specific keys (azure_rg_status, vm_states raw data)

## 2. State Migration Script
- [ ] 2.1 Create bin/migrate-state.sh to convert old format to new format
- [ ] 2.2 Extract infrastructure facts to infrastructure_facts cache
- [ ] 2.3 Convert single deployment to deployment_runs array with current run
- [ ] 2.4 Preserve runtime state (wireguard, k0s, k0rdent status)
- [ ] 2.5 Add backup of old state to old_deployments before migration

## 3. State Management Function Refactor
- [ ] 3.1 Rename update_state() to update_runtime_state() with deprecation warning
- [ ] 3.2 Create update_infra_cache() for Terraform output caching
- [ ] 3.3 Implement start_deployment_run() to initialize new run entry
- [ ] 3.4 Implement complete_deployment_run(outcome) to finalize run
- [ ] 3.5 Update get_state() to handle both runtime and cache lookups

## 4. Deployment Run Tracking
- [ ] 4.1 Generate unique run_id using timestamp + random suffix
- [ ] 4.2 Store run start time, configuration snapshot, enabled flags
- [ ] 4.3 Track phase completion per run (not global state)
- [ ] 4.4 Record run outcome (success, failed, interrupted)
- [ ] 4.5 Implement get_current_run_id() and get_run_info(run_id, key)

## 5. Phase Applicability Logic
- [ ] 5.1 Create phase_is_applicable(phase_name) function
- [ ] 5.2 Check deployment_flags (kof, azure_children) to determine applicability
- [ ] 5.3 Skip phase initialization for non-applicable phases
- [ ] 5.4 Update phase_mark_completed() to only mark applicable phases
- [ ] 5.5 Remove warnings for skipped non-applicable phases

## 6. Infrastructure Cache Management
- [ ] 6.1 Implement cache_terraform_outputs() to snapshot outputs in state
- [ ] 6.2 Add cache timestamp and Terraform state checksum for staleness detection
- [ ] 6.3 Create get_cached_infra(key) to read from infrastructure_facts
- [ ] 6.4 Implement cache_invalidate() when Terraform state changes
- [ ] 6.5 Add cache freshness validation with configurable threshold

## 7. Terraform State Reference Tracking
- [ ] 7.1 Store terraform_state_path in deployment state
- [ ] 7.2 Record terraform_backend type (azurerm, s3, local)
- [ ] 7.3 Store backend configuration (storage account, bucket name) for re-initialization
- [ ] 7.4 Add terraform_version used for infrastructure
- [ ] 7.5 Track last successful Terraform apply/refresh timestamp

## 8. VM State Abstraction
- [ ] 8.1 Remove raw vm_states map from deployment-state.yaml
- [ ] 8.2 Implement get_vm_info() to read from Terraform outputs or cache
- [ ] 8.3 Add minimal runtime VM tracking (SSH verified, cloud-init complete)
- [ ] 8.4 Store only runtime status, not infrastructure facts
- [ ] 8.5 Update refresh_all_vm_data() to sync from Terraform, not Azure API

## 9. Script Updates for New State Structure
- [ ] 9.1 Update deploy-k0rdent.sh to call start_deployment_run()
- [ ] 9.2 Update all scripts using update_state() to use update_runtime_state()
- [ ] 9.3 Modify bin/prepare-deployment.sh to use new phase tracking
- [ ] 9.4 Update bin/manage-vpn.sh to read from infrastructure cache
- [ ] 9.5 Modify bin/install-k0s.sh, install-k0rdent.sh for new state functions

## 10. Deployment History and Diagnostics
- [ ] 10.1 Create show_deployment_history() function to list past runs
- [ ] 10.2 Implement show_run_details(run_id) for debugging specific attempts
- [ ] 10.3 Add --show-history flag to deploy-k0rdent.sh status command
- [ ] 10.4 Create cleanup_old_runs() to archive runs older than threshold
- [ ] 10.5 Add run comparison function to diff configuration between runs

## 11. Testing and Validation
- [ ] 11.1 Test state migration from old format to new format
- [ ] 11.2 Verify deployment run tracking across full deployment
- [ ] 11.3 Test phase applicability with KOF enabled/disabled
- [ ] 11.4 Validate infrastructure cache freshness detection
- [ ] 11.5 Test state recovery after interrupted deployment
- [ ] 11.6 Verify backward compatibility handling in old scripts

## 12. Documentation
- [ ] 12.1 Document new deployment-state.yaml structure in docs/state-schema.md
- [ ] 12.2 Write migration guide for existing deployments
- [ ] 12.3 Document deployment run tracking and history features
- [ ] 12.4 Create troubleshooting guide for state issues
- [ ] 12.5 Update AGENTS.md with new state management patterns
