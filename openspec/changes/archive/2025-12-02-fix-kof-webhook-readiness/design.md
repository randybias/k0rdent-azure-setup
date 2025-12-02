# Design: KOF Victoria Metrics Webhook Readiness Check

## Overview

This change adds webhook readiness validation to the KOF installation process to eliminate race conditions between operator pod readiness and webhook service availability.

## Architecture

### Component Interaction

```
┌─────────────────────────────────────────────────────────────┐
│ bin/install-kof-mothership.sh                               │
│                                                               │
│  Step 3: Install kof-operators                              │
│    ├─> helm upgrade -i --wait kof-operators                 │
│    └─> Pods become ready (Helm --wait satisfied)            │
│                                                               │
│  [NEW] Webhook Readiness Check                              │
│    ├─> wait_for_victoria_metrics_webhook()                  │
│    ├─> Poll webhook endpoint every 10s                      │
│    ├─> Timeout after 180s                                   │
│    └─> Verify ValidatingWebhookConfiguration exists         │
│                                                               │
│  Step 4: Install kof-mothership                             │
│    └─> helm upgrade -i --wait kof-mothership                │
│        └─> Creates VictoriaMetrics CRs (webhook validated)  │
└─────────────────────────────────────────────────────────────┘
```

### Webhook Readiness Detection Strategy

The function will use a multi-layer validation approach:

1. **ValidatingWebhookConfiguration exists**
   ```bash
   kubectl get validatingwebhookconfiguration vm-operator-admission
   ```

2. **Webhook service endpoint is available**
   ```bash
   kubectl get endpoints -n kof kof-operators-victoria-metrics-operator
   ```

3. **Webhook pods are ready** (redundant check for safety)
   ```bash
   kubectl get pods -n kof -l app.kubernetes.io/name=victoria-metrics-operator
   ```

### Function Implementation Pattern

Following the established Sveltos CRD wait pattern from `etc/kof-functions.sh:46-70`:

```bash
wait_for_victoria_metrics_webhook() {
    local namespace="${1:-kof}"
    local timeout_seconds=180
    local check_interval=10
    local elapsed=0

    print_info "Waiting for Victoria Metrics webhook to be ready (timeout: ${timeout_seconds}s)..."

    while [[ $elapsed -lt $timeout_seconds ]]; do
        # Check 1: ValidatingWebhookConfiguration exists
        # Check 2: Webhook service has endpoints
        # Check 3: Webhook pods are running

        if [all checks pass]; then
            print_success "Victoria Metrics webhook is ready"
            return 0
        fi

        # Progress reporting
        if [[ $elapsed -eq 0 ]]; then
            print_info "Webhook not yet ready, waiting..."
        elif [[ $((elapsed % 30)) -eq 0 ]]; then
            print_info "Still waiting for webhook... (${elapsed}s elapsed)"
        fi

        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    print_error "Timeout waiting for Victoria Metrics webhook after ${timeout_seconds} seconds"
    return 1
}
```

## Integration Points

### etc/kof-functions.sh

**Location**: After `prepare_kof_namespace()` function (after line 122)

**Function signature**: `wait_for_victoria_metrics_webhook [namespace]`

**Dependencies**:
- `kubectl` CLI tool
- Functions from `common-functions.sh`: `print_info`, `print_success`, `print_error`
- Active Kubernetes context

### bin/install-kof-mothership.sh

**Location**: In `deploy_kof_mothership()` function, between Step 3 and Step 4

**Before** (current line 145-157):
```bash
# Step 3: Install KOF operators
if helm upgrade -i --reset-values --wait \
    -n "$kof_namespace" kof-operators \
    oci://ghcr.io/k0rdent/kof/charts/kof-operators \
    --version "$kof_version"; then
    print_success "KOF operators installed successfully"
else
    print_error "Failed to install KOF operators"
    return 1
fi

# Step 4: Install KOF mothership
print_header "Step 4: Installing KOF Mothership"
```

**After** (with webhook check):
```bash
# Step 3: Install KOF operators
if helm upgrade -i --reset-values --wait \
    -n "$kof_namespace" kof-operators \
    oci://ghcr.io/k0rdent/kof/charts/kof-operators \
    --version "$kof_version"; then
    print_success "KOF operators installed successfully"
else
    print_error "Failed to install KOF operators"
    return 1
fi

# Step 3.5: Wait for Victoria Metrics webhook readiness
print_info "Ensuring Victoria Metrics webhook is ready..."
if ! wait_for_victoria_metrics_webhook "$kof_namespace"; then
    print_error "Victoria Metrics webhook did not become ready"
    add_event "kof_webhook_timeout" "Victoria Metrics webhook readiness timeout"
    return 1
fi

# Step 4: Install KOF mothership
print_header "Step 4: Installing KOF Mothership"
```

## Configuration

### Timeout Configuration

Add optional configuration to KOF YAML section:

