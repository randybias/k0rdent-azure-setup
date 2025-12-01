#!/usr/bin/env bash

# config-resolution-functions.sh
# Configuration resolution functions for k0rdent
# Provides canonical configuration loading from deployment state
#
# Part of the canonical-config-from-state OpenSpec change
# Tasks 005-006: Security validation and multi-deployment state management
# Task 010: Development environment support
#
# =============================================================================
# DEVELOPMENT MODE USAGE GUIDE (Task 010)
# =============================================================================
#
# Development mode provides two features for easier testing and iteration:
#
# 1. K0RDENT_DEVELOPMENT_MODE - Prefer default configuration over deployment state
#    Use this when you want to quickly test changes without modifying state files.
#
#    Example:
#      export K0RDENT_DEVELOPMENT_MODE=true
#      ./bin/setup-azure-cluster-deployment.sh setup
#
#    Result: Uses default config (./config/k0rdent.yaml) instead of deployment state
#
# 2. K0RDENT_DEVELOPMENT_STATE - Test against specific state file
#    Use this when you want to test scripts against different deployment scenarios.
#
#    Example:
#      export K0RDENT_DEVELOPMENT_STATE=./state/test-deployment-state.yaml
#      ./bin/create-azure-child.sh
#
#    Result: Uses specified state file instead of default deployment state search
#
# Development Mode Benefits:
#   - Quick iteration: No need to modify actual deployment state
#   - Safe testing: Production state remains untouched
#   - Scenario testing: Easily test different deployment configurations
#   - Clear indication: Scripts show when development mode is active
#
# Development Mode Safety:
#   - Scripts show WARNING when development features are active
#   - Configuration source clearly indicates development mode
#   - Easy to switch back to production mode (unset variables)
#
# Switching Between Modes:
#   Development -> Production: unset K0RDENT_DEVELOPMENT_MODE K0RDENT_DEVELOPMENT_STATE
#   Production -> Development: export K0RDENT_DEVELOPMENT_MODE=true
#
# Priority Order (highest to lowest):
#   1. K0RDENT_CONFIG_FILE (explicit override - works in any mode)
#   2. K0RDENT_DEVELOPMENT_STATE (development state override)
#   3. K0RDENT_DEVELOPMENT_MODE=true (prefer default config)
#   4. Deployment state (production behavior)
#   5. Default configuration search (fallback)

# =============================================================================
# SECURITY VALIDATION FUNCTIONS (Task 005)
# =============================================================================

