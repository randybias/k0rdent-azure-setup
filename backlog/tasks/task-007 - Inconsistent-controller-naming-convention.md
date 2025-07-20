---
id: task-007
title: Inconsistent controller naming convention
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - bug
  - medium-priority
dependencies: []
---

## Description

Controller naming is inconsistent compared to worker naming, creating confusion and scripting difficulties. First controller is named k0s-controller without number suffix, while additional controllers and all workers have numbered suffixes.

## Acceptance Criteria

- [ ] Update controller naming logic in etc/config-internal.sh to use numbered suffixes
- [ ] Controllers named k0s-controller-1 k0s-controller-2 etc
- [ ] Workers remain k0s-worker-1 k0s-worker-2 etc
- [ ] Update all scripts that reference controller names
- [ ] Test VM creation with new naming convention
