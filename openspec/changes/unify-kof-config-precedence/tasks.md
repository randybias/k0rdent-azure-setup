# Tasks: Unify KOF Configuration Precedence

## Phase 1: Core Precedence Implementation

### Task 1.1: Add KOF configuration validation function
- Create `validate_kof_config()` in `etc/common-functions.sh`
- Check required fields: version, istio.version, istio.namespace, mothership.namespace
- Return detailed error messages listing missing fields
- Include example configuration in error output
- Test with missing fields, empty values, and complete config

### Task 1.2: Add regional KOF configuration validation
- Extend `validate_kof_config()` to accept validation mode parameter
- Add `--regional` mode that additionally checks: domain, admin_email, location, template
- Make regional validation optional (only when `--with-azure-children` provided)
- Test mothership-only validation (no regional fields required)
- Test regional validation (all fields required)

### Task 1.3: Implement configuration resolution logic in deploy-k0rdent.sh
- After loading configuration (after `source ./etc/k0rdent-config.sh`), resolve KOF enablement
- Resolution logic:
  - If `--with-kof` flag provided: Set `WITH_KOF=true` (already done in arg parsing)
  - If no flag: Read `kof.enabled` from YAML and set `WITH_KOF` to match
  - Default: `WITH_KOF=false` if neither flag nor config enable KOF
- Add logging: "==> KOF enabled via CLI flag" or "==> KOF enabled via configuration"
- Test all combinations: flag only, config only, both, neither

### Task 1.4: Add early validation for resolved KOF enablement
- After resolving `WITH_KOF` variable, check if KOF is enabled
- If `WITH_KOF=true`, call validation function immediately
- On validation failure, print error and exit before any state operations
- On validation success, proceed to deployment phases
- Test with invalid config to ensure early exit

### Task 1.5: Update deployment summary to show enablement source
- Modify deployment summary section (around line 362 in deploy-k0rdent.sh)
- Show enablement source based on how KOF was enabled:
  - Flag overrode config: "KOF Installation: ENABLED (via --with-kof flag, overrides config)"
  - Flag matched config: "KOF Installation: ENABLED (via --with-kof flag)"
  - Config only: "KOF Installation: ENABLED (via configuration)"
  - Disabled: "KOF Installation: Disabled"
- When flag overrides config, suggest: "Tip: Set kof.enabled: true in config for persistence"
- Test summary display with all combinations

## Phase 2: State Management Integration

### Task 2.1: Store resolved KOF configuration in deployment state
- In `deploy-k0rdent.sh` deploy command, before calling phase scripts
- Read current `kof.enabled` from YAML
- If `WITH_KOF=true`, override in-memory value to `true`
- Store resolved configuration in `state/deployment-state.yaml` under `config.kof.enabled`
- Verify state file contains correct resolved value

### Task 2.2: Update KOF functions to read from deployment state
- Modify `check_kof_enabled()` in `etc/kof-functions.sh`
- First try reading from deployment state: `$(get_state "config.kof.enabled")`
- Fall back to direct YAML read if state not available (backwards compatibility)
- Test with deployment state present and absent
- Ensure function works in both scenarios

### Task 2.3: Propagate resolved configuration to child scripts
- Ensure all KOF-related scripts source `etc/state-management.sh`
- Update scripts to use `check_kof_enabled()` consistently
- Remove any direct YAML reads that bypass state
- Verify: install-kof-mothership.sh, install-kof-regional.sh
- Test full deployment with flag override

## Phase 3: Enhanced Validation

### Task 3.1: Add validation timing check
- Ensure validation occurs immediately after argument parsing
- Place validation before any of these operations:
  - State file initialization
  - Azure CLI calls
  - WireGuard key generation
- Add timing log: "==> Validating KOF configuration..."
- Test that validation prevents any Azure resource creation on failure

### Task 3.2: Create validation error message templates
- Add `print_kof_validation_error()` helper to `etc/common-functions.sh`
- Template should include:
  - Clear heading: "✗ KOF configuration validation failed"
  - List of missing/invalid fields
  - Example configuration block
  - File path to edit
- Use consistent formatting with other error messages
- Test readability of error messages

### Task 3.3: Add optional validation skip flag (advanced)
- Add `--skip-kof-validation` flag to deploy-k0rdent.sh argument parser
- Store as `SKIP_KOF_VALIDATION` variable
- Skip validation when flag provided BUT show warning
- Warning: "⚠ KOF validation skipped - late-stage failures may occur"
- Test with invalid config and skip flag

