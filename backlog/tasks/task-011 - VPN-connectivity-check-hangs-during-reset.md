---
id: task-011
title: VPN connectivity check hangs during reset
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - bug
  - vpn
  - reset
dependencies: []
priority: low
---

## Description

When running reset operations (uninstalling k0rdent or removing k0s cluster), the VPN connectivity check hangs and requires multiple Ctrl+C to interrupt. Recent updates include ping timeouts (ping -c 3 -W 5000) in multiple scripts. This bug may have been resolved during recent improvements but needs testing to confirm.

## Acceptance Criteria

- [ ] VPN connectivity checks do not hang during reset operations
- [ ] Reset operations complete cleanly without requiring manual interruption
- [ ] Ping commands timeout properly if VPN is disconnected
