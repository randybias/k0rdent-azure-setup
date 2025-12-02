# Change: Fix Bash Arithmetic Post-Increment Bug with set -e

## Why

The deployment reset process was silently failing before reaching the WireGuard VPN disconnect step. After Step 3 (k0s cluster reset), the script would terminate without any error message, leaving the VPN connected and `/var/run/wireguard/` files orphaned.

Root cause: A classic bash pitfall where `((var++))` (post-increment) returns exit code 1 when the variable is 0, because `((0))` evaluates to false. With `set -euo pipefail` enabled, this terminates the script.

## What Changes

- **Bug Fix**: Replace `((index++))` with `((++index))` (pre-increment) in `phase_reset_from()` function
- **Bug Fix**: Replace `((retry_count++))` with `((++retry_count))` in `deploy_cluster_with_retry()` function
- Pre-increment evaluates to the new value (1), which returns exit code 0 (success)

## Impact

- Affected code:
  - `etc/state-management.sh:255` - `phase_reset_from()` function
  - `etc/azure-cluster-functions.sh:29` - `deploy_cluster_with_retry()` function
- No spec changes required (bug fix restoring intended behavior)

## Technical Details

### The Bug

```bash
# Post-increment: evaluates to OLD value (0), returns exit code 1
set -e
index=0
((index++))  # Script exits here!
echo "never reached"
```

### The Fix

```bash
# Pre-increment: evaluates to NEW value (1), returns exit code 0
set -e
index=0
((++index))  # index is now 1, expression evaluates to 1, success
echo "this runs"
```

### Why It Manifested

1. `deploy-k0rdent.sh reset` calls `uninstall_k0s()` in `bin/install-k0s.sh`
2. `uninstall_k0s()` completes k0sctl reset successfully
3. Then calls `phase_reset_from("install_k0s")` at line 67
4. In the loop searching for "install_k0s" (at index 5), the first iteration tries `((index++))` with `index=0`
5. `((0))` returns exit code 1, script terminates
6. Step 4 (VPN disconnect) is never reached
