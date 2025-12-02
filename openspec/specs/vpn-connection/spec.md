# vpn-connection Specification

## Purpose
TBD - created by archiving change fix-wireguard-wrapper-fallback. Update Purpose after archive.
## Requirements
### Requirement: WireGuard Wrapper Availability Check
The system SHALL check the availability and status of the WireGuard setuid wrapper before attempting any WireGuard operations.

#### Scenario: Wrapper is ready to use
- **WHEN** the `wg-wrapper` binary exists at `bin/utils/wg-wrapper`
- **AND** the binary has the setuid bit set
- **THEN** the system SHALL use the wrapper for WireGuard operations without prompting

#### Scenario: Wrapper binary not compiled
- **WHEN** the `wg-wrapper` binary does not exist
- **AND** the source file `bin/utils/code/wg-wrapper.c` exists
- **THEN** the system SHALL inform the user that the wrapper needs to be built
- **AND** SHALL offer to build it (unless in non-interactive mode)

#### Scenario: Wrapper missing setuid bit
- **WHEN** the `wg-wrapper` binary exists
- **AND** the binary does NOT have the setuid bit set
- **THEN** the system SHALL inform the user that the wrapper needs setuid permissions
- **AND** SHALL offer to rebuild it with proper permissions

### Requirement: No Silent Sudo Fallback
The system SHALL NOT silently fall back to using `sudo` for WireGuard operations when the wrapper is unavailable.

#### Scenario: Wrapper unavailable in interactive mode
- **WHEN** the wrapper is not available
- **AND** the system is running in interactive mode
- **THEN** the system SHALL prompt the user to build the wrapper
- **AND** SHALL NOT invoke `sudo` without explicit user action

#### Scenario: Wrapper unavailable in non-interactive mode
- **WHEN** the wrapper is not available
- **AND** the system is running in non-interactive mode (`SKIP_PROMPTS=true` or `-y` flag)
- **THEN** the system SHALL exit with an error
- **AND** SHALL provide instructions for building the wrapper manually

### Requirement: Wrapper Build Offer
The system SHALL offer to build the WireGuard wrapper when it is needed but unavailable.

#### Scenario: User accepts build offer
- **WHEN** the system offers to build the wrapper
- **AND** the user accepts (enters "yes" or "y")
- **THEN** the system SHALL invoke `bin/utils/build-wg-wrapper.sh`
- **AND** SHALL verify the wrapper is ready after build completes
- **AND** SHALL continue with the original WireGuard operation

#### Scenario: User declines build offer
- **WHEN** the system offers to build the wrapper
- **AND** the user declines (enters "no" or "n")
- **THEN** the system SHALL exit with a clear error message
- **AND** SHALL NOT fall back to `sudo`

### Requirement: Prerequisite Check Guidance
The prerequisite check SHALL report on WireGuard wrapper status and provide guidance.

#### Scenario: Wrapper ready during prerequisite check
- **WHEN** `bin/check-prerequisites.sh` is run
- **AND** the wrapper is properly configured
- **THEN** the system SHALL report "WireGuard wrapper: Ready"

#### Scenario: Wrapper not ready during prerequisite check
- **WHEN** `bin/check-prerequisites.sh` is run
- **AND** the wrapper is not ready
- **THEN** the system SHALL report the wrapper status as informational (not a failure)
- **AND** SHALL provide instructions for building the wrapper