## Phase 4: Backwards Compatibility

### Task 4.1: Test existing workflows without flag
- Deploy with `kof.enabled: true` in YAML, no `--with-kof` flag
- Deploy with `kof.enabled: false` in YAML, no `--with-kof` flag
- Verify behavior identical to pre-change implementation
- Ensure no breaking changes for existing users

### Task 4.2: Test all resolution scenarios
Create test matrix for all combinations:

| Flag | Config | Expected Behavior |
|------|--------|-------------------|
| `--with-kof` | `enabled: true` | KOF installed (both agree) |
| `--with-kof` | `enabled: false` | KOF installed (flag overrides) |
| `--with-kof` | not set | KOF installed (flag enables) |
| not provided | `enabled: true` | KOF installed (config enables) |
| not provided | `enabled: false` | KOF skipped (config disables) |
| not provided | not set | KOF skipped (default: disabled) |

- Test each scenario
- Verify correct behavior
- Document any deviations

### Task 4.3: Update deployment state migration
- Ensure old deployment states without `config.kof` section continue working
- Add migration logic if needed to handle old states
- Test with deployment state from before this change
- Verify graceful fallback to direct YAML read

## Phase 5: Documentation and Polish

### Task 5.1: Update CLI help text
- Document `--with-kof` flag behavior in help output
- Explain precedence: "Enables KOF installation, overrides configuration file"
- Add example: `./deploy-k0rdent.sh deploy --with-kof --config my-config.yaml`
- Update both deploy-k0rdent.sh help and README.md

### Task 5.2: Update configuration file comments
- Add comment to config/k0rdent-default.yaml explaining precedence
- Example: "# Can be overridden with --with-kof CLI flag"
- Clarify that false means "disabled by default" not "never enable"
- Update documentation about flag vs config relationship

### Task 5.3: Create troubleshooting guide
- Document common validation errors and fixes
- Add section: "KOF Configuration Validation Errors"
- List each required field with description and example
- Add to docs/ directory or README
- Include in error message reference: "See docs/KOF-CONFIG.md for details"

### Task 5.4: Add integration test
- Create test script: `tests/test-kof-flag-precedence.sh`
- Test matrix: all combinations of flag/config states
- Verify validation errors and successful deployments
- Add to CI/test suite if applicable
- Document expected behavior for each scenario

## Phase 6: Validation and Cleanup

### Task 6.1: Run full deployment test
- Test end-to-end deployment with `--with-kof` flag override
- Use config with `kof.enabled: false`
- Verify KOF installs successfully
- Check deployment state contains resolved configuration
- Validate no late-stage failures occur

### Task 6.2: Test validation failure paths
- Test each validation error condition:
  - Missing kof section
  - Missing version field
  - Missing istio configuration
  - Invalid regional configuration
- Verify clear error messages and no Azure resources created
- Confirm exit codes are non-zero

### Task 6.3: Review and refactor
- Check for code duplication in validation logic
- Ensure consistent error message formatting
- Verify all functions have appropriate sourcing
- Clean up any debug logging added during implementation
- Run syntax check on all modified scripts

### Task 6.4: Update OpenSpec status
- Mark all tasks as completed
- Update spec status from Draft to Implemented
- Document any deviations from original design
- Archive proposal if fully implemented
- Create follow-up proposals for any discovered issues

## Dependencies

- **Task 1.4 depends on**: 1.1, 1.2, 1.3 (validation functions and resolution logic must exist)
- **Task 1.5 depends on**: 1.3 (resolution logic must exist to show source)
- **Task 2.2 depends on**: 2.1 (state must be populated before reading)
- **Task 3.1 depends on**: 1.4 (validation logic must exist)
- **Phase 4 depends on**: Phases 1-3 complete (test after implementation)
- **Phase 6 depends on**: All other phases (final validation)

## Parallelization Opportunities

- Tasks 1.1 and 1.2 can be done together (same function, different modes)
- Tasks 2.1 and 2.2 can be developed in parallel (different files)
- Task 3.2 can be done anytime in Phase 3 (independent helper)
- All Phase 5 documentation tasks can be parallelized
- Phase 4 tests can run concurrently if independent test environments available

## Validation Criteria

Each task complete when:
- Code changes implemented and syntax-checked
- Manual testing completed with expected results
- Error cases tested and handled gracefully
- Documentation updated if user-facing changes
- No regressions in existing functionality
