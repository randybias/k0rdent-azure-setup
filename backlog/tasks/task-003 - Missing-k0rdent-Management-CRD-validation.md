---
id: task-003
title: Missing k0rdent Management CRD validation
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

k0rdent installation validation is incomplete - we only check pod status but don't verify the Management CRD is properly created and in Ready state. This could lead to k0rdent appearing installed but the Management controller failing.

## Acceptance Criteria

- [ ] Management CRD validation added to install-k0rdent.sh
- [ ] Management object exists and READY status is True
- [ ] Parse release name to confirm correct version deployment
- [ ] Add timeout/retry logic for Management CRD readiness
- [ ] Update state management to track Management CRD status
- [ ] Include validation in status check function

## Technical Details

### Current Validation
- Checks helm installation status with `helm list -n kcm-system`
- Verifies pods are running with `kubectl get pods -n kcm-system`
- Missing critical Management CRD validation

### Required Validation Command
```bash
kubectl get Management -n kcm-system
```

### Expected Output
```
NAME   READY   RELEASE     AGE
kcm    True    kcm-1-1-1   9m
```

### Implementation Requirements
- Add Management CRD validation to `bin/install-k0rdent.sh`
- Verify Management object exists and READY status is "True"
- Parse release name to confirm correct version deployment
- Add timeout/retry logic for Management CRD to become ready
- Update state management to track Management CRD status
- Include validation in status check function

### Current Impact
- k0rdent may appear "installed" but Management controller could be failing
- Silent failures in k0rdent management plane
- No verification that k0rdent is actually functional

**Location**: `bin/install-k0rdent.sh` lines 145-159 (ready check section)
