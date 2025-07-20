---
id: task-005
title: Reset operations fail when components are broken
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - bug
  - high-priority
dependencies: []
---

## Description

Reset operations fail when VPN is disconnected, WireGuard interfaces are corrupted, or other components are in broken states, preventing complete cleanup and requiring manual intervention.

## Acceptance Criteria

- [ ] Add --force flag to deploy-k0rdent.sh reset command
- [ ] Skip connectivity checks during forced reset
- [ ] Continue on errors when force flag is used
- [ ] Use Azure CLI directly to find and delete resources by tags/names
- [ ] Implement best-effort WireGuard cleanup for broken interfaces
- [ ] Skip VPN connectivity requirements during forced reset operations
