# Change: Fix WireGuard Wrapper Fallback Behavior

## Why
When the setuid `wg-wrapper` binary is not built (common in new clones, worktrees, or first-time deployments), the VPN setup silently falls back to `sudo`, triggering an unexpected password prompt. Users should be informed that the wrapper needs to be built and offered the option to build it, rather than falling back to `sudo` without explanation.

## What Changes
- **BREAKING**: Remove silent fallback to `sudo` in `run_wg_command()` when wrapper is missing
- Add detection logic to identify why the wrapper is unavailable (not built vs. built but not setuid)
- Prompt user to build the wrapper when it's missing, with clear explanation
- Add wrapper status check to prerequisite validation (`check-prerequisites.sh`)
- Add first-run detection to guide users through wrapper setup

## Impact
- Affected specs: vpn-connection (new capability spec)
- Affected code:
  - `etc/common-functions.sh`: `check_wg_wrapper()`, `run_wg_command()`
  - `bin/check-prerequisites.sh`: Add wrapper status check
  - `bin/utils/build-wg-wrapper.sh`: No changes, but will be invoked automatically
