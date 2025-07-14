# k0rdent Development Backlog

This file tracks future enhancements and improvements that are not currently prioritized but may be valuable additions.

## Summary Table

| Priority | Category | Item | Status |
|----------|----------|------|--------|
| **HIGH** | Bug Fixes | Bug 0: Deployment resumption doesn't handle partial state correctly | 🆕 NEW |
| **HIGH** | Bug Fixes | Bug 1: Missing k0rdent Management CRD validation | 🆕 NEW |
| **HIGH** | Bug Fixes | Bug 2: State not updated during uninstall/reset operations | 🆕 NEW |
| **HIGH** | Bug Fixes | Bug 9: Reset operations fail when components are broken | 🆕 NEW |
| **HIGH** | Minor Enhancements | Distribute kubeconfig to all k0rdent user home directories | 🆕 NEW |
| **HIGH** | Minor Enhancements | Idempotent Deployment Process with Clear Logging | 🆕 NEW |
| **MEDIUM** | Bug Fixes | Bug 3: Incorrect validation requiring at least 1 worker node | 🆕 NEW |
| **MEDIUM** | Bug Fixes | Bug 7: Inconsistent controller naming convention | 🆕 NEW |
| **MEDIUM** | Bug Fixes | Bug 12: Reset with --force doesn't clean up local state files | 🆕 NEW |
| **MEDIUM** | Bug Fixes | Bug 13: State not being archived to old_deployments | 🆕 NEW |
| **MEDIUM** | Bug Fixes | Bug 14: Fast reset option for development workflows | 🆕 NEW |
| **MEDIUM** | Minor Enhancements | Rationalize PREFIX/SUFFIX to CLUSTERID | 🆕 NEW |
| **MEDIUM** | Minor Enhancements | Rethink child cluster state management architecture | 🆕 NEW |
| **MEDIUM** | Minor Enhancements | Azure API Optimization with Local Caching | 🆕 NEW |
| **MEDIUM** | Minor Enhancements | Azure CLI Output Format Standardization | 🆕 NEW |
| **MEDIUM** | Minor Enhancements | Create sourceable KUBECONFIG file | 🆕 NEW |
| **MEDIUM** | Minor Enhancements | Documentation Improvements | 🆕 NEW |
| **MEDIUM** | Minor Enhancements | Versioning System | 🆕 NEW |
| **MEDIUM** | Minor Enhancements | Cloud Provider Abstraction | 🆕 NEW |
| **MEDIUM** | Minor Enhancements | Migrate from WireGuard to Nebula Mesh VPN | 🆕 NEW |
| **LOW** | Bug Fixes | Bug 5: VPN connectivity check hangs during reset | ⚠️ NEEDS TESTING |
| **LOW** | Bug Fixes | Bug 11: Cloud-init success doesn't guarantee WireGuard setup | 🆕 NEW |
| **LOW** | Minor Enhancements | Scoped Azure credentials management | 🆕 NEW |
| **LOW** | Minor Enhancements | Bicep-Based Multi-VM Deployment | 🆕 NEW |
| **LOW** | Minor Enhancements | Configuration Management Enhancements | 🆕 NEW |
| **LOW** | Minor Enhancements | CI/CD Pipeline Integration | 🆕 NEW |
| **LOW** | Minor Enhancements | Dependency Consolidation (jq to yq) | 🆕 NEW |
| **LOW** | Minor Enhancements | Improve print_usage Function | 🆕 NEW |
| **LOW** | Minor Enhancements | Reorganize Kubeconfig Storage Location | 🆕 NEW |
| **LOW** | Minor Enhancements | Evaluate Nushell for Bash Script Rewrites | 🆕 NEW |
| **LOW** | Minor Enhancements | direnv Integration | Optional |
| **LOW** | Minor Enhancements | Azure VM Launch Manager with NATS | 🆕 NEW |
| **LOW** | KOF Features | Extract KOF deployment logic into deploy-kof-stack.sh | 🆕 NEW |
| **MEDIUM** | Documentation | Create k0rdent Architecture Overview | 🆕 NEW |
| **MEDIUM** | KOF Testing | KOF End-to-End Deployment Validation | 🆕 NEW |
| **MEDIUM** | KOF Testing | KOF Multi-Child Cluster Testing | 🆕 NEW |
| **MEDIUM** | KOF Testing | KOF Observability Data Flow Verification | 🆕 NEW |
| **LOW** | KOF Features | Custom Collector Configurations | 🆕 NEW |
| **LOW** | KOF Features | Multi-Regional KOF Deployment Support | 🆕 NEW |
| **LOW** | KOF Features | KOF Backup and Restore Capabilities | 🆕 NEW |
| **FUTURE** | Future Ideas | Multi-Cluster Environment Management | 🆕 NEW |
| **FUTURE** | Future Ideas | State Management Migration to Key-Value Store | 🆕 NEW |

## High Priority Items

### Bug Fixes

#### Bug 0: Deployment resumption doesn't handle partial state correctly
**Status**: 🆕 **NEW**
**Priority**: High

**Description**: When a deployment is interrupted and restarted, the deployment script doesn't properly handle the existing state. Instead of intelligently resuming from where it left off, it attempts to re-run deployment steps, making poor decisions based on incomplete state analysis.

**Current Issues**:
- Script attempts to regenerate files that already exist
- SSH connectivity tests fail because VPN state isn't properly checked
- Doesn't validate that VMs are actually running before testing SSH
- Doesn't resume gracefully from the actual deployment phase
- State file exists but deployment logic doesn't use it effectively for resumption

**Example Problematic Behavior**:
```
=== k0s Configuration Generation ===
==> k0sctl configuration already exists: ./k0sctl-config/k0rdent-crqk4ma9-k0sctl.yaml

=== Testing SSH Connectivity ===
==> Testing SSH to k0s-controller (192.168.100.11)...
✗ SSH connectivity to k0s-controller: FAILED
```

**Root Cause**: 
- Deployment scripts don't properly check VPN connectivity before SSH tests
- State file indicates progress but scripts don't use state to determine proper resumption point
- Missing logic to validate actual infrastructure state vs. recorded state
- No reconciliation between expected state and actual Azure/cluster state

**Required Implementation**:
1. **State-aware resumption logic**: Check deployment state and resume from appropriate step
2. **Infrastructure validation**: Verify VMs are running and accessible before SSH tests
3. **VPN state checking**: Ensure VPN is connected before attempting cluster operations
4. **State reconciliation**: Compare recorded state with actual infrastructure state
5. **Graceful continuation**: Skip completed steps and resume from interruption point
6. **Validation gates**: Add checks between each major deployment phase

**Implementation Areas**:
- `deploy-k0rdent.sh` - Main orchestration with state-aware resumption
- `bin/install-k0s.sh` - VPN connectivity checks before SSH tests
- `etc/state-management.sh` - Enhanced state validation functions
- All deployment scripts - State checking before attempting operations

**Testing Requirements**:
- Test interrupted deployments at various stages
- Verify graceful resumption from each interruption point
- Validate that state file accurately reflects actual infrastructure
- Test VPN disconnect/reconnect scenarios during deployment

**Priority Justification**: This significantly impacts user experience and deployment reliability, especially for long-running deployments that can be interrupted by network issues, timeouts, or user interruption.

