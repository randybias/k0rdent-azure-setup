---
id: task-003
title: Missing k0rdent Management CRD validation
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - bug
  - high-priority
dependencies: []
---

## Description

k0rdent installation validation is incomplete - we only check pod status but don't verify the Management CRD is properly created and in Ready state. This could lead to k0rdent appearing installed but the Management controller failing.

## Acceptance Criteria

- [ ] Management CRD validation added to install-k0rdent.sh
- [ ] Management object exists and READY status is True
- [ ] Parse release name to confirm correct version deployment
- [ ] Add timeout/retry logic for Management CRD readiness
- [ ] Update state management to track Management CRD status
- [ ] Include validation in status check function
