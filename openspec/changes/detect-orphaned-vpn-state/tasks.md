# Implementation Tasks: Detect Orphaned WireGuard VPN State

## Overview
Implementation tasks for the orphaned VPN state detection system. This is a **detection-only** feature - no automatic cleanup is included to avoid interfering with concurrent deployments.

## Task Breakdown

### Task 1: Create Detection Function
**File**: `etc/common-functions.sh`
**Priority**: High
**Estimate**: 2-3 hours

#### Description
Create `detect_orphaned_vpn_state()` function that scans `/var/run/wireguard/` for orphaned state files.

#### Acceptance Criteria
- [ ] Function detects `.name` files matching pattern `wgk0<clusterid>.name`
- [ ] Extracts cluster ID from filename
- [ ] Checks if cluster ID exists in:
  - Current `state/deployment-state.yaml`
  - `.clusterid` file in project root
  - Any environment variable `K0RDENT_CLUSTERID`
- [ ] Reads `.name` file contents to find corresponding `.sock` file
- [ ] Returns list of orphaned state with cluster ID, .name file, and .sock file
- [ ] Handles missing directory gracefully (VPN never used)
- [ ] Handles permission errors gracefully (non-root user)

#### Implementation Notes
```bash
# Signature (pseudocode, not actual code)
detect_orphaned_vpn_state() {
    # Returns: Array of "clusterid|name_file|sock_file" strings
    # Returns: Empty array if no orphaned state found
    # Returns: Empty array on errors (missing dir, permissions)
}
```

---

### Task 2: Create User Notification Function
**File**: `etc/common-functions.sh`
**Priority**: High
**Estimate**: 1 hour

#### Description
Create `report_orphaned_vpn_state()` function that formats detection results for user display.

#### Acceptance Criteria
- [ ] Takes array of orphaned state from detection function
- [ ] Formats warning message with cluster ID, files, and paths
- [ ] Includes manual cleanup commands
- [ ] Distinguishes between truly orphaned vs potential concurrent deployment
- [ ] Uses clear warning symbols and formatting
- [ ] Provides option to skip notification if user prefers

#### Implementation Notes
```bash
# Signature (pseudocode, not actual code)
report_orphaned_vpn_state() {
    local orphaned_state=("$@")
    # Prints formatted warning to stdout
    # Exits silently if array is empty
}
```

---

### Task 3: Integrate Pre-Deployment Check
**File**: `deploy-k0rdent.sh`
**Priority**: Medium
**Estimate**: 1 hour

#### Description
Add orphaned state detection to `deploy` command before starting deployment.

#### Acceptance Criteria
- [ ] Detection runs after configuration loading
- [ ] Detection runs before any Azure resources are created
- [ ] Warning displayed if orphaned state detected
- [ ] Deployment continues after warning (non-blocking)
- [ ] Detection can be skipped with `--skip-vpn-check` flag
- [ ] Detection only runs on macOS (skipped on Linux/Windows)

#### Implementation Location
```bash
# In deploy-k0rdent.sh, deploy command
# After: Configuration loading
# Before: Azure resource creation
# Call: detect_orphaned_vpn_state() and report_orphaned_vpn_state()
```

---

### Task 4: Integrate Post-Reset Verification
**File**: `deploy-k0rdent.sh`
**Priority**: Medium
**Estimate**: 1 hour

#### Description
Add orphaned state detection after `reset` command completes cleanup.

#### Acceptance Criteria
- [ ] Detection runs after all cleanup operations complete
- [ ] Specifically checks for state matching the just-reset cluster ID
- [ ] Warning displayed if reset didn't fully clean VPN state
- [ ] Provides manual cleanup commands for the specific cluster
- [ ] Detection only runs on macOS
- [ ] Works with both `reset` and `reset --fast` modes

#### Implementation Location
```bash
# In deploy-k0rdent.sh, reset command
# After: All cleanup operations
# Before: Final success message
# Call: detect_orphaned_vpn_state() with cluster ID filter
```

---

### Task 5: Extend VPN Status Command
**File**: `bin/manage-vpn.sh`
**Priority**: Low
**Estimate**: 1-2 hours

#### Description
Extend `status` command to detect and report orphaned state separately from active connections.

