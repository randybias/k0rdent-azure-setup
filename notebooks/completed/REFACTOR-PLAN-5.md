# Refactoring Plan: Code Reduction and Consolidation

**Date**: December 5, 2024  
**Status**: Planning Phase  
**Priority**: High  
**Estimated Code Reduction**: 1,400-1,850 lines (~30-40%)

## Executive Summary

Analysis reveals significant code duplication across the k0rdent-azure-setup codebase. This plan outlines systematic consolidation opportunities that will reduce code size by 30-40% while improving maintainability and consistency.

---

## Major Redundancy Categories

### 1. Command Pattern Duplication (400-500 lines)

**Current State**: Every script implements identical command parsing:
- `deploy`, `reset`, `status`, `help` commands
- `-y, --yes, --no-wait` argument parsing  
- Similar usage display functions
- Duplicate command handling logic

**Solution**: Create unified command handler in `common-functions.sh`

### 2. Azure Operations (200-300 lines)

**Current State**: Repeated Azure patterns:
- Resource existence checks in 5+ scripts
- Azure CLI authentication checks duplicated
- Similar error handling for Azure commands

**Solution**: Create Azure operation wrapper functions

### 3. SSH Operations (150-200 lines)

**Current State**: Identical SSH command patterns across:
- `create-azure-vms.sh`
- `install-k0s.sh`
- `install-k0rdent.sh`

**Solution**: Single SSH execution function with standard options

### 4. Status Display Functions (200-250 lines)

**Current State**: Each script has its own status display implementation

**Solution**: Generic status display framework

### 5. Reset Operations (150-200 lines)

**Current State**: Reset logic duplicated in every script

**Solution**: Standardized reset handler

---

## Implementation Plan

### Phase 1: Core Consolidation (High Priority)

#### 1.1 Unified Command Handler

**New Function in `common-functions.sh`**:
```bash
# Handle standard script commands with consistent behavior
handle_standard_commands() {
    local script_name="$1"
    local supported_commands="$2"
    local -A command_functions=()
    
    # Parse command function mappings
    shift 2
    while [[ $# -gt 0 ]]; do
        command_functions["$1"]="$2"
        shift 2
    done
    
    # Standard argument parsing
    PARSED_ARGS=$(parse_standard_args "${ORIGINAL_ARGS[@]}")
    eval "$PARSED_ARGS"
    
    # Get command
    local command="${POSITIONAL_ARGS[0]:-}"
    
    # Handle help
    if [[ "$SHOW_HELP" == "true" ]] || [[ "$command" == "help" ]]; then
        ${command_functions["usage"]}
        exit 0
    fi
    
    # Validate command
    if [[ -z "$command" ]] || [[ ! " $supported_commands " =~ " $command " ]]; then
        print_error "Invalid command: $command"
        ${command_functions["usage"]}
        exit 1
    fi
    
    # Execute command function
    ${command_functions["$command"]}
}
```

**Usage Example**:
```bash
# In generate-wg-keys.sh
handle_standard_commands \
    "$0" \
    "deploy reset status help" \
    "deploy" "deploy_keys" \
    "reset" "reset_keys" \
    "status" "show_status" \
    "usage" "show_usage"
```

#### 1.2 SSH Execution Wrapper

**New Function**:
```bash
# Execute SSH command with standard options and error handling
execute_remote_command() {
    local host="$1"
    local command="$2"
    local description="${3:-Remote command}"
    local timeout="${4:-30}"
    
    print_info "$description on $host..."
    
    if ssh -i "$SSH_PRIVATE_KEY" \
           -o ConnectTimeout="$timeout" \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o LogLevel=ERROR \
           "$ADMIN_USER@$host" \
           "$command"; then
        return 0
    else
        print_error "$description failed on $host"
        return 1
    fi
}
```

#### 1.3 Centralized Prerequisites

**Move all checks to `deploy-k0rdent.sh`**:
```bash
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Existing checks
    check_azure_cli
    check_wireguard_tools
    
    # Add from other scripts
    check_k0sctl        # From install-k0s.sh
    check_netcat        # From connect-laptop-wireguard.sh
    
    print_success "All prerequisites satisfied"
}
```

### Phase 2: Script Consolidation (Medium Priority)

#### 2.1 Merge WireGuard Scripts

**Current Scripts**:
- `generate-laptop-wg-config.sh` (217 lines)
- `connect-laptop-wireguard.sh` (349 lines)

**New Script**: `manage-vpn.sh` (~400 lines total)
```bash
Commands:
- generate    # Generate laptop WireGuard config
- setup       # Setup WireGuard (from refactor plan)
- connect     # Connect to VPN
- disconnect  # Disconnect from VPN
- status      # Show VPN status
- test        # Test connectivity
- cleanup     # Clean up orphaned interfaces
```

#### 2.2 Merge Preparation Scripts

