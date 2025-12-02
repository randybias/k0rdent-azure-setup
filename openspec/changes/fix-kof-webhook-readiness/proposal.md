# Fix KOF Victoria Metrics Webhook Readiness Race Condition

## Problem Statement

KOF mothership installation fails with webhook validation errors when the Victoria Metrics operator webhook service is not fully ready. The current implementation installs `kof-operators` (which includes the Victoria Metrics operator) and immediately proceeds to install `kof-mothership`, which creates Victoria Metrics custom resources requiring webhook validation.

### Error Symptoms

```
Error: Internal error occurred: failed calling webhook "vmalert.victoriametrics.com":
failed to call webhook: Post "https://kof-mothership-victoria-metrics-operator.kof.svc:9443/validate-operator-victoriametrics-com-v1beta1-vmalert?timeout=10s":
dial tcp 10.106.77.33:9443: connect: connection refused
```

### Root Cause

Helm's `--wait` flag only waits for pods to reach ready state, not for webhooks to become functional. The Victoria Metrics operator webhook requires additional time after pod readiness to:

1. Start the webhook server process
2. Register ValidatingWebhookConfiguration resources
3. Establish network connectivity and accept requests

The timing gap between pod readiness and webhook functionality creates a race condition that causes installation failures.

## Proposed Solution

Add explicit webhook readiness validation between `kof-operators` installation (Step 3) and `kof-mothership` installation (Step 4) in the deployment process.

### Approach

1. **New function in `etc/kof-functions.sh`**: `wait_for_victoria_metrics_webhook()`
   - Poll webhook endpoint until it responds successfully
   - Follow the existing pattern used for Sveltos CRD waiting (lines 46-70)
   - Use configurable timeout (default: 180 seconds / 3 minutes)
   - Provide clear progress messages every 30 seconds

2. **Integration in `bin/install-kof-mothership.sh`**:
   - Insert webhook check after operator installation (after line 145)
   - Before mothership chart installation (before line 157)
   - Fail fast if webhook doesn't become ready within timeout

### Design Considerations

- **Polling strategy**: Check every 10 seconds to balance responsiveness and load
- **Timeout duration**: 3 minutes provides sufficient time for normal webhook startup
- **Progress reporting**: Status updates every 30 seconds to show progress
- **Error handling**: Clear error messages indicating webhook timeout vs. other failures
- **Consistency**: Follow existing wait pattern from Sveltos CRD check

## Affected Components

- `etc/kof-functions.sh` - New webhook wait function
- `bin/install-kof-mothership.sh` - Integration of webhook check

## Benefits

1. **Eliminates race condition**: Ensures webhook is functional before dependent resources are created
2. **Consistent installation**: Removes timing-based installation failures
3. **Clear diagnostics**: Explicit timeout messages help identify webhook issues
4. **Follows existing patterns**: Reuses established wait logic patterns from the codebase
5. **Production ready**: Handles normal startup delays without false positives

## Alternatives Considered

1. **Fixed delay**: Simple `sleep 30` after operator installation
   - Rejected: Unreliable, wastes time when webhook is ready quickly

2. **Retry in mothership install**: Retry `helm install kof-mothership` on webhook failures
   - Rejected: Helm retries are complex, doesn't address root cause

3. **Increase helm timeout**: Use longer `--timeout` for mothership install
   - Rejected: Masks problem, doesn't validate webhook readiness

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Webhook check gives false positive | Low | High | Test webhook with actual API call, not just pod check |
| Timeout too short for slow systems | Low | Medium | Configurable timeout, default 3 minutes is generous |
| Webhook endpoint changes in future versions | Low | Medium | Document version assumptions, add version detection |

## Success Criteria

- [ ] KOF mothership installs successfully on first attempt
- [ ] No webhook validation errors during installation
- [ ] Webhook readiness check completes in <60 seconds on typical systems
- [ ] Clear timeout error message if webhook doesn't start
- [ ] Installation works consistently across multiple test runs
