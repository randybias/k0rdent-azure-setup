---
id: doc-012
title: Deployment State Resume and Rollback Design
type: design
created_date: '2025-08-18'
updated_date: '2025-08-18'
---
# Deployment State Resume and Rollback Design

## Background

Repeated deployments currently re-run every phase without considering what has already succeeded. Interruptions leave partially created resources and stale state, forcing manual cleanup and undermining tasks 002, 004, and 015 in the backlog. This design formalizes the deployment phases, adds resumable phase tracking, and introduces rollback primitives so that the orchestrator can safely resume or rewind to earlier stages.

## Goals

- Provide deterministic resume behaviour for each deployment phase.
- Allow scripts to skip work when the required artefacts already exist and pass validation.
- Support rolling state backwards during reset/uninstall commands.
- Lay groundwork for richer idempotent logging and automated testing.

## Phase Model

Execution order is fixed and tracked inside `deployment-state.yaml`:

1. `prepare_deployment`
2. `setup_network`
3. `create_vms`
4. `setup_vpn`
5. `connect_vpn`
6. `install_k0s`
7. `install_k0rdent`
8. Optional: `setup_azure_children`
9. Optional: `install_azure_csi`
10. Optional: `install_kof_mothership`
11. Optional: `install_kof_regional`

Each phase owns:

- `status`: `pending`, `in_progress`, `completed`
- `updated_at`: last state update timestamp
- Validation expectations (summarised below)
- Rollback responsibility for downstream phases

## State Structure Changes

New sections in `deployment-state.yaml`:

```yaml
phases:
  prepare_deployment:
    status: pending
    updated_at: 2025-08-18T00:00:00Z
  # ...
artifacts: {}
```

- **Phase helpers** in `etc/state-management.sh`: `phase_mark_in_progress`, `phase_mark_completed`, `phase_reset_from`, `phase_needs_run`, etc.
- **Artifact registry** stores generated files (k0sctl, kubeconfig, laptop VPN config) to enable idempotent checks.
- **Migration** logic upgrades legacy state files on access.

## Resume Matrix (Summary)

| Phase | Validation Inputs | Resume Decision | Rollback Trigger |
| --- | --- | --- | --- |
| prepare_deployment | `wg_keys_generated`, cloud-init files, artifact entries | Skip if keys + files exist | Reset if files missing or keys invalid |
| setup_network | Azure RG/VNet/NSG existence, SSH key present | Skip if resources exist | Reset if any resource deleted externally |
| create_vms | VM entries in Azure + state `vm_states` | Skip if all VMs `Succeeded` | Reset if any VM missing or failed |
| setup_vpn | Laptop WireGuard config + state flags | Skip if config + state flag true | Reset if config missing |
| connect_vpn | Active tunnel or `wg_vpn_connected` false | Skip if `wg_vpn_connected` true and interface up | Reset if tunnel down |
| install_k0s | `k0s_cluster_deployed` flag, kubeconfig artifact | Skip if flag true and kubeconfig readable | Reset if kubeconfig missing |
| install_k0rdent | Helm status + flag | Skip if flag true | Reset if helm release missing |

Optional KOF/children phases follow the same pattern but are only evaluated when the corresponding deployment flags are set.

## Script Integration

- Each phase-driving script (`prepare-deployment.sh`, `setup-azure-network.sh`, etc.) now:
  - Validates existing state through helper functions.
  - Calls `phase_mark_in_progress` before doing work.
  - Records generated artefacts using `record_artifact`.
  - Calls `phase_mark_completed` after successful execution.
  - Invokes `phase_reset_from` to rewind downstream phases when validation fails.

- `deploy-k0rdent.sh` consults the phase status map before invoking a script. If validation fails, it resets the phase and retries.

- Reset/uninstall paths use `phase_reset_from` so state always reflects the effective rollback point.

## Testing Strategy

Short term:

- Add BATS unit tests for new state helpers.
- Scripted smoke test to simulate interruption and ensure `deploy-k0rdent.sh` resumes from the correct phase.

Long term:

- Extend integration tests to cover failure injection (e.g., delete a VM mid-run and verify the reconciling logic handles it).

## Follow-Up Tasks

1. Finish wiring validation and `phase_mark_*` hooks into every phase script (WIP in current change).
2. Add reset/uninstall updates so that rollback consistently clears downstream phases.
3. Introduce automated tests as outlined above.
4. Expand optional phase support once KOF automation matures.

This design unblocks the implementation of backlog tasks 002, 004, and 015 and sets the stage for more sophisticated recovery/validation logic.
