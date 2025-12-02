# Spec: Early Configuration Validation

## Status
**Draft** - Pending approval

## ADDED Requirements

### Requirement: Validate KOF configuration before deployment
When KOF is enabled (via flag or configuration), the system SHALL validate KOF configuration completeness before creating any Azure resources.

#### Scenario: Valid KOF configuration passes validation
- **GIVEN** user provides `--with-kof` flag
- **AND** configuration contains all required KOF fields
- **WHEN** deployment begins
- **THEN** validation SHALL pass silently
- **AND** deployment SHALL proceed to Azure resource creation

#### Scenario: Missing KOF section fails validation
- **GIVEN** user provides `--with-kof` flag
- **AND** configuration has no `kof` section
- **WHEN** deployment begins
- **THEN** validation SHALL fail immediately
- **AND** error message SHALL state "KOF configuration section missing"
- **AND** error SHALL suggest adding KOF configuration to YAML file
- **AND** no Azure resources SHALL be created
- **AND** exit code SHALL be non-zero

#### Scenario: Missing required KOF fields fails validation
- **GIVEN** KOF is enabled (flag or config)
- **AND** configuration is missing required fields (version, istio.version, etc.)
- **WHEN** deployment begins
- **THEN** validation SHALL fail immediately
- **AND** error message SHALL list all missing required fields
- **AND** error message SHALL provide example configuration
- **AND** no Azure resources SHALL be created

#### Scenario: Invalid KOF regional configuration fails validation
- **GIVEN** KOF is enabled
- **AND** `kof.regional.domain` is empty or invalid
- **WHEN** deployment begins
- **THEN** validation SHALL fail with specific error
- **AND** error SHALL explain domain requirement for KOF regional clusters
- **AND** error SHALL provide valid domain example

### Requirement: Validation runs immediately after argument parsing
Configuration validation SHALL occur before any state initialization or Azure API calls.

#### Scenario: Validation timing in deployment flow
- **GIVEN** user runs `./deploy-k0rdent.sh deploy --with-kof`
- **WHEN** script parses arguments
- **THEN** validation SHALL occur immediately after argument parsing completes
- **AND** validation SHALL occur before loading/initializing state files
- **AND** validation SHALL occur before any Azure CLI commands
- **AND** validation SHALL occur before WireGuard key generation

### Requirement: Clear validation error messages
Validation errors SHALL provide actionable guidance to fix configuration issues.

#### Scenario: Error message includes fix instructions
- **GIVEN** KOF configuration is invalid
- **WHEN** validation fails
- **THEN** error message SHALL include specific fix instructions
- **AND** error message SHALL include example of correct configuration
- **AND** error message SHALL indicate which configuration file to edit
- **AND** error message format SHALL be:
  ```
  ✗ KOF configuration validation failed

  Missing required fields:
    - kof.version
    - kof.regional.domain

  Add the following to config/k0rdent.yaml:

  kof:
    enabled: true
    version: "1.1.0"
    regional:
      domain: "regional.example.com"
      admin_email: "admin@example.com"
  ```

### Requirement: Validation checks required KOF fields
The validator SHALL check all fields required for KOF installation.

#### Scenario: Required fields list
- **WHEN** validating KOF configuration
- **THEN** the following fields SHALL be checked for presence and non-empty values:
  - `kof.version`
  - `kof.istio.version`
  - `kof.istio.namespace`
  - `kof.mothership.namespace`
  - `kof.regional.domain` (if regional clusters will be deployed)
  - `kof.regional.admin_email` (if regional clusters will be deployed)

#### Scenario: Optional fields not required
- **GIVEN** KOF is enabled for mothership only (no regional clusters)
- **WHEN** validating configuration
- **THEN** `kof.regional.*` fields SHALL NOT be required
- **AND** validation SHALL pass with only mothership configuration

### Requirement: Validation can be bypassed for advanced users
Advanced users SHALL be able to skip validation with explicit flag (not recommended).

#### Scenario: Skip validation flag
- **GIVEN** user runs with `--with-kof --skip-kof-validation`
- **WHEN** deployment begins
- **THEN** KOF configuration validation SHALL be skipped
- **AND** warning message SHALL indicate validation was skipped
- **AND** warning SHALL state "Proceeding without KOF validation may cause late-stage failures"

## Related Specs
- **kof-flag-precedence**: Defines when validation is triggered
- **configuration-consistency**: Ensures validated config is consistently used
