# Optional Component Management

## ADDED Requirements

### Requirement: Component Enablement Configuration

The deployment system SHALL support optional components that can be enabled or disabled via configuration.

#### Scenario: Component enabled in configuration
- **GIVEN** a configuration file with `kof.enabled: true`
- **WHEN** `check_kof_enabled()` is called
- **THEN** the function SHALL return true (exit code 0)

#### Scenario: Component disabled in configuration
- **GIVEN** a configuration file with `kof.enabled: false`
- **WHEN** `check_kof_enabled()` is called
- **THEN** the function SHALL return false (exit code 1)

#### Scenario: Component not configured (default)
- **GIVEN** a configuration file without `kof.enabled` key
- **WHEN** `check_kof_enabled()` is called
- **THEN** the function SHALL return false (default disabled)

### Requirement: Optional Component Phase Integration

The deployment orchestrator SHALL integrate optional component enablement checks with phase execution logic.

#### Scenario: Optional component phases skipped when disabled
- **GIVEN** KOF is disabled in configuration (`kof.enabled: false`)
- **WHEN** deployment runs
- **THEN** all KOF-related phases SHALL be marked as "skipped"
- **AND** KOF installation scripts SHALL NOT be executed
- **AND** no warning messages about KOF phases SHALL be emitted

#### Scenario: Optional component phases run when enabled
- **GIVEN** KOF is enabled in configuration (`kof.enabled: true`)
- **WHEN** deployment runs
- **THEN** all KOF-related phases SHALL execute normally
- **AND** phase status SHALL transition: pending → in_progress → completed

#### Scenario: Multiple optional components with independent enablement
- **GIVEN** multiple optional components exist (e.g., KOF mothership, KOF regional)
- **WHEN** only some components are enabled
- **THEN** each component's phases SHALL be independently evaluated
- **AND** disabled component phases SHALL be skipped
- **AND** enabled component phases SHALL execute

### Requirement: Enablement Checker Function Contract

Component enablement checker functions SHALL follow a standard contract for integration with phase management.

#### Scenario: Enablement checker returns boolean
- **GIVEN** an enablement checker function like `check_kof_enabled()`
- **WHEN** the checker is invoked
- **THEN** it SHALL return exit code 0 (true) if enabled
- **AND** it SHALL return exit code 1 (false) if disabled
- **AND** it SHALL NOT produce error output on false

#### Scenario: Enablement checker uses configuration
- **GIVEN** an enablement checker function
- **WHEN** the checker determines enablement status
- **THEN** it SHALL read from the active configuration file (`$CONFIG_YAML`)
- **AND** it SHALL use `yq` to query configuration values
- **AND** it SHALL handle missing configuration keys gracefully (default false)

### Requirement: Clear Messaging for Disabled Components

The deployment system SHALL provide clear, actionable messages when optional components are disabled.

#### Scenario: Deployment with disabled component
- **GIVEN** KOF is disabled in configuration
- **WHEN** deployment reaches KOF installation phase
- **THEN** a message SHALL be displayed: "Step X skipped - KOF not enabled in configuration."
- **AND** no error or warning SHALL be emitted
- **AND** deployment SHALL continue to next phase

#### Scenario: Status check for disabled component
- **GIVEN** KOF is disabled in configuration
- **WHEN** `./bin/install-kof-mothership.sh status` is executed
- **THEN** the output SHALL indicate: "KOF is not enabled in configuration"
- **AND** it SHALL suggest how to enable: "Set 'kof.enabled: true' in your k0rdent.yaml"

### Requirement: Reusable Optional Component Pattern

The optional component implementation SHALL provide a reusable pattern for future optional features.

#### Scenario: New optional component follows pattern
- **GIVEN** a new optional component needs to be added (e.g., monitoring stack)
- **WHEN** implementing the component
- **THEN** the developer SHALL create a `check_<component>_enabled()` function
- **AND** the developer SHALL pass the enablement checker to `should_run_phase()`
- **AND** the component phases SHALL be skipped when disabled
- **AND** the component phases SHALL execute when enabled