**Current Scripts**:
- `generate-wg-keys.sh` (151 lines)
- `generate-cloud-init.sh` (249 lines)

**New Script**: `prepare-deployment.sh` (~300 lines total)
```bash
Commands:
- keys        # Generate WireGuard keys
- cloud-init  # Generate cloud-init files
- all         # Generate both
- reset       # Reset all generated files
- status      # Show preparation status
```

### Phase 3: Advanced Consolidation (Low Priority)

#### 3.1 Resource Verification Framework

```bash
# Generic resource verification with retry logic
verify_resources() {
    local resource_type="$1"
    local check_function="$2"
    local timeout="${3:-300}"
    local interval="${4:-30}"
    shift 4
    local resources=("$@")
    
    # Common verification loop
    # Progress reporting
    # Retry logic
    # Result aggregation
}
```

#### 3.2 Status Display Framework

```bash
# Generic status display for any resource type
display_resource_status() {
    local title="$1"
    local check_exists_func="$2"
    local get_details_func="$3"
    shift 3
    local resources=("$@")
    
    print_header "$title Status"
    
    for resource in "${resources[@]}"; do
        if $check_exists_func "$resource"; then
            local details=$($get_details_func "$resource")
            print_success "$resource: $details"
        else
            print_error "$resource: Not found"
        fi
    done
}
```

---

## File Structure After Refactoring

### Removed Files
```
bin/generate-laptop-wg-config.sh  # Merged into manage-vpn.sh
bin/connect-laptop-wireguard.sh   # Merged into manage-vpn.sh
bin/generate-wg-keys.sh           # Merged into prepare-deployment.sh
bin/generate-cloud-init.sh        # Merged into prepare-deployment.sh
```

### New/Modified Files
```
bin/prepare-deployment.sh         # Handles all pre-deployment generation
bin/manage-vpn.sh                 # All VPN-related operations
bin/lockdown-ssh.sh              # SSH security management (new)
etc/common-functions.sh          # Enhanced with consolidated functions
```

### Unchanged Files
```
bin/setup-azure-network.sh       # Azure-specific, stays separate
bin/create-azure-vms.sh          # Complex VM logic, stays separate
bin/install-k0s.sh               # k0s-specific, stays separate
bin/install-k0rdent.sh           # k0rdent-specific, stays separate
```

---

## Benefits

### Code Reduction
- **Lines of code**: Reduce by ~1,500 lines (35%)
- **Number of files**: Reduce from 8 to 6 scripts in bin/
- **Duplication**: Eliminate ~90% of duplicate patterns

### Maintainability
- **Single source of truth**: Command handling, SSH operations, prerequisites
- **Consistent behavior**: All scripts work the same way
- **Easier updates**: Change once, apply everywhere

### User Experience  
- **Fewer scripts**: Clearer purpose for each script
- **Consistent interface**: Same commands and options everywhere
- **Better error messages**: Centralized, consistent error handling

---

## Implementation Strategy

### Step 1: Add Consolidated Functions (No Breaking Changes)
1. Add new functions to `common-functions.sh`
2. Update existing scripts to use new functions
3. Test thoroughly to ensure no regression

### Step 2: Refactor Existing Scripts
1. Update each script to use `handle_standard_commands`
2. Replace SSH operations with `execute_remote_command`
3. Remove duplicate prerequisite checks

### Step 3: Merge Scripts (Breaking Changes)
1. Create new consolidated scripts
2. Update `deploy-k0rdent.sh` to use new scripts
3. Remove old scripts
4. Update documentation

### Step 4: Optimize and Polish
1. Further consolidate any remaining duplication
2. Optimize performance where possible
3. Update all documentation and examples

---

## Risk Mitigation

### Testing Strategy
- Test each consolidation step independently
- Maintain backwards compatibility during transition
- Create comprehensive test suite before major changes

### Rollback Plan
- Tag repository before major changes
- Document all script name changes
- Provide migration guide for users

### Communication
- Announce changes in README
- Provide clear migration path
- Document new script structure

---

## Metrics

### Before Refactoring
- Total lines: ~4,200
- Scripts in bin/: 8
- Duplicate patterns: ~40%

### After Refactoring  
- Total lines: ~2,700
- Scripts in bin/: 6
- Duplicate patterns: <5%

### Success Criteria
- All existing functionality preserved
- Deployment time unchanged or improved
- No new bugs introduced
- Documentation updated

---

## Timeline

### Week 1: Core Consolidation
- Implement unified command handler
- Add SSH execution wrapper
- Centralize prerequisites

### Week 2: Script Refactoring
- Update all scripts to use new functions
- Test thoroughly
- Update documentation

### Week 3: Script Merging
- Create consolidated scripts
- Update deployment flow
- Remove old scripts

### Week 4: Polish and Release
- Final testing
- Documentation updates
- Release announcement