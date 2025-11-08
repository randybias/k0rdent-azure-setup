---
id: task-009
title: State not being archived to old_deployments
status: Done
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

State files under state/ directory are not being archived into old_deployments/ when starting new deployments, causing loss of historical deployment data.

## Acceptance Criteria

- [ ] Check for existing state files during deployment initialization
- [ ] Create timestamped subdirectory under old_deployments/
- [ ] Move all state files to archive before creating new ones
- [ ] Include deployment ID in archive directory name
- [ ] Ensure atomic move operation to prevent data loss
- [ ] Implement archive structure with deployment ID and timestamp


## Implementation Notes

Implemented archive_existing_state() function that archives to timestamped directories with deployment ID. Listed as completed in BACKLOG-COMPLETED-2025-01-20.md.
## Technical Details

### Current Behavior
- State files (deployment-state.yaml, deployment-events.yaml) remain in state/ directory
- No automatic archival to old_deployments/ during new deployments
- Previous deployment history is overwritten
- Manual backup required to preserve state

### Expected Behavior
- When starting a new deployment, existing state files should be moved to old_deployments/
- Archive should include timestamp and deployment ID for identification
- State directory should be clean for new deployment
- Historical deployments preserved for reference

### Implementation Requirements
- Check for existing state files during deployment initialization
- Create timestamped subdirectory under old_deployments/
- Move all state files to archive before creating new ones
- Include deployment ID in archive directory name
- Ensure atomic move operation to prevent data loss

### Archive Structure Example
```
old_deployments/
├── k0rdent-abc123_2025-07-13_08-30-00/
│   ├── deployment-state.yaml
│   └── deployment-events.yaml
└── k0rdent-xyz789_2025-07-12_14-45-30/
    ├── deployment-state.yaml
    └── deployment-events.yaml
```

### Files to Archive
- state/deployment-state.yaml
- state/deployment-events.yaml
- Any other state files created during deployment

### Impact
- Loss of deployment history
- Cannot review previous deployment configurations
- Difficulty debugging issues from past deployments
- No audit trail of deployment activities
