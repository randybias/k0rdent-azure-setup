---
id: task-044
title: Refactor create-child scripts to extract common components
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - refactoring
dependencies: []
priority: medium
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
