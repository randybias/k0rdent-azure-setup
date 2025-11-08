# Proposal: Detect Orphaned WireGuard VPN State

**Status**: Draft
**Type**: Enhancement
**Priority**: Low
**Created**: 2025-11-08

## Problem Statement

After performing a cluster reset (via `deploy-k0rdent.sh reset` or `manage-vpn.sh disconnect`), WireGuard VPN state files occasionally remain orphaned in `/var/run/wireguard/` on macOS systems. This edge case occurs when:

1. Multiple deployment instances run concurrently in different terminal sessions
2. VPN disconnection fails silently or is interrupted
3. Manual VPN operations bypass the standard cleanup workflow

### Current Behavior

Orphaned state manifests as:
- **`.name` files**: Pattern `wgk0<clusterid>.name` (e.g., `wgk0ju6h3ehi.name`)
- **`.sock` files**: Pattern `utun*.sock` (e.g., `utun5.sock`)

The `.name` file contains the path to the corresponding `.sock` file, creating a pointer relationship between the cluster identifier and the active utun interface.

### Impact

- **Low severity**: Orphaned files don't break functionality
- **Confusion**: Makes it unclear which VPN connections are truly active
- **Disk space**: Minimal (files are small)
- **Manual cleanup required**: Users must identify and remove orphaned files manually

## Proposed Solution

Implement a **detection and notification** system that identifies orphaned WireGuard state after cluster operations. This proposal explicitly does **NOT** include automatic cleanup to avoid interfering with concurrent deployment instances.

### Detection Strategy

Add detection checks at strategic points in the deployment lifecycle:

1. **Pre-deployment validation** (`deploy-k0rdent.sh deploy`)
   - Scan `/var/run/wireguard/` for `.name` files matching non-existent deployments
   - Compare against current `DEPLOYMENT_STATE_FILE` and `.clusterid`
   - Warn if orphaned state detected

2. **Post-reset verification** (`deploy-k0rdent.sh reset`)
   - After successful reset, check if VPN state was fully cleaned
   - Verify both `.name` and `.sock` files were removed
   - Flag any remaining files matching the reset cluster ID

3. **VPN status reporting** (`manage-vpn.sh status`)
   - Extend status command to detect orphaned state
   - Display orphaned files separately from active connections
   - Provide manual cleanup commands

### Detection Logic

```yaml
# Pseudocode (not actual code)
detection_logic:
  step_1: scan /var/run/wireguard/*.name files
  step_2: extract clusterid from filename pattern wgk0<clusterid>.name
  step_3: check if deployment exists:
    - state/deployment-state.yaml contains matching deployment_id
    - OR .clusterid file contains matching ID
    - OR any active deployment using this ID
  step_4: if no matching deployment found:
    - flag as orphaned
    - identify corresponding .sock file from .name contents
    - report to user with manual cleanup instructions
```

### User Notification Format

When orphaned state is detected:

```
⚠️  WARNING: Orphaned WireGuard state detected
    Cluster ID: k0rdent-abc123
    Files:
      - /var/run/wireguard/wgk0abc123.name → utun5.sock
      - /var/run/wireguard/utun5.sock

    This state may belong to a concurrent deployment in another terminal.
    To clean up manually (only if you're sure it's orphaned):
      sudo rm /var/run/wireguard/wgk0abc123.name
      sudo rm /var/run/wireguard/utun5.sock

    To keep this state (if it's from another active deployment):
      No action needed - detection will run again next time.
```

## Non-Goals

This proposal explicitly does **NOT** include:

1. **Automatic cleanup**: Risk of interfering with concurrent deployments
2. **Process management**: Killing or managing `wireguard-go` processes
3. **Interface state modification**: Changes to active VPN connections
4. **Forced cleanup flags**: No `--force-cleanup` or similar dangerous options

## Success Criteria

1. **Detection accuracy**:
   - Correctly identifies orphaned state from terminated deployments
   - Never flags active deployment VPN state as orphaned

2. **Clear communication**:
   - Users understand what orphaned state means
   - Manual cleanup instructions are provided
   - Warning distinguishes between truly orphaned vs concurrent deployment state

3. **Non-invasive**:
   - Detection never modifies system state
   - No automatic cleanup that could break concurrent deployments
   - Safe to run at any time

## Implementation Phases

### Phase 1: Detection Function
Create `detect_orphaned_vpn_state()` function in `etc/common-functions.sh`

### Phase 2: Integration Points
Add detection calls to:
- `deploy-k0rdent.sh deploy` (pre-deployment check)
- `deploy-k0rdent.sh reset` (post-reset verification)
- `manage-vpn.sh status` (status reporting)

### Phase 3: Documentation
Update troubleshooting documentation with orphaned state detection and cleanup procedures

## Security Considerations

- **No sudo operations**: Detection runs without elevated privileges
- **Read-only access**: Only reads `/var/run/wireguard/` directory
- **User confirmation**: All cleanup is manual and user-initiated

## Testing Strategy

Test scenarios:
1. **Clean state**: No orphaned files → no warnings
2. **Orphaned state**: Old deployment files → warning with cleanup instructions
3. **Concurrent deployments**: Active deployment in another terminal → clear distinction
4. **Partial cleanup**: Only `.name` or only `.sock` → detect both cases
5. **Permission issues**: Unreadable directory → graceful degradation

## Related Work

- Existing `cleanup_all_macos_wireguard_interfaces()` in `etc/common-functions.sh`
- Existing `cleanup_orphaned_interfaces()` in `bin/manage-vpn.sh`
- Current reset workflow in `deploy-k0rdent.sh`

## Open Questions

1. Should detection run automatically on every deployment, or only on-demand?
2. How long should we consider state "orphaned" (immediate vs time-based)?
3. Should we maintain a registry of known cluster IDs to improve detection accuracy?

## References

- macOS WireGuard state directory: `/var/run/wireguard/`
- File patterns: `wgk0<clusterid>.name` and `utun*.sock`
- Related documentation: `CLAUDE.md` macOS WireGuard Interface Naming section
