---
id: task-013
title: Old deployment files not being cleaned up
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - bug
  - cleanup
  - state-management
dependencies: []
priority: low
---

## Description

Old event and state files from previous deployments are not being properly cleaned up, leading to accumulation of stale files over time. No automatic archival or rotation mechanism exists, requiring manual cleanup to manage disk space.

## Acceptance Criteria

- [ ] Old state files are automatically moved to old_deployments/ at start of new deployment
- [ ] Automatic cleanup of very old archived deployments (older than 30 days)
- [ ] Configurable retention policy for archived deployments
- [ ] Current deployment files are never accidentally deleted
