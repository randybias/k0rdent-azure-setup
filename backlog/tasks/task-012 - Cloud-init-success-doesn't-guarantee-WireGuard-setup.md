---
id: task-012
title: Cloud-init success doesn't guarantee WireGuard setup
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - bug
  - wireguard
  - cloud-init
dependencies: []
priority: low
---

## Description

VMs can pass cloud-init status verification but still fail WireGuard configuration verification, indicating cloud-init completion doesn't guarantee all services are properly configured. Cloud-init may report success before WireGuard service fully initializes or WireGuard systemd service may not be properly enabled/started.

## Acceptance Criteria

- [ ] Cloud-init status accurately reflects WireGuard service readiness
- [ ] WireGuard interface is properly configured when cloud-init reports success
- [ ] VM verification includes WireGuard-specific validation
- [ ] Deployment reliably establishes WireGuard connectivity on all VMs

## Technical Details

### Observed Behavior
- VM passes SSH connectivity test
- Cloud-init reports successful completion (`sudo cloud-init status` returns success)
- VM marked as "fully operational" by create-azure-vms.sh
- Later WireGuard verification fails with "WireGuard interface wg0 not found or not configured"

### Root Cause Analysis Needed
- **Timing Issue**: Cloud-init may report success before WireGuard service fully initializes
- **Service Dependencies**: WireGuard systemd service may not be properly enabled or started
- **Cloud-init Script Issues**: WireGuard configuration in cloud-init may have silent failures
- **Network Interface Timing**: VM networking may not be fully ready when WireGuard starts

### Current Impact
- VMs appear operational but lack proper WireGuard connectivity
- Deployment continues to k0s installation which may fail without proper networking
- Manual intervention required to fix WireGuard on affected VMs
- Inconsistent deployment success rates

### Investigation Areas
- Review cloud-init YAML templates for WireGuard configuration
- Check systemd service dependencies and startup order
- Add more granular cloud-init status checking (per-module status)
- Consider adding WireGuard-specific validation to VM verification loop

### Potential Solutions
- **Enhanced Cloud-init Validation**: Check specific cloud-init modules beyond overall status
- **WireGuard-specific Checks**: Add WireGuard interface verification to create-azure-vms.sh
- **Retry Logic**: Implement WireGuard setup retry mechanism in cloud-init
- **Service Dependencies**: Ensure proper systemd service ordering and dependencies

**Workaround**: Manual WireGuard setup on affected VMs, but defeats automation purpose

**Impact**: Reduces deployment reliability, requires manual intervention, potential k0s installation failures
