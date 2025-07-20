---
id: task-009
title: State not being archived to old_deployments
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - bug
  - medium-priority
dependencies: []
---

## Description

State files under state/ directory are not being archived into old_deployments/ when starting new deployments, causing loss of historical deployment data.

## Acceptance Criteria

- [ ] Check for existing state files during deployment initialization
- [ ] Create timestamped subdirectory under old_deployments/
- [ ] Move all state files to archive before creating new ones
- [ ] Include deployment ID in archive directory name
- [ ] Ensure atomic move operation to prevent data loss
- [ ] Implement archive structure with deployment ID and timestamp