#### Bug 1: Missing k0rdent Management CRD validation
**Status**: 🆕 **NEW**
**Priority**: High

**Description**: k0rdent installation validation is incomplete - we only check pod status but don't verify the Management CRD is properly created and in Ready state.

**Current Validation**: 
- Checks helm installation status with `helm list -n kcm-system`
- Verifies pods are running with `kubectl get pods -n kcm-system`
- Missing critical Management CRD validation

**Required Validation Command**:
```bash
kubectl get Management -n kcm-system
```

**Expected Output**:
```
NAME   READY   RELEASE     AGE
kcm    True    kcm-1-1-1   9m
```

**Implementation Requirements**:
- Add Management CRD validation to `bin/install-k0rdent.sh`
- Verify Management object exists and READY status is "True"
- Parse release name to confirm correct version deployment
- Add timeout/retry logic for Management CRD to become ready
- Update state management to track Management CRD status
- Include validation in status check function

**Current Impact**: 
- k0rdent may appear "installed" but Management controller could be failing
- Silent failures in k0rdent management plane
- No verification that k0rdent is actually functional

**Location**: `bin/install-k0rdent.sh` lines 145-159 (ready check section)

#### Bug 2: State not updated during uninstall/reset operations
**Status**: 🆕 **NEW**
**Priority**: High

**Description**: State management is not properly updated when uninstalling k0rdent or k0s, or during reset operations. This causes inconsistent state tracking when moving backwards through deployment stages.

**Current Issues**:
- Uninstalling k0rdent doesn't properly reset state to previous phase
- Uninstalling k0s doesn't update state appropriately
- Reset operations may leave stale state information
- No systematic state rollback when undoing deployment steps

**Expected Behavior**:
- **k0rdent uninstall**: Should revert state from `k0rdent_deployed` back to `k0s_deployed`
- **k0s uninstall**: Should revert state from `k0s_deployed` back to `vms_ready` or `infrastructure_ready`
- **Reset operations**: Should systematically clean up state as each component is removed
- **State consistency**: State should always reflect the actual deployment status

**Implementation Requirements**:
- Update `bin/install-k0rdent.sh uninstall` to properly reset state
- Update `bin/install-k0s.sh uninstall` to properly reset state
- Add state rollback functions to handle phase transitions backwards
- Ensure reset operations update state at each step
- Add validation that state matches actual system status

**State Fields to Track**:
- `phase` - Current deployment phase
- `k0rdent_installed` - k0rdent installation status
- `k0rdent_ready` - k0rdent readiness status
- `k0s_installed` - k0s installation status
- `vms_ready` - VM deployment status
- `infrastructure_ready` - Azure infrastructure status

**Affected Scripts**:
- `bin/install-k0rdent.sh` - uninstall command
- `bin/install-k0s.sh` - uninstall command
- `deploy-k0rdent.sh` - reset operations
- All scripts that perform reset/cleanup operations

**Current Impact**:
- State file shows incorrect status after uninstalls
- Difficulty determining actual deployment state
- Potential for script logic errors based on stale state
- Inconsistent behavior during repeated deploy/undeploy cycles

#### Bug 9: Reset operations fail when components are broken, preventing cleanup
**Status**: 🆕 **NEW** - Reported 2025-06-10
**Priority**: High

**Description**: Reset operations fail when VPN is disconnected, WireGuard interfaces are corrupted, or other components are in broken states, preventing complete cleanup and requiring manual intervention.

**Observed failures**:
- VPN connectivity checks block k0rdent/k0s uninstall during reset
- WireGuard interface cleanup fails when interface is in inconsistent state
- Partial deployments can't be cleaned up due to dependency checks
- Reset operations stop on first error instead of continuing with cleanup

**Root cause**: Reset operations have the same dependency requirements as deployment operations, but should be more aggressive about cleanup when things are broken.

**Proposed fix**: Add `--force` or `--ignore-errors` flag for reset operations
- **Skip connectivity checks**: Don't require VPN for reset operations
- **Continue on errors**: Log errors but continue cleanup process
- **Brute force cleanup**: Use Azure CLI directly to find and delete resources by tags/names
- **Best effort approach**: Clean up what can be cleaned, ignore what can't
- **Nuclear option**: Complete reset regardless of component states

**Implementation needed**:
- Add `--force` flag to deploy-k0rdent.sh reset command
- Modify all reset functions to continue on errors when force flag is used
- Add resource discovery via Azure CLI for orphaned resources
- Implement best-effort WireGuard cleanup that handles broken interfaces
- Skip VPN connectivity requirements during forced reset operations

**Benefits**:
- Enables cleanup after failed deployments
- Reduces manual intervention requirements
- Supports "cattle" methodology by making resource disposal reliable
- Prevents resource leakage from partial deployments

**Impact**: Blocks cleanup operations, leads to resource leakage and manual cleanup requirements

### Minor Enhancements

#### Distribute kubeconfig to all k0rdent user home directories
**Priority**: High
**Status**: 🆕 **NEW**

**Description**: After k0s is fully installed, the kubeconfig file should be automatically copied to every k0rdent user's home directory on all VMs for easy kubectl access.

**Current Behavior**: 
- Kubeconfig is only available locally in `./k0sctl-config/` directory
- Users must manually copy or specify --kubeconfig flag

**Expected Behavior**:
- After k0s installation completes, copy kubeconfig to `~k0rdent/.kube/config` on all VMs
- Set proper permissions (600) for security
- Create `.kube` directory if it doesn't exist

**Implementation Requirements**:
- Add to `bin/install-k0s.sh` deploy function after successful k0s deployment
- Use existing SSH connectivity to distribute file
- Ensure k0rdent user owns the file
- Update user's `.bashrc` to set KUBECONFIG if needed

**Benefits**:
- Users can run `kubectl` commands immediately after SSH to any VM
- No need to specify --kubeconfig flag
- Consistent kubectl access across all nodes

#### Idempotent Deployment Process with Clear Logging
**Priority**: High
**Status**: 🆕 **NEW**

**Description**: The entire deployment process needs to be idempotent with clear logging about when files are regenerated versus reused, ensuring transparent and predictable behavior during partial deployments.

**Current Issues**:
- Re-running partial deployments regenerates files that already exist
- Unclear logging about whether files are being reused or regenerated
- Lack of transparency about what actions are being taken vs skipped
- State management doesn't clearly track what has been generated
- Users unsure if re-running is safe or will overwrite configurations

**Required Improvements**:
1. **File Generation Tracking**:
   - Check if files exist before regenerating
   - Log clearly when reusing existing files vs creating new ones
   - Track file generation timestamps in state
   - Provide options to force regeneration when needed

2. **Clear Logging Standards**:
   - "==> Using existing file: [filename]" for reused files
   - "==> Generating new file: [filename]" for new creation
   - "==> Regenerating file: [filename] (forced)" for forced updates
   - "==> Skipping: [action] (already completed)" for idempotent operations

3. **State-Aware Operations**:
   - Track which files have been generated in deployment state
   - Skip regeneration unless explicitly requested or files missing
   - Provide --force-regenerate flag for specific operations
   - Validate existing files before reuse

4. **Idempotent Script Updates**:
   - All generation scripts check for existing files
   - Clear decision logic for regeneration vs reuse
   - Consistent behavior across all deployment scripts
   - State tracking for all generated artifacts

