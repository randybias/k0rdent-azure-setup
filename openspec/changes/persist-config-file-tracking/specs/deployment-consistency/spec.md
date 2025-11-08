# Deployment Consistency with Configuration File Tracking

## ADDED Requirements

### Requirement: Configuration File Path Persistence
The deployment state tracking system SHALL persist the configuration file path used during initial deployment, ensuring subsequent operations can locate and use the same configuration file.

#### Scenario: Deployment with custom configuration file
**Given** the user deploys with `./deploy-k0rdent.sh deploy --config config/k0rdent-baseline-westeu.yaml`
**When** the deployment state is initialized
**Then** the configuration file path `config/k0rdent-baseline-westeu.yaml` SHALL be stored in deployment-state.yaml
**AND** the file modification time and checksum SHALL be recorded for validation
**AND** subsequent operations SHALL reference this stored path

#### Scenario: Deployment with default configuration file
**Given** the user deploys with default configuration (no --config specified)
**When** the deployment state is initialized
**Then** no custom configuration path SHALL be stored
**AND** normal default configuration search SHALL continue to work
**AND** existing deployments SHALL remain unaffected

### Requirement: Configuration File Resolution Enhancement
All deployment operations SHALL first check for tracked configuration files before falling back to default configuration search, maintaining consistency across the deployment lifecycle.

#### Scenario: Reset operation with tracked configuration
**Given** a previous deployment used config/k0rdent-baseline-westeu.yaml
**When** the user runs `./deploy-k0rdent.sh reset`
**Then** the reset operation SHALL attempt to load config/k0rdent-baseline-westeu.yaml
**AND** SHALL NOT default to ./config/k0rdent.yaml if the tracked file exists
**AND** SHALL use the same configuration settings as the original deployment

#### Scenario: Status operation with tracked configuration
**Given** a deployment was completed with custom configuration
**When** the user runs status or other operations
**Then** the operation SHALL use the same configuration file as the original deployment
**AND** SHALL display the configuration source in status output
**AND** SHALL provide consistent behavior across all operations

### Requirement: Configuration File Validation and Change Detection
The system SHALL validate configuration file integrity and detect changes between deployment and operation times, providing appropriate warnings and guidance.

#### Scenario: Configuration file content changed
**Given** the tracked configuration file has been modified since deployment
**When** a deployment operation is initiated
**Then** the system SHALL detect the content change via checksum comparison
**AND** SHALL display a warning about potential configuration inconsistencies
**AND** SHALL allow the user to proceed or abort based on preference

#### Scenario: Configuration file missing or moved
**Given** the tracked configuration file no longer exists at the stored path
**When** a deployment operation requires the configuration
**Then** the system SHALL provide clear error messaging
**AND** SHALL offer options for resolution (create file, specify new path, use default)
**AND** SHALL gracefully handle the missing file scenario

## MODIFIED Requirements

### Requirement: Enhanced Configuration Loading Logic
The configuration loading mechanism in k0rdent-config.sh SHALL be enhanced to prioritize tracked configuration files while maintaining backward compatibility and environment variable override support.

#### Scenario: Configuration loading with tracked config
**Given** a deployment state contains a tracked configuration file path
**When** scripts load configuration via k0rdent-config.sh
**Then** the tracked configuration SHALL be loaded before default search
**AND** environment variable K0RDENT_CONFIG_FILE SHALL still override tracked config
**AND** backward compatibility SHALL be maintained for deployments without tracked config

#### Scenario: Environment variable override behavior
**Given** a tracked configuration file exists in deployment state
**When** K0RDENT_CONFIG_FILE environment variable is set
**Then** the environment variable SHALL take precedence over tracked config
**AND** the override SHALL be temporary for the current operation
**And** manual override behavior SHALL continue to work as expected

## ADDED Requirements

### Requirement: Configuration File Integrity Validation
The system SHALL validate configuration file integrity and detect unauthorized changes, providing security and consistency assurances for deployment operations.

#### Scenario: Configuration file corruption or format errors
**Given** the tracked configuration file exists but is corrupted or invalid YAML
**When** a deployment operation attempts to load the configuration
**Then** the system SHALL detect the file format issues
**And** SHALL provide clear error messaging about the corruption
**And** SHALL offer fallback to default configuration search

#### Scenario: Configuration file permission issues
**Given** the tracked configuration file exists but has permission restrictions
**When** a deployment operation attempts to read the file
**Then** the system SHALL detect the permission error
**And** SHALL provide guidance on fixing file permissions
**And** SHALL offer alternative configuration options

### Requirement: Configuration File Location Normalization
The system SHALL handle configuration file path variations and ensure consistent file location tracking across different system environments and relative path usage.

#### Scenario: Relative vs absolute configuration paths
**Given** a user specifies configuration file with relative path during deployment
**When** the configuration path is stored in deployment state
**Then** relative paths SHALL be resolved to absolute paths for tracking
**And** subsequent operations SHALL locate the file regardless of working directory
**And** path normalization SHALL prevent location ambiguities

#### Scenario: Configuration file path resolution
**Given** configuration tracking may be used from different working directories
**When** operations resolve configuration file paths
**Then** path resolution SHALL be relative to the project root directory
**And** shall handle both absolute and relative path inputs consistently
**And** SHALL prevent confusion between multiple config files with same name

## Technical Implementation Notes

### State File Structure Enhancement
```yaml
deployment:
  config_file: "config/k0rdent-baseline-westeu.yaml"
  config_last_modified: "2025-11-07T22:30:00Z"
  config_checksum: "abcdef123456789"
```

### Integration Points
- **Deployment Initialization**: Capture config file path when state is created
- **All Operations**: Use tracked config before falling back to defaults
- **Validation Layer**: Check file integrity and change detection
- **Error Handling**: Graceful degradation when config is missing or invalid

### Backward Compatibility
- Deployments without tracked config work exactly as before
- Default configuration search remains unchanged
- Environment variable override behavior preserved
- No breaking changes to existing workflows

### Security Considerations
- Path validation prevents directory traversal attacks
- Permission checking prevents unauthorized file access
- Checksum validation detects unauthorized modifications
- Normalization prevents path-based security issues

### Error Recovery
- Missing configuration files offer clear resolution options
- Changed configuration files provide user choice to proceed
- Permission issues give actionable guidance
- Format errors provide fallback mechanisms
