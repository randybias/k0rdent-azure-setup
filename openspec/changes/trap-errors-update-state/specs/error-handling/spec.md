# Error Handling Spec Delta

## ADDED Requirements

### Requirement: Deployment state reflects unexpected failures

When a deployment script exits unexpectedly due to an error (command failure, unbound variable, syntax error, or signal), the state file MUST be updated to reflect the failure before the process terminates.

#### Scenario: Command failure during deployment phase

- Given a deployment is running with phase "create_vms" in progress
- When a command in `bin/create-azure-vms.sh` fails
- And bash exits due to `set -e`
- Then `deployment-state.yaml` shows `status: failed`
- And `deployment-state.yaml` shows `phase: create_vms`
- And an event is logged with the exit code

#### Scenario: User interrupts deployment with Ctrl+C

- Given a deployment is running with phase "install_k0s" in progress
- When the user presses Ctrl+C (SIGINT)
- Then `deployment-state.yaml` shows `status: failed`
- And `deployment-state.yaml` shows `phase: install_k0s`
- And an event is logged indicating user interruption

#### Scenario: Successful deployment completes normally

- Given a deployment completes all phases successfully
- When the script exits normally with code 0
- Then `deployment-state.yaml` shows `status: completed`
- And no failure events are logged

### Requirement: Failed deployments can be resumed

After a deployment fails and state is updated, the operator MUST be able to resume from the failed phase without re-running completed phases.

#### Scenario: Resume after network setup failure

- Given a deployment failed during "setup_network" phase
- And `deployment-state.yaml` shows `status: failed` and `phase: setup_network`
- When the operator fixes the issue and runs `./deploy-k0rdent.sh deploy`
- Then phases before "setup_network" are skipped
- And deployment resumes from "setup_network"
