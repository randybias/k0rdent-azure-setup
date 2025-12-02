# Design: Codebase Cleanup and Optimization

## Context

The k0rdent-azure-setup codebase has accumulated technical debt through rapid development. Analysis revealed:

- **147 total functions** across 7 library files
- **58 unused functions (39%)** consuming maintenance attention
- **22 single-use functions (15%)** that could be inlined
- **2 duplicate functions** with conflicting implementations
- **3 deprecated functions** still present
- **Problematic exit patterns** that prevent proper error recovery

This design documents the approach to systematically clean up the codebase while preserving all functionality.

## Goals / Non-Goals

### Goals
- Remove all unused functions to reduce maintenance burden
- Fix duplicate function definitions that cause unpredictable behavior
- Replace `exit 1` with `return 1` in utility functions for proper error handling
- Consolidate duplicate code patterns into shared helpers
- Maintain 100% backward compatibility with existing deployments

### Non-Goals
- Architectural changes (keeping current function library approach)
- New features or capabilities
- Changes to deployment workflow or phases
- Performance optimizations beyond code removal
- Configuration file changes (YAML files represent distinct deployment profiles)

## Decisions

### Decision 1: Phased Approach
**What:** Split cleanup into 3 phases with validation between each.

**Why:** Allows incremental testing and easy rollback if issues discovered.

**Phases:**
1. Critical fixes (duplicates, exit patterns, deprecated functions)
2. Unused code removal
3. Code consolidation (new helpers)

### Decision 2: Keep azure-cluster-functions.sh
**What:** Keep file but remove 4 unused functions, leaving 2 used functions.

**Why:** The remaining 2 functions (`deploy_cluster_with_retry`, `validate_azure_cluster_ready`) are specialized for Azure child cluster deployment and logically belong in a separate file.

**Alternative considered:** Merge into common-functions.sh. Rejected because it would mix Azure-specific retry logic with general utilities.

### Decision 3: Return 1 vs Exit 1 in Utility Functions
**What:** All utility functions will use `return 1` for errors.

**Why:** Allows callers to handle errors gracefully. Scripts can still `exit 1` after checking return codes if termination is desired.

**Migration:**
```bash
# Before (problematic)
check_azure_cli  # Exits entire script if Azure CLI missing

# After (proper)
if ! check_azure_cli; then
    print_error "Azure CLI required"
    exit 1
fi
```

### Decision 4: New Helper Functions
**What:** Create 5 new helper functions to consolidate duplicated patterns.

**Functions:**
1. `find_ssh_key()` - SSH key path lookup (replaces 4 duplicated find commands)
2. `kubectl_delete_resources()` - Batch kubectl delete with --ignore-not-found
3. `get_controller_nodes()` - Extract controller nodes from VM_HOSTS
4. `get_worker_nodes()` - Extract worker nodes from VM_HOSTS
5. `check_phase_completion()` - Generic phase validation pattern

**Location:** common-functions.sh (except check_phase_completion in state-management.sh)

## Risks / Trade-offs

### Risk 1: Breaking Existing Scripts
**Risk:** Removing functions that appear unused but are actually called via dynamic invocation.

**Mitigation:**
- Search for all function names using grep before removal
- Check for `eval` and variable-based function calls
- Run comprehensive tests after each phase

### Risk 2: Exit to Return Migration
**Risk:** Scripts that depended on `exit 1` behavior may continue silently after errors.

**Mitigation:**
- Document all changed functions
- Update callers to explicitly handle return codes
- Add comments in code explaining the change

## Migration Plan

### Step 1: Create Backup
```bash
git checkout -b feature/codebase-cleanup
```

### Step 2: Phase 1 (Critical Fixes)
1. Remove duplicate function definitions
2. Fix exit patterns
3. Remove deprecated functions
4. Test: `./bin/check-prerequisites.sh`

### Step 3: Phase 2 (Unused Code Removal)
1. Remove unused functions from each file
2. Verify no broken calls
3. Test: `./tests/state-phase-smoke.sh`

### Step 4: Phase 3 (Code Consolidation)
1. Add new helper functions
2. Update callers to use helpers
3. Test: Full deployment dry-run

### Rollback Plan
If issues discovered:
1. `git diff` to identify problematic changes
2. `git checkout -- <file>` to revert specific files
3. Or `git reset --hard origin/main` for full rollback

## Open Questions

1. **Should single-use functions be inlined?**
   - Current decision: No, keep for readability
   - May revisit in future cleanup

2. **Should azure-cluster-functions.sh be removed entirely?**
   - Current decision: Keep with 2 functions
   - May consolidate if more Azure-specific functions needed

## Metrics

### Before Cleanup
- Total functions: 147
- Unused functions: 58 (39%)
- Single-use functions: 22 (15%)
- Duplicate functions: 2
- Total shell code: ~16,757 lines

### After Cleanup (Expected)
- Total functions: ~95 (+5 new helpers)
- Unused functions: 0
- Single-use functions: ~20 (acceptable for domain-specific logic)
- Duplicate functions: 0
- Total shell code: ~15,200 lines (-9%)

### Code Quality Improvements
- Function reusability: 40% -> 70%+
- Maintenance burden: Significantly reduced
- Onboarding clarity: Improved (less dead code to understand)
