---
id: task-MEDIUM.06
title: Refactor create-child scripts to extract common components
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - enhancement
  - refactoring
dependencies: []
parent_task_id: task-MEDIUM
---

## Description

Refactor the create-child scripts to extract common components into a single support script, leaving only cloud-specific pieces in the per-cloud scripts.

## Acceptance Criteria

- [ ] Identify all common code between existing scripts
- [ ] Create etc/child-cluster-common.sh with common functions
- [ ] Update create-azure-child.sh to use common functions
- [ ] Update create-aws-child.sh to use common functions
- [ ] Ensure backward compatibility
- [ ] Create template for new cloud providers
