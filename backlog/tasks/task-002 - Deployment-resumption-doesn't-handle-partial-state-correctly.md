---
id: task-002
title: Deployment resumption doesn't handle partial state correctly
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - bug
  - high-priority
dependencies: []
priority: high
---

## Description

When a deployment is interrupted and restarted, the deployment script doesn't properly handle the existing state. Instead of intelligently resuming from where it left off, it attempts to re-run deployment steps, making poor decisions based on incomplete state analysis.

## Acceptance Criteria

- [ ] State-aware resumption logic implemented
- [ ] Infrastructure validation before operations
- [ ] VPN state checking before SSH attempts
- [ ] State reconciliation between recorded and actual state
- [ ] Graceful continuation from interruption point
- [ ] Validation gates between deployment phases

## Technical Details

### Current Issues
- Script attempts to regenerate files that already exist
- SSH connectivity tests fail because VPN state isn't properly checked
- Doesn't validate that VMs are actually running before testing SSH
- Doesn't resume gracefully from the actual deployment phase
- State file exists but deployment logic doesn't use it effectively for resumption

### Example Problematic Behavior
```
=== k0s Configuration Generation ===
==> k0sctl configuration already exists: ./k0sctl-config/k0rdent-crqk4ma9-k0sctl.yaml

=== Testing SSH Connectivity ===
==> Testing SSH to k0s-controller (192.168.100.11)...
✗ SSH connectivity to k0s-controller: FAILED
```

### Root Cause
- Deployment scripts don't properly check VPN connectivity before SSH tests
- State file indicates progress but scripts don't use state to determine proper resumption point
- Missing logic to validate actual infrastructure state vs. recorded state
- No reconciliation between expected state and actual Azure/cluster state

### Required Implementation
1. **State-aware resumption logic**: Check deployment state and resume from appropriate step
2. **Infrastructure validation**: Verify VMs are running and accessible before SSH tests
3. **VPN state checking**: Ensure VPN is connected before attempting cluster operations
4. **State reconciliation**: Compare recorded state with actual infrastructure state
5. **Graceful continuation**: Skip completed steps and resume from interruption point
6. **Validation gates**: Add checks between each major deployment phase

### Implementation Areas
- `deploy-k0rdent.sh` - Main orchestration with state-aware resumption
- `bin/install-k0s.sh` - VPN connectivity checks before SSH tests
- `etc/state-management.sh` - Enhanced state validation functions
- All deployment scripts - State checking before attempting operations

### Testing Requirements
- Test interrupted deployments at various stages
- Verify graceful resumption from each interruption point
- Validate that state file accurately reflects actual infrastructure
- Test VPN disconnect/reconnect scenarios during deployment

**Priority Justification**: This significantly impacts user experience and deployment reliability, especially for long-running deployments that can be interrupted by network issues, timeouts, or user interruption.
