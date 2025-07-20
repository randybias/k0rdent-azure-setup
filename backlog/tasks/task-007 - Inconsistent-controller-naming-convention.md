---
id: task-007
title: Inconsistent controller naming convention
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - bug
dependencies: []
priority: medium
---

## Description

Controller naming is inconsistent compared to worker naming, creating confusion and scripting difficulties. First controller is named k0s-controller without number suffix, while additional controllers and all workers have numbered suffixes.

## Acceptance Criteria

- [ ] Update controller naming logic in etc/config-internal.sh to use numbered suffixes
- [ ] Controllers named k0s-controller-1 k0s-controller-2 etc
- [ ] Workers remain k0s-worker-1 k0s-worker-2 etc
- [ ] Update all scripts that reference controller names
- [ ] Test VM creation with new naming convention

## Technical Details

### Current Behavior
- First controller: `k0s-controller` (no number suffix)
- Additional controllers: `k0s-controller-2`, `k0s-controller-3`
- All workers: `k0s-worker-1`, `k0s-worker-2`, `k0s-worker-3` (consistently numbered)

### Expected Behavior
Consistent numbered naming for all nodes:
- Controllers: `k0s-controller-1`, `k0s-controller-2`, `k0s-controller-3`
- Workers: `k0s-worker-1`, `k0s-worker-2`, `k0s-worker-3`

### Fix Needed
Update controller naming logic in `etc/config-internal.sh` lines 54-70 to always use numbered suffixes starting from 1.

### Impact
Affects VM creation, k0s configuration generation, and any scripts that reference controller names.
