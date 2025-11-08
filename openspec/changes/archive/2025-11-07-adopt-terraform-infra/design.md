# Design: Adopt Terraform for Azure Infrastructure

## Current Flow
1. `deploy-k0rdent.sh deploy` calls bash scripts to:
   - Validate config.
   - Provision the resource group, VNet, subnet, NSG, SSH key (Azure CLI).
   - Create controller/worker VMs (Azure CLI) and wait for cloud-init.
   - Generate WireGuard artifacts, connect VPN.
   - Run k0sctl/Helm to install k0s and k0rdent.
2. Infrastructure details are written into `deployment-state.yaml` alongside runtime status.

## Target Architecture
- **Terraform Root Module**: Owns Azure RG, network components, and computes WireGuard port + VM metadata.
- **Terraform Submodules**:
  - `modules/network`: VNet, subnet, NSG, rules.
  - `modules/linux-vm`: Parameterised module capable of controller/worker roles (size, priority, zone, cloud-init).
- **Inputs**: Derived from `config/k0rdent.yaml` (location, counts, VM sizes, spot flag, WireGuard CIDR).
  - Provide helper to render tfvars (`./bin/configure.sh export` ➔ JSON ➔ tfvars) or document manual mapping.
- **Outputs**: Resource group name, VNet/subnet names, VM hostnames, private/public IPs, WireGuard port.
- **State Backend**: Local state by default, with documented steps to configure remote backend (Azure Storage) for teams.

## Workflow Integration
1. Operator runs `terraform init`/`terraform apply` at `infrastructure/terraform/` (new directory).
2. Terraform writes `terraform.tfstate` and outputs; we capture outputs in JSON (`terraform output -json`).
3. New `./deploy-k0rdent.sh bootstrap` (or `deploy --from-terraform`) drives the existing bash flow, but skips Azure CLI provisioning and instead consumes the Terraform outputs for IPs, hostnames, and WireGuard port.
4. Existing scripts (`bin/prepare-deployment.sh`, `bin/manage-vpn.sh`, etc.) accept the Terraform-derived values and continue unchanged for WireGuard/k0s/k0rdent.

## Data Flow
```
config/k0rdent.yaml --> configure.sh export --> tfvars / env vars --> Terraform
Terraform state --> terraform output -json --> deploy-k0rdent.sh bootstrap --> runtime scripts
```

## Open Questions
- Should we generate tfvars automatically or require operators to maintain one? (Initial plan: CLI helper to produce tfvars, but allow manual override.)
- Do we default to remote backend with locking, or document it as a follow-up step? (Start with local backend; mention remote backend setup in docs.)

## Alternatives Considered
- Rewriting entire workflow in Terraform (including k0s/k0rdent) via provisioners: rejected due to poor retry/observability and Terraform’s guidance against long imperative steps.
- Keeping Azure CLI and only using Terraform for drift detection: rejected—duplicative effort and still lacks terraform state benefits.
