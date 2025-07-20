---
id: task-008
title: Reset with --force doesn't clean up local state files
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - bug
  - medium-priority
dependencies: []
---

## Description

The --force reset operation doesn't properly clean up local deployment state files, leaving stale data that can interfere with subsequent deployments.

## Acceptance Criteria

- [ ] Force reset cleans up deployment-state.yaml
- [ ] Force reset cleans up deployment-events.yaml
- [ ] Force reset cleans up .clusterid file
- [ ] Force reset removes all local deployment artifacts
- [ ] Complete reset leaves system in clean state for new deployments
- [ ] Test subsequent deployments work correctly after force reset
