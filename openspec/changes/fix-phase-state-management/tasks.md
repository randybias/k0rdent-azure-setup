# Implementation Tasks: Fix Phase State Management

## 1. State Management Foundation
- [ ] 1.1 Add `phase_mark_skipped()` function to `etc/state-management.sh`
- [ ] 1.2 Add `phase_is_skipped()` helper function to `etc/state-management.sh`
- [ ] 1.3 Update `phase_status()` to return "skipped" state correctly
- [ ] 1.4 Add unit tests for skipped phase state transitions

## 2. Enhanced Phase Checking Logic
- [ ] 2.1 Update `should_run_phase()` signature to accept optional enablement checker
- [ ] 2.2 Add enablement check logic before validation in `should_run_phase()`
- [ ] 2.3 Update `handle_completed_phase()` to skip validation for disabled components
- [ ] 2.4 Add logging for skipped phases (why they were skipped)

## 3. Deployment Orchestrator Integration
- [ ] 3.1 Update KOF mothership phase call to pass `check_kof_enabled` as enablement checker
- [ ] 3.2 Update KOF regional phase call to pass `check_kof_enabled` as enablement checker
- [ ] 3.3 Add appropriate messaging for skipped vs. already-completed phases
- [ ] 3.4 Remove manual cleanup logic in lines 511-515 of `deploy-k0rdent.sh`

## 4. Testing & Validation
- [ ] 4.1 Test fresh deployment without KOF (verify phases marked as skipped)
- [ ] 4.2 Test fresh deployment with KOF (verify phases run normally)
- [ ] 4.3 Test resume after disabling KOF (verify completed phases marked skipped)
- [ ] 4.4 Test resume after enabling KOF (verify skipped phases transition to pending)
- [ ] 4.5 Verify no warning messages for skipped phases

## 5. Phase Completion Notification Accuracy
- [ ] 5.1 Update `add_event()` in `etc/state-management.sh` to accept optional phase name parameter
- [ ] 5.2 Modify `phase_mark_completed()` to pass phase name to `add_event()`
- [ ] 5.3 Update event structure to include phase name in JSON: `{..., "phase": "install_k0s"}`
- [ ] 5.4 Update `bin/utils/desktop-notifier.sh` to extract phase from event data, not state file
- [ ] 5.5 Add `get_phase_display_name()` function to `etc/notifier-functions.sh`
- [ ] 5.6 Update `phase_completed` handler to use `get_phase_display_name()` for notifications
- [ ] 5.7 Test notification shows "k0s installation" when install_k0s completes
- [ ] 5.8 Test notification shows "k0rdent installation" when install_k0rdent completes
- [ ] 5.9 Verify backward compatibility with old events (without phase field)

## 6. Documentation
- [ ] 6.1 Update CLAUDE.md with optional component phase pattern
- [ ] 6.2 Add inline comments explaining enablement checker usage
- [ ] 6.3 Document state transitions in `etc/state-management.sh` header comment
- [ ] 6.4 Document phase name event structure in `etc/state-management.sh`
- [ ] 6.5 Add comments explaining phase name extraction in `bin/utils/desktop-notifier.sh`
