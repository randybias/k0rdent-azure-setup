---
id: task-LOW.07
title: Reorganize Kubeconfig Storage Location
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - enhancement
  - organization
dependencies: []
parent_task_id: task-LOW
---

## Description

Move kubeconfig files from k0sctl-config/ directory to a dedicated kubeconfig/ directory for better organization and clarity.

## Acceptance Criteria

- [ ] Create new kubeconfig/ directory structure
- [ ] Update all scripts to use new location
- [ ] Implement backward compatibility checks
- [ ] Update .gitignore for new directory
- [ ] Update all documentation references
- [ ] Create migration strategy for existing deployments
