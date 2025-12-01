# Capability: Deployment Status Reporting

## Overview

Provides users with a command to view the current state of a k0rdent deployment, including deployment phases, configuration parameters, and timing information.

## ADDED Requirements

### Requirement: Status Command Interface
**ID**: REQ-DSR-001

The deploy-k0rdent.sh script MUST support a `status` command that displays deployment state information.

#### Scenario: User checks deployment status
```bash
$ ./deploy-k0rdent.sh status
# Displays formatted deployment status information
```

#### Scenario: Status command in help text
```bash
$ ./deploy-k0rdent.sh help
# Output includes:
#   status    Show deployment status
```

### Requirement: Deployment State Detection
**ID**: REQ-DSR-002

The status command MUST determine deployment state by checking for state file existence and reading deployment status.

#### Scenario: No deployment exists
```bash
$ ./deploy-k0rdent.sh status
# Returns:
# Deployment State: NOT DEPLOYED
# No deployment state found
```

#### Scenario: Deployment in progress
```bash
$ ./deploy-k0rdent.sh status
# Returns:
# Deployment State: IN PROGRESS
# Current Phase: create_vms
# Phase Status: in_progress
```

#### Scenario: Deployment completed
```bash
$ ./deploy-k0rdent.sh status
# Returns:
# Deployment State: DEPLOYED
# All phases completed
```

### Requirement: Configuration Summary
**ID**: REQ-DSR-003

The status command MUST display key deployment configuration parameters from state.

#### Scenario: Display cluster configuration
```bash
$ ./deploy-k0rdent.sh status
# Output includes:
# Cluster Configuration:
#   Controllers: 1 (Standard_B2s)
#   Workers: 1 (Standard_B2s)
#   k0s Version: v1.30.7+k0s.0
#   k0rdent Version: 0.3.0
```

#### Scenario: Display network configuration
```bash
$ ./deploy-k0rdent.sh status
# Output includes:
# Network:
#   VPN Status: Connected (utun8)
#   VPN Network: 192.168.100.0/24
#   Region: southeastasia
```

#### Scenario: Display deployment flags
```bash
$ ./deploy-k0rdent.sh status
# Output includes:
# Deployment Flags:
#   Azure Children: Enabled
#   KOF: Disabled
```

### Requirement: Deployment Timeline
**ID**: REQ-DSR-004

The status command MUST display deployment timing information when available.

#### Scenario: Show deployment duration
```bash
$ ./deploy-k0rdent.sh status
# Output includes:
# Deployment Timeline:
#   Started: 2025-12-01 10:59:57 PST
#   Completed: 2025-12-01 11:11:12 PST
#   Duration: 11 minutes 15 seconds
```

#### Scenario: Show in-progress timing
```bash
$ ./deploy-k0rdent.sh status
# When deployment is running:
# Deployment Timeline:
#   Started: 2025-12-01 10:59:57 PST
#   Status: In Progress
#   Elapsed: 5 minutes 30 seconds
```

### Requirement: Phase Status Display
**ID**: REQ-DSR-005

The status command MUST display the status of each deployment phase.

#### Scenario: Show completed phases
```bash
$ ./deploy-k0rdent.sh status
# Output includes:
# Deployment Phases:
#   ✓ Prepare deployment
#   ✓ Setup network
#   ✓ Create VMs
#   ✓ Setup VPN
#   ✓ Connect VPN
#   ✓ Install k0s
#   ✓ Install k0rdent
```

#### Scenario: Show in-progress phase
```bash
$ ./deploy-k0rdent.sh status
# Output includes:
# Deployment Phases:
#   ✓ Prepare deployment
#   ✓ Setup network
#   ⏳ Create VMs (in progress)
#   ○ Setup VPN
#   ○ Install k0s
```

