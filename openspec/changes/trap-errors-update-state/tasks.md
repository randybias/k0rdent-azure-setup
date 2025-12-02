# Tasks: Trap Errors and Update State on Unexpected Exit

## Implementation Tasks

- [ ] 1. Add `mark_phase_failed()` helper to `etc/state-management.sh`
  - Updates status to "failed"
  - Records the failed phase
  - Logs error event with exit code and timestamp
  - Safe to call even if state file doesn't exist yet

- [ ] 2. Add `CURRENT_PHASE` tracking to `deploy-k0rdent.sh`
  - Declare global variable at script start
  - Set before each phase execution
  - Clear after successful `phase_mark_completed`

- [ ] 3. Implement `cleanup_on_error()` trap handler in `deploy-k0rdent.sh`
  - Capture exit code
  - Disable trap to prevent re-entry
  - Call `mark_phase_failed()` if exit code non-zero and phase is set
  - Call existing `stop_desktop_notifier`
  - Exit with original exit code

- [ ] 4. Register trap for SIGINT SIGTERM ERR EXIT
  - Replace existing `trap 'stop_desktop_notifier' EXIT`
  - Use combined handler for all signals

- [ ] 5. Test scenarios
  - Simulate failure in each phase (e.g., bad Azure credentials)
  - Verify state file shows failed status
  - Verify resume works from failed phase
  - Verify Ctrl+C during deployment updates state
  - Verify successful deployment still works normally

## Optional Enhancements

- [ ] 6. Add traps to individual bin/*.sh scripts for granular tracking
  - Lower priority - main script trap covers most cases
  - Useful for long-running scripts like `create-azure-vms.sh`
