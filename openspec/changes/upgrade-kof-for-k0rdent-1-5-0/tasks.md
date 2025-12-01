# Implementation Tasks: Upgrade KOF for k0rdent 1.5.0

## 1. Research and Planning
- [ ] 1.1 Identify correct KOF version compatible with k0rdent 1.5.0
- [ ] 1.2 Research k0rdent 1.5.0 Istio installation details (namespace, components, configuration)
- [ ] 1.3 Review KOF release notes for k0rdent 1.5.0 compatibility requirements
- [ ] 1.4 Document KOF's Istio feature dependencies (ingress, gateways, policies, etc.)
- [ ] 1.5 Verify k0rdent 1.5.0 Istio meets KOF requirements
- [ ] 1.6 Create test plan for KOF with k0rdent 1.5.0

## 2. Code Cleanup - Remove Istio Installation
- [ ] 2.1 Remove `install_istio_for_kof()` function from `etc/kof-functions.sh`
- [ ] 2.2 Remove Istio installation step from `bin/install-kof-mothership.sh` (lines 118-129)
- [ ] 2.3 Remove Istio uninstallation logic from `bin/install-kof-mothership.sh` (lines 240-248)
- [ ] 2.4 Remove Sveltos CRD waiting logic specific to Istio installation
- [ ] 2.5 Update any remaining Istio installation references in scripts
- [ ] 2.6 Verify no Istio Helm chart installation commands remain

## 3. Add Istio Validation Logic
- [ ] 3.1 Create `validate_k0rdent_istio()` function in `etc/kof-functions.sh`
- [ ] 3.2 Implement namespace check (`kubectl get namespace istio-system`)
- [ ] 3.3 Implement istiod deployment check with replica validation
- [ ] 3.4 Implement ingress gateway service check
- [ ] 3.5 Add 60-second timeout with progress reporting
- [ ] 3.6 Return detailed validation results (component-by-component)
- [ ] 3.7 Add retry logic for transient failures

## 4. Update check_istio_installed Function
- [ ] 4.1 Modify `check_istio_installed()` to be validation-focused
- [ ] 4.2 Add detailed component checks (not just namespace existence)
- [ ] 4.3 Return boolean success/failure
- [ ] 4.4 Log validation details for debugging

## 5. Add Error Messaging
- [ ] 5.1 Create error message helper functions for common Istio issues
- [ ] 5.2 Implement "Istio namespace missing" error with remediation steps
- [ ] 5.3 Implement "istiod not ready" error with replica status and check command
- [ ] 5.4 Implement "ingress gateway missing" error with impact explanation
- [ ] 5.5 Implement "k0rdent prerequisite" error for missing k0rdent
- [ ] 5.6 Test all error messages for clarity and actionability

## 6. Update KOF Mothership Installation
- [ ] 6.1 Replace Istio installation step with Istio validation step
- [ ] 6.2 Add k0rdent 1.5.0 prerequisite check (kcm-system namespace, deployment ready)
- [ ] 6.3 Add detailed Istio validation before KOF namespace creation
- [ ] 6.4 Keep KOF namespace creation with Istio injection label
- [ ] 6.5 Ensure KOF operators and mothership installation unchanged
- [ ] 6.6 Update progress messages to reflect new workflow
- [ ] 6.7 Update event logging (remove istio_installation events, add validation events)

## 7. Update KOF Uninstallation
- [ ] 7.1 Remove Istio uninstallation logic from cleanup functions
- [ ] 7.2 Add log message "Istio managed by k0rdent - not removing"
- [ ] 7.3 Verify Istio resources are not touched during cleanup
- [ ] 7.4 Test uninstallation leaves k0rdent Istio intact

## 8. Update Configuration Files
- [ ] 8.1 Update `config/k0rdent-default.yaml` - set KOF version to k0rdent 1.5.0 compatible version
- [ ] 8.2 Remove or deprecate `kof.istio.version` setting
- [ ] 8.3 Remove or deprecate `kof.istio.namespace` setting
- [ ] 8.4 Add comment explaining Istio managed by k0rdent
- [ ] 8.5 Update `config/k0rdent-baseline-southeastasia.yaml` similarly
- [ ] 8.6 Update `config/k0rdent-baseline-westeu.yaml` similarly
- [ ] 8.7 Update all example configs in `config/examples/`
- [ ] 8.8 Verify configuration validation still works