# validate_state_file_path - Prevent directory traversal and symlink attacks
#
# Purpose: Ensure state file paths are safe and within expected project boundaries
#
# Security checks:
# 1. Prevent directory traversal attacks (../ sequences)
# 2. Ensure path is within project root directory
# 3. Detect and reject symbolic links (security risk)
# 4. Validate path format and structure
#
# Arguments:
#   $1 - state_file_path: Path to state file to validate
#
# Returns:
#   0 - Path is valid and safe
#   1 - Path validation failed (security issue detected)
#
# Example:
#   if validate_state_file_path "./state/deployment-state.yaml"; then
#       echo "Path is safe to use"
#   fi
validate_state_file_path() {
    local state_file="$1"

    if [[ -z "$state_file" ]]; then
        if command -v print_error &>/dev/null; then
            print_error "State file path is empty (security validation)"
        else
            echo "ERROR: State file path is empty (security validation)" >&2
        fi
        return 1
    fi

    # Get absolute path of the project root (where the script is running)
    # Use pwd instead of relying on any potentially manipulated environment variables
    local project_root
    project_root="$(cd "$(pwd)" && pwd)" || {
        if command -v print_error &>/dev/null; then
            print_error "Cannot determine project root directory"
        else
            echo "ERROR: Cannot determine project root directory" >&2
        fi
        return 1
    }

    # Resolve the state file to its absolute path
    # This handles relative paths, symlinks, and normalizes the path
    local resolved_state_file
    if [[ -e "$state_file" ]]; then
        # File exists - resolve to absolute path
        # Use different commands for Linux vs macOS compatibility
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS doesn't have realpath by default
            resolved_state_file="$(cd "$(dirname "$state_file")" 2>/dev/null && pwd)/$(basename "$state_file")" || {
                if command -v print_error &>/dev/null; then
                    print_error "Cannot resolve state file path (security validation)"
                else
                    echo "ERROR: Cannot resolve state file path (security validation)" >&2
                fi
                return 1
            }
        else
            # Linux has realpath
            resolved_state_file="$(realpath "$state_file" 2>/dev/null)" || {
                if command -v print_error &>/dev/null; then
                    print_error "Cannot resolve state file path (security validation)"
                else
                    echo "ERROR: Cannot resolve state file path (security validation)" >&2
                fi
                return 1
            }
        fi
    else
        # File doesn't exist yet - resolve parent directory
        local parent_dir
        parent_dir="$(dirname "$state_file")"
        local filename
        filename="$(basename "$state_file")"

        if [[ -d "$parent_dir" ]]; then
            if [[ "$(uname)" == "Darwin" ]]; then
                resolved_state_file="$(cd "$parent_dir" 2>/dev/null && pwd)/$filename" || {
                    if command -v print_error &>/dev/null; then
                        print_error "Cannot resolve parent directory (security validation)"
                    else
                        echo "ERROR: Cannot resolve parent directory (security validation)" >&2
                    fi
                    return 1
                }
            else
                local resolved_parent
                resolved_parent="$(realpath "$parent_dir" 2>/dev/null)" || {
                    if command -v print_error &>/dev/null; then
                        print_error "Cannot resolve parent directory (security validation)"
                    else
                        echo "ERROR: Cannot resolve parent directory (security validation)" >&2
                    fi
                    return 1
                }
                resolved_state_file="$resolved_parent/$filename"
            fi
        else
            if command -v print_error &>/dev/null; then
                print_error "Parent directory does not exist: $parent_dir (security validation)"
            else
                echo "ERROR: Parent directory does not exist: $parent_dir (security validation)" >&2
            fi
            return 1
        fi
    fi

    # Check if resolved path is within project root
    # This prevents directory traversal attacks like ../../etc/passwd
    if [[ "$resolved_state_file" != "$project_root"* ]]; then
        if command -v print_error &>/dev/null; then
            print_error "State file is outside project directory (security violation)"
            print_error "  Project root: $project_root"
            print_error "  State file:   $resolved_state_file"
        else
            echo "ERROR: State file is outside project directory (security violation)" >&2
            echo "ERROR:   Project root: $project_root" >&2
            echo "ERROR:   State file:   $resolved_state_file" >&2
        fi
        return 1
    fi

    # Check for symbolic links (only if file exists)
    # Symlinks can be used to redirect to sensitive files
    if [[ -e "$state_file" ]] && [[ -L "$state_file" ]]; then
        if command -v print_error &>/dev/null; then
            print_error "State file is a symbolic link (potential security risk)"
            print_error "  State file: $state_file"
            print_error "  Links to:   $(readlink "$state_file")"
        else
            echo "ERROR: State file is a symbolic link (potential security risk)" >&2
            echo "ERROR:   State file: $state_file" >&2
            echo "ERROR:   Links to:   $(readlink "$state_file")" >&2
        fi
        return 1
    fi

    # Validate filename format for state files
    # Expected patterns: deployment-state.yaml, kof-state.yaml, azure-state.yaml
    local filename
    filename="$(basename "$state_file")"
    if [[ ! "$filename" =~ ^[a-z0-9_-]+-state\.yaml$ ]]; then
        if command -v print_warning &>/dev/null; then
            print_warning "State file name doesn't match expected pattern: $filename"
            print_warning "Expected pattern: <name>-state.yaml"
        fi
        # Don't fail - just warn, as this might be intentional
    fi

    return 0
}

