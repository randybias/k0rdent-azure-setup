---
id: task-006
title: Incorrect validation requiring at least 1 worker node
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

The validation in etc/config-internal.sh incorrectly requires at least 1 worker node, but k0s can operate with a single controller+worker node configuration (controller with workload scheduling enabled).

## Acceptance Criteria

- [ ] Update validation in etc/config-internal.sh to allow worker count of 0
- [ ] Add appropriate warning when worker count is 0
- [ ] Document single-node deployment pattern
- [ ] Ensure k0s configuration enables workload scheduling on controllers when worker count is 0
- [ ] Test single controller node can run k0rdent and workloads

## Technical Details

### Current Behavior
```bash
ERROR: K0S_WORKER_COUNT must be at least 1
```

### Expected Behavior
- Should allow `worker.count: 0` when controller nodes can run workloads
- k0s supports controller nodes that also schedule workloads (not tainted)
- Single node deployments should be possible with just a controller

### Technical Details
- k0s controllers can run workloads if not tainted with `node-role.kubernetes.io/master:NoSchedule`
- The `--enable-worker` flag or configuration allows controllers to schedule pods
- Common pattern for development/testing environments

### Fix Required
- Update validation in `etc/config-internal.sh` lines 14-17
- Allow worker count of 0 with appropriate warning
- Document single-node deployment pattern
- Ensure k0s configuration enables workload scheduling on controllers when worker count is 0

### Testing Requirements
- Verify single controller node can run k0rdent and workloads
- Test with `worker.count: 0` configuration
- Confirm pods schedule on controller node
- Validate k0rdent installation works without dedicated workers

### Impact
- Blocks minimal single-node deployments
- Forces unnecessary resource usage for development
- Prevents valid k0s deployment patterns
