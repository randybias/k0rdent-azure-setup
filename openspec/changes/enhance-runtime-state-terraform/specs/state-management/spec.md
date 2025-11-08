# State Management Specification

## MODIFIED Requirements

### Requirement: Deployment State Structure
The system SHALL maintain separate layers for infrastructure facts (from Terraform) and runtime orchestration state (bash-managed).

#### Scenario: Terraform-aware state initialization
- **WHEN** init_deployment_state() is called with Terraform enabled
- **THEN** deployment-state.yaml includes terraform_state_path and terraform_backend sections
- **AND** infrastructure_facts section is initialized empty (populated on first sync)
- **AND** deployment_runs array is initialized with first run entry

#### Scenario: Legacy state initialization
- **WHEN** init_deployment_state() is called without Terraform
- **THEN** deployment-state.yaml uses legacy structure with runtime state only
- **AND** infrastructure facts are stored directly (azure_rg_status, vm_states)
- **AND** terraform_state_path is null

#### Scenario: State migration on script execution
- **WHEN** script detects old state format (no deployment_runs)
- **THEN** automatic migration converts to new structure
- **AND** old state is backed up to old_deployments with migration timestamp
- **AND** infrastructure facts are preserved in infrastructure_facts cache

### Requirement: Deployment Run Tracking
The system SHALL track each deployment attempt as a separate run with configuration snapshot and outcome.

#### Scenario: New deployment run initialization
- **WHEN** deploy-k0rdent.sh deploy is executed
- **THEN** unique run_id is generated (timestamp-RANDOM)
- **AND** run entry is added to deployment_runs array
- **AND** configuration snapshot (cluster size, versions, flags) is stored
- **AND** current_run_id is set to new run_id

#### Scenario: Run completion recording
- **WHEN** deployment completes or fails
- **THEN** complete_deployment_run(outcome) updates run entry
- **AND** outcome is set to "success", "failed", or "interrupted"
- **AND** end_time and duration are recorded
- **AND** final phase status is snapshot in run entry

#### Scenario: Deployment history retrieval
- **WHEN** user executes deploy-k0rdent.sh status --show-history
- **THEN** all runs from deployment_runs array are displayed
- **AND** each run shows run_id, start time, duration, outcome, configuration
- **AND** failed runs highlight error phase and message

### Requirement: Phase Applicability Filtering
The system SHALL only initialize and track phases applicable to current deployment configuration.

#### Scenario: KOF phases excluded when disabled
- **WHEN** deployment_flags.kof is false
- **THEN** install_kof_mothership and install_kof_regional phases are not initialized
- **AND** phase_is_applicable("install_kof_mothership") returns false
- **AND** no warnings about incomplete KOF phases are shown

#### Scenario: Azure child cluster phases excluded when disabled
- **WHEN** deployment_flags.azure_children is false
- **THEN** setup_azure_children phase is not initialized
- **AND** phase completion checks skip azure_children phase
- **AND** deployment is considered complete without Azure child phases

#### Scenario: Dynamic phase list generation
- **WHEN** start_deployment_run() initializes phases
- **THEN** only applicable phases from PHASE_SEQUENCE are included
- **AND** phase applicability is determined by deployment_flags
- **AND** phases map is created with only applicable phase entries

## REMOVED Requirements

### Requirement: Direct Infrastructure Fact Storage in State
**Reason**: Infrastructure facts now sourced from Terraform state; cached copy in infrastructure_facts only for offline access.

**Migration**: Scripts read from get_terraform_output() which checks Terraform first, then cache; no longer populate azure_rg_status, azure_network_status, vm_states directly.

#### Scenario: VM states map in deployment state
- **Previous behavior**: vm_states map stored public_ip, private_ip, state per VM
- **New behavior**: VM info retrieved from Terraform outputs; minimal runtime status (ssh_verified, cloud_init_done) tracked separately

## ADDED Requirements

### Requirement: Infrastructure Facts Caching
The system SHALL cache Terraform outputs in deployment-state.yaml for offline access and performance.

#### Scenario: Terraform output sync to cache
- **WHEN** sync_terraform_to_state() is called after Terraform apply
- **THEN** terraform output -json results are stored in infrastructure_facts section
- **AND** cache_timestamp and terraform_state_checksum are recorded
- **AND** cached data includes all outputs: controller_ips, worker_ips, vm_details, resource identifiers

