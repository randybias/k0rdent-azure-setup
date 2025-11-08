# Proposal: Adopt Terraform for Azure Infrastructure

## Summary
Introduce Terraform as the authoritative way to provision the Azure resource group, network stack, and controller/worker virtual machines. The existing bash tooling will consume Terraform outputs rather than invoking Azure CLI for infrastructure, leaving WireGuard, k0s, k0rdent, and KOF installation logic in bash.

## Motivation
- Azure CLI scripts are growing complex (spot retries, VM size validation) and duplicate configuration that could live in declarative IaC.
- Current YAML state tracking mixes infrastructure and runtime status, making resume/rollback noisy (e.g., KOF warnings).
- Terraform provides proven state management, locking, drift detection, and reusability with minimal reinvention.

## Goals
- Deliver Terraform modules matching today’s Azure footprint (RG, VNet, NSG, controller/worker VMs with cloud-init).
- Map the existing `config/k0rdent.yaml` inputs into Terraform variables (directly or via generated tfvars).
- Expose Terraform outputs that existing scripts can read to continue WireGuard/k0s/k0rdent orchestration.
- Update documentation and bootstrap workflow to show the new flow (`terraform apply` ➔ `deploy-k0rdent.sh bootstrap`).

## Non-Goals
- Rewriting WireGuard, k0s, or k0rdent installation in Terraform.
- Removing the current bash path immediately; we can keep a transition flag so operators can opt in.
- Solving runtime state reorganisation (handled by a separate proposal).

## Risks & Mitigations
- **Terraform complexity**: Keep modules small, start with core network + VM creation, reuse existing cloud-init files.
- **Secrets in state**: Ensure private keys and WireGuard secrets stay in bash workflow; Terraform only stores public references.
- **Operational shift**: Provide clear docs and defaults so infra-only users can adopt Terraform without breaking legacy scripts.