# validate_state_file_permissions - Check file permissions and ownership
#
# Purpose: Ensure state file has appropriate permissions and ownership
#
# Security checks:
# 1. File must be readable by current user
# 2. Check file ownership (warn if owned by different user)
# 3. Validate permissions aren't world-writable
# 4. Ensure parent directory is accessible
#
# Arguments:
#   $1 - state_file_path: Path to state file to validate
#
# Returns:
#   0 - Permissions are valid and safe
#   1 - Permission validation failed (access issue)
#
# Example:
#   if validate_state_file_permissions "./state/deployment-state.yaml"; then
#       echo "File permissions are safe"
#   fi
validate_state_file_permissions() {
    local state_file="$1"

    if [[ -z "$state_file" ]]; then
        if command -v print_error &>/dev/null; then
            print_error "State file path is empty (permission validation)"
        else
            echo "ERROR: State file path is empty (permission validation)" >&2
        fi
        return 1
    fi

    # Check if file exists
    if [[ ! -e "$state_file" ]]; then
        # File doesn't exist yet - check parent directory permissions
        local parent_dir
        parent_dir="$(dirname "$state_file")"

        if [[ ! -d "$parent_dir" ]]; then
            if command -v print_error &>/dev/null; then
                print_error "Parent directory does not exist: $parent_dir"
            else
                echo "ERROR: Parent directory does not exist: $parent_dir" >&2
            fi
            return 1
        fi

        if [[ ! -w "$parent_dir" ]]; then
            if command -v print_error &>/dev/null; then
                print_error "Cannot write to parent directory (permissions): $parent_dir"
            else
                echo "ERROR: Cannot write to parent directory (permissions): $parent_dir" >&2
            fi
            return 1
        fi

        # Parent directory is writable - we can create the file
        return 0
    fi

    # Check if file is readable
    if [[ ! -r "$state_file" ]]; then
        if command -v print_error &>/dev/null; then
            print_error "Cannot read state file (permissions): $state_file"
            print_error "Current user: $(whoami)"
            print_error "File permissions: $(ls -l "$state_file" 2>/dev/null | awk '{print $1}')"
        else
            echo "ERROR: Cannot read state file (permissions): $state_file" >&2
            echo "ERROR: Current user: $(whoami)" >&2
            echo "ERROR: File permissions: $(ls -l "$state_file" 2>/dev/null | awk '{print $1}')" >&2
        fi
        return 1
    fi

    # Get file ownership
    local file_owner
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS uses -f format
        file_owner=$(stat -f "%Su" "$state_file" 2>/dev/null)
    else
        # Linux uses -c format
        file_owner=$(stat -c "%U" "$state_file" 2>/dev/null)
    fi

    # Check if file is owned by current user
    local current_user
    current_user=$(whoami)
    if [[ "$file_owner" != "$current_user" ]]; then
        if command -v print_warning &>/dev/null; then
            print_warning "State file owned by different user: $file_owner (current: $current_user)"
            print_warning "This may indicate a security concern or shared deployment"
            print_warning "File: $state_file"
        fi
        # Don't fail - just warn, as this might be intentional in team environments
    fi

    # Check for world-writable permissions (security risk)
    local perms
    if [[ "$(uname)" == "Darwin" ]]; then
        perms=$(stat -f "%Lp" "$state_file" 2>/dev/null)
    else
        perms=$(stat -c "%a" "$state_file" 2>/dev/null)
    fi

    # Check if others have write permission (last digit is 2, 3, 6, or 7)
    if [[ "$perms" =~ [2367]$ ]]; then
        if command -v print_error &>/dev/null; then
            print_error "State file is world-writable (security violation)"
            print_error "File: $state_file"
            print_error "Permissions: $perms"
            print_error "Run: chmod o-w '$state_file'"
        else
            echo "ERROR: State file is world-writable (security violation)" >&2
            echo "ERROR: File: $state_file" >&2
            echo "ERROR: Permissions: $perms" >&2
            echo "ERROR: Run: chmod o-w '$state_file'" >&2
        fi
        return 1
    fi

    # Validate parent directory permissions
    local parent_dir
    parent_dir="$(dirname "$state_file")"
    if [[ ! -r "$parent_dir" ]]; then
        if command -v print_error &>/dev/null; then
            print_error "Cannot read parent directory (permissions): $parent_dir"
        else
            echo "ERROR: Cannot read parent directory (permissions): $parent_dir" >&2
        fi
        return 1
    fi

    return 0
}

# =============================================================================
# MULTI-DEPLOYMENT STATE MANAGEMENT FUNCTIONS (Task 006)
# =============================================================================