**Implementation Areas**:
- `bin/prepare-deployment.sh` - File generation logic
- `bin/create-azure-vms.sh` - Cloud-init generation
- `bin/install-k0s.sh` - Configuration file generation
- `etc/state-management.sh` - Track generated files
- All scripts that create files or configurations

**Benefits**:
- Safe to re-run deployments at any stage
- Clear understanding of what's happening
- Prevents accidental configuration overwrites
- Easier debugging of partial deployments
- Better user confidence in the system

### Future Ideas

[Moved completed items to the completed section]

## Medium Priority Items

### Bug Fixes

#### Bug 3: Incorrect validation requiring at least 1 worker node
**Status**: 🆕 **NEW**
**Priority**: Medium

**Description**: The validation in `etc/config-internal.sh` incorrectly requires at least 1 worker node, but k0s can operate with a single controller+worker node configuration (controller with workload scheduling enabled).

**Current Behavior**:
```bash
ERROR: K0S_WORKER_COUNT must be at least 1
```

**Expected Behavior**:
- Should allow `worker.count: 0` when controller nodes can run workloads
- k0s supports controller nodes that also schedule workloads (not tainted)
- Single node deployments should be possible with just a controller

**Technical Details**:
- k0s controllers can run workloads if not tainted with `node-role.kubernetes.io/master:NoSchedule`
- The `--enable-worker` flag or configuration allows controllers to schedule pods
- Common pattern for development/testing environments

**Fix Required**:
- Update validation in `etc/config-internal.sh` lines 14-17
- Allow worker count of 0 with appropriate warning
- Document single-node deployment pattern
- Ensure k0s configuration enables workload scheduling on controllers when worker count is 0

**Testing Requirements**:
- Verify single controller node can run k0rdent and workloads
- Test with `worker.count: 0` configuration
- Confirm pods schedule on controller node
- Validate k0rdent installation works without dedicated workers

**Impact**:
- Blocks minimal single-node deployments
- Forces unnecessary resource usage for development
- Prevents valid k0s deployment patterns

#### Bug 7: Inconsistent controller naming convention
**Status**: 🆕 **NEW**
**Priority**: Medium

**Description**: Controller naming is inconsistent compared to worker naming, creating confusion and scripting difficulties.

**Current behavior**:
- First controller: `k0s-controller` (no number suffix)
- Additional controllers: `k0s-controller-2`, `k0s-controller-3`
- All workers: `k0s-worker-1`, `k0s-worker-2`, `k0s-worker-3` (consistently numbered)

**Expected behavior**: Consistent numbered naming for all nodes:
- Controllers: `k0s-controller-1`, `k0s-controller-2`, `k0s-controller-3`
- Workers: `k0s-worker-1`, `k0s-worker-2`, `k0s-worker-3`

**Fix needed**: Update controller naming logic in `etc/config-internal.sh` lines 54-70 to always use numbered suffixes starting from 1.

**Impact**: Affects VM creation, k0s configuration generation, and any scripts that reference controller names.

#### Bug 12: Reset with --force doesn't clean up local state files
**Status**: 🆕 **NEW**
**Priority**: Medium

**Description**: The `--force` reset operation doesn't properly clean up local deployment state files, leaving stale data that can interfere with subsequent deployments.

**Files Not Cleaned Up**:
- `deployment-state.yaml`
- `deployment-events.yaml` 
- `.project-suffix` file
- Potentially other local state files

**Current Behavior**: 
- Reset removes Azure resources but leaves local state
- Subsequent deployments may use stale configuration or state data
- Manual cleanup required between deployments

**Expected Behavior**:
- Force reset should clean up all local deployment artifacts
- Fresh state for new deployments
- Complete reset experience

**Implementation Tasks**:
- Identify all local state files that need cleanup
- Add local file cleanup to force reset path
- Ensure reset leaves system in clean state for new deployments
- Test that subsequent deployments work correctly after force reset

#### Bug 13: State not being archived to old_deployments
**Status**: 🆕 **NEW**
**Priority**: Medium

**Description**: State files under `state/` directory are not being archived into `old_deployments/` when starting new deployments, causing loss of historical deployment data.

**Current Behavior**:
- State files (deployment-state.yaml, deployment-events.yaml) remain in state/ directory
- No automatic archival to old_deployments/ during new deployments
- Previous deployment history is overwritten
- Manual backup required to preserve state

**Expected Behavior**:
- When starting a new deployment, existing state files should be moved to old_deployments/
- Archive should include timestamp and deployment ID for identification
- State directory should be clean for new deployment
- Historical deployments preserved for reference

**Implementation Requirements**:
- Check for existing state files during deployment initialization
- Create timestamped subdirectory under old_deployments/
- Move all state files to archive before creating new ones
- Include deployment ID in archive directory name
- Ensure atomic move operation to prevent data loss

**Archive Structure Example**:
```
old_deployments/
├── k0rdent-abc123_2025-07-13_08-30-00/
│   ├── deployment-state.yaml
│   └── deployment-events.yaml
└── k0rdent-xyz789_2025-07-12_14-45-30/
    ├── deployment-state.yaml
    └── deployment-events.yaml
```

**Files to Archive**:
- state/deployment-state.yaml
- state/deployment-events.yaml
- Any other state files created during deployment

**Impact**:
- Loss of deployment history
- Cannot review previous deployment configurations
- Difficulty debugging issues from past deployments
- No audit trail of deployment activities

#### Bug 14: Fast reset option for development workflows
**Status**: 🆕 **NEW**
**Priority**: Medium

**Description**: Add fast reset option that skips k0rdent and k0s uninstall steps and jumps straight to deleting Azure resource groups for faster development iterations.

**Current Reset Process**:
- Uninstall k0rdent from cluster
- Uninstall k0s cluster 
- Disconnect VPN
- Delete VMs individually
- Delete Azure network resources
- Clean up local files

**Proposed Fast Reset**:
- Skip k0rdent uninstall
- Skip k0s uninstall 
- Skip VPN disconnect (may be broken anyway)
- **Delete entire Azure resource group** (removes all VMs, networks, etc. in one operation)
- Clean up local files

**Implementation Approach**:
- Add `--fast` flag to reset operations
- Single Azure CLI command: `az group delete --name $RG --yes --no-wait`
- Bypass all individual resource cleanup steps
- Maintain local file cleanup for consistency

**Benefits**:
- Dramatically faster reset times (seconds vs minutes)
- Works even when cluster/VPN is broken
- Simpler implementation with fewer failure points
- Better developer experience for iterative testing

**Cloud Provider Considerations**:
- **Azure-specific**: Leverages Azure resource group deletion
- **Future multi-cloud**: Other providers may not have equivalent grouping
- **Design note**: Keep this Azure-specific, implement differently for other clouds
- **Architecture**: Consider cloud provider abstraction layer for reset operations

**Caveats**:
- Resource group deletion is irreversible
- May delete shared resources if RG contains non-k0rdent resources
- Requires careful resource group naming/isolation

**Implementation Tasks**:
- Add `--fast` flag to deploy-k0rdent.sh reset command
- Implement fast reset path in reset functions
- Add safety checks for resource group naming
- Update documentation with fast reset option
- Test compatibility with existing state management

### Minor Enhancements

