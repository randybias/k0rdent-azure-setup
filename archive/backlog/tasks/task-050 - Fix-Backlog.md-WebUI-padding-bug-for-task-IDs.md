---
id: task-050
title: Fix Backlog.md WebUI padding bug for task IDs
status: To Do
assignee:
  - '@rbias'
created_date: '2025-07-22'
labels:
  - bug
  - external
dependencies: []
---

## Description

The Backlog.md WebUI is not respecting the 3-digit padding setting when creating new tasks. Task-49 was created without leading zero despite the configuration.

Additionally, the CLI is creating task IDs based on priority instead of sequential numbering (e.g., task-high.01 instead of task-051) when priority is specified during task creation.

## Acceptance Criteria

- [ ] WebUI respects configured padding when creating tasks
- [ ] Task IDs are consistently padded according to settings
