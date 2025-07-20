---
id: task-006
title: Incorrect validation requiring at least 1 worker node
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - bug
  - medium-priority
dependencies: []
---

## Description

The validation in etc/config-internal.sh incorrectly requires at least 1 worker node, but k0s can operate with a single controller+worker node configuration (controller with workload scheduling enabled).

## Acceptance Criteria

- [ ] Update validation in etc/config-internal.sh to allow worker count of 0
- [ ] Add appropriate warning when worker count is 0
- [ ] Document single-node deployment pattern
- [ ] Ensure k0s configuration enables workload scheduling on controllers when worker count is 0
- [ ] Test single controller node can run k0rdent and workloads
