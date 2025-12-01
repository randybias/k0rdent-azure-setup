# Change: Codebase Cleanup and Optimization

## Why

Deep analysis of the k0rdent-azure-setup codebase revealed significant technical debt:
- **39% of functions are unused** (58 of 147 functions)
- **15% are single-use** (22 functions that could be inlined)
- **2 functions are duplicated** with conflicting implementations
- **~174 lines of redundant YAML** configuration across 6 files
- **3 deprecated functions** still present in state-management.sh
- **Problematic exit patterns** in utility functions prevent proper error handling

This cleanup will reduce maintenance burden, improve code quality, and make the codebase more approachable for contributors.

## What Changes

### Phase 1: Critical Fixes (Required)
- **BREAKING**: Remove duplicate `check_k0sctl()` and `check_netcat()` definitions in common-functions.sh
- Replace `exit 1` with `return 1` in utility functions to enable proper error handling
- Remove 3 deprecated cluster state functions from state-management.sh

### Phase 2: Unused Code Removal
- Remove 24 unused functions from common-functions.sh (~400-500 lines)
- Remove 10 unused functions from config-resolution-functions.sh (~600-700 lines)
- Remove 14 unused functions from state-management.sh (~200 lines)
- Remove 4 unused functions from azure-cluster-functions.sh (~150 lines)
- Remove 2 unused functions from kof-functions.sh (~30 lines)

### Phase 3: Code Consolidation
- Extract SSH key lookup into shared `find_ssh_key()` helper
- Create batch kubectl delete helper `kubectl_delete_resources()`
- Create controller/worker node getters `get_controller_nodes()`, `get_worker_nodes()`
- Consolidate phase completion check pattern into `check_phase_completion()`

## Impact

### Affected Specs
- None (internal refactoring, no behavior changes)

### Affected Code

**Files to modify:**
- `etc/common-functions.sh` - Remove 24 unused functions, fix duplicates, fix exit patterns
- `etc/state-management.sh` - Remove 14 unused functions, remove deprecated functions
- `etc/config-resolution-functions.sh` - Remove 10 unused functions
- `etc/azure-cluster-functions.sh` - Remove 4 unused functions or consolidate file
- `etc/kof-functions.sh` - Remove 2 unused functions

**Estimated reduction:**
- ~1,200-1,500 lines of code removed (18-23% of shell code)
- Function reusability improved from 40% to 70%+
- Maintenance burden significantly reduced

## Risk Assessment

- **Low risk**: Internal refactoring, all behavior preserved
- **Mitigation**: Comprehensive testing via existing smoke tests and manual validation
- **Rollback**: Git revert if issues discovered

## Success Criteria

1. All unused functions removed
2. No duplicate function definitions
3. All utility functions return proper error codes (not exit)
4. Configuration defaults centralized in single file
5. All existing tests pass
6. No regression in deployment functionality
