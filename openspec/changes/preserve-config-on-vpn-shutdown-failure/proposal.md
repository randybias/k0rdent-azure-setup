# Proposal: Preserve WireGuard Config on Shutdown Failure

## Summary

During VPN reset/cleanup, verify the WireGuard interface is fully down before deleting the configuration file. If shutdown fails, preserve the config file and exit with an error so the operator can manually troubleshoot.

## Problem

Currently, `reset_and_cleanup()` in `bin/manage-vpn.sh` attempts to shut down WireGuard and then unconditionally deletes the config file regardless of whether shutdown succeeded. This leaves operators without the config file needed to manually clean up a stuck interface.

## Solution

1. Check the return code from `shutdown_wireguard_interface()`
2. On macOS, verify `/var/run/wireguard/${interface_name}.name` no longer exists
3. On Linux, verify `wg show` no longer shows the interface
4. Only delete `WG_CONFIG_FILE` if verification passes
5. Exit with error (return 1) if VPN is still up, preserving the config file

## Scope

- **File**: `bin/manage-vpn.sh` - `reset_and_cleanup()` function
- **Behavior change**: Config file preserved on failure instead of deleted

## Success Criteria

- Config file remains if shutdown fails
- Clear error message indicating manual intervention needed
- Successful shutdown still removes config file as before
