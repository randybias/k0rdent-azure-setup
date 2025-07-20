---
id: task-010
title: Fast reset option for development workflows
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - bug
  - medium-priority
dependencies: []
---

## Description

Add fast reset option that skips k0rdent and k0s uninstall steps and jumps straight to deleting Azure resource groups for faster development iterations.

## Acceptance Criteria

- [ ] Add --fast flag to deploy-k0rdent.sh reset command
- [ ] Implement fast reset path that deletes entire Azure resource group
- [ ] Bypass all individual resource cleanup steps
- [ ] Maintain local file cleanup for consistency
- [ ] Add safety checks for resource group naming
- [ ] Test compatibility with existing state management
