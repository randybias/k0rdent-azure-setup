# Tasks: Fix KOF Victoria Metrics Webhook Readiness

## Phase 1: Core Implementation

### Task 1.1: Implement webhook readiness check function
- [x] Create `wait_for_victoria_metrics_webhook()` function in `etc/kof-functions.sh`
- [x] Implement ValidatingWebhookConfiguration existence check
- [x] Implement webhook service endpoint verification
- [x] Implement webhook pod readiness check
- [x] Add timeout logic with configurable duration
- [x] Add progress reporting every 30 seconds
- [x] Return appropriate exit codes (0=success, 1=failure)
- **Validation**: Function can be called independently and reports status correctly

### Task 1.2: Add diagnostic error reporting
- [x] On timeout, report ValidatingWebhookConfiguration status
- [x] On timeout, report webhook service endpoint count
- [x] On timeout, report webhook pod status
- [x] Format error output with troubleshooting guidance
- [x] Add suggestion to check operator logs
- **Validation**: Timeout produces clear, actionable error message

### Task 1.3: Integrate webhook check into mothership installation
- [x] Add retry logic with webhook readiness check in `bin/install-kof-mothership.sh`
- [x] Webhook check runs on retry after first failure (not before, since webhook doesn't exist yet)
- [x] Add deployment event logging for webhook ready/timeout/retry
- [x] Ensure failure halts installation with appropriate error after max retries
- **Validation**: Installation script retries on webhook failure and succeeds on second attempt

## Phase 2: Configuration and Documentation

### Task 2.1: Add configuration support
- [x] Add `kof.mothership.install_retries` configuration option (default: 3)
- [x] Add `kof.mothership.retry_delay_seconds` configuration option (default: 30)
- [x] Implement retry configuration retrieval using `get_kof_config()`
- [x] Add inline comments documenting configuration options
- **Validation**: Custom retry settings from YAML are respected

### Task 2.2: Update code comments and documentation
- [x] Add function header comment for `wait_for_victoria_metrics_webhook()`
- [x] Document function parameters (namespace, optional timeout)
- [x] Add inline comments explaining webhook validation layers
- [x] Document return codes in function header
- [x] Document the chicken-and-egg problem in install script comments
- **Validation**: Function purpose and usage are clear from comments

### Task 2.3: Add example configuration
- [x] Add example retry settings to `config/k0rdent-default.yaml`
- [x] Include comment explaining webhook race condition
- [x] Document default values in example
- **Validation**: Template config shows retry options

## Phase 3: Testing and Validation

### Task 3.1: Test normal installation flow
- [x] Test fresh KOF installation with retry logic
- [x] Verify first attempt fails with webhook error (expected)
- [x] Verify retry succeeds after webhook stabilizes
- [x] Verify progress messages appear appropriately
- **Validation**: Clean installation succeeds with retry

### Task 3.2: Test retry behavior
- [x] Verify retry waits configured delay (30s default)
- [x] Verify webhook readiness check runs before retry
- [x] Verify installation succeeds on second attempt
- [x] Verify deployment events are recorded
- **Validation**: Retry logic works as designed

## Phase 4: Bug Fixes

### Task 4.1: Fix install-kof-regional.sh script reference
- [x] Change `bin/create-child.sh` to `bin/create-azure-child.sh`
- [x] Remove `--cloud azure` flag (not needed for azure-specific script)
- **Validation**: Regional cluster deployment works

### Task 4.2: Fix deploy-k0rdent.sh help text
- [x] Update reference from `create-child.sh` to `create-azure-child.sh`
- **Validation**: Help text shows correct script name

## Phase 5: Integration and Cleanup

### Task 5.1: Review code quality
- [x] Run `bash -n` on modified bash files - all pass
- [x] Verify bash function follows existing code style
- [x] Verify variable naming follows project conventions
- [x] Verify error handling is consistent with codebase
- **Validation**: Code passes syntax check and style review

### Task 5.2: Verify state management integration
- [x] Verify deployment events are recorded correctly
- [x] Verify phase management is not disrupted
- [x] Check that uninstall is not affected by new function
- **Validation**: State management continues to work correctly

## Implementation Notes

### Key Insight: Chicken-and-Egg Problem

The Victoria Metrics operator webhook is installed **as part of** the kof-mothership Helm chart, not separately. This creates a race condition:

1. Helm starts installing mothership chart
2. Victoria Metrics operator deployment is created
3. ValidatingWebhookConfiguration is registered
4. Helm tries to create VMAlert/VMCluster CRs
5. Webhook pod isn't ready yet → validation fails → helm fails

**Solution**: Retry the helm install. On first failure, the webhook has been created and starts becoming ready. On retry (after 30s delay), the webhook is ready and the install succeeds.

### Changes Made

1. **etc/kof-functions.sh**: Added `wait_for_victoria_metrics_webhook()` function
   - Three-layer webhook validation (config, endpoints, pod readiness)
   - Configurable timeout with 30-second minimum safety
   - Progress reporting every 30 seconds
   - Comprehensive diagnostic output on timeout

2. **bin/install-kof-mothership.sh**: Added retry logic for Step 4
   - Up to 3 retries (configurable)
   - 30-second delay between retries (configurable)
   - Calls webhook readiness check on retry
   - Records deployment events for success/failure/retry

3. **config/k0rdent-default.yaml**: Added retry configuration
   - `kof.mothership.install_retries: 3`
   - `kof.mothership.retry_delay_seconds: 30`

4. **bin/install-kof-regional.sh**: Fixed broken script reference
   - Changed `bin/create-child.sh` to `bin/create-azure-child.sh`
   - Removed obsolete `--cloud azure` flag

5. **deploy-k0rdent.sh**: Fixed help text reference

### Test Results

- First helm install attempt fails with webhook connection refused (expected)
- Retry after 30s delay succeeds
- Webhook readiness check shows config=true, endpoints=true, pod=false initially
- Webhook becomes ready ~40s after first failure
- Full KOF installation completes successfully

## Success Metrics

1. **Zero webhook validation failures blocking installation** ✓
2. **Automatic retry handles race condition** ✓
3. **Clear progress messages during retry** ✓
4. **No manual intervention required** ✓
5. **Regional cluster deployment works** ✓
