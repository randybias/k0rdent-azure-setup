# Design: Phase State Management with Optional Components

## Context

The k0rdent deployment system uses a phase-based state machine to track deployment progress. Phases are sequential steps like `prepare_deployment`, `install_k0s`, `install_kof_mothership`, etc. The current implementation has two critical flaws:

**Flaw 1: Optional component phases are treated as always required**

Current behavior:
1. Phase is marked `completed` after successful installation
2. On subsequent runs, `should_run_phase()` checks if phase needs to run
3. For completed phases, `handle_completed_phase()` runs validation
4. For optional components with empty validator, validation "fails" and phase is reset
5. This triggers confusing warnings about re-running phases

**Flaw 2: Phase completion notifications show incorrect component names**

Current behavior:
1. `phase_mark_completed()` records a `phase_completed` event with only a message
2. `bin/utils/desktop-notifier.sh` reads events and enriches them with phase info
3. Phase name is extracted from **current state file** (`.phase` field)
4. By the time event is processed, `.phase` has moved to next phase
5. Notification shows wrong component name (e.g., "k0rdent_installation" when k0s completed)

**Constraints:**
- Must maintain backward compatibility with existing state files
- Must not break existing deployment flows
- Must be explicit about skipped vs. failed phases

**Stakeholders:**
- Deployment automation (relies on phase state accuracy)
- End users (need clear feedback about what's being deployed)
- Future optional components (need consistent pattern)

## Goals / Non-Goals

**Goals:**
- Introduce explicit "skipped" state for optional components
- Prevent validation of phases for disabled components
- Provide clear messaging about which phases are being skipped
- Create reusable pattern for future optional components

**Non-Goals:**
- Changing the core phase execution order
- Adding dynamic phase dependencies
- Supporting conditional phase ordering (phases still run in fixed sequence)
- Parallelizing phase execution

## Decisions

### Decision 1: Add Explicit "Skipped" Phase State

**What:** Add a fourth phase state: `skipped`, alongside `pending`, `in_progress`, `completed`.

**Why:**
- Makes intent explicit (intentionally skipped vs. failed validation)
- Prevents validation logic from running on disabled components
- Improves observability (can query which phases were skipped)
- Follows state machine best practices (explicit states for all transitions)

**Alternatives considered:**
1. Use phase status "pending" for skipped phases
   - Rejected: Ambiguous, can't distinguish never-started from intentionally-skipped
2. Delete phase state for disabled components
   - Rejected: Loses history, makes debugging harder
3. Add boolean flag `phase.skipped_reason`
   - Rejected: More complex than adding a state

### Decision 2: Check Component Enablement Before Phase Validation

**What:** Update `should_run_phase()` to accept optional enablement checker function.

**Why:**
- Prevents unnecessary validation of disabled components
- Centralizes enablement logic in one place
- Makes phase execution conditional on feature flags

**Implementation:**
```bash
should_run_phase() {
    local phase="$1"
    local validator="$2"
    local enablement_checker="${3:-}"  # Optional

    # Check if component is enabled (if checker provided)
    if [[ -n "$enablement_checker" ]] && ! "$enablement_checker"; then
        # Component disabled - mark phase as skipped
        if phase_is_completed "$phase"; then
            # Phase was completed in previous run but now disabled
            phase_mark_skipped "$phase" "Component no longer enabled"
        elif ! phase_is_skipped "$phase"; then
            # Phase never run and component disabled
            phase_mark_skipped "$phase" "Component not enabled"
        fi
        return 1  # Don't run phase
    fi

    # ... rest of existing logic
}
```

**Alternatives considered:**
1. Embed enablement checks in each script
   - Rejected: Duplicates logic, harder to maintain
2. Use phase dependencies to express enablement
   - Rejected: Conflates dependency with enablement

### Decision 3: Update Deployment Orchestrator to Pass Enablement Checkers

**What:** Update `deploy-k0rdent.sh` to pass enablement checker functions to `should_run_phase()`.

**Why:**
- Keeps component-specific logic in deployment orchestrator
- Makes enablement decisions visible in main deployment flow
- Allows different enablement criteria per component

**Implementation:**
```bash
# Step 10: Install KOF mothership (if requested)
if should_run_phase "install_kof_mothership" "" "check_kof_enabled"; then
    print_header "Step 10: Installing KOF Mothership"
    bash bin/install-kof-mothership.sh deploy $DEPLOY_FLAGS
else
    local phase_status=$(phase_status "install_kof_mothership")
    if [[ "$phase_status" == "skipped" ]]; then
        print_info "Step 10 skipped - KOF not enabled in configuration."
    else
        print_success "Step 10 skipped - KOF mothership already installed."
    fi
fi
```

**Alternatives considered:**
1. Use global variable like `$WITH_KOF` everywhere
   - Rejected: Hardcoded to KOF, not reusable for other components
2. Query configuration inside `should_run_phase()`
   - Rejected: Requires knowledge of all component config keys

### Decision 4: Remove Stale Completion State Cleanup

**What:** Remove the manual cleanup in lines 511-515 of `deploy-k0rdent.sh`.

**Why:**
- The new `should_run_phase()` logic handles this automatically
- Reduces special-case code
- Makes behavior consistent across all optional components

**What gets removed:**
```bash
} else {
    # Clear any stale completion state so we do not emit warnings
    if state_file_exists && phase_is_completed "install_kof_regional"; then
        phase_reset_from "install_kof_regional"
    fi
}
```

### Decision 5: Store Completed Phase Name in Event Data

**What:** Modify `add_event()` to accept an optional phase name parameter and store it in the event structure.

**Why:**
- Phase name from event is authoritative (not subject to race conditions)
- Notifications can use the correct phase name regardless of timing
- Event log accurately records which phase completed
- Eliminates dependency on state file's current phase

**Implementation:**
```bash
# In etc/state-management.sh
add_event() {
    local action="$1"
    local message="$2"
    local phase_name="${3:-}"  # Optional phase name
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local event_data="{\"timestamp\": \"${timestamp}\", \"action\": \"${action}\", \"message\": \"${message}\""

    if [[ -n "$phase_name" ]]; then
        event_data="${event_data}, \"phase\": \"${phase_name}\""
    fi

    event_data="${event_data}}"

    yq eval ".events += [${event_data}]" -i "$DEPLOYMENT_EVENTS_FILE"
}

# In phase_mark_completed()
phase_mark_completed() {
    local phase="$1"
    phase_mark_status "$phase" "completed"
    update_state "phase" "$(normalize_phase_name "$phase")"
    add_event "phase_completed" "Phase completed: $(normalize_phase_name "$phase")" "$phase"
}
```

**Alternatives considered:**
1. Parse phase name from event message
   - Rejected: Fragile, depends on message format
2. Store phase history in separate array
   - Rejected: Over-engineered, event already has the data we need
3. Query state file at event creation time
   - Rejected: Same race condition, just moved earlier

### Decision 6: Extract Phase Name from Event Data in Notifier

**What:** Update `bin/utils/desktop-notifier.sh` to use phase name from event data instead of state file.

**Why:**
- Event data is immutable and represents what actually happened
- State file's `.phase` field represents current/next phase (race condition)
- Fixes the bug where "install_k0s" completion shows "k0rdent_installation"

**Implementation:**
```bash
# In bin/utils/desktop-notifier.sh (lines 190-195)
# OLD (buggy):
local phase="unknown"
if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
    phase=$(yq eval '.phase // "unknown"' "$DEPLOYMENT_STATE_FILE" 2>/dev/null || echo "unknown")
    event_json=$(echo "$event_json" | jq --arg phase "$phase" '. + {phase: $phase}')
fi

# NEW (fixed):
# Phase is already in event data from add_event(), use it directly
# If not present, fall back to "unknown" (for backward compatibility with old events)
local phase=$(echo "$event_json" | jq -r '.phase // "unknown"')
```

**Backward Compatibility:**
- Old events without `.phase` field will show "unknown" (acceptable)
- New events will have correct phase name
- No migration needed - old events are historical

### Decision 7: Add Phase Name to Human-Readable Component Mapping

**What:** Add function to map phase names to human-readable component names for notifications.

**Why:**
- "install_k0s" → "k0s installation" (clearer for users)
- "install_k0rdent" → "k0rdent installation" (not "k0rdent_installation")
- Consistent naming across all notifications

**Implementation:**
```bash
# In etc/notifier-functions.sh
get_phase_display_name() {
    local phase="$1"

    case "$phase" in
        "install_k0s") echo "k0s installation" ;;
        "install_k0rdent") echo "k0rdent installation" ;;
        "install_kof_mothership") echo "KOF mothership deployment" ;;
        "install_kof_regional") echo "KOF regional cluster deployment" ;;
        "setup_azure_children") echo "Azure child cluster setup" ;;
        "install_azure_csi") echo "Azure CSI driver installation" ;;
        "prepare_deployment") echo "deployment preparation" ;;
        "setup_network") echo "network setup" ;;
        "create_vms") echo "VM creation" ;;
        "setup_vpn") echo "VPN setup" ;;
        "connect_vpn") echo "VPN connection" ;;
        *) echo "$phase" ;;
    esac
}

# In phase_completed handler
"phase_completed")
    local display_name=$(get_phase_display_name "$phase")
    send_notification "✓ Phase Completed" "$display_name completed successfully" "$message" "$notification_group"
    ;;
```

**Alternatives considered:**
1. Store display names in state file
   - Rejected: Increases complexity, mapping is static
2. Use phase name as-is with string manipulation
   - Rejected: Can't handle special cases like "KOF" vs "Kof"

## Risks / Trade-offs

### Risk: Backward Compatibility with Existing State Files

**Mitigation:**
- The new "skipped" state is additive (doesn't break existing pending/in_progress/completed)
- Existing completed phases remain completed
- Migration happens automatically on next deployment
- Add tests to verify state file migration

### Trade-off: More Complex Phase State Machine

**Impact:**
- 3-state machine (pending/in_progress/completed) becomes 4-state (+ skipped)
- More branches in phase checking logic
- Slightly harder to understand state transitions

**Justification:**
- Explicit is better than implicit (skipped vs. never-started)
- Improves observability and debugging
- Prevents confusing warning messages

### Risk: Inconsistent Enablement Checks

**Scenario:** Developer forgets to pass enablement checker to `should_run_phase()`

**Mitigation:**
- Document pattern in CLAUDE.md
- Add comment in `should_run_phase()` explaining when to use enablement checker
- Consider future validation that all optional component phases have enablement checkers

## Migration Plan

### Phase 1: State Management Updates (Non-Breaking)
1. Add `phase_mark_skipped()` function to `etc/state-management.sh`
2. Update `should_run_phase()` to accept optional enablement checker
3. Add `phase_is_skipped()` helper function
4. Update `phase_status()` to return "skipped" when appropriate

### Phase 2: Deployment Orchestrator Updates
1. Update `deploy-k0rdent.sh` KOF mothership phase (line 494)
2. Update `deploy-k0rdent.sh` KOF regional phase (line 504)
3. Remove manual cleanup logic (lines 511-515)

### Phase 3: Validation & Testing
1. Test fresh deployment without KOF (phases should be skipped)
2. Test fresh deployment with KOF (phases should run normally)
3. Test deployment resume after KOF was enabled (completed phases stay completed)
4. Test deployment resume after KOF was disabled (completed phases marked skipped)

### Rollback Plan
If issues arise:
1. Revert `deploy-k0rdent.sh` changes (restore old `should_run_phase()` calls)
2. State files will still work (skipped state is ignored by old code)
3. Manual cleanup in lines 511-515 can be restored if needed

## Open Questions

1. **Should we add "disabled" as separate state from "skipped"?**
   - Skipped = never started because disabled
   - Disabled = was completed, now disabled
   - **Decision:** No, "skipped" covers both cases. Use skipped_reason for distinction.

2. **Should phase_mark_skipped() accept a reason parameter?**
   - Would improve observability
   - **Decision:** Yes, add optional reason: `phase_mark_skipped "$phase" "KOF not enabled"`

3. **Do we need to validate that skipped phases have enablement checkers?**
   - Would prevent developer errors
   - **Decision:** Not yet. Add if pattern proves error-prone.