#### Scenario: Show optional phases
```bash
$ ./deploy-k0rdent.sh status
# When --with-kof was used:
# Deployment Phases:
#   ✓ Prepare deployment
#   ...
#   ✓ Install k0rdent
#   ✓ Setup Azure children
#   ✓ Install Azure CSI
#   ✓ Install KOF mothership
#   ✓ Install KOF regional
```

### Requirement: Resource Location Display
**ID**: REQ-DSR-006

The status command MUST display the location of key deployment artifacts.

#### Scenario: Show kubeconfig location
```bash
$ ./deploy-k0rdent.sh status
# Output includes:
# Kubeconfig: ./k0sctl-config/k0rdent-c8fsc8uu-kubeconfig
```

#### Scenario: Show state file location
```bash
$ ./deploy-k0rdent.sh status
# Output includes:
# State File: ./state/deployment-state.yaml
```

### Requirement: Error Handling
**ID**: REQ-DSR-007

The status command MUST handle missing or corrupted state files gracefully.

#### Scenario: State file missing
```bash
$ ./deploy-k0rdent.sh status
# Returns:
# Deployment State: NOT DEPLOYED
# No deployment state found at: ./state/deployment-state.yaml
# Exit code: 0
```

#### Scenario: State file corrupted
```bash
$ ./deploy-k0rdent.sh status
# Returns:
# Error: Unable to read deployment state
# State file may be corrupted: ./state/deployment-state.yaml
# Exit code: 1
```

### Requirement: Configuration Source Reporting
**ID**: REQ-DSR-008

The status command MUST report which configuration source is being used, consistent with state-based configuration resolution.

#### Scenario: Using deployment state configuration
```bash
$ ./deploy-k0rdent.sh status
# Output includes:
# Configuration source: deployment-state
```

#### Scenario: Using default configuration
```bash
$ ./deploy-k0rdent.sh status
# When no deployment exists:
# Configuration source: default
```

## Design Decisions

### State File as Source of Truth

The status command reads exclusively from `state/deployment-state.yaml`, not from individual component state files or live system checks. This ensures:
- Fast execution (no network calls or system checks)
- Consistency with recorded deployment state
- Simplicity (single source of truth)

### Read-Only Operation

The status command performs no modifications to state or configuration. It is purely informational and safe to run at any time.

### Human-Readable Output

Output is formatted for human readability, not machine parsing. Future iterations could add a `--json` flag for machine-readable output if needed.

### Graceful Degradation

If certain state fields are missing (e.g., timing information on older deployments), the status command displays available information without failing.

## Implementation Notes

### Function Structure
```bash
show_deployment_status() {
    # Check state file existence
    # Read deployment state
    # Format and display:
    #   - Overall status
    #   - Cluster configuration
    #   - Network information
    #   - Deployment timeline
    #   - Phase status
    #   - Resource locations
}
```

### Reused Components
- `state_file_exists()` from `etc/state-management.sh`
- `get_state()` from `etc/state-management.sh`
- `print_header()`, `print_info()`, `print_success()` from `etc/common-functions.sh`
- Configuration loading from `etc/k0rdent-config.sh`

### Phase Status Symbols
- `✓` - Completed phase
- `⏳` - In progress phase
- `○` - Pending phase
- `✗` - Failed phase (future enhancement)

## Testing Requirements

1. Unit-level testing scenarios:
   - State file does not exist
   - State file exists but is empty
   - State file with partial deployment
   - State file with complete deployment
   - State file with all optional features enabled

2. Integration testing:
   - Run after fresh deployment
   - Run during deployment (if possible)
   - Run after partial deployment reset
   - Run after configuration changes

3. Edge cases:
   - Very old state files (missing new fields)
   - State files with unexpected values
   - Concurrent access during deployment

## Future Enhancements

1. **Machine-readable output**: Add `--json` flag for JSON output
2. **Live checks**: Add `--verify` flag to check actual resources vs state
3. **Health status**: Add component health checks (cluster reachable, pods running)
4. **Resource consumption**: Add VM and cluster resource usage information
5. **Child clusters**: Add child cluster status when Azure children are deployed
