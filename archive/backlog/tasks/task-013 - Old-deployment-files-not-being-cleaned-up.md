---
id: task-013
title: Old deployment files not being cleaned up
status: Done
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
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


## Implementation Notes

Archival mechanism exists with archive_existing_state() function. Archives are created with timestamps but no automatic cleanup after 30 days. Basic archival functionality is complete.
## Technical Details

### Current Issues
- Old deployment state files remain in the `state/` directory
- Previous event logs accumulate without cleanup
- No automatic archival or rotation mechanism
- Manual cleanup required to manage disk space
- Potential confusion with multiple old state files present

### Files Affected
- `state/deployment-state.yaml` from previous runs
- `state/deployment-events.yaml` from previous runs
- Any temporary state files created during deployment
- Potentially other deployment artifacts

### Expected Behavior
- Old state files should be moved to `old_deployments/` at start of new deployment
- Automatic cleanup of very old archived deployments (e.g., older than 30 days)
- Option to control retention period
- Clear separation between current and historical state

### Implementation Requirements
- Add cleanup logic to deployment initialization
- Implement file rotation/archival mechanism
- Add configurable retention policy
- Ensure current deployment files are never deleted
- Add cleanup command for manual maintenance

### Proposed Solution
1. **On New Deployment Start**:
   - Check for existing state files
   - Archive to timestamped directory under `old_deployments/`
   - Clean state directory for new deployment

2. **Retention Policy**:
   - Keep last N deployments (configurable, default: 10)
   - Delete archives older than X days (configurable, default: 30)
   - Never delete if only one deployment exists

3. **Manual Cleanup Command**:
   - Add `--cleanup-old` flag to deployment script
   - Provide dry-run option to see what would be deleted
   - Allow force cleanup of all old deployments

### Benefits
- Prevents disk space issues from accumulated files
- Cleaner working directory
- Easier to identify current vs old deployments
- Maintains useful history while removing ancient data

**Impact**: Low priority as it doesn't affect functionality, but good housekeeping practice for long-term usage.
