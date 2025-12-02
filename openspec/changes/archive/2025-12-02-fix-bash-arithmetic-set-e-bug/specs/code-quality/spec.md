## ADDED Requirements

### Requirement: Safe Bash Arithmetic with set -e
All bash scripts using `set -e` (errexit) SHALL use pre-increment `((++var))` instead of post-increment `((var++))` when the variable may be 0. Post-increment returns the old value, which evaluates to exit code 1 when 0, causing silent script termination.

#### Scenario: Loop counter starting at zero
- **WHEN** a loop uses an index starting at 0
- **AND** the script uses `set -e` or `set -euo pipefail`
- **THEN** the counter MUST use `((++index))` (pre-increment)
- **AND** NOT `((index++))` (post-increment)

#### Scenario: Retry counter starting at zero
- **WHEN** a retry loop uses a counter starting at 0
- **AND** the counter is incremented after a failed attempt
- **THEN** the counter MUST use `((++retry_count))` (pre-increment)
- **AND** the script continues to the next retry iteration

#### Scenario: Alternative safe patterns
- **WHEN** arithmetic increment is needed with `set -e`
- **THEN** any of these safe patterns MAY be used:
  - `((++var))` - pre-increment (preferred)
  - `var=$((var + 1))` - assignment (always safe)
  - `((var++)) || true` - suppress error (less readable)
