# Tasks: Add Deployment Status Command

## Implementation Tasks

### Phase 1: Core Status Function

- [x] **Task 1.1**: Create `show_deployment_status()` function in deploy-k0rdent.sh
  - Add function before main execution section
  - Define function signature
  - Add function documentation comment

- [x] **Task 1.2**: Implement state file existence check
  - Call `state_file_exists()` helper
  - Handle "NOT DEPLOYED" case
  - Display appropriate message and exit gracefully

- [x] **Task 1.3**: Read deployment state variables
  - Read `deployment_id`, `phase`, `status` from state
  - Read `deployment_flags` for azure_children and kof
  - Read `config` section for cluster parameters
  - Handle missing fields gracefully

### Phase 2: Status Display Sections

- [x] **Task 2.1**: Implement overall status determination
  - Determine DEPLOYED vs IN PROGRESS vs NOT DEPLOYED
  - Base determination on phase and status fields
  - Display status with appropriate formatting

- [x] **Task 2.2**: Display cluster configuration section
  - Show cluster ID
  - Show region from config
  - Show controller/worker counts
  - Show VM sizes
  - Show k0s and k0rdent versions

- [x] **Task 2.3**: Display network information section
  - Show VPN network configuration
  - Show VPN connection status
  - Show WireGuard interface (if connected)
  - Handle VPN not connected case

- [x] **Task 2.4**: Display deployment timeline section
  - Read `deployment_start_time` and `deployment_end_time`
  - Calculate and display duration
  - Handle in-progress deployments (show elapsed time)
  - Handle missing timing information

- [x] **Task 2.5**: Display deployment flags section
  - Show Azure Children status (Enabled/Disabled)
  - Show KOF status (Enabled/Disabled)
  - Read from `deployment_flags` in state

### Phase 3: Phase Status Display

- [x] **Task 3.1**: Implement phase status iteration
  - Iterate through standard deployment phases
  - Read status for each phase from state
  - Map status to display symbols (✓, ⏳, ○)

- [x] **Task 3.2**: Display standard phases
  - Show all standard phases: prepare_deployment through install_k0rdent
  - Use appropriate symbols based on status
  - Display phase display names (not internal keys)

- [x] **Task 3.3**: Display optional phases
  - Check deployment flags for azure_children and kof
  - Show optional phases when enabled
  - Skip optional phases when not enabled

### Phase 4: Resource Locations

- [x] **Task 4.1**: Display kubeconfig location
  - Build kubeconfig path from cluster ID
  - Check if file exists
  - Display path with appropriate formatting

- [x] **Task 4.2**: Display state file location
  - Show path to deployment-state.yaml
  - Add note about configuration source

- [x] **Task 4.3**: Display configuration source
  - Show K0RDENT_CONFIG_SOURCE value
  - Add brief explanation (deployment-state vs default)

### Phase 5: Command Integration

- [x] **Task 5.1**: Add status case to main case statement
  - Add `"status")` case handler
  - Call `show_deployment_status` function
  - Position before existing commands

- [x] **Task 5.2**: Update help text
  - Add status command to command list
  - Add description: "Show deployment status"
  - Update examples section if appropriate

- [x] **Task 5.3**: Update usage function
  - Ensure status appears in help output
  - Verify formatting consistency

### Phase 6: Error Handling

- [x] **Task 6.1**: Handle corrupted state files
  - Wrap state reads in error handling
  - Detect YAML parsing errors
  - Display helpful error message

- [x] **Task 6.2**: Handle missing required fields
  - Provide defaults for missing fields
  - Log warning for unexpected missing data
  - Continue execution where possible

- [x] **Task 6.3**: Handle partial state
  - Detect incomplete deployments
  - Show appropriate "IN PROGRESS" status
  - Display completed vs pending phases clearly

### Phase 7: Testing

- [x] **Task 7.1**: Test with no deployment
  - Remove state file
  - Run `./deploy-k0rdent.sh status`
  - Verify "NOT DEPLOYED" message
  - Verify exit code 0

- [x] **Task 7.2**: Test with completed deployment
  - Use existing deployment state
  - Run `./deploy-k0rdent.sh status`
  - Verify all sections display correctly
  - Verify phase status shows all completed

- [x] **Task 7.3**: Test with deployment flags
  - Test with azure_children=true
  - Test with kof=true
  - Test with both flags true
  - Verify optional phases display

- [x] **Task 7.4**: Test with partial deployment
  - Simulate in-progress deployment (modify state)
  - Run status command
  - Verify "IN PROGRESS" status
  - Verify phase display shows mix of completed/pending

- [x] **Task 7.5**: Test with old state file
  - Use state file missing new fields (timing, etc.)
  - Run status command
  - Verify graceful degradation
  - Verify no errors, just missing sections

- [x] **Task 7.6**: Test with corrupted state file
  - Create invalid YAML in state file
  - Run status command
  - Verify error handling
  - Verify helpful error message

### Phase 8: Documentation

- [x] **Task 8.1**: Update README
  - Add status command to command reference
  - Add example output
  - Document use cases

- [x] **Task 8.2**: Update CLAUDE.md if needed
  - Add status command to development guidelines
  - Document status function patterns if establishing new pattern

- [x] **Task 8.3**: Add inline documentation
  - Add comments to `show_deployment_status()` function
  - Document key logic decisions
  - Add examples in comments

### Phase 9: Validation

- [x] **Task 9.1**: Run OpenSpec validation
  - Execute `openspec validate add-deployment-status-command --strict`
  - Resolve any validation errors
  - Ensure all requirements are traceable

- [x] **Task 9.2**: Cross-check with requirements
  - Verify REQ-DSR-001 through REQ-DSR-008 are satisfied
  - Test each scenario in spec
  - Document any deviations

- [x] **Task 9.3**: Code review checklist
  - Verify follows existing patterns
  - Check error handling completeness
  - Verify output formatting consistency
  - Ensure no hardcoded values

## Dependencies

- Requires `etc/state-management.sh` functions
- Requires `etc/common-functions.sh` formatting functions
- Requires `etc/k0rdent-config.sh` configuration loading
- Requires existing state file structure in `state/deployment-state.yaml`

## Testing Strategy

1. **Manual Testing**: Test all scenarios listed in Phase 7
2. **Regression Testing**: Verify existing commands (deploy, reset, config) still work
3. **User Acceptance**: Have users test status command for readability and usefulness

## Success Criteria

- [x] Status command executes without errors
- [x] All test scenarios pass
- [x] Output is readable and well-formatted
- [x] No breaking changes to existing functionality
- [x] OpenSpec validation passes
- [x] Documentation is complete and accurate

## Estimated Complexity

- **Complexity**: Low to Medium
- **Risk**: Low (read-only operation)
- **Effort**: 2-3 hours of development + 1 hour testing
- **Lines of Code**: ~150-200 lines (function + integration)

## Notes

- This is a purely additive change - no modifications to existing code except adding the new command
- Follow existing patterns from component status commands (e.g., `bin/manage-vpn.sh status`)
- Reuse existing helper functions extensively
- Focus on human-readable output; machine-readable output can be future enhancement
