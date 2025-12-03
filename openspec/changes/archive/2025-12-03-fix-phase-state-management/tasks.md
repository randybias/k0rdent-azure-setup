# Implementation Tasks: Fix Phase State Management

## 1. State Management Foundation
- [x] 1.1 Add `phase_mark_skipped()` function to `etc/state-management.sh`
- [x] 1.2 Add `phase_is_skipped()` helper function to `etc/state-management.sh`
- [x] 1.3 Update `phase_status()` to return "skipped" state correctly
- [x] 1.4 Update `phase_needs_run()` to exclude skipped phases

## 2. Enhanced Phase Checking Logic
- [x] 2.1 Update `should_run_phase()` signature to accept optional enablement checker
- [x] 2.2 Add enablement check logic before validation in `should_run_phase()`
- [x] 2.3 Update `handle_completed_phase()` to skip validation for disabled components
- [x] 2.4 Add logging for skipped phases (why they were skipped)

## 3. Deployment Orchestrator Integration
- [x] 3.1 Update KOF mothership phase call to pass `is_kof_deployment_enabled` as enablement checker
- [x] 3.2 Update KOF regional phase call to pass `is_kof_deployment_enabled` as enablement checker
- [x] 3.3 Add appropriate messaging for skipped vs. already-completed phases
- [x] 3.4 Remove manual cleanup logic (now handled by enablement checker pattern)
- [x] 3.5 Move deployment flags recording before first phase (ensures correct status display)
- [x] 3.6 Add `populate_wg_ips_array` call after `assign_wireguard_ips` (fixes early state init)

## 4. Testing & Validation
- [x] 4.1 Test fresh deployment without KOF (verify phases marked as skipped)
- [x] 4.2 Test fresh deployment with KOF (verify phases run normally)
- [x] 4.3 Test resume after disabling KOF (verify completed phases marked skipped)
- [x] 4.4 Test resume after enabling KOF (verify skipped phases transition to pending)
- [x] 4.5 Verify no warning messages for skipped phases

## 5. Phase Completion Notification Accuracy
- [x] 5.1 Update `add_event()` in `etc/state-management.sh` to accept optional phase name parameter
- [x] 5.2 Modify `phase_mark_completed()` to pass phase name to `add_event()`
- [x] 5.3 Update event structure to include phase name in JSON: `{..., "phase": "install_k0s"}`
- [x] 5.4 Update `bin/utils/desktop-notifier.sh` to extract phase from event data, not state file
- [x] 5.5 Add `get_phase_display_name()` function to `etc/notifier-functions.sh`
- [x] 5.6 Update `phase_completed` handler to use `get_phase_display_name()` for notifications
- [x] 5.7 Add `phase_skipped` event handler in notifier-functions.sh
- [x] 5.8 Add skipped phase symbol (⏭) to status display
- [x] 5.9 Verify backward compatibility with old events (without phase field)

## 6. Documentation
- [x] 6.1 Add inline comments explaining enablement checker usage in deploy-k0rdent.sh
- [x] 6.2 Document state transitions in `etc/state-management.sh` function comments
- [x] 6.3 Add comments explaining phase name extraction in `bin/utils/desktop-notifier.sh`