## 9. Update KOF Regional Cluster Scripts
- [ ] 9.1 Review `bin/install-kof-regional.sh` for Istio references
- [ ] 9.2 Update cluster labels for Istio integration if needed
- [ ] 9.3 Verify regional cluster installation works with k0rdent Istio
- [ ] 9.4 Test regional cluster Istio sidecar injection

## 10. Update Tests
- [ ] 10.1 Update `tests/test-kof-with-default.sh` to remove Istio installation tests
- [ ] 10.2 Add Istio discovery tests to test suite
- [ ] 10.3 Add Istio validation tests (success and failure cases)
- [ ] 10.4 Update expected KOF version in tests
- [ ] 10.5 Add prerequisite check tests (k0rdent 1.5.0 required)
- [ ] 10.6 Create test for legacy config with Istio section (should be ignored/warned)

## 11. Create New Test Scenarios
- [ ] 11.1 Create test for KOF with k0rdent 1.5.0 Istio (happy path)
- [ ] 11.2 Create test for missing Istio namespace (error path)
- [ ] 11.3 Create test for istiod not ready (error path)
- [ ] 11.4 Create test for missing ingress gateway (warning/error path)
- [ ] 11.5 Create test for KOF uninstallation preserving Istio
- [ ] 11.6 Create test for mothership with k0rdent Istio sidecars

## 12. Integration Testing
- [ ] 12.1 Set up k0rdent 1.5.0 test environment with Istio
- [ ] 12.2 Test KOF mothership installation end-to-end
- [ ] 12.3 Test KOF regional cluster deployment
- [ ] 12.4 Verify KOF features work with k0rdent Istio (collectors, dashboards)
- [ ] 12.5 Test Istio ingress routing to KOF services
- [ ] 12.6 Test KOF uninstallation
- [ ] 12.7 Verify k0rdent Istio remains operational after KOF removal

## 13. Error Scenario Testing
- [ ] 13.1 Test KOF installation with k0rdent not deployed
- [ ] 13.2 Test KOF installation with k0rdent deployed but Istio missing
- [ ] 13.3 Test KOF installation with Istio namespace present but istiod not ready
- [ ] 13.4 Test KOF installation with incomplete Istio (missing gateway)
- [ ] 13.5 Verify all error messages are clear and actionable
- [ ] 13.6 Test timeout scenarios for Istio validation

## 14. Performance Testing
- [ ] 14.1 Benchmark KOF mothership API latency via k0rdent Istio ingress
- [ ] 14.2 Measure KOF resource usage with Istio sidecars
- [ ] 14.3 Test regional cluster performance with Istio mesh
- [ ] 14.4 Compare with baseline (if previous metrics available)
- [ ] 14.5 Document performance characteristics

## 15. Documentation Updates
- [ ] 15.1 Update CLAUDE.md to reflect KOF Istio changes
- [ ] 15.2 Document k0rdent 1.5.0 prerequisite for KOF
- [ ] 15.3 Update KOF installation documentation
- [ ] 15.4 Document breaking changes (Istio no longer managed by KOF)
- [ ] 15.5 Create troubleshooting guide for Istio validation failures
- [ ] 15.6 Add examples of error messages and remediation steps
- [ ] 15.7 Update configuration examples with comments

## 16. Validation and Cleanup
- [ ] 16.1 Run `openspec validate upgrade-kof-for-k0rdent-1-5-0 --strict`
- [ ] 16.2 Fix any validation errors
- [ ] 16.3 Review all changed files for consistency
- [ ] 16.4 Verify no hardcoded Istio versions remain (except in validation)
- [ ] 16.5 Check for any remaining references to `kof-istio` Helm chart
- [ ] 16.6 Verify bash script syntax with shellcheck

## 17. Final Testing
- [ ] 17.1 Run complete test suite with k0rdent 1.5.0
- [ ] 17.2 Verify all tests pass
- [ ] 17.3 Test manual KOF installation following updated documentation
- [ ] 17.4 Test error scenarios manually
- [ ] 17.5 Verify configuration validation
- [ ] 17.6 Test on different k0rdent configurations (minimal, production)

## 18. Regression Testing
- [ ] 18.1 Verify all existing KOF features still work
- [ ] 18.2 Test mothership APIs
- [ ] 18.3 Test regional cluster management
- [ ] 18.4 Check KOF collectors functionality
- [ ] 18.5 Verify no new errors or warnings in logs
- [ ] 18.6 Confirm no performance degradation

## Notes
- All tasks should be completed sequentially within their section
- Testing tasks can run in parallel with development tasks where appropriate
- Each task should include verification step before marking complete
- Document any issues or deviations discovered during implementation
