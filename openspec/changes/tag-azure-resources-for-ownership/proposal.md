# Tag Azure Resources for Ownership Identification

## Problem Statement

When multiple team members use this tool within the same Azure subscription, they cannot easily identify which k0rdent clusters belong to whom when viewing resources in the Azure portal. This creates confusion about resource ownership and makes cleanup difficult.

## Proposed Solution

### Part 1: Azure Resource Tagging

Add Azure resource tags to the resource group to identify:
1. **Owner** - Who created the cluster (user@hostname or git email)
2. **Created by tool** - That this resource was created by k0rdent-azure-setup
3. **Cluster ID** - The k0rdent cluster ID
4. **Creation timestamp** - When the resource was created

Azure supports tags on resource groups via the `--tags` parameter in `az group create`:
```bash
az group create --name "$RG" --location "$AZURE_LOCATION" \
    --tags owner="$OWNER" created-by="k0rdent-azure-setup" cluster-id="$K0RDENT_CLUSTERID" created="$TIMESTAMP"
```

Note: VMs inherit ownership from the resource group, so only the resource group needs tagging.

### Part 2: Local Deployment History

Add a deployment history index file:

**deployment-history.yaml format:**
```yaml
deployments:
  - cluster_id: "k0rdent-abc123"
    deployed_at: "2025-12-02T10:30:00Z"
    config_file: "config/k0rdent-baseline-westeu.yaml"
    deployer: "rbias@macbook"
  - cluster_id: "k0rdent-xyz789"
    deployed_at: "2025-12-01T15:45:00Z"
    config_file: "config/k0rdent-default.yaml"
    deployer: "alice@workstation"
```

## Implementation Approach

### 1. Deployer Identity Detection
Auto-detect deployer identity with this fallback chain:
1. `metadata.owner` from YAML config (if explicitly set)
2. `git config user.email` (if available)
3. `$USER@$(hostname -s)` (username + short hostname)
4. `$(whoami)@$(hostname -s)` (fallback)
5. `unknown` (final fallback)

### 2. Resource Group Tagging
Modify `bin/setup-azure-network.sh` to add tags when creating the resource group.

### 3. Deployment History Tracking
- On each deployment, append entry to `old_deployments/deployment-history.yaml`
- Add `./deploy-k0rdent.sh history` command to view deployment history

## Benefits

1. **Easy identification** - Filter resources by owner in Azure portal
2. **Team coordination** - Know which clusters belong to teammates
3. **Cost attribution** - Track costs by owner using Azure Cost Management
4. **Cleanup safety** - Avoid accidentally deleting someone else's resources
5. **Audit trail** - Know when and by whom resources were created
6. **Simple index** - Quick lookup of all deployments in one file

## Affected Components

- `config/k0rdent-default.yaml` - Add `metadata.owner` field documentation
- `etc/common-functions.sh` - Add `get_deployer_identity()` and `sanitize_tag_value()` functions
- `etc/state-management.sh` - Add `record_deployment_history()` and `show_deployment_history()` functions
- `bin/setup-azure-network.sh` - Add tags to resource group creation
- `deploy-k0rdent.sh` - Record deployment in history, add `history` command

## Success Criteria

- [x] Resource groups show owner tag in Azure portal
- [x] Deployer identity auto-detected as `user@hostname` or git email
- [x] Tags visible when filtering resources in Azure
- [x] `deployment-history.yaml` updated on each deployment
- [x] `./deploy-k0rdent.sh history` shows past deployments
