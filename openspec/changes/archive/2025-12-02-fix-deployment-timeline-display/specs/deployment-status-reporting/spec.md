# Capability: Deployment Status Reporting

## Overview

Fixes the deployment status reporting to correctly display deployment timeline using the existing `created_at` field.

## MODIFIED Requirements

### Requirement: Deployment Timeline Display
**ID**: REQ-DSR-004 (Modified)

The status command MUST display deployment timing information using `created_at` for start time and convert UTC to local timezone.

#### Scenario: Show start time from created_at
```bash
$ ./deploy-k0rdent.sh status
# Output includes:
# Deployment Timeline:
#   Started: 2025-12-01 00:56:05 PST  (converted from created_at: 2025-12-01T08:56:05Z)
```

#### Scenario: Show current runtime for in-progress deployment
```bash
$ ./deploy-k0rdent.sh status
# When deployment is running (no deployment_end_time):
# Deployment Timeline:
#   Started: 2025-12-01 00:56:05 PST
#   Current Run Time: 15 minutes 32 seconds
#   Status: In Progress
```

#### Scenario: Show completed deployment timeline
```bash
$ ./deploy-k0rdent.sh status
# When deployment is complete:
# Deployment Timeline:
#   Started: 2025-12-01 00:56:05 PST
#   Completed: 2025-12-01 09:06:14 PST
#   Duration: 8 hours 10 minutes 9 seconds
```

## ADDED Requirements

### Requirement: Use created_at for Start Time
**ID**: REQ-DSR-014

The status command MUST read `created_at` field from state for deployment start time, not `deployment_start_time`.

#### Scenario: Read created_at field
```bash
# Status command reads from state:
$ yq eval '.created_at' state/deployment-state.yaml
# 2025-12-01T08:56:05Z

# Status displays as local time:
#   Started: 2025-12-01 00:56:05 PST
```

#### Scenario: Handle missing created_at
```bash
# If created_at not present (shouldn't happen):
$ ./deploy-k0rdent.sh status
# (Timeline section omitted)
```

### Requirement: Convert UTC to Local Timezone
**ID**: REQ-DSR-015

The status command MUST convert ISO 8601 UTC timestamps to local timezone for display.

#### Scenario: Convert UTC to local timezone
```bash
# State has: created_at: "2025-12-01T08:56:05Z" (UTC)
# Display shows: 2025-12-01 00:56:05 PST (local)
```

#### Scenario: Include timezone indicator
```bash
$ ./deploy-k0rdent.sh status
# Must include timezone abbreviation:
#   Started: 2025-12-01 00:56:05 PST
# NOT just:
#   Started: 2025-12-01 00:56:05
```

#### Scenario: Handle timezone conversion errors
```bash
# If conversion fails:
# Display UTC time as-is with UTC indicator
#   Started: 2025-12-01 08:56:05 UTC
```

### Requirement: Display Current Runtime
**ID**: REQ-DSR-016

The status command MUST display "Current Run Time" for in-progress deployments.

#### Scenario: Calculate runtime from created_at
```bash
# State has:
#   created_at: "2025-12-01T08:56:05Z"
#   deployment_end_time: null (or missing)

$ ./deploy-k0rdent.sh status
# Shows:
#   Current Run Time: 15 minutes 32 seconds
```

#### Scenario: Runtime increases on each check
```bash
# First check:
$ ./deploy-k0rdent.sh status
#   Current Run Time: 5 minutes 12 seconds

# 5 minutes later:
$ ./deploy-k0rdent.sh status
#   Current Run Time: 10 minutes 18 seconds
```

#### Scenario: No runtime for completed deployments
```bash
# When deployment_end_time exists:
$ ./deploy-k0rdent.sh status
# Shows duration, NOT current runtime:
#   Duration: 8 hours 10 minutes 9 seconds
```

### Requirement: Set deployment_start_time Field
**ID**: REQ-DSR-017

The deployment process MUST copy `created_at` to `deployment_start_time` at deployment start for API consistency.

#### Scenario: Copy created_at to deployment_start_time
```bash
# At deployment start (after line 403):
# State file updated:
#   created_at: "2025-12-01T08:56:05Z"
#   deployment_start_time: "2025-12-01T08:56:05Z"  # Same value
```

