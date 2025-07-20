---
id: task-008
title: Reset with --force doesn't clean up local state files
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - bug
dependencies: []
priority: medium
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

## Technical Details

### Files Not Cleaned Up
- `deployment-state.yaml`
- `deployment-events.yaml` 
- `.clusterid` file
- Potentially other local state files

### Current Behavior
- Reset removes Azure resources but leaves local state
- Subsequent deployments may use stale configuration or state data
- Manual cleanup required between deployments

### Expected Behavior
- Force reset should clean up all local deployment artifacts
- Fresh state for new deployments
- Complete reset experience

### Implementation Tasks
- Identify all local state files that need cleanup
- Add local file cleanup to force reset path
- Ensure reset leaves system in clean state for new deployments
- Test that subsequent deployments work correctly after force reset
