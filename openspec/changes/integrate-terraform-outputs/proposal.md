# Change: Integrate Terraform Outputs with Bash Orchestration

## Why

After migrating infrastructure to Terraform, bash orchestration scripts (prepare-deployment.sh, manage-vpn.sh, install-k0s.sh, install-k0rdent.sh) need to consume infrastructure data. Current scripts query Azure/AWS APIs directly or read from deployment-state.yaml populated by bash scripts.

With Terraform managing infrastructure, scripts must:
- Read VM/instance IPs from Terraform outputs instead of API queries
- Use Terraform-tracked resource names for SSH connections and WireGuard config
- Detect whether Terraform or legacy bash created infrastructure
- Maintain existing orchestration logic with minimal changes

## What Changes

Update bash scripts to consume Terraform outputs transparently:

**State Management Functions (etc/state-management.sh)**:
- Add `get_terraform_output(key)` function to read outputs from state
- Update `get_vm_info()` to prefer Terraform outputs over Azure CLI
- Add `terraform_state_exists()` predicate for conditional logic
- Implement `sync_terraform_to_state()` to copy outputs → deployment-state.yaml

**Orchestration Scripts**:
- `bin/prepare-deployment.sh`: Generate cloud-init, validate Terraform outputs available
- `bin/manage-vpn.sh`: Read VM IPs from Terraform or fallback to state/API
- `bin/install-k0s.sh`: Build k0sctl inventory from Terraform outputs
- `bin/install-k0rdent.sh`: Use kubeconfig from k0s (no change needed)

**Deploy Script (deploy-k0rdent.sh)**:
- Call `terraform-wrapper.sh apply` before orchestration phase
- Pass `--skip-terraform` flag to use pre-existing infrastructure
- Add `--terraform-only` flag to provision infrastructure without software

## Impact

- **Affected code**:
  - `etc/state-management.sh` - adds Terraform output reading
  - `bin/prepare-deployment.sh` - validates Terraform outputs before proceeding
  - `bin/manage-vpn.sh` - uses `get_vm_info()` which now reads Terraform first
  - `bin/install-k0s.sh` - builds inventory from state (already abstracted)
  - `deploy-k0rdent.sh` - orchestrates Terraform + bash workflow
- **Affected specs**: Creates `deployment-orchestration`, `script-integration` capabilities
- **Backward compatible**: Scripts detect Terraform availability and fallback to legacy behavior
- **Multi-cloud**: Works for both Azure and AWS once respective modules exist

## Benefits

- **Single source of truth**: Terraform state is authoritative for infrastructure
- **Reduced API calls**: Bash scripts read cached Terraform outputs instead of querying APIs
- **Consistent workflow**: Same orchestration scripts work with Terraform or legacy bash
- **Error detection**: Scripts can validate Terraform outputs before proceeding with configuration

## Risks & Mitigations

- **Output schema changes**: Pin Terraform output structure; version modules to prevent breaking changes
- **State sync delays**: terraform-wrapper.sh must refresh outputs immediately after apply
- **Fallback complexity**: get_vm_info() has layered fallback logic (Terraform → state → API) which must be well-tested
