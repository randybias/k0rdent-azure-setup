---
id: task-004
title: State not updated during uninstall/reset operations
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - bug
  - high-priority
dependencies: []
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
