# Tasks: Preserve WireGuard Config on Shutdown Failure

## Implementation Tasks

- [ ] 1. Add VPN-down verification function to `common-functions.sh`
  - Check `/var/run/wireguard/${interface}.name` absence on macOS
  - Check `wg show` returns empty on Linux
  - Return 0 if down, 1 if still up

- [ ] 2. Modify `reset_and_cleanup()` in `bin/manage-vpn.sh`
  - Capture return code from `shutdown_wireguard_interface()`
  - Call verification function after shutdown attempt
  - Only delete config file if verification passes
  - Print error and return 1 if VPN still up

- [ ] 3. Test scenarios
  - Normal shutdown: config deleted, success
  - Failed shutdown: config preserved, error returned
  - No config file: graceful handling
