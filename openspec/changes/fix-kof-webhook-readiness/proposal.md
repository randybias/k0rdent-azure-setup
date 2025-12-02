# Fix KOF Victoria Metrics Webhook Readiness Race Condition

## Problem Statement

KOF mothership installation fails with webhook validation errors when the Victoria Metrics operator webhook service is not fully ready. The race condition occurs because the Victoria Metrics operator is installed **as part of** the kof-mothership Helm chart itself, not as a separate step.

### Error Symptoms

```
Error: Internal error occurred: failed calling webhook "vmalert.victoriametrics.com":
failed to call webhook: Post "https://kof-mothership-victoria-metrics-operator.kof.svc:9443/validate-operator-victoriametrics-com-v1beta1-vmalert?timeout=10s":
dial tcp 10.106.77.33:9443: connect: connection refused
```

### Root Cause (Updated Understanding)

The Victoria Metrics operator webhook is bundled inside the kof-mothership chart as a subchart dependency. When Helm installs the chart:

1. Helm creates the Victoria Metrics operator Deployment
2. Helm creates the ValidatingWebhookConfiguration
3. Helm tries to create VMAlert/VMCluster custom resources
4. The webhook pod isn't ready yet → validation fails → helm fails

This is a **chicken-and-egg problem**: the webhook doesn't exist until mothership installation starts, but the CRs need the webhook to be ready during the same installation.

## Implemented Solution

Add **retry logic with webhook readiness checking** to the kof-mothership installation step.

### Approach

1. **New function in `etc/kof-functions.sh`**: `wait_for_victoria_metrics_webhook()`
   - Three-layer validation: webhook config exists, service has endpoints, pod is ready
   - Configurable timeout (default: 60 seconds on retry)
   - Progress reporting every 30 seconds
   - Comprehensive diagnostic output on timeout

2. **Retry logic in `bin/install-kof-mothership.sh`**:
   - First attempt will likely fail (webhook not ready yet)
   - Wait configured delay (default: 30 seconds)
   - Check webhook readiness before retry
   - Retry up to 3 times (configurable)
   - Succeed once webhook is ready

### Design Considerations

- **Retry vs pre-check**: Pre-check doesn't work because webhook doesn't exist until helm starts
- **Retry delay**: 30 seconds allows webhook pod to fully start
- **Webhook check on retry**: Validates webhook is actually ready before retrying
- **Configurable**: Both retry count and delay are configurable via YAML

## Affected Components

- `etc/kof-functions.sh` - New webhook wait function
- `bin/install-kof-mothership.sh` - Retry logic for Step 4
- `config/k0rdent-default.yaml` - New configuration options
- `bin/install-kof-regional.sh` - Bug fix: script reference
- `deploy-k0rdent.sh` - Bug fix: help text reference

## Benefits

1. **Handles race condition**: Automatic retry allows webhook to stabilize
2. **No manual intervention**: Installation completes without user action
3. **Clear diagnostics**: Progress messages show retry status and webhook state
4. **Follows helm patterns**: Retry is similar to helm's `--atomic` behavior
5. **Production ready**: Tested with real KOF deployments

## Alternatives Considered

1. **Pre-check webhook before mothership install**
   - Rejected: Webhook doesn't exist until mothership starts installing

2. **Fixed delay before helm install**
   - Rejected: Doesn't help - race happens during helm install, not before

3. **Increase helm timeout**
   - Rejected: Masks problem, helm would still fail on webhook validation

4. **Modify upstream chart to use helm hooks**
   - Rejected: Not in our control, requires upstream changes

## Configuration Options

```yaml
kof:
  mothership:
    install_retries: 3           # Number of helm install attempts
    retry_delay_seconds: 30      # Delay between retries
```

## Success Criteria

- [x] KOF mothership installs successfully (with expected retry)
- [x] No webhook validation errors block installation
- [x] Webhook readiness check completes in <60 seconds on retry
- [x] Clear progress messages during retry
- [x] Installation works consistently across multiple test runs
- [x] Regional cluster deployment works (bug fix included)

## Test Results

```
=== Step 4: Installing KOF Mothership ===
==> Installing kof-mothership chart...
Error: Internal error occurred: failed calling webhook "vmalert.victoriametrics.com"...
⚠ Helm install attempt 1 failed (exit code: 1)
==> This may be due to webhook race condition, will retry...
==> Retry attempt 2 of 3 (waiting 30s for webhook to stabilize)...
==> Waiting for Victoria Metrics webhook to be ready...
==> Still waiting for webhook... (30s elapsed) - Webhook status: config=true, endpoints=true, pod=false
✓ Victoria Metrics operator webhook is ready (40s elapsed)
[helm succeeds on retry]
✓ KOF mothership installed successfully
```
