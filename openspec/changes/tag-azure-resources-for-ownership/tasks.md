# Tasks: Tag Azure Resources for Ownership Identification

## Phase 1: Deployer Identity Detection

### Task 1.1: Implement get_deployer_identity function
- [x] Add `get_deployer_identity()` function to `etc/common-functions.sh`
- [x] Check for `metadata.owner` in CONFIG_YAML first
- [x] Fall back to `git config user.email` if not configured
- [x] Fall back to `$USER@$(hostname -s)` (short hostname, no domain)
- [x] Fall back to `$(whoami)@$(hostname -s)`
- [x] Use "unknown" as final fallback
- [x] Export result as `DEPLOYER_IDENTITY` variable

### Task 1.2: Add owner configuration support
- [x] Document `metadata.owner` field in `config/k0rdent-default.yaml` comments
- [x] Ensure yq can read the optional field without errors

## Phase 2: Azure Resource Tagging

### Task 2.1: Modify resource group creation
- [x] Update `bin/setup-azure-network.sh` to call `get_deployer_identity`
- [x] Add `--tags` parameter to `az group create` command
- [x] Include tags: `owner`, `created-by`, `cluster-id`, `created`
- [x] Format timestamp as ISO 8601 UTC

### Task 2.2: Sanitize tag values for Azure
- [x] Add `sanitize_tag_value()` function to escape special characters
- [x] Truncate values exceeding 256 characters (Azure limit)

### Task 2.3: Record deployer in deployment state
- [x] Add `deployer` field to deployment state when deployment starts

## Phase 3: Deployment History Tracking

### Task 3.1: Create deployment history recording function
- [x] Add `record_deployment_history()` function to `etc/state-management.sh`
- [x] Create/append to `old_deployments/deployment-history.yaml`
- [x] Record: `cluster_id`, `deployed_at`, `config_file`, `deployer`
- [x] Use ISO 8601 UTC timestamp format

### Task 3.2: Integrate history recording into deployment
- [x] Call `record_deployment_history()` at deployment start in `deploy-k0rdent.sh`
- [x] Pass cluster ID, config file path, and deployer identity

### Task 3.3: Add history lookup command
- [x] Add `history` subcommand to `deploy-k0rdent.sh`
- [x] Add `show_deployment_history()` function to `etc/state-management.sh`
- [x] Display recent deployments with cluster ID, date, deployer

## Implementation Summary

**Files modified:**
- `etc/common-functions.sh` - Added `get_deployer_identity()` and `sanitize_tag_value()` functions
- `etc/state-management.sh` - Added `record_deployment_history()` and `show_deployment_history()` functions, plus deployer field in state init
- `bin/setup-azure-network.sh` - Added Azure resource group tagging with 4 tags
- `deploy-k0rdent.sh` - Added history recording on deploy + `history` command
- `config/k0rdent-default.yaml` - Added `metadata.owner` documentation

**Not implemented (by design):**
- VM tagging - Not needed since VMs inherit ownership from resource group
- Old deployments directory reorganization - Existing structure is sufficient
