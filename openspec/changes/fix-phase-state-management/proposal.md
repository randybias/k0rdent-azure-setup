# Change: Fix Phase State Management for Optional Components

## Why

The current phase state management has two critical issues:

### Issue 1: Incorrect Re-run Attempts for Optional Components

The phase state management incorrectly attempts to re-run KOF regional install phases even when KOF is not being deployed. This occurs because:

1. The phase completion state is checked without first verifying if the component is enabled
2. The validation function for the phase is empty (""), which causes `handle_completed_phase()` to attempt validation and fail
3. The logic treats a completed phase with failed validation as needing re-run, even when the component is disabled

This results in confusing warning messages like:
```
⚠ KOF regional install marked complete but validation failed. Re-running phase.
```

This is a systemic issue that affects any optional component (KOF mothership, KOF regional, future optional features).

### Issue 2: Phase Completion Notifications Show Wrong Component Name

Desktop notifications incorrectly display the wrong component name when phases complete. For example:

- When "install_k0s" phase completes, notification says: "k0rdent_installation completed successfully"
- Should say: "k0s installation completed successfully"

**Root Cause:**
In `bin/utils/desktop-notifier.sh` lines 193-194, the phase name is extracted from the **current phase in the state file** rather than from the completed event itself:

```bash
phase=$(yq eval '.phase // "unknown"' "$DEPLOYMENT_STATE_FILE")
event_json=$(echo "$event_json" | jq --arg phase "$phase" '. + {phase: $phase}')
```

By the time the `phase_completed` event is processed, the state file's `.phase` field has already been updated to the next phase (e.g., "install_k0rdent"), causing the notification to show the wrong component name.

**Impact:**
- Users receive misleading notifications about what actually completed
- k0s and k0rdent are completely different components - this confusion is unacceptable
- The bug affects all phase completion notifications, not just k0s/k0rdent

## What Changes

### Fix 1: Optional Component Phase Management
- Introduce explicit phase state: `pending`, `in_progress`, `completed`, `skipped`
- Add `phase_mark_skipped()` function to mark phases as intentionally skipped
- Update `should_run_phase()` to check if component is enabled before checking completion
- Update `handle_completed_phase()` to properly distinguish between skipped and failed validations
- Add component enablement checks to phase validation logic
- Update deployment orchestrator to skip optional component phases when not enabled

### Fix 2: Phase Completion Notification Accuracy
- Update `phase_mark_completed()` to include the completed phase name in the event data
- Modify event structure to store phase name: `add_event "phase_completed" "Phase completed: $phase" "$phase"`
- Update `bin/utils/desktop-notifier.sh` to extract phase name from event data, not current state
- Add phase name mapping for human-readable notification messages (install_k0s → "k0s installation")
- Ensure notification messages accurately reflect the component that completed

**Breaking Changes:**
- None - this is an internal state management enhancement
- Existing state files will continue to work (backward compatible)

## Impact

**Affected specs:**
- New: `phase-management` - Defines phase lifecycle and state transitions
- New: `optional-components` - Defines how optional components are enabled/disabled

**Affected code:**
- `etc/state-management.sh` - Add skipped state, enhanced phase checking, and phase name in events
- `deploy-k0rdent.sh` - Update KOF phase execution logic to check enablement first
- `bin/utils/desktop-notifier.sh` - Fix phase name extraction from event data
- `etc/notifier-functions.sh` - Add phase name to notification message mapping
- `bin/install-kof-mothership.sh` - No changes (already checks `check_kof_enabled()`)
- `bin/install-kof-regional.sh` - No changes (already checks `check_kof_enabled()`)

**Migration:**
- Existing deployments will automatically adopt the new behavior
- Phases previously marked "completed" will remain completed
- No manual intervention required
