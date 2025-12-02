# code-quality Specification

## Purpose
TBD - created by archiving change refactor-codebase-cleanup. Update Purpose after archive.
## Requirements
### Requirement: No Duplicate Function Definitions
All shell function libraries SHALL have unique function definitions. Each function name MUST appear exactly once across the entire file.

#### Scenario: Function name uniqueness validation
- **WHEN** a shell library file is loaded
- **THEN** no function name appears more than once in the file
- **AND** the last definition would silently override earlier definitions

### Requirement: Utility Function Error Handling
Utility functions in shared libraries SHALL use `return 1` for error conditions instead of `exit 1`. This allows calling scripts to handle errors appropriately.

#### Scenario: Error handling in prerequisite check
- **WHEN** a prerequisite check function (e.g., check_azure_cli) detects a missing dependency
- **THEN** the function returns 1
- **AND** the calling script decides whether to exit or continue

#### Scenario: Caller handles utility function error
- **WHEN** a script calls a utility function that returns 1
- **THEN** the script can check the return code
- **AND** take appropriate action (exit, retry, or continue with alternatives)

### Requirement: No Unused Functions in Libraries
Function libraries SHALL NOT contain functions that are never called by any script. Unused functions MUST be removed to reduce maintenance burden and cognitive load.

#### Scenario: Function usage audit
- **WHEN** a codebase audit is performed
- **THEN** each function in etc/*.sh can be traced to at least one caller
- **AND** functions with zero callers are candidates for removal

### Requirement: No Deprecated Functions
Function libraries SHALL NOT contain deprecated functions. Deprecated code MUST be removed after migration period.

#### Scenario: Deprecated function removal
- **WHEN** a function is marked deprecated
- **THEN** callers are migrated to replacement function
- **AND** deprecated function is removed from the codebase

### Requirement: Common Pattern Extraction
Code patterns that appear in 3 or more locations SHALL be extracted into shared helper functions to reduce duplication and ensure consistency.

#### Scenario: SSH key lookup consolidation
- **WHEN** multiple scripts need to find the SSH key path
- **THEN** they call the shared find_ssh_key() helper
- **AND** the lookup logic is defined in exactly one place

#### Scenario: Batch kubectl delete consolidation
- **WHEN** multiple resources need to be deleted with kubectl
- **THEN** scripts call kubectl_delete_resources() with a list of resources
- **AND** the --ignore-not-found flag is applied consistently

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

