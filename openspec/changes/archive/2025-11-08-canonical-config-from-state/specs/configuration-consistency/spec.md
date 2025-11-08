# Configuration Consistency Across Scripts

## ADDED Requirements

### Requirement: Canonical Configuration Resolution from Deployment State
All k0rdent scripts SHALL derive their configuration from the canonical deployment state rather than default configuration files, ensuring consistency across the entire deployment ecosystem.

#### Scenario: Post-deployment script uses deployment state configuration
**Given** a k0rdent deployment was completed with a custom configuration file
**When** a post-deployment script like setup-azure-cluster-deployment.sh is executed
**Then** the script SHALL read configuration from deployment-state.yaml
**And** SHALL use the same Azure region, VM sizes, and settings as the original deployment
**And** SHALL NOT fall back to default ./config/k0rdent.yaml when deployment state is available

#### Scenario: Multiple scripts operate on same deployment with consistent configuration
**Given** a deployment completed with specific configuration parameters
**When** multiple scripts (Azure setup, child cluster creation, KOF installation) are executed
**Then** ALL scripts SHALL use identical configuration derived from deployment state
**And** configuration variables SHALL be consistent across all script executions
**And** scripts SHALL report the configuration source for transparency

## ADDED Requirements

### Requirement: Enhanced Configuration Loading with State Integration
The k0rdent-config.sh configuration loader SHALL be enhanced to prioritize deployment state configuration while maintaining backward compatibility with existing deployments.

#### Scenario: Configuration loader prioritization with fallback logic
**Given** deployment-state.yaml exists with canonical configuration
**When** any script loads configuration via etc/k0rdent-config.sh
**Then** the configuration loader SHALL prioritize deployment-state.yaml first
**And** SHALL fall back to default configuration files when state is unavailable
**And** SHALL provide clear messaging about which configuration source is used
**And** SHALL maintain compatibility with existing deployment workflows

#### Scenario: Environment variable override behavior
**Given** K0RDENT_CONFIG_FILE environment variable is explicitly set
**When** configuration loading occurs via enhanced k0rdent-config.sh
**Then** the environment variable SHALL still override state and default sources
**And** manual overrides SHALL work for advanced users and diagnostics
**And** configuration source reporting SHALL indicate manual override is active

## ADDED Requirements

### Requirement: State File Access and Validation
The system SHALL provide robust access to deployment state files with proper validation and fallback handling for various state file conditions.

#### Scenario: Deployment state file is present and valid
**Given** deployment-state.yaml exists with complete configuration
**When** canonical configuration resolution is attempted
**Then** the system SHALL successfully extract configuration from the state file
**And** SHALL validate that required configuration elements are present
**And** SHALL use the extracted configuration for script execution
**And** SHALL log the configuration source and timestamp

#### Scenario: Deployment state file is missing or unavailable
**Given** deployment-state.yaml does not exist or is inaccessible
**When** configuration resolution is attempted
**Then** the system SHALL gracefully fall back to default configuration file search
**And** SHALL provide warning message about missing deployment state
**And** SHALL continue normal operation using default configuration
**And** SHALL not fail due to missing state file

#### Scenario: Deployment state file is corrupted or malformed
**Given** deployment-state.yaml exists but contains invalid YAML or missing sections
**When** configuration resolution is attempted
**Then** the system SHALL detect the corruption through validation failures
**And** SHALL provide clear error message about state file issues
**And** SHALL fall back to default configuration with appropriate warning
**And** SHALL continue operation using default configuration to maintain functionality

### Requirement: Configuration Source Attribution and Reporting
All scripts SHALL clearly report their configuration source and provide transparency about which configuration is being used for operations.

#### Scenario: Script reports configuration source during execution
**Given** any k0rdent script is executed with configuration loading
**When** the script begins loading configuration
**Then** the script SHALL display which configuration source is being used
**And** SHALL show the configuration file path when using file-based sources
**And** SHALL show "deployment-state" when using state-based configuration
**And** SHALL include configuration metadata like last updated timestamp when available

#### Scenario: Configuration inconsistency detection and warning
**Given** there is potential for mismatch between expected and actual configuration
**When** configuration loading completes
**Then** the system SHALL validate key configuration elements against script expectations
**And** SHALL warn if critical configuration seems inconsistent
**And** SHALL provide guidance about potential configuration drift
**And** SHALL continue execution with clear warnings about inconsistencies

### Requirement: Multiple Deployment State Management
The system SHALL handle environments with multiple deployment states, providing clear rules for which deployment state to use for configuration resolution.

#### Scenario: Multiple deployment directories exist
**Given** multiple deployment-state.yaml files exist in different locations
**When** configuration resolution is attempted without explicit deployment context
**Then** the system SHALL select the most recently modified deployment state
**And** SHALL clearly report which deployment is being used for configuration
**And** SHALL provide option to specify deployment context explicitly if needed
**And** SHALL warn about potential ambiguity when multiple deployments exist

#### Scenario: Explicit deployment context specification
**Given** users need to operate on a specific deployment in a multi-deployment environment
**When** configuration resolution needs specific deployment context
**Then** the system SHALL support specifying deployment context via environment variables
**And** SHALL allow DEPLOYMENT_STATE_FILE to override the default state file location
**And** SHALL validate the specified state file exists and is usable
**And** SHALL provide clear error messages when specified context is invalid