#### Scenario: Field available for future use
```bash
# Both fields present for consistency:
$ yq eval '.created_at, .deployment_start_time' state/deployment-state.yaml
# 2025-12-01T08:56:05Z
# 2025-12-01T08:56:05Z
```

### Requirement: Mark Phases as Completed
**ID**: REQ-DSR-018

The deployment process MUST call `phase_mark_completed()` after each successful phase execution.

#### Scenario: Mark phase completed after execution
```bash
# After each phase completes:
if should_run_phase "prepare_deployment" validate_prepare_phase; then
    bash bin/prepare-deployment.sh deploy $DEPLOY_FLAGS
    phase_mark_completed "prepare_deployment"
fi

# State updated:
# phases:
#   prepare_deployment:
#     status: "completed"
#     updated_at: "2025-12-01T09:01:23Z"
```

#### Scenario: Status shows completed phases
```bash
$ ./deploy-k0rdent.sh status
# Deployment Phases:
#   ✓ Prepare deployment
#   ✓ Setup network
#   ⏳ Create VMs (in progress)
#   ○ Setup VPN
```

#### Scenario: All phases marked when deployment completes
```bash
# After full deployment:
$ yq eval '.phases | to_entries[] | select(.value.status == "completed") | .key' state/deployment-state.yaml
# prepare_deployment
# setup_network
# create_vms
# setup_vpn
# connect_vpn
# install_k0s
# install_k0rdent
```

## Design Decisions

### Use Existing created_at Field

The `created_at` field already exists and represents deployment start time. Status command just needs to read the correct field.

**Before** (broken):
```bash
local start_time=$(get_state "deployment_start_time")  # Field doesn't exist!
```

**After** (fixed):
```bash
local start_time=$(get_state "created_at")  # Uses existing field
```

### ISO 8601 UTC Format

State files already use ISO 8601 UTC format (`2025-12-01T08:56:05Z`). No changes needed to storage format - only need to parse and convert for display.

### Platform-Specific Date Commands

**macOS**:
```bash
date -j -f "%Y-%m-%dT%H:%M:%SZ" "2025-12-01T08:56:05Z" "+%Y-%m-%d %H:%M:%S %Z"
```

**Linux**:
```bash
date -d "2025-12-01T08:56:05Z" "+%Y-%m-%d %H:%M:%S %Z"
```

Detect OS with `uname` and use appropriate command.

### Current Runtime Calculation

1. Parse `created_at` to epoch seconds
2. Get current epoch time
3. Calculate difference
4. Format as "X hours Y minutes Z seconds"

## Implementation Notes

### Changes Required

**File**: `deploy-k0rdent.sh` - Status command (~line 1050)

1. Change field read:
   ```bash
   # OLD:
   local start_time=$(get_state "deployment_start_time" 2>/dev/null || echo "")

   # NEW:
   local start_time=$(get_state "created_at" 2>/dev/null || echo "")
   ```

2. Add timezone conversion helper function

3. Add current runtime calculation

4. Update display logic

**File**: `deploy-k0rdent.sh` - Deployment start (~line 403)

Add `deployment_start_time` field:
```bash
local created_at=$(get_state "created_at")
update_state "deployment_start_time" "$created_at"
```

### Helper Functions Needed

```bash
convert_utc_to_local() {
    local utc_time="$1"
    # Detect OS and convert to local timezone
    # Return formatted string with TZ indicator
}

calculate_current_runtime() {
    local start_time="$1"
    # Parse to epoch, calculate elapsed, format
    # Return "X hours Y minutes Z seconds"
}
```

## Testing Requirements

1. **With existing deployment**:
   - Run status command
   - Verify start time appears (not null)
   - Verify times in local timezone

2. **With new deployment**:
   - Start deployment
   - Check status during deployment
   - Verify "Current Run Time" appears

3. **Timezone conversion**:
   - Verify UTC converted to local
   - Verify timezone indicator present
   - Test on macOS (primary platform)

4. **Edge cases**:
   - Missing created_at (shouldn't happen)
   - Invalid timestamp format
   - Date command errors

## Future Enhancements

- Add phase timing (how long each phase took)
- Show estimated time remaining
- Display phase-by-phase performance metrics