#### Scenario: Cache freshness validation
- **WHEN** get_cached_infra(key) is called
- **THEN** function checks cache_timestamp against freshness threshold (default 1 hour)
- **AND** if cache is stale, warning is logged suggesting terraform refresh
- **AND** stale cache data is still returned unless --require-fresh flag set

#### Scenario: Cache invalidation on infrastructure change
- **WHEN** Terraform apply modifies infrastructure
- **THEN** previous infrastructure_facts cache is marked stale with old_cache_timestamp
- **AND** new cache overwrites infrastructure_facts with fresh outputs
- **AND** scripts automatically use new cache on next invocation

### Requirement: Runtime State Functions
The system SHALL provide separate functions for runtime orchestration state vs infrastructure cache updates.

#### Scenario: Runtime state update
- **WHEN** update_runtime_state("wg_keys_generated", true) is called
- **THEN** value is stored in runtime section of state (not infrastructure)
- **AND** timestamp is updated on runtime section
- **AND** infrastructure cache is not affected

#### Scenario: Infrastructure cache update
- **WHEN** update_infra_cache("controller_ips", ["10.0.1.4", "10.0.1.5"]) is called
- **THEN** value is stored in infrastructure_facts section
- **AND** cache_timestamp is updated
- **AND** runtime state is not affected

#### Scenario: Unified state getter
- **WHEN** get_state(key) is called
- **THEN** function first checks runtime state for key
- **AND** if not found, checks infrastructure_facts cache
- **AND** if still not found, attempts get_terraform_output(key) if Terraform available
- **AND** returns null if all sources exhausted

### Requirement: Terraform State Reference Tracking
The system SHALL track Terraform state location and configuration for re-initialization and diagnostics.

#### Scenario: Terraform state path recording
- **WHEN** Terraform infrastructure is applied
- **THEN** terraform_state_path is stored (absolute path to state file or backend identifier)
- **AND** terraform_backend type is recorded (local, azurerm, s3)
- **AND** terraform_version used for apply is logged

#### Scenario: Backend configuration persistence
- **WHEN** Terraform uses remote backend (azurerm or s3)
- **THEN** backend configuration is stored in state (storage account, bucket, key)
- **AND** configuration can be reused to initialize Terraform in new shell session
- **AND** terraform-wrapper.sh reads backend config from state for init command

#### Scenario: State file migration tracking
- **WHEN** Terraform state is migrated from local to remote backend
- **THEN** old state path is archived in state with migration_timestamp
- **AND** new backend configuration replaces terraform_backend section
- **AND** migration event is logged in deployment_events

### Requirement: Minimal Runtime VM Tracking
The system SHALL track only runtime status of VMs (SSH connectivity, cloud-init completion) separate from infrastructure facts.

#### Scenario: VM runtime status recording
- **WHEN** VM SSH connectivity is verified
- **THEN** vm_runtime_status map stores ssh_verified: true for VM
- **AND** verification_timestamp is recorded
- **AND** infrastructure facts (IP, size, zone) are not duplicated from Terraform

#### Scenario: Cloud-init completion tracking
- **WHEN** cloud-init completes on VM
- **THEN** vm_runtime_status stores cloud_init_complete: true
- **AND** completion_timestamp is recorded
- **AND** runtime status is independent of infrastructure facts

#### Scenario: Runtime status vs infrastructure facts separation
- **WHEN** scripts query VM information
- **THEN** get_vm_info(vm_name, "public_ip") reads from Terraform outputs/cache
- **AND** get_vm_runtime_status(vm_name, "ssh_verified") reads from vm_runtime_status map
- **AND** two lookups are independent and serve different purposes

### Requirement: State History and Debugging
The system SHALL provide tools to inspect deployment history and debug state issues.

#### Scenario: Deployment history display
- **WHEN** show_deployment_history() is called
- **THEN** function displays table of all deployment runs
- **AND** table includes run_id, start_time, duration, outcome, phases completed
- **AND** failed runs are highlighted with error information

#### Scenario: Detailed run inspection
- **WHEN** show_run_details(run_id) is called
- **THEN** function displays full configuration snapshot for run
- **AND** shows phase progression with timestamps
- **AND** displays Terraform state path and backend config at time of run
- **AND** includes error messages and logs if run failed

#### Scenario: Run comparison for debugging
- **WHEN** compare_runs(run_id1, run_id2) is called
- **THEN** function shows configuration differences between runs
- **AND** highlights changed settings (VM sizes, versions, enabled flags)
- **AND** shows phase outcome differences
- **AND** helps identify what changed between successful and failed deployments
