# Phase Management

## ADDED Requirements

### Requirement: Phase State Lifecycle

The deployment system SHALL maintain explicit phase states throughout the deployment lifecycle: `pending`, `in_progress`, `completed`, and `skipped`.

#### Scenario: Phase marked as skipped
- **GIVEN** a deployment phase exists
- **WHEN** the component associated with the phase is disabled
- **THEN** the phase SHALL be marked with status "skipped"
- **AND** the phase SHALL NOT execute
- **AND** the phase SHALL NOT run validation

#### Scenario: Phase transitions from completed to skipped
- **GIVEN** a phase was previously marked "completed"
- **WHEN** the deployment is resumed with the component disabled
- **THEN** the phase SHALL transition to "skipped" state
- **AND** a skipped_reason SHALL be recorded
- **AND** the phase SHALL NOT execute again

#### Scenario: Phase transitions from skipped to pending
- **GIVEN** a phase was previously marked "skipped"
- **WHEN** the deployment is resumed with the component enabled
- **THEN** the phase SHALL transition to "pending" state
- **AND** the phase SHALL execute on the next deployment run

### Requirement: Phase Enablement Checking

The deployment system SHALL support optional enablement checking for phases to determine if a phase should run based on component configuration.

#### Scenario: Phase with enablement checker disabled
- **GIVEN** a phase has an associated enablement checker function
- **WHEN** the enablement checker returns false
- **THEN** the phase SHALL be marked as "skipped"
- **AND** the phase SHALL NOT execute

#### Scenario: Phase with enablement checker enabled
- **GIVEN** a phase has an associated enablement checker function
- **WHEN** the enablement checker returns true
- **THEN** the phase SHALL follow normal lifecycle (pending → in_progress → completed)

#### Scenario: Phase without enablement checker
- **GIVEN** a phase has no associated enablement checker
- **THEN** the phase SHALL always be eligible to run (not skipped)

### Requirement: Phase Validation Skipping

The deployment system SHALL NOT run validation logic for phases that are skipped due to disabled components.

#### Scenario: Completed phase for disabled component
- **GIVEN** a phase is marked "completed"
- **AND** the associated component is disabled
- **WHEN** deployment validation runs
- **THEN** the phase validation SHALL be skipped
- **AND** no warning messages SHALL be emitted

#### Scenario: Completed phase with empty validator and disabled component
- **GIVEN** a phase is marked "completed"
- **AND** the phase has an empty validator function ("")
- **AND** the associated component is disabled
- **WHEN** deployment validation runs
- **THEN** the phase SHALL be marked as "skipped"
- **AND** no "validation failed" warnings SHALL be emitted

### Requirement: Skipped Phase Observability

The deployment system SHALL provide clear visibility into which phases were skipped and why.

#### Scenario: Query skipped phase status
- **GIVEN** a phase is marked as "skipped"
- **WHEN** `phase_status()` is called
- **THEN** the status SHALL return "skipped"

#### Scenario: Skip reason recorded
- **GIVEN** a phase is being marked as skipped
- **WHEN** `phase_mark_skipped()` is called with a reason
- **THEN** the reason SHALL be stored in the state file
- **AND** the reason SHALL be retrievable via `get_state()`

#### Scenario: Deployment summary shows skipped phases
- **GIVEN** phases were skipped during deployment
- **WHEN** deployment summary is displayed
- **THEN** skipped phases SHALL be listed separately from completed phases
- **AND** each skipped phase SHALL show its skip reason

### Requirement: Accurate Phase Completion Notifications

The deployment system SHALL send desktop notifications with accurate phase names when phases complete.

#### Scenario: Phase completion event includes phase name
- **GIVEN** a phase is completing
- **WHEN** `phase_mark_completed()` is called
- **THEN** the generated event SHALL include the phase name in the event data
- **AND** the phase name SHALL match the phase that actually completed

#### Scenario: Notification shows correct component name
- **GIVEN** the "install_k0s" phase completes
- **WHEN** desktop notification is sent
- **THEN** the notification SHALL display "k0s installation completed successfully"
- **AND** the notification SHALL NOT display "k0rdent installation completed successfully"

#### Scenario: Notification shows correct component name for k0rdent
- **GIVEN** the "install_k0rdent" phase completes
- **WHEN** desktop notification is sent
- **THEN** the notification SHALL display "k0rdent installation completed successfully"
- **AND** the notification SHALL NOT display "k0s installation completed successfully"

#### Scenario: Phase name extracted from event data not state file
- **GIVEN** a phase_completed event exists
- **WHEN** the notifier processes the event
- **THEN** the phase name SHALL be extracted from the event's `.phase` field
- **AND** the phase name SHALL NOT be extracted from the state file's current `.phase` field

#### Scenario: Human-readable phase names in notifications
- **GIVEN** a phase with technical name completes (e.g., "install_k0s")
- **WHEN** desktop notification is sent
- **THEN** the notification SHALL use a human-readable display name (e.g., "k0s installation")
- **AND** the display name SHALL be consistent across all notifications for that phase

#### Scenario: Backward compatibility with events without phase field
- **GIVEN** an old event without a `.phase` field
- **WHEN** the notifier processes the event
- **THEN** the phase SHALL default to "unknown"
- **AND** the notification SHALL still be sent with "unknown completed successfully"
- **AND** no errors SHALL be raised
