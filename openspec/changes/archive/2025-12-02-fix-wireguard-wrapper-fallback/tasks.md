## 1. Core Logic Changes

- [x] 1.1 Enhance `check_wg_wrapper()` in `etc/common-functions.sh` to return status codes indicating:
  - Wrapper exists and has setuid (ready to use)
  - Wrapper source exists but binary not compiled
  - Wrapper binary exists but missing setuid bit
  - Wrapper not found at all
- [x] 1.2 Create `offer_to_build_wg_wrapper()` function that:
  - Explains what the wrapper is and why it's needed
  - Offers to build it interactively (respects `SKIP_PROMPTS`)
  - Invokes `bin/utils/build-wg-wrapper.sh` if user accepts
  - Returns appropriate exit code
- [x] 1.3 Modify `run_wg_command()` to:
  - Call enhanced `check_wg_wrapper()` first
  - If wrapper unavailable, call `offer_to_build_wg_wrapper()` instead of falling back to sudo
  - Exit with clear error if user declines and wrapper is required

## 2. Prerequisite Checks

- [x] 2.1 Add `check_wg_wrapper_status_prereq()` function to `bin/check-prerequisites.sh`
- [x] 2.2 Report wrapper status as informational (not blocking) during prerequisite check
- [x] 2.3 Provide guidance on building wrapper if not ready

## 3. First-Run Experience

- [x] 3.1 Add wrapper status check early in `bin/manage-vpn.sh` setup flow
- [x] 3.2 Offer to build wrapper before any VPN operations that require it
- [x] 3.3 Handle worktree scenarios where wrapper may not be symlinked

## 4. Testing and Validation

- [x] 4.1 Test with missing wrapper binary
- [x] 4.2 Test with binary present but no setuid bit
- [x] 4.3 Test with fully configured wrapper
- [x] 4.4 Test interactive prompts (yes/no responses)
- [x] 4.5 Test non-interactive mode (`-y` / `SKIP_PROMPTS=true`)
