---
id: task-010
title: Fast reset option for development workflows
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - bug
  - medium-priority
dependencies: []
priority: medium
---

## Description

Add fast reset option that skips k0rdent and k0s uninstall steps and jumps straight to deleting Azure resource groups for faster development iterations.

## Acceptance Criteria

- [ ] Add --fast flag to deploy-k0rdent.sh reset command
- [ ] Implement fast reset path that deletes entire Azure resource group
- [ ] Bypass all individual resource cleanup steps
- [ ] Maintain local file cleanup for consistency
- [ ] Add safety checks for resource group naming
- [ ] Test compatibility with existing state management

## Technical Details

### Current Reset Process
- Uninstall k0rdent from cluster
- Uninstall k0s cluster 
- Disconnect VPN
- Delete VMs individually
- Delete Azure network resources
- Clean up local files

### Proposed Fast Reset
- Skip k0rdent uninstall
- Skip k0s uninstall 
- Skip VPN disconnect (may be broken anyway)
- **Delete entire Azure resource group** (removes all VMs, networks, etc. in one operation)
- Clean up local files

### Implementation Approach
- Add `--fast` flag to reset operations
- Single Azure CLI command: `az group delete --name $RG --yes --no-wait`
- Bypass all individual resource cleanup steps
- Maintain local file cleanup for consistency

### Benefits
- Dramatically faster reset times (seconds vs minutes)
- Works even when cluster/VPN is broken
- Simpler implementation with fewer failure points
- Better developer experience for iterative testing

### Cloud Provider Considerations
- **Azure-specific**: Leverages Azure resource group deletion
- **Future multi-cloud**: Other providers may not have equivalent grouping
- **Design note**: Keep this Azure-specific, implement differently for other clouds
- **Architecture**: Consider cloud provider abstraction layer for reset operations

### Caveats
- Resource group deletion is irreversible
- May delete shared resources if RG contains non-k0rdent resources
- Requires careful resource group naming/isolation

### Implementation Tasks
- Add `--fast` flag to deploy-k0rdent.sh reset command
- Implement fast reset path in reset functions
- Add safety checks for resource group naming
- Update documentation with fast reset option
- Test compatibility with existing state management
