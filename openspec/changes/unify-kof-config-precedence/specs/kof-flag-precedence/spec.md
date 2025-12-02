# Spec: KOF Flag Precedence

## Status
**Draft** - Pending approval

## ADDED Requirements

### Requirement: Configuration resolution with precedence
The system SHALL resolve KOF enablement using standard CLI precedence: flag overrides config, config overrides default. Both flag and config mechanisms SHALL work independently and together.

#### Scenario: Flag enables KOF when config has it disabled
- **GIVEN** configuration file has `kof.enabled: false`
- **WHEN** user runs `./deploy-k0rdent.sh deploy --with-kof`
- **THEN** KOF installation SHALL proceed as if `kof.enabled: true`
- **AND** deployment state SHALL record `kof.enabled: true` in resolved configuration
- **AND** downstream scripts SHALL read KOF as enabled from deployment state

#### Scenario: Flag enables KOF when config has no KOF section
- **GIVEN** configuration file has no `kof` section
- **WHEN** user runs `./deploy-k0rdent.sh deploy --with-kof`
- **THEN** deployment SHALL fail with clear error message
- **AND** error message SHALL indicate required KOF configuration fields
- **AND** no Azure resources SHALL be created

#### Scenario: Configuration enables KOF without flag
- **GIVEN** configuration file has `kof.enabled: true`
- **WHEN** user runs `./deploy-k0rdent.sh deploy` (no `--with-kof`)
- **THEN** deployment script SHALL detect KOF enabled from configuration
- **AND** KOF installation phases SHALL be executed
- **AND** deployment state SHALL record `config.kof.enabled: true`
- **AND** deployment state SHALL record `deployment_flags.kof: true` (resolved from config)
- **NOTE**: This fixes current broken behavior where YAML setting is ignored

#### Scenario: No flag and no config enables KOF
- **GIVEN** configuration file has `kof.enabled: false` or unset
- **WHEN** user runs `./deploy-k0rdent.sh deploy` (no `--with-kof`)
- **THEN** KOF installation SHALL be skipped
- **AND** behavior SHALL remain unchanged from current implementation

### Requirement: Override notification to user
When CLI flag overrides configuration file, the system SHALL notify the user of the precedence being applied.

#### Scenario: User informed of override during deployment summary
- **GIVEN** configuration file has `kof.enabled: false`
- **WHEN** user runs `./deploy-k0rdent.sh deploy --with-kof`
- **AND** deployment summary is displayed before proceeding
- **THEN** summary SHALL indicate "KOF Installation: ENABLED (via --with-kof flag)"
- **AND** summary MAY suggest updating configuration file for future deployments

### Requirement: Deployment state records resolved configuration
The deployment state SHALL store the resolved configuration with CLI overrides applied, not the original file configuration.

#### Scenario: State captures CLI override
- **GIVEN** configuration file has `kof.enabled: false`
- **WHEN** user deploys with `--with-kof` flag
- **THEN** `state/deployment-state.yaml` SHALL contain `config.kof.enabled: true`
- **AND** `deployment_flags.kof: true` SHALL be recorded
- **AND** downstream scripts reading state SHALL see KOF as enabled

#### Scenario: State captures configuration-based enablement
- **GIVEN** configuration file has `kof.enabled: true`
- **WHEN** user deploys without `--with-kof` flag
- **THEN** `state/deployment-state.yaml` SHALL contain `config.kof.enabled: true`
- **AND** `deployment_flags.kof: true` SHALL be recorded

### Requirement: Downstream scripts use deployment state
KOF installation scripts SHALL read configuration from deployment state rather than directly from configuration files.

#### Scenario: KOF scripts check deployment state
- **GIVEN** deployment is in progress with KOF enabled via flag
- **WHEN** `install-kof-mothership.sh` executes
- **THEN** it SHALL read KOF enablement from deployment state
- **AND** it SHALL NOT re-check the original configuration file
- **AND** it SHALL proceed with installation

## Related Specs
- **early-config-validation**: Validates KOF configuration before deployment
- **configuration-consistency**: Ensures consistent configuration resolution
