# Tasks: Fix Bash Arithmetic Post-Increment Bug

## Status: COMPLETED

All tasks have been completed. The fix has been applied and is ready for testing.

## 1. Investigation

- [x] 1.1 Analyze reset output to identify where script terminates
  - Found: Script terminates after "k0s cluster reset completed" but before "k0s cluster uninstall completed"
  - Step 4 (VPN disconnect) never printed

- [x] 1.2 Trace code path from `deploy-k0rdent.sh` reset through `install-k0s.sh`
  - Located: `uninstall_k0s()` calls `phase_reset_from("install_k0s")` at line 67

- [x] 1.3 Identify root cause of silent script termination
  - Found: `((index++))` at `state-management.sh:255` with `index=0` returns exit code 1
  - With `set -euo pipefail`, this terminates the script

## 2. Fix Implementation

- [x] 2.1 Fix `phase_reset_from()` in `etc/state-management.sh:255`
  - Changed: `((index++))` to `((++index))`
  - Added comment explaining the fix

- [x] 2.2 Search codebase for similar `((var++))` patterns that start at 0
  - Found: `etc/azure-cluster-functions.sh:29` - `((retry_count++))` with `retry_count=0`
  - Other occurrences start at 1 or are only incremented conditionally (safe)

- [x] 2.3 Fix `deploy_cluster_with_retry()` in `etc/azure-cluster-functions.sh:29`
  - Changed: `((retry_count++))` to `((++retry_count))`
  - Added comment explaining the fix

## 3. Validation

- [x] 3.1 Verify syntax of modified files
  - Ran: `bash -n ./etc/state-management.sh` - OK
  - Ran: `bash -n ./etc/azure-cluster-functions.sh` - OK

- [x] 3.2 Verify pre-increment fix works with `set -e`
  - Tested: `bash -c 'set -euo pipefail; index=0; ((++index)); echo "works: $index"'`
  - Result: Outputs "works: 1" (success)

- [x] 3.3 Test full reset cycle to confirm VPN is properly disconnected
  - Command: `./deploy-k0rdent.sh reset -y`
  - Result: Step 4 (VPN disconnect) executes, `/var/run/wireguard/` is cleaned up
  - Verified by user
