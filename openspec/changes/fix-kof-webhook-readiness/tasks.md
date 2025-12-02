# Tasks: Fix KOF Victoria Metrics Webhook Readiness

## Phase 1: Core Implementation

### Task 1.1: Implement webhook readiness check function
- [ ] Create `wait_for_victoria_metrics_webhook()` function in `etc/kof-functions.sh`
- [ ] Implement ValidatingWebhookConfiguration existence check
- [ ] Implement webhook service endpoint verification
- [ ] Implement webhook pod readiness check
- [ ] Add timeout logic with configurable duration
- [ ] Add progress reporting every 30 seconds
- [ ] Return appropriate exit codes (0=success, 1=failure)
- **Validation**: Function can be called independently and reports status correctly

### Task 1.2: Add diagnostic error reporting
- [ ] On timeout, report ValidatingWebhookConfiguration status
- [ ] On timeout, report webhook service endpoint count
- [ ] On timeout, report webhook pod status
- [ ] Format error output with troubleshooting guidance
- [ ] Add suggestion to check operator logs
- **Validation**: Timeout produces clear, actionable error message

### Task 1.3: Integrate webhook check into mothership installation
- [ ] Add webhook readiness check call in `bin/install-kof-mothership.sh`
- [ ] Insert check between Step 3 (operators) and Step 4 (mothership)
- [ ] Add deployment event logging for webhook ready/timeout
- [ ] Ensure failure halts installation with appropriate error
- [ ] Update step numbering/naming if needed (Step 3.5)
- **Validation**: Installation script calls webhook check at correct point

## Phase 2: Configuration and Documentation

### Task 2.1: Add configuration support
- [ ] Document `kof.operators.webhook_timeout_seconds` configuration option
- [ ] Implement timeout value retrieval using `get_kof_config()`
- [ ] Set default timeout to 180 seconds
- [ ] Add inline comment documenting configuration option
- **Validation**: Custom timeout from YAML is respected

### Task 2.2: Update code comments and documentation
- [ ] Add function header comment for `wait_for_victoria_metrics_webhook()`
- [ ] Document function parameters (namespace, optional timeout)
- [ ] Add inline comments explaining webhook validation layers
- [ ] Document return codes in function header
- **Validation**: Function purpose and usage are clear from comments

### Task 2.3: Add example configuration
- [ ] Add example webhook timeout to `config/k0rdent-default.yaml`
- [ ] Include comment explaining when to adjust timeout
- [ ] Document default value (180s) in example
- **Validation**: Template config shows webhook timeout option

## Phase 3: Testing and Validation

### Task 3.1: Test normal installation flow
- [ ] Test fresh KOF installation with webhook check
- [ ] Verify webhook check completes within 60 seconds
- [ ] Verify mothership installation succeeds after webhook ready
- [ ] Verify no regression in total installation time
- [ ] Verify progress messages appear appropriately
- **Validation**: Clean installation succeeds with webhook check

### Task 3.2: Test timeout scenario
- [ ] Simulate webhook failure (e.g., delete ValidatingWebhookConfiguration)
- [ ] Verify timeout occurs at configured duration (180s default)
- [ ] Verify error message includes diagnostic information
- [ ] Verify installation halts and does not proceed to mothership
- [ ] Verify deployment event is recorded for troubleshooting
- **Validation**: Webhook timeout is detected and handled correctly

### Task 3.3: Test slow webhook startup
- [ ] Test on system where webhook takes 60-90 seconds to start
- [ ] Verify webhook check waits appropriately
- [ ] Verify progress messages appear at 30-second intervals
- [ ] Verify installation succeeds once webhook is ready
- **Validation**: Slow webhook startup does not cause false failures

### Task 3.4: Verify webhook detection accuracy
- [ ] Verify check detects ValidatingWebhookConfiguration correctly
- [ ] Verify check detects webhook service endpoints correctly
- [ ] Verify check detects webhook pod readiness correctly
- [ ] Verify all three checks must pass for webhook to be considered ready
- **Validation**: Multi-layer detection works as designed

## Phase 4: Edge Cases and Hardening

### Task 4.1: Test with partial webhook state
- [ ] Test when ValidatingWebhookConfiguration exists but no endpoints
- [ ] Test when endpoints exist but pods are not ready
- [ ] Test when pods are ready but webhook config is missing
- [ ] Verify clear diagnostic messages for each partial state
- **Validation**: Partial readiness states are detected and reported

### Task 4.2: Test configuration edge cases
- [ ] Test with webhook_timeout_seconds not set (uses default)
- [ ] Test with webhook_timeout_seconds set to custom value
- [ ] Test with very short timeout (30s) to verify timeout works
- [ ] Test with zero or negative timeout (should use safe minimum)
- **Validation**: Configuration handling is robust

### Task 4.3: Verify namespace handling
- [ ] Test with default KOF namespace ('kof')
- [ ] Test with custom KOF namespace from configuration
- [ ] Verify function parameter allows namespace override
- [ ] Verify namespace is passed correctly from installation script
- **Validation**: Namespace handling works for all configurations

## Phase 5: Integration and Cleanup

### Task 5.1: Review code quality
- [ ] Run `shellcheck` on modified bash files
- [ ] Verify bash function follows existing code style
- [ ] Verify variable naming follows project conventions
- [ ] Check for any unbound variable issues
- [ ] Verify error handling is consistent with codebase
- **Validation**: Code passes shellcheck and style review

### Task 5.2: Test backwards compatibility
- [ ] Verify function works with KOF 1.4.0 (current version)
- [ ] Verify function gracefully handles missing webhooks (old versions)
- [ ] Document any version-specific assumptions
- [ ] Add version compatibility note in code comments
- **Validation**: Change works with current KOF version

### Task 5.3: Verify state management integration
- [ ] Verify deployment events are recorded correctly
- [ ] Verify phase management is not disrupted
- [ ] Verify state file is updated appropriately
- [ ] Check that uninstall is not affected by new function
- **Validation**: State management continues to work correctly

### Task 5.4: Update related documentation
- [ ] Update CLAUDE.md with webhook check information if relevant
- [ ] Ensure troubleshooting guidance mentions webhook check
- [ ] Document common webhook timeout scenarios
- [ ] Add reference to webhook check in KOF installation notes
- **Validation**: Documentation reflects new webhook check

## Dependencies

- **No dependencies**: Tasks are sequential within phases
- **Recommended order**: Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5
- **Parallel work possible**:
  - Phase 2 (config/docs) can start after Phase 1.1 is complete
  - Phase 3 testing can begin as soon as Phase 1.3 is complete

## Validation Checklist

Before marking change as complete:

- [ ] All Phase 1-5 tasks completed
- [ ] Webhook check function exists and works correctly
- [ ] Integration into installation script is correct
- [ ] Configuration support is implemented and tested
- [ ] All test scenarios pass (normal, timeout, slow startup)
- [ ] Error messages are clear and actionable
- [ ] Code follows project conventions and passes shellcheck
- [ ] Documentation is updated
- [ ] No regressions in existing functionality
- [ ] Change validated with `openspec validate fix-kof-webhook-readiness --strict`

## Estimated Complexity

- **Implementation**: ~2-3 hours
- **Testing**: ~2-3 hours
- **Documentation**: ~1 hour
- **Total**: ~5-7 hours

## Success Metrics

1. **Zero webhook validation failures** in KOF mothership installations
2. **Webhook ready within 60 seconds** on typical systems
3. **Clear timeout messages** when webhook fails to start
4. **No increase in installation time** for normal scenarios
5. **100% test pass rate** for all scenarios (normal, timeout, slow)