# find_latest_deployment_state - Identify most recent deployment state file
#
# Purpose: Locate the most recently modified deployment state file in the project
#
# Search strategy:
# 1. Look for deployment-state.yaml in ./state/ directory (primary location)
# 2. If multiple found (e.g., in subdirectories), select most recent by modification time
# 3. Validate found state file using security checks
# 4. Return absolute path to selected state file
#
# Arguments:
#   None (searches in standard ./state directory)
#
# Returns:
#   0 - Found valid state file (path written to stdout)
#   1 - No valid state file found
#
# Output:
#   Absolute path to latest deployment-state.yaml file
#
# Example:
#   latest_state=$(find_latest_deployment_state)
#   if [[ -n "$latest_state" ]]; then
#       echo "Using: $latest_state"
#   fi
find_latest_deployment_state() {
    local state_dir="./state"
    local state_filename="deployment-state.yaml"

    # Check if state directory exists
    if [[ ! -d "$state_dir" ]]; then
        return 1
    fi

    # Find all deployment-state.yaml files (including in subdirectories)
    local state_files=()
    while IFS= read -r -d '' file; do
        # Validate each found file using security checks
        if validate_state_file_path "$file" &>/dev/null && validate_state_file_permissions "$file" &>/dev/null; then
            state_files+=("$file")
        fi
    done < <(find "$state_dir" -name "$state_filename" -type f -print0 2>/dev/null)

    # No valid state files found
    if [[ ${#state_files[@]} -eq 0 ]]; then
        return 1
    fi

    # Single state file - return it
    if [[ ${#state_files[@]} -eq 1 ]]; then
        # Return absolute path
        if [[ "$(uname)" == "Darwin" ]]; then
            echo "$(cd "$(dirname "${state_files[0]}")" && pwd)/$(basename "${state_files[0]}")"
        else
            realpath "${state_files[0]}"
        fi
        return 0
    fi

    # Multiple state files - find most recent by modification time
    local latest_file=""
    local latest_mtime=0

    for file in "${state_files[@]}"; do
        local mtime
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS: get modification time as seconds since epoch
            mtime=$(stat -f "%m" "$file" 2>/dev/null || echo "0")
        else
            # Linux: get modification time as seconds since epoch
            mtime=$(stat -c "%Y" "$file" 2>/dev/null || echo "0")
        fi

        if [[ $mtime -gt $latest_mtime ]]; then
            latest_mtime=$mtime
            latest_file="$file"
        fi
    done

    if [[ -n "$latest_file" ]]; then
        # Return absolute path
        if [[ "$(uname)" == "Darwin" ]]; then
            echo "$(cd "$(dirname "$latest_file")" && pwd)/$(basename "$latest_file")"
        else
            realpath "$latest_file"
        fi
        return 0
    fi

    return 1
}

# select_deployment_state - Select appropriate deployment state with explicit override support
#
# Purpose: Determine which deployment state file to use based on environment and context
#
# Selection priority:
# 1. Explicit environment variable: K0RDENT_DEPLOYMENT_STATE (highest priority)
# 2. Most recent deployment state in ./state/ directory (standard case)
# 3. No state file found (returns error)
#
# The function handles multi-deployment scenarios by allowing explicit specification
# or defaulting to the most recent deployment.
#
# Arguments:
#   None (uses environment variables and filesystem search)
#
# Environment Variables:
#   K0RDENT_DEPLOYMENT_STATE - Explicit path to deployment state file (optional)
#
# Returns:
#   0 - Successfully selected state file (path written to stdout)
#   1 - No valid state file could be selected
#
# Output:
#   Absolute path to selected deployment state file
#   Status messages to stderr about selection process
#
# Example:
#   selected_state=$(select_deployment_state)
#   if [[ $? -eq 0 ]]; then
#       echo "Using deployment state: $selected_state"
#   fi
select_deployment_state() {
    # Priority 1: Explicit deployment state override
    if [[ -n "${K0RDENT_DEPLOYMENT_STATE:-}" ]]; then
        if command -v print_info &>/dev/null; then
            print_info "Using explicitly specified deployment state: $K0RDENT_DEPLOYMENT_STATE" >&2
        else
            echo "INFO: Using explicitly specified deployment state: $K0RDENT_DEPLOYMENT_STATE" >&2
        fi

        # Validate the specified state file
        if [[ ! -f "$K0RDENT_DEPLOYMENT_STATE" ]]; then
            if command -v print_error &>/dev/null; then
                print_error "Specified deployment state file not found: $K0RDENT_DEPLOYMENT_STATE" >&2
            else
                echo "ERROR: Specified deployment state file not found: $K0RDENT_DEPLOYMENT_STATE" >&2
            fi
            return 1
        fi

        # Validate security and permissions
        if ! validate_state_file_path "$K0RDENT_DEPLOYMENT_STATE" || ! validate_state_file_permissions "$K0RDENT_DEPLOYMENT_STATE"; then
            if command -v print_error &>/dev/null; then
                print_error "Specified deployment state failed validation" >&2
            else
                echo "ERROR: Specified deployment state failed validation" >&2
            fi
            return 1
        fi

        # Validate it's actually a deployment state file (has required structure)
        if ! validate_deployment_state_structure "$K0RDENT_DEPLOYMENT_STATE"; then
            if command -v print_error &>/dev/null; then
                print_error "Specified file is not a valid deployment state file" >&2
            else
                echo "ERROR: Specified file is not a valid deployment state file" >&2
            fi
            return 1
        fi

        # Return absolute path
        if [[ "$(uname)" == "Darwin" ]]; then
            echo "$(cd "$(dirname "$K0RDENT_DEPLOYMENT_STATE")" && pwd)/$(basename "$K0RDENT_DEPLOYMENT_STATE")"
        else
            realpath "$K0RDENT_DEPLOYMENT_STATE"
        fi
        return 0
    fi

    # Priority 2: Find most recent deployment state
    local latest_state
    latest_state=$(find_latest_deployment_state)

    if [[ -n "$latest_state" ]]; then
        # Check if there are multiple deployments (inform user)
        local state_count
        state_count=$(find ./state -name "deployment-state.yaml" -type f 2>/dev/null | wc -l | tr -d ' ')

        if [[ $state_count -gt 1 ]]; then
            if command -v print_info &>/dev/null; then
                print_info "Multiple deployment states found ($state_count), using most recent" >&2
                print_info "To use a specific deployment, set K0RDENT_DEPLOYMENT_STATE=/path/to/state.yaml" >&2
            else
                echo "INFO: Multiple deployment states found ($state_count), using most recent" >&2
                echo "INFO: To use a specific deployment, set K0RDENT_DEPLOYMENT_STATE=/path/to/state.yaml" >&2
            fi
        fi

        echo "$latest_state"
        return 0
    fi

    # No state file found
    if command -v print_warning &>/dev/null; then
        print_warning "No deployment state file found in ./state directory" >&2
    fi
    return 1
}

# validate_deployment_state_structure - Validate state file has required structure
#
# Purpose: Ensure state file contains minimum required fields and valid YAML structure
#
# Validation checks:
# 1. File contains valid YAML syntax
# 2. Required top-level fields exist (deployment_id, config, etc.)
# 3. Config section has minimum required configuration elements
# 4. File hasn't been corrupted or truncated
#
# Arguments:
#   $1 - state_file_path: Path to deployment state file to validate
#
# Returns:
#   0 - State file structure is valid
#   1 - State file structure is invalid or corrupted
#
# Example:
#   if validate_deployment_state_structure "./state/deployment-state.yaml"; then
#       echo "State file structure is valid"
#   fi
validate_deployment_state_structure() {
    local state_file="$1"

    if [[ -z "$state_file" ]]; then
        if command -v print_error &>/dev/null; then
            print_error "State file path is empty (structure validation)"
        else
            echo "ERROR: State file path is empty (structure validation)" >&2
        fi
        return 1
    fi

    if [[ ! -f "$state_file" ]]; then
        if command -v print_error &>/dev/null; then
            print_error "State file does not exist: $state_file"
        else
            echo "ERROR: State file does not exist: $state_file" >&2
        fi
        return 1
    fi

    # Check if yq is available (required for YAML parsing)
    if ! command -v yq &> /dev/null; then
        if command -v print_error &>/dev/null; then
            print_error "yq is not installed (required for state validation)"
        else
            echo "ERROR: yq is not installed (required for state validation)" >&2
        fi
        return 1
    fi

    # Validate YAML syntax
    if ! yq eval '.' "$state_file" &>/dev/null; then
        if command -v print_error &>/dev/null; then
            print_error "State file contains invalid YAML syntax: $state_file"
        else
            echo "ERROR: State file contains invalid YAML syntax: $state_file" >&2
        fi
        return 1
    fi

    # Check for required top-level fields
    local required_fields=("deployment_id" "created_at" "config")
    for field in "${required_fields[@]}"; do
        local value
        value=$(yq eval ".$field" "$state_file" 2>/dev/null)
        if [[ "$value" == "null" ]] || [[ -z "$value" ]]; then
            if command -v print_error &>/dev/null; then
                print_error "State file missing required field: $field"
                print_error "File may be corrupted or incomplete: $state_file"
            else
                echo "ERROR: State file missing required field: $field" >&2
                echo "ERROR: File may be corrupted or incomplete: $state_file" >&2
            fi
            return 1
        fi
    done

    # Validate config section exists and has content
    local config_section
    config_section=$(yq eval '.config' "$state_file" 2>/dev/null)
    if [[ "$config_section" == "null" ]] || [[ "$config_section" == "{}" ]]; then
        if command -v print_error &>/dev/null; then
            print_error "State file has empty or missing config section"
            print_error "File: $state_file"
        else
            echo "ERROR: State file has empty or missing config section" >&2
            echo "ERROR: File: $state_file" >&2
        fi
        return 1
    fi

    # Check for minimum required config fields
    # Note: These are the most critical fields needed for configuration resolution
    local required_config_fields=("azure_location" "resource_group")
    for field in "${required_config_fields[@]}"; do
        local value
        value=$(yq eval ".config.$field" "$state_file" 2>/dev/null)
        if [[ "$value" == "null" ]] || [[ -z "$value" ]]; then
            if command -v print_warning &>/dev/null; then
                print_warning "State config missing recommended field: $field"
            fi
            # Don't fail - just warn, as not all deployments need all fields
        fi
    done

    return 0
}

# report_deployment_context - Display information about selected deployment state
#
# Purpose: Provide clear visibility into which deployment context is being used
#
# Displays:
# 1. Deployment ID and creation timestamp
# 2. Current deployment status and phase
# 3. Azure location and resource group
# 4. Configuration source information
# 5. Warnings about multi-deployment environments
#
# Arguments:
#   $1 - state_file_path: Path to deployment state file to report on
#
# Returns:
#   0 - Successfully reported deployment context
#   1 - Failed to read or parse state file
#
# Example:
#   report_deployment_context "./state/deployment-state.yaml"
report_deployment_context() {
    local state_file="$1"

    if [[ -z "$state_file" ]]; then
        if command -v print_error &>/dev/null; then
            print_error "State file path is empty (context reporting)"
        else
            echo "ERROR: State file path is empty (context reporting)" >&2
        fi
        return 1
    fi

    if [[ ! -f "$state_file" ]]; then
        if command -v print_error &>/dev/null; then
            print_error "State file does not exist: $state_file"
        else
            echo "ERROR: State file does not exist: $state_file" >&2
        fi
        return 1
    fi

    # Extract deployment information
    local deployment_id
    deployment_id=$(yq eval '.deployment_id' "$state_file" 2>/dev/null || echo "unknown")

    local created_at
    created_at=$(yq eval '.created_at' "$state_file" 2>/dev/null || echo "unknown")

    local current_phase
    current_phase=$(yq eval '.phase' "$state_file" 2>/dev/null || echo "unknown")

    local current_status
    current_status=$(yq eval '.status' "$state_file" 2>/dev/null || echo "unknown")

    local azure_location
    azure_location=$(yq eval '.config.azure_location' "$state_file" 2>/dev/null || echo "unknown")

    local resource_group
    resource_group=$(yq eval '.config.resource_group' "$state_file" 2>/dev/null || echo "unknown")

    # Display deployment context
    if command -v print_header &>/dev/null; then
        print_header "Deployment Context"
    else
        echo "=== Deployment Context ===" >&2
    fi

    if command -v print_info &>/dev/null; then
        print_info "Deployment ID: $deployment_id"
        print_info "Created: $created_at"
        print_info "Current phase: $current_phase"
        print_info "Status: $current_status"
        print_info "Azure location: $azure_location"
        print_info "Resource group: $resource_group"
        print_info "State file: $state_file"
    else
        echo "==> Deployment ID: $deployment_id"
        echo "==> Created: $created_at"
        echo "==> Current phase: $current_phase"
        echo "==> Status: $current_status"
        echo "==> Azure location: $azure_location"
        echo "==> Resource group: $resource_group"
        echo "==> State file: $state_file"
    fi

    # Check for multiple deployments and warn
    local state_count
    state_count=$(find ./state -name "deployment-state.yaml" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ $state_count -gt 1 ]]; then
        if command -v print_warning &>/dev/null; then
            print_warning "Multiple deployments detected ($state_count total)"
            print_warning "Using most recent deployment state"
            print_warning "To specify a different deployment: export K0RDENT_DEPLOYMENT_STATE=/path/to/state.yaml"
        else
            echo "WARNING: Multiple deployments detected ($state_count total)" >&2
            echo "WARNING: Using most recent deployment state" >&2
            echo "WARNING: To specify a different deployment: export K0RDENT_DEPLOYMENT_STATE=/path/to/state.yaml" >&2
        fi
    fi

    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# is_valid_deployment_state - Quick validation check for state file
#
# Purpose: Lightweight validation for state file without detailed error messages
#
# This is useful for conditional logic where you just need a yes/no answer
# without verbose error output.
#
# Arguments:
#   $1 - state_file_path: Path to state file to check
#
# Returns:
#   0 - State file is valid
#   1 - State file is invalid
#
# Example:
#   if is_valid_deployment_state "$state_file"; then
#       use_state_based_config
#   else
#       use_default_config
#   fi
is_valid_deployment_state() {
    local state_file="$1"

    # Quick checks without verbose error output
    [[ -n "$state_file" ]] || return 1
    [[ -f "$state_file" ]] || return 1

    # Security validation (suppress output)
    validate_state_file_path "$state_file" &>/dev/null || return 1
    validate_state_file_permissions "$state_file" &>/dev/null || return 1

    # Structure validation (suppress output)
    validate_deployment_state_structure "$state_file" &>/dev/null || return 1

    return 0
}

# get_deployment_state_info - Extract specific field from deployment state
#
# Purpose: Safely extract configuration values from deployment state file
#
# Arguments:
#   $1 - state_file_path: Path to deployment state file
#   $2 - field_path: YAML path to field (e.g., "config.azure_location")
#
# Returns:
#   0 - Successfully extracted field (value written to stdout)
#   1 - Failed to extract field
#
# Example:
#   azure_location=$(get_deployment_state_info "$state_file" "config.azure_location")
get_deployment_state_info() {
    local state_file="$1"
    local field_path="$2"

    if [[ -z "$state_file" ]] || [[ -z "$field_path" ]]; then
        return 1
    fi

    if ! is_valid_deployment_state "$state_file"; then
        return 1
    fi

    local value
    value=$(yq eval ".$field_path" "$state_file" 2>/dev/null)

    if [[ "$value" == "null" ]] || [[ -z "$value" ]]; then
        return 1
    fi

    echo "$value"
    return 0
}



# =============================================================================
# EXISTING CONFIGURATION RESOLUTION FUNCTIONS (Enhanced for Task 003)
# =============================================================================




# Resolve canonical configuration using priority order:
# 1. Explicit override (K0RDENT_CONFIG_FILE environment variable)
# 2. Deployment state (canonical source) - UNLESS development mode overrides it
# 3. Default configuration search (backward compatibility)
#
# Development Mode Support:
#   Set K0RDENT_DEVELOPMENT_MODE=true to prefer default configuration over deployment state
#   This is useful for iterative development and testing scenarios where you want to
#   quickly test changes without modifying deployment state.
#
#   Set K0RDENT_DEVELOPMENT_STATE=/path/to/state.yaml to use a specific state file
#   for testing. This allows testing against different deployment scenarios without
#   changing the actual deployment state.
#
# Examples:
#   # Use default config for quick development iteration
#   K0RDENT_DEVELOPMENT_MODE=true ./bin/setup-azure-cluster-deployment.sh
#
#   # Test against a specific development state
#   K0RDENT_DEVELOPMENT_STATE=./state/dev-state.yaml ./bin/create-azure-child.sh
#
#   # Production mode (default behavior - uses deployment state)
#   ./bin/setup-azure-cluster-deployment.sh
resolve_canonical_config() {
    # Check for development mode
    local development_mode="${K0RDENT_DEVELOPMENT_MODE:-false}"
    local development_state="${K0RDENT_DEVELOPMENT_STATE:-}"

    # Priority 1: Explicit override (highest priority, even in development mode)
    if [[ -n "${K0RDENT_CONFIG_FILE:-}" ]]; then
        if [[ -f "$K0RDENT_CONFIG_FILE" ]]; then
            export K0RDENT_CONFIG_SOURCE="explicit-override"
            if command -v print_info &>/dev/null; then
                print_info "Using explicit configuration override: $K0RDENT_CONFIG_FILE"
            fi
            return 0
        else
            echo "ERROR: Custom config file not found: $K0RDENT_CONFIG_FILE" >&2
            return 1
        fi
    fi

    # Development Mode: Check if development state override is specified
    if [[ -n "$development_state" ]]; then
        if command -v print_info &>/dev/null; then
            print_info "Development mode: Using specified state file"
        else
            echo "INFO: Development mode: Using specified state file" >&2
        fi

        # Validate the development state file
        if [[ ! -f "$development_state" ]]; then
            if command -v print_error &>/dev/null; then
                print_error "Development state file not found: $development_state"
            else
                echo "ERROR: Development state file not found: $development_state" >&2
            fi
            return 1
        fi

        # Set as temporary deployment state for this invocation
        local original_state="${DEPLOYMENT_STATE_FILE:-}"
        export DEPLOYMENT_STATE_FILE="$development_state"

        # Try to load from the development state
        if load_config_from_deployment_state; then
            export K0RDENT_CONFIG_SOURCE="development-state"
            if command -v print_info &>/dev/null; then
                print_info "Successfully loaded development state: ${development_state##*/}"
            fi
            return 0
        else
            # Restore original state file setting
            if [[ -n "$original_state" ]]; then
                export DEPLOYMENT_STATE_FILE="$original_state"
            else
                unset DEPLOYMENT_STATE_FILE
            fi

            if command -v print_error &>/dev/null; then
                print_error "Failed to load development state, falling back to default"
            else
                echo "ERROR: Failed to load development state, falling back to default" >&2
            fi
            export K0RDENT_CONFIG_SOURCE="default"
            return 0
        fi
    fi

    # Development Mode: Prefer default configuration over deployment state
    if [[ "$development_mode" == "true" ]]; then
        if command -v print_info &>/dev/null; then
            print_info "Development mode enabled: Using default configuration"
            print_info "To use deployment state, unset K0RDENT_DEVELOPMENT_MODE or set to 'false'"
        else
            echo "INFO: Development mode enabled: Using default configuration" >&2
            echo "INFO: To use deployment state, unset K0RDENT_DEVELOPMENT_MODE or set to 'false'" >&2
        fi
        export K0RDENT_CONFIG_SOURCE="development-default"
        return 0
    fi

    # Priority 2: Deployment state (production behavior)
    if load_config_from_deployment_state; then
        return 0
    fi

    # Priority 3: Default search (backward compatibility)
    export K0RDENT_CONFIG_SOURCE="default"
    return 0
}

# Show configuration source for transparency
#
# Purpose: Display clear information about where configuration is being loaded from
#
# This function provides visibility into the configuration resolution process,
# including development mode indicators and state file information.
#
# Development Mode Indicators:
#   - development-default: Using default config (K0RDENT_DEVELOPMENT_MODE=true)
#   - development-state: Using specified state file (K0RDENT_DEVELOPMENT_STATE)
#
# Production Indicators:
#   - deployment-state: Using canonical deployment state (normal production)
#   - explicit-override: Using K0RDENT_CONFIG_FILE override
#   - default: Fallback to default configuration
#
# Example Output:
#   ==> Configuration source: development mode (using default configuration)
#   ==> Development mode active: K0RDENT_DEVELOPMENT_MODE=true
show_configuration_source() {
    local source="${K0RDENT_CONFIG_SOURCE:-unknown}"
    local config_file="${K0RDENT_CONFIG_FILE:-unknown}"
    local timestamp="${K0RDENT_CONFIG_TIMESTAMP:-unknown}"
    local development_mode="${K0RDENT_DEVELOPMENT_MODE:-false}"
    local development_state="${K0RDENT_DEVELOPMENT_STATE:-}"

    case "$source" in
        deployment-state)
            echo "==> Configuration source: deployment state (${config_file##*/}, last updated: $timestamp)"
            ;;
        explicit-override)
            echo "==> Configuration source: explicit override ($config_file)"
            ;;
        development-default)
            echo "==> Configuration source: development mode (using default configuration)"
            echo "==> Development mode active: K0RDENT_DEVELOPMENT_MODE=true"
            echo "==> To use deployment state: unset K0RDENT_DEVELOPMENT_MODE"
            ;;
        development-state)
            echo "==> Configuration source: development state (${config_file##*/})"
            echo "==> Development state override: $development_state"
            echo "==> To use production state: unset K0RDENT_DEVELOPMENT_STATE"
            ;;
        default)
            echo "==> Configuration source: default configuration file"
            if [[ "$development_mode" == "true" ]]; then
                echo "==> Note: Development mode is enabled but deployment state was not available"
            fi
            ;;
        *)
            echo "==> Configuration source: unknown"
            ;;
    esac

    # Show general development mode status if any development features are active
    if [[ "$development_mode" == "true" ]] || [[ -n "$development_state" ]]; then
        if command -v print_warning &>/dev/null; then
            print_warning "Development mode features are active"
            print_warning "Ensure you're not running production operations"
        else
            echo "WARNING: Development mode features are active" >&2
            echo "WARNING: Ensure you're not running production operations" >&2
        fi
    fi
}

# =============================================================================
# CONFIGURATION VALIDATION AND DRIFT DETECTION (Task 0010)
# =============================================================================




