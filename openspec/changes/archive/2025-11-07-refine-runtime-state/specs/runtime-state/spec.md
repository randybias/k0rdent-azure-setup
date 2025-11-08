## ADDED Requirements

### Requirement: Run-Scoped State Files
Deployment state MUST be recorded per-run in `state/runs/<run-id>.yaml`, with `state/runtime.yaml` tracking only the latest snapshot and pointers to Terraform outputs.

#### Scenario: Start new deployment
- **WHEN** a new deployment run is started
- **THEN** a unique run file is created with metadata (timestamp, flags, phase status) and `state/runtime.yaml` references that run without copying completed phases from prior runs.

### Requirement: Optional Phase Reconciliation
The orchestrator MUST clear optional phase status from prior runs when the corresponding feature is disabled for the current run.

#### Scenario: Run without KOF after previous KOF-enabled run
- **GIVEN** the previous run enabled KOF and completed `install_kof_regional`
- **WHEN** the next run starts with `--with-kof` disabled
- **THEN** the new run does not log or emit warnings about KOF phases, and state tracking proceeds without stale entries.

### Requirement: Run History Inspection
Operators MUST be able to list recent runs and their outcomes via CLI.

#### Scenario: List runs
- **WHEN** `deploy-k0rdent.sh runs` (or an equivalent command) is executed
- **THEN** it reads `state/runs/` and prints recent run IDs with timestamps, flags, and success/failure outcome.
