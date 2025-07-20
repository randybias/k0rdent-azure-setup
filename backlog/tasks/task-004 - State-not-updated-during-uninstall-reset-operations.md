---
id: task-004
title: State not updated during uninstall/reset operations
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - bug
  - high-priority
dependencies: []
priority: high
---

## Description

State management is not properly updated when uninstalling k0rdent or k0s, or during reset operations. This causes inconsistent state tracking when moving backwards through deployment stages.

## Acceptance Criteria

- [ ] k0rdent uninstall reverts state from k0rdent_deployed to k0s_deployed
- [ ] k0s uninstall reverts state from k0s_deployed to vms_ready
- [ ] Reset operations systematically clean up state at each step
- [ ] State always reflects actual deployment status
- [ ] Add state rollback functions for phase transitions backwards
- [ ] Add validation that state matches actual system status

## Technical Details

### Current Issues
- Uninstalling k0rdent doesn't properly reset state to previous phase
- Uninstalling k0s doesn't update state appropriately
- Reset operations may leave stale state information
- No systematic state rollback when undoing deployment steps

### Expected Behavior
- **k0rdent uninstall**: Should revert state from `k0rdent_deployed` back to `k0s_deployed`
- **k0s uninstall**: Should revert state from `k0s_deployed` back to `vms_ready` or `infrastructure_ready`
- **Reset operations**: Should systematically clean up state as each component is removed
- **State consistency**: State should always reflect the actual deployment status

### Implementation Requirements
- Update `bin/install-k0rdent.sh uninstall` to properly reset state
- Update `bin/install-k0s.sh uninstall` to properly reset state
- Add state rollback functions to handle phase transitions backwards
- Ensure reset operations update state at each step
- Add validation that state matches actual system status

### State Fields to Track
- `phase` - Current deployment phase
- `k0rdent_installed` - k0rdent installation status
- `k0rdent_ready` - k0rdent readiness status
- `k0s_installed` - k0s installation status
- `vms_ready` - VM deployment status
- `infrastructure_ready` - Azure infrastructure status

### Affected Scripts
- `bin/install-k0rdent.sh` - uninstall command
- `bin/install-k0s.sh` - uninstall command
- `deploy-k0rdent.sh` - reset operations
- All scripts that perform reset/cleanup operations

### Current Impact
- State file shows incorrect status after uninstalls
- Difficulty determining actual deployment state
- Potential for script logic errors based on stale state
- Inconsistent behavior during repeated deploy/undeploy cycles
