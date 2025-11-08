# Change: Enhance Runtime State Management for Terraform Integration

## Why

Current deployment-state.yaml mixes infrastructure facts (VM IPs, Azure resource status) with runtime orchestration state (WireGuard connected, k0s installed). With Terraform owning infrastructure:

- Infrastructure facts should be read from Terraform state, not duplicated in YAML
- deployment-state.yaml should focus on runtime orchestration status
- Optional components (KOF, Azure child clusters) cause confusing phase warnings
- No run/attempt tracking makes troubleshooting multi-attempt deployments difficult
- State file grows with unused keys from previous deployment attempts

Need clean separation: Terraform state → infrastructure, YAML state → runtime orchestration.

## What Changes

Restructure deployment-state.yaml to reference Terraform state and track runtime orchestration:

**Infrastructure Layer (read from Terraform)**:
- terraform_state_path: Location of Terraform state file
- terraform_backend: Backend configuration (azurerm, s3, local)
- last_terraform_sync: Timestamp of last output sync
- infrastructure_facts: Cached Terraform outputs for offline access

**Runtime Orchestration Layer (managed by bash)**:
- deployment_runs: Array of deployment attempts with timestamps
- current_run_id: Active run identifier
- phases: Only phases relevant to current run (skip KOF if not enabled)
- wireguard_config: Keys, IPs, laptop config status
- k0s_cluster_state: k0sctl status, kubeconfig location
- k0rdent_install_state: Helm release status, namespace

**Changes to etc/state-management.sh**:
- Split `update_state()` into `update_runtime_state()` and `update_infra_cache()`
- Remove `azure_rg_status`, `azure_network_status` (read from Terraform)
- Add `start_deployment_run()` and `complete_deployment_run()`
- Implement `phase_is_applicable()` to skip optional component phases

## Impact

- **BREAKING**: deployment-state.yaml structure changes; migration script provided
- **Affected code**:
  - `etc/state-management.sh` - major refactor of state functions
  - All scripts using `update_state()` - need to use new split functions
  - `bin/prepare-deployment.sh` - uses new run tracking
  - `deploy-k0rdent.sh` - initializes deployment runs
- **Affected specs**: Updates `state-management` capability
- **Migration**: Auto-migrate old state format on first script execution

## Benefits

- **Clear separation**: Infrastructure in Terraform, orchestration in YAML
- **Run tracking**: Each deployment attempt tracked with outcomes
- **No phase noise**: Only applicable phases appear in state
- **Smaller state**: No infrastructure duplication, cleaner structure
- **Better debugging**: Run history aids troubleshooting

## Risks & Mitigations

- **State migration failures**: Test migration script thoroughly; provide manual conversion guide
- **Script updates**: Update all scripts using state functions; use deprecation warnings during transition
- **Backward compatibility**: Old scripts detect new state format and advise upgrade
