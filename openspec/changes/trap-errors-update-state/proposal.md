# Proposal: Trap Errors and Update State on Unexpected Exit

## Summary

Add bash trap handlers to deployment scripts so that when bash exits unexpectedly (syntax errors, unbound variables, command failures with `set -e`), the state files are updated to reflect the failure before the script terminates.

## Problem

Currently, scripts use `set -euo pipefail` which causes immediate exit on errors, but:
1. State files are only updated on successful phase completion via `phase_mark_completed`
2. If bash bails out due to a hard error (syntax, unbound variable, failed command), state is never updated
3. The cluster's actual state becomes inconsistent with what's recorded in `deployment-state.yaml`
4. Operators cannot trust the state file to know where the deployment actually failed

## Current Behavior

```bash
set -euo pipefail
# ...
bash bin/some-script.sh  # If this fails...
phase_mark_completed "phase_name"  # ...this never runs
```

The only trap currently in `deploy-k0rdent.sh` is for desktop notifier cleanup:
```bash
trap 'stop_desktop_notifier' EXIT
```

## Proposed Solution

Implement the standard bash trap pattern for error handling:

```bash
# Global to track current phase
CURRENT_PHASE=""

cleanup_on_error() {
    local exit_code=$?
    trap - SIGINT SIGTERM ERR EXIT  # Prevent re-entry

    if [[ $exit_code -ne 0 ]] && [[ -n "$CURRENT_PHASE" ]]; then
        update_state "status" "failed"
        update_state "phase" "$CURRENT_PHASE"
        update_state "error_exit_code" "$exit_code"
        add_event "deployment_failed" "Deployment failed during phase: $CURRENT_PHASE (exit code: $exit_code)"
    fi

    stop_desktop_notifier
    exit $exit_code
}

trap cleanup_on_error SIGINT SIGTERM ERR EXIT
```

Before each phase:
```bash
CURRENT_PHASE="setup_network"
bash bin/setup-azure-network.sh deploy $DEPLOY_FLAGS
phase_mark_completed "setup_network"
CURRENT_PHASE=""  # Clear after success
```

## Key Design Decisions

1. **Single trap handler** in main `deploy-k0rdent.sh` - sub-scripts inherit the parent's exit behavior via `set -e`
2. **Track current phase** in a global variable so the trap knows what was running
3. **Clear trap on entry** to prevent recursive trap calls
4. **Preserve exit code** so the script exits with the original error code
5. **Only update state on non-zero exit** to avoid overwriting success state

## Scope

Primary changes:
- `deploy-k0rdent.sh` - Add trap handler and phase tracking
- `etc/state-management.sh` - Add helper function `mark_phase_failed()`

Secondary (optional):
- Individual bin/*.sh scripts could add their own traps for finer granularity

## Success Criteria

1. When deployment fails unexpectedly, `deployment-state.yaml` shows:
   - `status: failed`
   - `phase: <phase where failure occurred>`
   - Event logged with exit code
2. Operators can resume from the failed phase after fixing the issue
3. No change to behavior on successful deployments
