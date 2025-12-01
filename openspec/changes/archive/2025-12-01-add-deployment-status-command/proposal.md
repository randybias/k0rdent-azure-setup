# Proposal: Add Deployment Status Command

## Summary

Add a `status` command to `deploy-k0rdent.sh` that reads deployment state files to determine if a cluster is deployed and summarizes key deployment parameters. This provides users with a quick way to check deployment status without manually inspecting state files.

## Motivation

Currently, users have two issues when trying to understand their deployment:
1. No centralized way to check if a cluster is deployed or what state it's in
2. No easy way to see key deployment parameters without manually reading YAML files

The only way to check deployment status is to:
- Manually read `state/deployment-state.yaml`
- Run individual component status commands (`bin/install-k0s.sh status`, etc.)
- Rely on trial and error (try to connect and see what happens)

This creates a poor user experience, especially for users returning to a deployment after time away.

## Proposed Solution

Add a new `status` command to `deploy-k0rdent.sh` that:
1. Checks if deployment state files exist
2. Reads current deployment phase and status
3. Summarizes key deployment parameters from state
4. Shows deployment timing information
5. Provides a clear "deployed" vs "not deployed" vs "partially deployed" status

The command will follow the existing pattern used by component scripts (e.g., `bin/manage-vpn.sh status`, `bin/install-k0s.sh status`) but provide an overview of the entire deployment.

## User Impact

### Before
```bash
# No easy way to check status
$ cat state/deployment-state.yaml | grep status
status: completed

# Must check multiple places for information
$ ./bin/install-k0s.sh status
$ ./bin/manage-vpn.sh status
```

### After
```bash
$ ./deploy-k0rdent.sh status

k0rdent Deployment Status
=========================

Deployment State: DEPLOYED
Cluster ID: k0rdent-c8fsc8uu
Region: southeastasia

Deployment Timeline:
  Started: 2025-12-01 10:59:57 PST
  Completed: 2025-12-01 11:11:12 PST
  Duration: 11 minutes 15 seconds

Cluster Configuration:
  Controllers: 1 (Standard_B2s)
  Workers: 1 (Standard_B2s)
  k0s Version: v1.30.7+k0s.0
  k0rdent Version: 0.3.0

Network:
  VPN Status: Connected (utun8)
  VPN Network: 192.168.100.0/24

Deployment Flags:
  Azure Children: Disabled
  KOF: Disabled

Deployment Phases:
  ✓ Prepare deployment
  ✓ Setup network
  ✓ Create VMs
  ✓ Setup VPN
  ✓ Connect VPN
  ✓ Install k0s
  ✓ Install k0rdent

Kubeconfig: ./k0sctl-config/k0rdent-c8fsc8uu-kubeconfig
```

## Implementation Strategy

1. Add `status` command handler to main case statement in `deploy-k0rdent.sh`
2. Implement `show_deployment_status()` function that:
   - Checks for state file existence
   - Reads deployment state from YAML
   - Formats and displays status information
   - Handles cases: not deployed, partially deployed, fully deployed
3. Reuse existing helper functions from `etc/state-management.sh` and `etc/common-functions.sh`
4. Follow existing patterns from component status commands

## Alternatives Considered

1. **Create a separate `bin/deployment-status.sh` script**
   - Rejected: Users expect status to be a command of the main deployment script
   - Precedent: All component scripts have status subcommands

2. **Extend existing `config` command**
   - Rejected: `config` shows configuration, not deployment state
   - Status is fundamentally different from configuration display

3. **Use `state/deployment-state.yaml` directly**
   - Rejected: Poor UX, requires users to understand YAML structure
   - Status command should provide formatted, human-readable output

## Dependencies

- Depends on existing state file structure in `state/deployment-state.yaml`
- Depends on helper functions in `etc/state-management.sh`
- Depends on helper functions in `etc/common-functions.sh`

## Related Changes

This change is independent and has no dependencies on other pending changes. It complements:
- `canonical-config-from-state` (archived) - uses state-based configuration
- State management patterns already established in the codebase

## Validation Plan

1. Test with no deployment (state file missing)
2. Test with partial deployment (deployment in progress)
3. Test with completed deployment
4. Test with failed deployment phases
5. Test with various deployment flag combinations (--with-azure-children, --with-kof)
6. Verify output formatting and readability
7. Test that existing commands still work (deploy, reset, config)

## Risks

- **Low Risk**: This is a read-only operation that doesn't modify any state
- **No Breaking Changes**: Adds new command without changing existing behavior
- **Minimal Complexity**: Uses existing state management infrastructure

## Success Criteria

- Users can run `./deploy-k0rdent.sh status` to see deployment state
- Command shows clear "deployed" / "not deployed" / "partial" status
- Command displays all key deployment parameters from state
- Command handles missing state files gracefully
- Output is readable and well-formatted
- Command follows existing patterns from component scripts