#### Rationalize and normalize PREFIX and SUFFIX to become CLUSTERID everywhere
**Priority**: Medium
**Status**: 🆕 **NEW**

**Description**: The codebase currently uses both PREFIX and SUFFIX concepts for cluster identification, which creates confusion and inconsistency. These should be unified into a single CLUSTERID concept throughout the codebase.

**Current Issues**:
- `K0RDENT_PREFIX` contains the full cluster identifier (e.g., "k0rdent-wuwrp8f0")
- Suffix is extracted from prefix in various places
- Naming is inconsistent and confusing
- Different scripts handle the prefix/suffix differently

**Proposed Changes**:
- Replace `K0RDENT_PREFIX` with `K0RDENT_CLUSTERID` throughout
- Remove all suffix extraction logic
- Use consistent naming: `${K0RDENT_CLUSTERID}` everywhere
- Update all references in scripts, configs, and state files

**Implementation Areas**:
- `etc/k0rdent-config.sh` - Main configuration loading
- `etc/config-internal.sh` - Internal configuration generation
- All `bin/*.sh` scripts that reference PREFIX
- State files and naming conventions
- Documentation and examples

**Benefits**:
- Clearer, more intuitive naming
- Reduced cognitive load
- Simpler code without prefix/suffix manipulation
- Better consistency across the codebase

#### Rethink child cluster state management architecture
**Priority**: Medium
**Status**: 🆕 **NEW**

**Description**: Current local cluster state tracking duplicates information that k0rdent already manages, creating potential inconsistencies and maintenance overhead. The architecture should be redesigned with k0rdent as the single source of truth.

**Current Issues**:
- Local state files duplicate cluster configuration and status from k0rdent
- State synchronization required to maintain consistency  
- Risk of local state becoming stale or conflicting with k0rdent reality
- Overhead of maintaining parallel state tracking

**Proposed Architecture**:
- **k0rdent as Source of Truth**: All cluster state (status, configuration, readiness) comes from k0rdent ClusterDeployments
- **Local Event Tracking Only**: Local files track operational events and history:
  - When clusters were created/deleted
  - Who initiated operations
  - Deployment parameters used
  - Operational notes and troubleshooting history
  - Local development context
- **Query k0rdent for Current State**: Scripts query kubectl for live cluster status rather than local files
- **Event-Driven Updates**: Local events appended when operations occur, but no state duplication

**Benefits**:
- Eliminates state synchronization complexity
- Reduces inconsistency risks  
- Aligns with "cattle not pets" philosophy
- Simpler mental model: k0rdent owns state, local owns history
- Better separation of concerns

**Implementation Strategy**:
1. **Phase 1**: Modify existing scripts to query k0rdent directly for current state
2. **Phase 2**: Convert local state files to pure event logs
3. **Phase 3**: Remove state synchronization logic
4. **Phase 4**: Add rich event tracking for operational history

**Event Log Structure Example**:
```yaml
cluster_name: "my-cluster"
events:
  - timestamp: "2025-07-11T14:30:00Z"
    action: "cluster_created"
    user: "rbias"
    parameters:
      location: "eastus"
      instance_sizes: "Standard_A4_v2"
    command: "create-child.sh --cluster-name my-cluster ..."
  - timestamp: "2025-07-11T15:45:00Z"
    action: "cluster_deleted"
    user: "rbias"
    reason: "testing completed"
```

**Backward Compatibility**: Transition can be gradual with existing state files continuing to work during migration.

#### Azure API Optimization with Local Caching
**Priority**: Medium
**Status**: 🆕 **NEW**

**Description**: Cache Azure zone/region state data locally to reduce API calls and speed up deployment process.

**Current Issue**: Multiple Azure API calls during deployment for data that rarely changes:
- VM size availability validation in specific zones/regions
- Region capability checks
- Zone availability verification
- Repeated calls for the same data across multiple deployments

**Proposed Solution**: Implement local caching system with timestamped data
- **Cache VM size availability**: Store validated VM sizes per region/zone with timestamp
- **Cache region capabilities**: Store region features and limits
- **Cache zone availability**: Store availability zone support per region
- **Automatic cache refresh**: Implement time-based cache expiration (e.g., 24 hours)
- **Cache validation**: Option to force cache refresh or validate cached data
- **Cache location**: Store in `~/.k0rdent/cache/` or similar location
- **Cache format**: JSON or YAML files with timestamp metadata

**Implementation Details**:
- Add caching functions to `etc/common-functions.sh`
- Integrate with existing validation scripts
- Add cache management commands (clear, refresh, status)
- Implement cache expiration logic
- Add fallback to live API calls if cache is stale/missing

**Benefits**:
- Faster deployment times (reduced API latency)
- Reduced Azure API throttling risk
- Better offline capability for validation
- Improved user experience with faster feedback

**Cache Structure Example**:
```yaml
metadata:
  last_updated: "2025-06-18T10:30:00Z"
  cache_version: "1.0"
regions:
  westus2:
    vm_sizes:
      Standard_B2s: 
        zones: [1, 2, 3]
        validated: "2025-06-18T10:30:00Z"
      Standard_D4s_v5:
        zones: [1, 2]
        validated: "2025-06-18T10:30:00Z"
```

#### Azure CLI Output Format Standardization
**Priority**: Medium
**Status**: 🆕 **NEW**

**Description**: Switch all Azure CLI commands to use native JSON output format instead of TSV for improved performance and consistency.

**Current Issue**: Mixed output formats across Azure CLI commands:
- Some commands use `--output tsv` for parsing
- Others use `--output table` for display
- Inconsistent parsing methods (cut, awk vs jq/yq) 
- TSV parsing can be slower and more error-prone than JSON

**Proposed Solution**: Standardize on JSON output format
- **Convert all `--output tsv` to `--output json`**: Update existing Azure CLI commands
- **Standardize JSON parsing**: Use consistent jq/yq parsing throughout codebase
- **Performance improvement**: JSON parsing is typically faster than TSV
- **Better error handling**: JSON provides structured error information
- **Consistent data structures**: Eliminates parsing inconsistencies

**Implementation Tasks**:
- Audit all Azure CLI commands in codebase for `--output` usage
- Convert TSV-based commands to JSON with equivalent jq/yq parsing
- Update any table output commands used for data extraction
- Test performance improvements
- Update any dependent parsing logic

**Benefits**:
- Faster command execution and parsing
- More reliable data extraction
- Consistent error handling
- Better maintainability
- Future-proof for complex data structures

#### Create sourceable KUBECONFIG file
**Priority**: Medium
**Status**: 🆕 **NEW**

**Description**: Create a sourceable shell script in the k0sctl-config directory that properly sets the KUBECONFIG environment variable for easy cluster access.

**Current Situation**:
- Kubeconfig file is generated at `./k0sctl-config/${K0RDENT_PREFIX}-kubeconfig`
- Users must manually set KUBECONFIG or use --kubeconfig flag
- No convenient way to quickly set up shell environment for cluster access

**Proposed Solution**:
Create a file `./k0sctl-config/kubeconfig-env.sh` (or similar) that contains:
```bash
export KUBECONFIG="$(pwd)/k0sctl-config/${K0RDENT_PREFIX}-kubeconfig"
```

**Implementation Details**:
- Generate this file after successful k0s deployment
- Update the file path if deployment prefix changes
- Make it work with both absolute and relative paths
- Consider adding kubectl aliases or completions

