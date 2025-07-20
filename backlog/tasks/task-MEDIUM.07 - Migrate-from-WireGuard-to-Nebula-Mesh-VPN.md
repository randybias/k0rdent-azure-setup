---
id: task-MEDIUM.07
title: Migrate from WireGuard to Nebula Mesh VPN
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - enhancement
  - networking
  - nebula
dependencies: []
parent_task_id: task-MEDIUM
---

## Description

Plan migration from WireGuard to Nebula to avoid potential conflicts with other mesh VPN solutions, particularly WireGuard support in Calico CNI.

## Acceptance Criteria

- [ ] Research and prototype Nebula implementation
- [ ] Design certificate management approach
- [ ] Update network configuration for Nebula
- [ ] Modify cloud-init templates for Nebula installation
- [ ] Update bin/manage-vpn.sh for Nebula client configuration
- [ ] Test with various CNI configurations
- [ ] Create migration documentation