#### Acceptance Criteria
- [ ] Status command shows active VPN connections (existing behavior)
- [ ] Status command shows orphaned state in separate section
- [ ] Clear visual distinction between active and orphaned
- [ ] Manual cleanup commands provided for orphaned state
- [ ] `--check-orphaned` flag to only check orphaned state
- [ ] Works on macOS only (graceful skip on other platforms)

#### Implementation Location
```bash
# In manage-vpn.sh, status command
# After: Display active connections
# Add: Orphaned state detection and reporting section
```

---

### Task 6: Add Configuration Option
**Files**: `config/k0rdent-default.yaml`, `config/examples/*.yaml`
**Priority**: Low
**Estimate**: 30 minutes

#### Description
Add configuration option to control orphaned state detection behavior.

#### Acceptance Criteria
- [ ] New config section: `vpn.orphaned_state_detection.enabled` (default: true)
- [ ] New config option: `vpn.orphaned_state_detection.on_deploy` (default: true)
- [ ] New config option: `vpn.orphaned_state_detection.on_reset` (default: true)
- [ ] Configuration respected by all detection integration points
- [ ] Documentation in YAML comments explaining the options

#### Implementation Example
```yaml
vpn:
  orphaned_state_detection:
    enabled: true          # Enable orphaned state detection
    on_deploy: true        # Check before deployments
    on_reset: true         # Check after resets
```

---

### Task 7: Update Documentation
**Files**: `backlog/docs/doc-XXX - Orphaned-VPN-State.md`, `CLAUDE.md`
**Priority**: Medium
**Estimate**: 1 hour

#### Description
Create troubleshooting documentation for orphaned VPN state detection and manual cleanup.

#### Acceptance Criteria
- [ ] New doc in `backlog/docs/` explaining the feature
- [ ] Troubleshooting steps for manual cleanup
- [ ] Explanation of when orphaned state occurs
- [ ] How to distinguish truly orphaned vs concurrent deployment state
- [ ] Update `CLAUDE.md` with detection pattern for future reference
- [ ] Examples of warning messages and cleanup commands

---

### Task 8: Add Unit Tests
**Files**: `tests/test-vpn-orphaned-state.sh` (new)
**Priority**: Low
**Estimate**: 2 hours

#### Description
Create test suite for orphaned state detection logic.

#### Acceptance Criteria
- [ ] Test: No orphaned state (clean system)
- [ ] Test: Orphaned state detected correctly
- [ ] Test: Active deployment not flagged as orphaned
- [ ] Test: Concurrent deployment state distinguished
- [ ] Test: Permission errors handled gracefully
- [ ] Test: Missing directory handled gracefully
- [ ] Test: Malformed .name files handled gracefully
- [ ] All tests pass on macOS

---

## Testing Checklist

Before marking this change as complete:

- [ ] Manual test: Clean state → no warnings
- [ ] Manual test: Create orphaned files → warning shown
- [ ] Manual test: Concurrent deployments → not flagged
- [ ] Manual test: Post-reset with incomplete cleanup → warning shown
- [ ] Manual test: VPN status shows orphaned state separately
- [ ] Manual test: Configuration options respected
- [ ] Manual test: Linux/non-macOS systems gracefully skip detection
- [ ] Code review: Detection logic is read-only
- [ ] Code review: No automatic cleanup operations
- [ ] Documentation review: Clear instructions for users

---

## Dependencies

- `yq` installed (YAML processing)
- macOS system (detection is macOS-specific)
- Existing VPN management functions in `etc/common-functions.sh`
- Existing state management in `etc/state-management.sh`

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| False positives (flagging active deployments) | Comprehensive detection logic checks multiple sources |
| Permission errors reading /var/run/wireguard/ | Graceful error handling, skip detection if needed |
| User confusion about concurrent deployments | Clear messaging distinguishing orphaned vs concurrent |
| Performance impact | Detection is lightweight, only reads directory and small files |
| Platform compatibility | Detection is macOS-only, gracefully skipped elsewhere |

---

## Future Enhancements (Out of Scope)

These are explicitly **NOT** included in this proposal:

- Automatic cleanup of orphaned state
- Time-based orphaned detection (e.g., "older than 24 hours")
- Central registry of active cluster IDs
- Process management or killing wireguard-go
- Forced cleanup flags or operations
