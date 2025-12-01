# Proposal: Fix Deployment Timeline Display

## Summary

Fix the deployment timeline display to use the existing `created_at` field for start time, add "Current Run Time" for in-progress deployments, and convert UTC timestamps to local timezone for display.

## Motivation

The deployment status command currently displays "null" for start and completion times:

```
Deployment Timeline:
  Started: null
  Completed: null
```

This occurs because:
1. **Status reads wrong field**: Status command reads `deployment_start_time` which doesn't exist - should read `created_at`
2. **Missing current runtime**: No "Current Run Time" field for in-progress deployments
3. **No timezone conversion**: Times stored in UTC but displayed as-is without local conversion
4. **Phases not marked complete**: Phases stay "pending" even after successful completion

The data already exists in the state file:
```yaml
created_at: "2025-12-01T08:56:05Z"           # This is the start time!
deployment_end_time: "2025-12-01 17:06:14 PST"  # End time (when deployment completes)
```

## Proposed Solution

### 1. Fix Status Command to Read `created_at` for Start Time

Change status command from reading non-existent `deployment_start_time` to reading `created_at`:

```bash
# OLD (wrong):
local start_time=$(get_state "deployment_start_time" 2>/dev/null || echo "")

# NEW (correct):
local start_time=$(get_state "created_at" 2>/dev/null || echo "")
```

### 2. Add `deployment_start_time` Field (Bug Fix)

At deployment beginning, copy `created_at` to `deployment_start_time` for consistency:

```bash
# After line 403 in deploy-k0rdent.sh:
local created_at=$(get_state "created_at")
update_state "deployment_start_time" "$created_at"
```

### 3. Convert UTC to Local Timezone for Display

Status command should convert UTC timestamps to local timezone:

```bash
# Input: "2025-12-01T08:56:05Z"
# Output: "2025-12-01 00:56:05 PST"
```

### 4. Add "Current Run Time" Field

For in-progress deployments (no `deployment_end_time`), calculate and display runtime:

```
Deployment Timeline:
  Started: 2025-12-01 00:56:05 PST
  Current Run Time: 15 minutes 32 seconds
  Status: In Progress
```

### 5. Fix Phase Completion Tracking

Phases are never marked as completed. After each phase succeeds, call `phase_mark_completed()`:

```bash
# After each phase in deploy-k0rdent.sh:
if should_run_phase "prepare_deployment" validate_prepare_phase; then
    bash bin/prepare-deployment.sh deploy $DEPLOY_FLAGS
    phase_mark_completed "prepare_deployment"  # ADD THIS
fi
```

This will make phase status show correctly:
```
Deployment Phases:
  ✓ Prepare deployment
  ✓ Setup network
  ✓ Create VMs
```

## User Impact

### Before
```bash
$ ./deploy-k0rdent.sh status

Deployment Timeline:
  Started: null
  Completed: null
```

### After (Completed Deployment)
```bash
$ ./deploy-k0rdent.sh status

Deployment Timeline:
  Started: 2025-12-01 00:56:05 PST
  Completed: 2025-12-01 09:06:14 PST
  Duration: 8 hours 10 minutes 9 seconds

Deployment Phases:
  ✓ Prepare deployment
  ✓ Setup network
  ✓ Create VMs
  ✓ Setup VPN
  ✓ Connect VPN
  ✓ Install k0s
  ✓ Install k0rdent
```

### After (In-Progress Deployment)
```bash
$ ./deploy-k0rdent.sh status

Deployment Timeline:
  Started: 2025-12-01 00:56:05 PST
  Current Run Time: 15 minutes 32 seconds
  Status: In Progress
```

## Implementation Strategy

### Phase 1: Fix Status Command to Read `created_at`
1. Change status command to read `created_at` instead of `deployment_start_time`
2. Test that status shows actual start time (not null)

### Phase 2: Add `deployment_start_time` Field
1. At deployment start, copy `created_at` to `deployment_start_time`
2. This provides consistent field name for future use

### Phase 3: Add UTC to Local Timezone Conversion
1. Create helper function to convert ISO 8601 UTC to local time
2. Update status display to convert timestamps
3. Handle both macOS and Linux date command differences

### Phase 4: Add Current Run Time
1. Detect in-progress deployment (no end_time)
2. Calculate elapsed time from `created_at` to now
3. Display "Current Run Time" field

### Phase 5: Fix Phase Completion Tracking
1. Add `phase_mark_completed()` calls after each phase
2. Test that phases show as completed (✓) in status

## Design Decisions

### Use Existing `created_at` Field

The `created_at` field already exists in every deployment state file and represents when deployment started. No need to create new infrastructure - just use what's already there.

### Add `deployment_start_time` for Consistency

While `created_at` is sufficient, add `deployment_start_time` field by copying `created_at` value at deployment start for API consistency with `deployment_end_time`.

### UTC to Local Timezone Conversion

Convert ISO 8601 UTC timestamps to local time for display:

```bash
# macOS
date -j -f "%Y-%m-%dT%H:%M:%SZ" "2025-12-01T08:56:05Z" "+%Y-%m-%d %H:%M:%S %Z"
# Output: 2025-12-01 00:56:05 PST

# Linux
date -d "2025-12-01T08:56:05Z" "+%Y-%m-%d %H:%M:%S %Z"
# Output: 2025-12-01 00:56:05 PST
```

### Current Run Time Calculation

For in-progress deployments (no `deployment_end_time`), calculate elapsed time from `created_at`:

```bash
# Parse ISO 8601 to epoch
start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$created_at" +%s)
current_epoch=$(date +%s)
elapsed=$((current_epoch - start_epoch))

# Format as "X hours Y minutes Z seconds"
```

## Alternatives Considered

### 1. Create New Start Time Field

**Rejected**: The `created_at` field already captures deployment start time. Using it is simpler than creating new infrastructure.

### 2. Store Times in Local Timezone

**Rejected**: State files already use UTC (ISO 8601), which is correct. We just need to convert for display.

### 3. Skip "Current Run Time" Field

**Rejected**: Users need to see how long a deployment has been running. This is valuable feedback during long deployments.

## Dependencies

- Requires existing state management (etc/state-management.sh)
- Requires existing status command implementation
- No dependencies on other pending changes

## Validation Plan

1. **Test with existing deployment**:
   - Run status on existing deployment
   - Verify start time shows (from `created_at`)
   - Verify completion time shows
   - Verify both converted to local timezone

2. **Test with new deployment**:
   - Start new deployment
   - Check status during deployment
   - Verify "Current Run Time" appears
   - Verify start time shows immediately

3. **Test timezone conversion**:
   - Verify UTC timestamps converted to local
   - Verify timezone indicator present (PST, EST, etc.)
   - Verify calculations use correct time

## Risks

- **Low Risk**: Simple fix - just read the right field
- **Date Command Differences**: macOS vs Linux syntax differs
- **Parse Errors**: Must handle gracefully if date parsing fails

## Success Criteria

- Status shows start time from `created_at` (not null)
- Start time displayed in local timezone
- "Current Run Time" appears for in-progress deployments
- All timestamp conversions work correctly
- No errors on macOS or Linux

## Related Work

- Fixes bug in `add-deployment-status-command` implementation
- Uses existing state file structure
- No conflicts with pending changes