**Enhanced Version Could Include**:
```bash
# Set kubeconfig
export KUBECONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/${K0RDENT_PREFIX}-kubeconfig"

# Helpful aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'

# Show current context
echo "KUBECONFIG set to: $KUBECONFIG"
kubectl config current-context
```

**Benefits**:
- Quick environment setup: `source ./k0sctl-config/kubeconfig-env.sh`
- Consistent KUBECONFIG handling across team members
- Reduces command-line friction for cluster access
- Self-documenting cluster access method

**Integration Points**:
- Generate during `install-k0s.sh deploy`
- Update during any operation that changes kubeconfig
- Include instructions in deployment success messages
- Add to documentation and README

#### Documentation Improvements
**Priority**: Medium

- **Update docs to be more clear and concise**: Streamline documentation for better readability
- **Update docs to make it clear how to use the configuration examples**: Add clearer guidance on using example configurations
- **Move all of the details out of README.md to some other doc**: Refactor README to be more focused
- **Make README.md the basic how to install and quickstart without everything else**: Transform README into a simple getting started guide
- **All of the details in README.md to an ARCHITECTURE.md doc maybe**: Create separate architecture documentation
- **Create a diagram showing program flow somehow**: Visual representation of the system workflow

#### Versioning System
**Priority**: Medium

- **Add versioning**: Implement versioning system for the project to track releases and ensure compatibility

#### Cloud Provider Abstraction
**Priority**: Medium

- **Separate Azure business logic for multi-cloud support**: Refactor to separate all Azure-specific logic into a provider layer, enabling swap-out capability for AWS or GCP controllers
  - Create provider interface/abstraction layer
  - Move Azure-specific commands to dedicated modules
  - Design plugin architecture for cloud providers
  - Enable configuration-driven provider selection

#### Create k0rdent Architecture Overview
**Priority**: Medium
**Status**: 🆕 **NEW**

**Description**: Create a comprehensive architecture overview of k0rdent platform to serve as a reference for troubleshooting and understanding the system.

**Approach**: 
- Read docs at docs.k0rdent.io
- Gather user input and knowledge
- Investigate k0rdent components and interactions
- Create summary document for future reference

#### Migrate from WireGuard to Nebula Mesh VPN
**Priority**: Medium
**Status**: 🆕 **NEW**