### Requirement: Development Environment Support
The system SHALL provide development-friendly behavior while maintaining production-grade configuration resolution for deployment consistency.

#### Scenario: Development mode configuration behavior
**Given** developers are iterating on configurations in a development environment
**When** development mode is enabled via K0RDENT_DEVELOPMENT_MODE environment variable
**Then** the system SHALL prioritize default configuration files for easier iteration
**And** SHALL disable state-based configuration by default
**And** SHALL provide option to explicitly enable state-based configuration in development
**And** SHALL maintain normal production behavior when development mode is disabled

#### Scenario: Development deployment state override
**Given** developers need to test with specific deployment state in development
**When** K0RDENT_DEVELOPMENT_STATE environment variable is specified
**Then** the system SHALL use the specified state file regardless of development mode setting
**And** SHALL validate the specified state file is usable for development testing
**And** SHALL provide clear indication when using development state override
**And** SHALL maintain normal error handling and validation for the specified state

## ADDED Requirements

### Requirement: Backward Compatibility for Existing Deployments
The enhanced configuration system SHALL maintain full backward compatibility with existing deployments and workflows.

#### Scenario: Existing deployment without configuration tracking
**Given** a deployment was completed before configuration state tracking was implemented
**When** post-deployment scripts are executed on the existing deployment
**Then** the configuration system SHALL fall back to default configuration search
**And** SHALL work exactly as before the enhancement implementation
**And** SHALL provide helpful message about upgrading to state-based configuration
**And** SHALL not break any existing automation or manual workflows

#### Scenario: Mixed environment with tracked and untracked deployments
**Given** some deployments have configuration tracking while others do not
**When** scripts are executed across different deployment types
**Then** the system SHALL use state-based configuration for tracked deployments
**And** SHALL use default configuration for untracked deployments
**And** SHALL clearly indicate which approach is being used for transparency
**And** SHALL provide upgrade path suggestions for untracked deployments

## Technical Implementation Notes

### Configuration Resolution Order Implementation
```bash
# Priority order for configuration resolution
1. K0RDENT_CONFIG_FILE (explicit override)
2. deployment-state.yaml (canonical source)  
3. ./config/k0rdent.yaml (default file)
4. ./config/k0rdent-default.yaml (ultimate fallback)
```

### State Configuration Extraction
```bash
# Extract configuration from deployment state
load_config_from_deployment_state() {
    local config_section=$(yq eval '.config' "$DEPLOYMENT_STATE_FILE")
    echo "$config_section" | yaml_to_shell_vars
    export K0RDENT_CONFIG_SOURCE="deployment-state"
    export K0RDENT_CONFIG_FILE="$DEPLOYMENT_STATE_FILE"
}
```

### Enhanced Script Integration Points
All affected scripts will consistently use the enhanced configuration loader:
- setup-azure-cluster-deployment.sh
- create-azure-child.sh
- create-aws-cluster-deployment.sh
- setup-aws-cluster-deployment.sh
- install-kof-mothership.sh
- install-kof-regional.sh
- sync-cluster-state.sh
- list-child-clusters.sh
- azure-configuration-validation.sh

### Environment Variables for Configuration Control
```bash
# Override configuration source
export K0RDENT_CONFIG_FILE="./config/custom-azure.yaml"

# Specify deployment state location
export DEPLOYMENT_STATE_FILE="./state/specific-deployment-state.yaml"

# Development mode settings
export K0RDENT_DEVELOPMENT_MODE="true"
export K0RDENT_DEVELOPMENT_STATE="./test-state/deployment-state.yaml"
```

### Error Handling Strategy
```bash
# Graceful fallback when state is unavailable
if ! load_config_from_deployment_state; then
    echo "WARNING: Deployment state unavailable, using default configuration"
    load_default_configuration_search
fi

# Validation for extracted configuration
if ! validate_state_config_requirements; then
    echo "ERROR: Configuration from state file is incomplete"
    fallback_to_default_config
fi
```

### Security Considerations
- State file path validation to prevent directory traversal
- Permission checking for state file access
- Symlink detection to prevent potential security issues
- Ownership validation for deployment state files

### Performance Impact
- Additional ~50ms state file parsing cost (negligible)
- No performance impact for deployments without state tracking
- Caching opportunities for repeated configuration access
- Optimized YAML extraction using yq eval '.config'

### Backward Compatibility Guarantees
- All existing deployments continue working unchanged
- Configuration loading only enhanced when state is available
- Existing environment variable overrides preserved
- No breaking changes to any script interfaces

### Configuration Source Reporting
```bash
# Enhanced script output example
==> Loading YAML configuration: ./state/deployment-state.yaml
==> Using configuration from deployment state (deployment-state.yaml)
==> k0rdent configuration loaded (cluster ID: k0rdent-xyoeeex2, region: southeastasia)
==> Configuration source: deployment-state (last updated: 2025-11-07T14:23:07Z)
```

This enhancement ensures complete configuration consistency across the k0rdent ecosystem while maintaining robust fallback behavior for all deployment scenarios.