```yaml
kof:
  enabled: true
  version: "1.4.0"
  operators:
    webhook_timeout_seconds: 180  # Optional, defaults to 180
```

Implementation:
```bash
local timeout_seconds=$(get_kof_config "operators.webhook_timeout_seconds" "180")
```

## Error Handling

### Timeout Scenario

**Detection**: `elapsed >= timeout_seconds`

**Actions**:
1. Log detailed error with component status
2. Add deployment event for troubleshooting
3. Return exit code 1 to halt installation

**Error message**:
```
✗ Timeout waiting for Victoria Metrics webhook after 180 seconds
Debugging information:
  ValidatingWebhookConfiguration: [present/missing]
  Webhook service endpoints: [count]
  Webhook pods ready: [count/total]
Run 'kubectl get pods -n kof' to check operator status
```

### Partial Readiness

If some checks pass but not all, report which components are ready/not ready to aid troubleshooting.

## Testing Strategy

### Unit Testing

Not applicable - bash function with kubectl dependencies

### Integration Testing

**Test scenarios**:

1. **Normal installation**: Webhook becomes ready within 60 seconds
   - Expected: Function returns success, installation proceeds

2. **Slow webhook startup**: Webhook takes 90 seconds to become ready
   - Expected: Function waits, eventually returns success

3. **Webhook failure**: Operator pod crashes, webhook never starts
   - Expected: Function times out after 180s with clear error

4. **Network issues**: Service exists but endpoints aren't ready
   - Expected: Function waits for endpoints, times out if not resolved

### Manual Testing Procedure

```bash
# 1. Fresh installation
./bin/install-kof-mothership.sh deploy

# 2. Monitor logs for webhook wait messages
# Expected: "Waiting for Victoria Metrics webhook..."
#           "Victoria Metrics webhook is ready"

# 3. Verify timing
# Expected: Webhook ready in <60s on healthy systems

# 4. Test with deleted webhook (simulate failure)
kubectl delete validatingwebhookconfiguration vm-operator-admission
./bin/install-kof-mothership.sh deploy
# Expected: Clear timeout error after 180s
```

## Performance Considerations

### Timing Impact

- **Best case**: +10 seconds (one check cycle, webhook already ready)
- **Typical case**: +20-40 seconds (webhook starting up)
- **Worst case**: +180 seconds (timeout on failure)

### Resource Impact

- Minimal: Periodic kubectl API calls (every 10 seconds)
- No significant CPU/memory overhead

## Version Compatibility

### Tested Versions

- KOF: 1.4.0 (current)
- Victoria Metrics Operator: version included in kof-operators 1.4.0

### Future Compatibility

**Risk**: Webhook configuration name or service name changes in future KOF versions

**Mitigation**:
- Document version assumptions in code comments
- Consider version detection logic if changes occur
- Add fallback checks for different naming patterns

### Backward Compatibility

This change only adds validation, doesn't modify existing behavior. Safe to deploy to existing installations.

## Rollback Plan

If webhook check causes issues:

1. **Quick fix**: Comment out webhook check, revert to immediate installation
2. **Detection**: Installation takes >3 minutes longer than before
3. **Rollback**: Remove webhook check function and call site

## Monitoring and Observability

### Deployment Events

New events added to deployment state:

- `kof_webhook_ready`: Webhook became ready (with timing)
- `kof_webhook_timeout`: Webhook failed to become ready

### Log Messages

```
==> Waiting for Victoria Metrics webhook to be ready (timeout: 180s)...
==> Webhook not yet ready, waiting...
==> Still waiting for webhook... (30s elapsed)
==> Still waiting for webhook... (60s elapsed)
✓ Victoria Metrics webhook is ready
```

### Troubleshooting Aids

On timeout, dump diagnostic information:
- ValidatingWebhookConfiguration status
- Webhook service endpoints
- Operator pod status and logs (last 20 lines)

## Open Questions

1. **Should webhook check be optional/skippable?**
   - Concern: Advanced users may want to skip for faster iteration
   - Proposal: Add `--skip-webhook-check` flag
   - Decision: Not in initial implementation, can add if needed

2. **Should we test webhook with actual validation request?**
   - Concern: More reliable than just checking existence
   - Proposal: Create temporary VictoriaMetrics CR to trigger webhook
   - Decision: Too complex for initial implementation, existence checks sufficient

3. **What if multiple webhook configurations exist?**
   - Concern: Non-standard deployments with custom webhooks
   - Proposal: Check for specific webhook name
   - Decision: Use specific name, add fallback if needed later

## Dependencies

### Prerequisites

- `kubectl` configured with access to target cluster
- Kubernetes cluster with admission webhooks enabled (standard)
- Network connectivity to Kubernetes API server

### Related Changes

None - standalone fix

## References

- Existing pattern: `etc/kof-functions.sh:46-70` (Sveltos CRD wait)
- Related issue: KOF mothership installation failure with webhook errors
- Helm wait behavior: https://helm.sh/docs/helm/helm_install/#options
