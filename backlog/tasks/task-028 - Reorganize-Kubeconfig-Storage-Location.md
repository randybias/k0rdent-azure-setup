---
id: task-028
title: Reorganize Kubeconfig Storage Location
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - organization
dependencies: []
priority: low
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
