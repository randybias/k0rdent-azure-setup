---
id: task-017
title: Create delete-all-child-clusters.sh with filtering
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - automation
  - child-clusters
dependencies: []
priority: high
---

## Description

Create a script to delete all child clusters managed by k0rdent with filtering options by namespace, cloud provider, or region. This will enable bulk cleanup operations for development and testing workflows.

## Acceptance Criteria

- [ ] Script can list all child clusters before deletion
- [ ] Filtering by namespace cloud provider or region works correctly
- [ ] Dry-run mode shows what would be deleted
- [ ] Confirmation prompt prevents accidental deletions
- [ ] Proper error handling for failed deletions
