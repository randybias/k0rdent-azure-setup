---
id: task-014
title: Fast reset doesn't clean up azure-resources and state directories
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - bug
  - reset
  - cleanup
dependencies: []
priority: low
---

## Description

The fast reset option deletes the Azure resource group but fails to clean up local directories that should be removed for a complete reset. The azure-resources/ directory containing SSH keys and state/ directory persist after fast reset, requiring manual cleanup.

## Acceptance Criteria

- [ ] Fast reset removes azure-resources/ directory
- [ ] Fast reset removes state/ directory
- [ ] Fast reset provides complete cleanup equivalent to full reset
- [ ] No manual cleanup required after fast reset

## Technical Details

### Current Issues
- `azure-resources/` directory containing SSH keys is not removed
- `state/` directory is not removed
- These directories persist after fast reset, requiring manual cleanup
- Inconsistent with full reset behavior which properly cleans these up

### Root Cause
- Fast reset focuses on Azure resource deletion but misses local cleanup
- The `setup-azure-network.sh reset` step (which removes azure-resources) is skipped in fast reset
- State directory cleanup is missing from the fast reset path

### Expected Behavior
- Fast reset should clean up all local artifacts just like full reset
- Both `azure-resources/` and `state/` directories should be removed
- Complete cleanup for fresh deployment

### Proposed Solution
- Rethink the fast reset architecture and implementation
- Consider what "fast" means - is it just about skipping k0rdent/k0s uninstall?
- Ensure all local cleanup happens regardless of reset type
- May need to restructure how cleanup is organized in the code

### Benefits
- Consistent reset behavior across fast and full modes
- No manual cleanup required after fast reset
- Better user experience with complete cleanup
- Cleaner workspace for subsequent deployments

**Impact**: Low priority but affects user experience when using fast reset for development iterations.
