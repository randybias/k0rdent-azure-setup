---
id: task-005
title: Reset operations fail when components are broken
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

Reset operations fail when VPN is disconnected, WireGuard interfaces are corrupted, or other components are in broken states, preventing complete cleanup and requiring manual intervention.

## Acceptance Criteria

- [ ] Add --force flag to deploy-k0rdent.sh reset command
- [ ] Skip connectivity checks during forced reset
- [ ] Continue on errors when force flag is used
- [ ] Use Azure CLI directly to find and delete resources by tags/names
- [ ] Implement best-effort WireGuard cleanup for broken interfaces
- [ ] Skip VPN connectivity requirements during forced reset operations

## Technical Details

### Observed Failures
- VPN connectivity checks block k0rdent/k0s uninstall during reset
- WireGuard interface cleanup fails when interface is in inconsistent state
- Partial deployments can't be cleaned up due to dependency checks
- Reset operations stop on first error instead of continuing with cleanup

### Root Cause
Reset operations have the same dependency requirements as deployment operations, but should be more aggressive about cleanup when things are broken.

### Proposed Fix
Add `--force` or `--ignore-errors` flag for reset operations:
- **Skip connectivity checks**: Don't require VPN for reset operations
- **Continue on errors**: Log errors but continue cleanup process
- **Brute force cleanup**: Use Azure CLI directly to find and delete resources by tags/names
- **Best effort approach**: Clean up what can be cleaned, ignore what can't
- **Nuclear option**: Complete reset regardless of component states

### Implementation Needed
- Add `--force` flag to deploy-k0rdent.sh reset command
- Modify all reset functions to continue on errors when force flag is used
- Add resource discovery via Azure CLI for orphaned resources
- Implement best-effort WireGuard cleanup that handles broken interfaces
- Skip VPN connectivity requirements during forced reset operations

### Benefits
- Enables cleanup after failed deployments
- Reduces manual intervention requirements
- Supports "cattle" methodology by making resource disposal reliable
- Prevents resource leakage from partial deployments

**Impact**: Blocks cleanup operations, leads to resource leakage and manual cleanup requirements

**Reported**: 2025-06-10