**Description**: Plan migration from WireGuard to Nebula (https://github.com/slackhq/nebula) to avoid potential conflicts with other mesh VPN solutions, particularly WireGuard support in Calico CNI.

**Current Issues with WireGuard**:
- **CNI Conflicts**: Calico and other CNIs now include WireGuard support, creating potential conflicts
- **Port Conflicts**: WireGuard's fixed UDP port can conflict with CNI implementations
- **Interface Naming**: Potential wg0 interface naming conflicts between deployment VPN and CNI
- **Encryption Overhead**: Double encryption when both deployment VPN and CNI use WireGuard

**Benefits of Nebula**:
- **Certificate-based**: Uses certificate-based authentication instead of pre-shared keys
- **Built-in CA**: Integrated certificate authority for easier node management
- **Lighthouse Architecture**: Built-in NAT traversal and peer discovery
- **No Port Conflicts**: Different default ports and protocols from WireGuard
- **Better Scaling**: Designed for large-scale deployments
- **Firewall Rules**: Built-in host-based firewall rules in configuration

**Migration Plan Requirements**:
1. **Configuration Changes**:
   - Replace WireGuard network configuration with Nebula settings
   - Update cloud-init templates for Nebula installation
   - Modify network security group rules for Nebula ports

2. **Certificate Management**:
   - Implement Nebula CA certificate generation
   - Create host certificates for each VM
   - Secure certificate distribution during VM provisioning

3. **Script Updates**:
   - Update `bin/manage-vpn.sh` for Nebula client configuration
   - Modify VM provisioning scripts for Nebula setup
   - Update connectivity checks for Nebula

4. **Backward Compatibility**:
   - Support both WireGuard and Nebula during transition
   - Configuration option to choose VPN backend
   - Migration path for existing deployments

**Technical Considerations**:
- Nebula uses UDP port 4242 by default (configurable)
- Requires certificate generation and distribution
- Different configuration file format (YAML-based)
- Performance characteristics may differ from WireGuard

**Implementation Phases**:
1. **Phase 1**: Research and prototype Nebula implementation
2. **Phase 2**: Add Nebula as optional VPN backend
3. **Phase 3**: Test with various CNI configurations
4. **Phase 4**: Make Nebula the default VPN backend
5. **Phase 5**: Deprecate WireGuard support

**Dependencies**:
- Nebula binary availability in package repositories
- Certificate management implementation
- Update to all network-related scripts
- Documentation updates

**Testing Requirements**:
- Verify no conflicts with Calico WireGuard mode
- Test with other CNIs (Cilium, Weave)
- Performance comparison with WireGuard
- Multi-node connectivity testing
- Firewall rule validation

## Low Priority Items

### Bug Fixes

#### Bug 5: VPN connectivity check hangs during reset operations
**Status**: ⚠️ **NEEDS TESTING** - Ping timeouts have been implemented, may be resolved
**Priority**: Low

**Description**: When running reset operations (uninstalling k0rdent or removing k0s cluster), the VPN connectivity check hangs and requires multiple Ctrl+C to interrupt.

**Recent Updates**: Codebase now includes ping timeouts (`ping -c 3 -W 5000`) in multiple scripts. This bug may have been resolved during recent improvements but needs testing to confirm.

#### Bug 11: Cloud-init success doesn't guarantee WireGuard setup completion
**Status**: 🆕 **NEW**
**Priority**: Low

**Description**: VMs can pass cloud-init status verification but still fail WireGuard configuration verification, indicating cloud-init completion doesn't guarantee all services are properly configured.

**Observed Behavior**:
- VM passes SSH connectivity test
- Cloud-init reports successful completion (`sudo cloud-init status` returns success)
- VM marked as "fully operational" by create-azure-vms.sh
- Later WireGuard verification fails with "WireGuard interface wg0 not found or not configured"

**Root Cause Analysis Needed**:
- **Timing Issue**: Cloud-init may report success before WireGuard service fully initializes
- **Service Dependencies**: WireGuard systemd service may not be properly enabled or started
- **Cloud-init Script Issues**: WireGuard configuration in cloud-init may have silent failures
- **Network Interface Timing**: VM networking may not be fully ready when WireGuard starts

**Current Impact**:
- VMs appear operational but lack proper WireGuard connectivity
- Deployment continues to k0s installation which may fail without proper networking
- Manual intervention required to fix WireGuard on affected VMs
- Inconsistent deployment success rates

**Investigation Areas**:
- Review cloud-init YAML templates for WireGuard configuration
- Check systemd service dependencies and startup order
- Add more granular cloud-init status checking (per-module status)
- Consider adding WireGuard-specific validation to VM verification loop

**Potential Solutions**:
- **Enhanced Cloud-init Validation**: Check specific cloud-init modules beyond overall status
- **WireGuard-specific Checks**: Add WireGuard interface verification to create-azure-vms.sh
- **Retry Logic**: Implement WireGuard setup retry mechanism in cloud-init
- **Service Dependencies**: Ensure proper systemd service ordering and dependencies

**Workaround**: Manual WireGuard setup on affected VMs, but defeats automation purpose

**Impact**: Reduces deployment reliability, requires manual intervention, potential k0s installation failures

### Minor Enhancements

#### Scoped Azure credentials management
**Priority**: Low
**Status**: 🆕 **NEW**

**Description**: Currently Azure credentials (AzureClusterIdentity) are configured with `allowedNamespaces: {}` which allows all namespaces to use the credentials. This provides maximum flexibility but reduces security isolation.

**Current Implementation**:
- AzureClusterIdentity allows access from any namespace
- Single credential for all Azure deployments
- No scoping or isolation between different uses

**Future Enhancement Options**:
1. **Namespace-specific credentials**: Create separate AzureClusterIdentity resources for different namespaces/purposes
2. **Role-based scoping**: Different service principals with different Azure permissions (contributor vs reader)
3. **Project-based isolation**: Separate credentials per project or deployment type
4. **Tenant/subscription scoping**: Support for multi-tenant scenarios

**Benefits of Scoped Credentials**:
- Better security isolation between projects
- Principle of least privilege
- Audit trail by credential usage
- Support for complex organizational structures

**Implementation Considerations**:
- Backward compatibility with existing open configuration
- Balance between security and operational complexity
- Integration with k0rdent's multi-tenancy features
- Documentation and migration path for existing deployments

#### Bicep-Based Multi-VM Deployment
**Priority**: Low
**Status**: 🆕 **NEW**

**Description**: Investigate using Azure Bicep templates to deploy multiple VMs simultaneously with individual cloud-init configurations in a single API call.

**Current Approach**: Sequential VM creation with individual `az vm create` calls
- Each VM created separately with its own API call
- Background processes track individual VM creation PIDs
- Multiple API calls increase deployment time and complexity

**Proposed Investigation**: Bicep template for parallel VM deployment
- **Single deployment call**: Use `az deployment group create` with Bicep template
- **Parallel VM creation**: Azure Resource Manager handles parallel provisioning
- **Individual cloud-init**: Each VM gets unique cloud-init configuration
- **Atomic deployment**: All-or-nothing deployment with rollback capability
- **Resource dependencies**: Proper dependency management within template

**Research Areas**:
- Bicep template structure for multiple VMs with different configurations
- Cloud-init parameter passing to individual VMs in template
- Deployment monitoring and status checking
- Error handling and rollback scenarios
- Integration with existing state management
- Performance comparison with current approach

**Potential Benefits**:
- Faster deployment through true parallelization
- Atomic deployments with built-in rollback
- Reduced API calls and complexity
- Better resource dependency management
- Native Azure tooling integration

**Technical Challenges**:
- Template complexity for different VM configurations
- Cloud-init file management and parameter passing
- State tracking integration with existing scripts
- Error handling and recovery logic adaptation
- Learning curve for Bicep template development

**Success Criteria**:
- Deployment time reduction compared to current approach
- Maintains all current functionality (zones, sizes, cloud-init)
- Integrates with existing state management
- Provides equivalent or better error handling

#### Configuration Management Enhancements
**Priority**: Low

- **Environment Variable Override System**: Allow env vars to override YAML config
- **Configurable Config File Location**: Support custom config file paths
- **Configuration Profiles**: Multiple named configurations per project
- **Configuration Diff and Merge**: Tools to compare and merge configurations
- **YAML Schema for IDE Support**: Autocomplete and validation in editors

#### Integration and Workflow Enhancements
**Priority**: Low

- **CI/CD Pipeline Integration**: Support for automated deployments
- **Configuration Testing Framework**: Dry-run and validation testing

#### Dependency Consolidation
**Priority**: Low

- **Swap out usage of jq everywhere for yq**: Replace jq with yq to reduce dependencies since yq can handle both YAML and JSON

#### Improve print_usage Function
**Priority**: Low
**Status**: 🆕 **NEW**

**Description**: The print_usage function in common-functions.sh needs refactoring for better readability and maintainability.

**Current Issues**:
- Function is "fugly" and hard to read
- Complex string concatenation makes it difficult to maintain
- Inconsistent formatting across different scripts
- Hard to add new options or modify existing ones

**Improvement Ideas**:
- Use heredoc syntax for cleaner multi-line output
- Implement consistent formatting patterns
- Add color coding for different sections (commands, options, examples)
- Create reusable templates for common usage patterns
- Consider using arrays for building option lists
- Add automatic width detection for better terminal display

**Example Refactor Approach**:
```bash
print_usage() {
    cat << EOF
$(print_bold "Usage:") $1 [COMMAND] [OPTIONS]

$(print_bold "Commands:")
$(print_command_list "$2")

$(print_bold "Options:")
$(print_option_list "$3")

$(print_bold "Examples:")
$(print_example_list "$4")
EOF
}
```

**Benefits**:
- Easier to read and maintain
- Consistent help output across all scripts
- Better user experience with formatted output
- Simpler to add new commands/options
- Reusable formatting functions

**Implementation Tasks**:
- Analyze current print_usage implementations
- Design consistent formatting approach
- Create helper functions for formatting
- Update all scripts to use new approach
- Test across different terminal widths

#### Reorganize Kubeconfig Storage Location
**Priority**: Low
**Status**: 🆕 **NEW**

**Description**: Move kubeconfig files from `k0sctl-config/` directory to a dedicated `kubeconfig/` directory for better organization and clarity.

**Current Structure**:
```
k0sctl-config/
├── k0rdent-xxx-kubeconfig          # Management cluster
├── kof-regional-xxx-kubeconfig     # Regional clusters  
├── k0rdent-xxx-k0sctl.yaml         # k0sctl config file
└── other-cluster-kubeconfig         # Child clusters
```

**Proposed Structure**:
```
k0sctl-config/
└── k0rdent-xxx-k0sctl.yaml         # Only k0sctl config files

kubeconfig/
├── k0rdent-xxx-kubeconfig          # Management cluster
├── kof-regional-xxx-kubeconfig     # Regional clusters
└── other-cluster-kubeconfig         # Child clusters
```

**Benefits**:
- Clear separation of concerns (k0sctl configs vs kubeconfigs)
- Easier to manage and find kubeconfig files
- Better organization as number of clusters grows
- Cleaner directory structure
- More intuitive for users

**Implementation Requirements**:
- Create new `kubeconfig/` directory
- Update all scripts to use new location:
  - `install-k0s.sh` - Management cluster kubeconfig
  - `install-kof-regional.sh` - Regional cluster kubeconfig
  - `create-child.sh` - Child cluster kubeconfigs
  - Any other scripts that retrieve kubeconfigs
- Update `.gitignore` to include `kubeconfig/`
- Update documentation references
- Consider backward compatibility (symlinks during transition)

**Migration Strategy**:
1. Update scripts to check both locations (backward compatibility)
2. Create new directory structure
3. Move existing kubeconfigs on next retrieval
4. Update documentation
5. Remove backward compatibility after transition period

**Files to Update**:
- All scripts that reference `K0SCTL_DIR/*-kubeconfig`
- `KUBECONFIG-RETRIEVAL.md` documentation
- `CLAUDE.md` technical notes
- README examples
- State management if it tracks kubeconfig locations

#### Evaluate Nushell for Bash Script Rewrites
**Priority**: Low
**Status**: 🆕 **NEW**

**Description**: Evaluate the impact and benefits of rewriting some bash scripts in Nushell for improved maintainability and error handling.

**Areas to Investigate**:
- **Type Safety**: Nushell's structured data approach could reduce parsing errors
- **Error Handling**: Built-in error propagation vs bash's manual error checking
- **Cross-Platform Support**: Better Windows compatibility if needed in future
- **Performance**: Potential performance improvements for data processing tasks
- **Maintainability**: More readable code with structured data pipelines

**Candidate Scripts for Rewrite**:
- Configuration parsing and validation scripts
- Scripts with heavy JSON/YAML manipulation
- Data transformation and reporting utilities
- Scripts with complex error handling requirements

**Evaluation Criteria**:
- Learning curve for team members
- Nushell availability in deployment environments
- Integration with existing bash scripts
- Performance benchmarks vs current implementations
- Debugging and troubleshooting capabilities

**Considerations**:
- Would require adding Nushell as a dependency
- Team familiarity with Nushell syntax
- Potential for hybrid approach (keep critical path in bash)
- Cost/benefit analysis for each script conversion

#### direnv Integration for Environment Management
**Priority**: Low
**Status**: Optional - Needs exploration and planning

**Description**: Add support for direnv to enable automatic environment variable loading based on project directory context, supporting the "cattle not pets" methodology for cluster management.

**Potential Benefits**:
- Automatic KUBECONFIG switching when entering project directories
- Environment-specific variable isolation (dev/staging/prod clusters)
- Seamless integration with multi-cluster workflow
- Auto-loading of deployment state file paths per environment
- Natural support for multiple k0rdent deployments

**Planning Required**:
- **Environment Variable Strategy**: Determine which variables should be direnv-managed vs script-managed
- **Configuration File Integration**: How direnv variables interact with YAML configuration system
- **State File Isolation**: Directory structure for multiple environment state files
- **KUBECONFIG Management**: Automatic switching vs manual control preferences
- **Deployment Script Compatibility**: Ensure existing scripts work with direnv-loaded variables
- **Documentation**: Clear setup instructions and workflow examples

**Technical Considerations**:
- Integration with existing `etc/k0rdent-config.sh` configuration loading
- Potential conflicts between .envrc variables and YAML configuration
- Directory structure recommendations for multi-environment setups
- Backwards compatibility with current single-environment workflow

**Dependencies**: May overlap with Multi-Cluster Environment Management future enhancement

#### Azure VM Launch Manager with NATS Communication
**Priority**: Low
**Status**: 🆕 **NEW**

**Description**: Create a plan for an Azure VM launch manager script that uses NATS messaging to communicate state and issues back to the main loop that creates Azure VMs.

**Current Architecture**:
- Background processes track individual VM creation PIDs
- Monitoring loop polls Azure API for VM states
- File-based state tracking via deployment-state.yaml

**Proposed Architecture**:
- **NATS Message Broker**: Central communication hub for VM creation events
- **VM Launch Workers**: Separate processes that handle VM creation and report via NATS
- **Main Orchestrator**: Subscribes to NATS topics for real-time state updates
- **Event-Driven Updates**: Replace polling with push-based status updates

**Benefits**:
- **Real-time Status**: Immediate notification of VM state changes
- **Reduced API Calls**: Workers push updates instead of constant polling
- **Better Scalability**: Can spawn multiple workers for parallel VM creation
- **Cleaner Architecture**: Decoupled components communicate via messages
- **Enhanced Debugging**: Message history provides audit trail

**Implementation Components**:
1. **NATS Server Setup**:
   - Local NATS server or container
   - Topic structure for VM events
   - Message schemas for state updates

2. **VM Launch Worker Script**:
   - Subscribes to VM creation requests
   - Executes `az vm create` commands
   - Publishes status updates to NATS
   - Handles retry logic independently

3. **Main Orchestrator Updates**:
   - Publishes VM creation requests to NATS
   - Subscribes to status update topics
   - Updates deployment-state.yaml based on messages
   - Coordinates overall deployment flow

**Technical Considerations**:
- NATS as additional dependency
- Message persistence requirements
- Error handling and dead letter queues
- Integration with existing state management
- Backward compatibility with current approach

**Message Topics Structure**:
- `vm.create.request` - VM creation requests
- `vm.create.status` - Status updates from workers
- `vm.create.complete` - Successful VM creation
- `vm.create.failed` - VM creation failures
- `vm.ssh.verified` - SSH connectivity confirmed
- `vm.cloudinit.complete` - Cloud-init finished

**Future Extensions**:
- Use NATS for other async operations
- Implement distributed tracing
- Add metrics collection via NATS
- Enable remote monitoring capabilities

#### Extract KOF Deployment Logic into deploy-kof-stack.sh
**Priority**: Low
**Status**: 🆕 **NEW**

**Description**: Extract the KOF deployment logic currently embedded in deploy-k0rdent.sh into a dedicated deploy-kof-stack.sh script for better modularity and maintainability.

**Current Situation**:
- KOF deployment is handled by deploy-k0rdent.sh with the `--with-kof` flag
- Logic is embedded within the main orchestration script
- Works well for current needs but could be more modular

**Future Enhancement**:
- Create `bin/deploy-kof-stack.sh` that orchestrates full KOF deployment
- Move KOF-specific logic from deploy-k0rdent.sh
- Maintain backward compatibility with `--with-kof` flag
- Provide standalone KOF deployment capability

**Benefits**:
- Better separation of concerns
- Easier to maintain KOF-specific logic
- Allows independent KOF deployment/updates
- Cleaner main deployment script

**Implementation Approach**:
1. Extract KOF deployment steps from deploy-k0rdent.sh
2. Create orchestration script that calls existing KOF scripts in order
3. Support partial deployments (mothership only, regional only, etc.)
4. Include rollback capabilities
5. Maintain integration with main deployment flow

## KOF Testing and Validation

### KOF End-to-End Deployment Validation
**Priority**: Medium
**Status**: 🆕 **NEW**

**Description**: Comprehensive testing of the complete KOF deployment flow from mothership to child clusters.

**Test Scenarios**:
1. **Fresh Deployment**: Complete KOF stack on new k0rdent cluster
2. **Incremental Deployment**: Add KOF to existing k0rdent cluster
3. **Multi-Child Testing**: Deploy KOF across multiple child clusters
4. **Failure Recovery**: Test deployment recovery from various failure points
5. **Uninstall/Reinstall**: Clean removal and redeployment

**Validation Points**:
- Istio service mesh properly configured
- KOF operators running and healthy
- ClusterProfiles correctly applied
- Metrics collection functioning
- Cross-cluster communication working
- Resource cleanup on uninstall

### KOF Multi-Child Cluster Testing
**Priority**: Medium
**Status**: 🆕 **NEW**

**Description**: Test KOF functionality across multiple child clusters to ensure proper scaling and federation.

**Test Cases**:
1. **Multiple Children per Regional**: Deploy 3-5 child clusters under one regional
2. **Cross-Cluster Metrics**: Verify metrics flow from all children to regional
3. **Label Management**: Test proper labeling and ClusterProfile application
4. **Resource Isolation**: Ensure child clusters are properly isolated
5. **Concurrent Deployments**: Deploy multiple children simultaneously

**Success Criteria**:
- All child clusters receive KOF components
- Metrics aggregation works correctly
- No resource conflicts between children
- Proper namespace isolation maintained
- Observability data flows correctly

### KOF Observability Data Flow Verification
**Priority**: Medium
**Status**: 🆕 **NEW**

**Description**: Verify that observability data (metrics, logs, traces) flows correctly through the KOF stack.

**Verification Steps**:
1. **Metrics Pipeline**: Test Prometheus/VictoriaMetrics data flow
2. **Log Aggregation**: Verify log collection and forwarding
3. **Trace Collection**: Test distributed tracing if configured
4. **Data Retention**: Verify storage and retention policies
5. **Query Performance**: Test Grafana dashboard responsiveness

**Test Scenarios**:
- Generate test metrics from child clusters
- Verify data appears in regional cluster storage
- Test data retention and cleanup
- Validate dashboard functionality
- Check alerting pipeline if configured

## KOF Nice-to-Have Features

### Custom Collector Configurations
**Priority**: Low
**Status**: 🆕 **NEW**

**Description**: Support for custom metric collectors and exporters in KOF deployments.

**Features**:
- Custom Prometheus scrape configurations
- Additional exporter deployments
- Custom dashboard templates
- Alert rule customization
- Log parsing rules

**Implementation Ideas**:
- ConfigMap-based collector definitions
- Helm values overlay support
- Dynamic scrape target discovery
- Custom dashboard provisioning
- Alert routing configuration

### Multi-Regional KOF Deployment Support
**Priority**: Low
**Status**: 🆕 **NEW**

**Description**: Support for deploying KOF across multiple Azure regions with proper federation.

**Capabilities**:
- Deploy regional clusters in different Azure regions
- Cross-region metrics federation
- Global dashboard views
- Region-specific resource optimization
- Disaster recovery considerations

**Technical Challenges**:
- Cross-region networking
- Data sovereignty compliance
- Latency optimization
- Cost management
- Federation complexity

### KOF Backup and Restore Capabilities
**Priority**: Low
**Status**: 🆕 **NEW**

**Description**: Implement backup and restore functionality for KOF configuration and data.

**Backup Scope**:
- KOF configuration (ClusterProfiles, etc.)
- Grafana dashboards and settings
- Alert rules and configurations
- Historical metrics data (optional)
- Istio configurations

**Features**:
- Scheduled configuration backups
- On-demand backup capability
- Point-in-time restore
- Selective component restore
- Backup validation testing

**Implementation Approach**:
- Kubernetes resource backup (Velero integration?)
- Persistent volume snapshots
- Configuration export/import tools
- Automated backup testing
- Restore runbooks

## Future Ideas

### Multi-Cluster Environment Management
**Priority**: Future Enhancement
**Description**: Support multi-cluster deployments and switching between different cluster "environments" similar to Python venv

**Concept**:
- Allow users to maintain multiple isolated k0rdent clusters (dev, staging, prod, etc.)
- Provide commands to switch active cluster context
- Manage separate state files, configurations, and WireGuard networks per environment
- Enable easy switching between clusters without conflicts

**Technical Challenges** (NEEDS TO BE DISCUSSED WITH THE DEVELOPER):
- **WireGuard Network Isolation**: Each cluster MAY need separate WireGuard network ranges to avoid IP conflicts
- **State Management**: Multiple deployment-state.yaml files (one per environment)
- **Configuration Isolation**: Separate config files and SSH keys per environment
- **VPN Management**: Switch between different WireGuard configurations
- **Resource Naming**: Ensure Azure resource names don't conflict between environments

**Potential Commands**:
```bash
./bin/k0rdent-env create dev --config config/dev.yaml
./bin/k0rdent-env switch prod
./bin/k0rdent-env list
./bin/k0rdent-env delete staging
```

**Dependencies**:
- Requires detailed planning phase
- May break current working assumptions about WireGuard networking
- Needs thorough testing of network isolation
- Consider impact on current single-cluster workflow

**Benefits**:
- Enable proper dev/staging/prod separation
- Allow experimentation without affecting production clusters
- Support team workflows with isolated environments
- Simplify cluster lifecycle management

### State Management Migration to Key-Value Store
**Priority**: Future Enhancement
**Status**: 🆕 **NEW**

**Description**: Migrate from file-based state management (YAML files in `state/` directory) to a proper key-value store for better scalability, performance, and multi-instance support.

**Current State Management Limitations**:
- **File-based storage**: State stored in local YAML files under `state/` directory
- **Single instance**: No support for concurrent operations or shared state
- **Performance**: Multiple file I/O operations for state updates
- **Backup complexity**: Manual backup to `old_deployments/` directory
- **No locking**: Potential race conditions with concurrent script execution
- **Local only**: State not available across different systems

**Proposed Key-Value Store Options**:
1. **Redis** - Fast, lightweight, with persistence options
2. **etcd** - Kubernetes-native, strong consistency, watch capabilities
3. **Consul** - Service discovery integration, strong consistency
4. **Local SQLite** - Simple embedded database with SQL capabilities

**Technical Considerations**:
- **Backward compatibility**: Support reading existing YAML state files during migration
- **Connection management**: Handle KV store unavailability gracefully
- **State structure**: Maintain hierarchical key structure (deployment.phase, kof.mothership_installed, etc.)
- **Atomic operations**: Ensure state consistency during updates
- **Watch/notification**: Real-time state change notifications for monitoring

**Implementation Approach**:
- **Phase 1**: Abstract state management behind interface layer
- **Phase 2**: Implement KV store backend with YAML fallback
- **Phase 3**: Migration utilities for existing deployments
- **Phase 4**: Deprecate file-based storage

**Benefits**:
- **Shared state**: Multiple instances can share deployment state
- **Performance**: Faster state access and updates
- **Atomic operations**: Guaranteed state consistency
- **Real-time monitoring**: Watch for state changes
- **Distributed deployments**: Support for remote state management
- **Better concurrency**: Handle multiple operations safely

**Use Cases**:
- **Multi-cluster management**: Centralized state for multiple k0rdent deployments
- **Team workflows**: Shared state across team members
- **CI/CD integration**: Pipeline access to deployment state
- **Monitoring dashboards**: Real-time deployment status
- **Disaster recovery**: Persistent state backup and restoration

**Configuration Integration**:
- Add KV store configuration to existing YAML config files
- Support multiple backend types with automatic fallback
- Maintain existing API compatibility for scripts

**Example Configuration**:
```yaml
state_management:
  backend: "redis"  # redis, etcd, consul, file
  redis:
    host: "localhost"
    port: 6379
    database: 0
    password: ""
  fallback: "file"  # Always fall back to file-based storage
```

**Migration Path**:
- Existing deployments continue using file-based storage
- New deployments can opt-in to KV store backend
- Migration tool to move existing state to KV store
- Gradual deprecation of file-based storage

**Dependencies**:
- Requires KV store infrastructure setup
- Network connectivity for remote KV stores
- Backup strategy for KV store data
- Monitoring for KV store health

**Priority Justification**: Future enhancement that becomes important as the system scales to multiple clusters, teams, or automated deployments. Not critical for current single-cluster workflows but valuable for operational maturity.

## Completed Items

Completed items have been moved to `notebooks/completed/BACKLOG-COMPLETED.md`

_Add other backlog items here as they come up during development..._