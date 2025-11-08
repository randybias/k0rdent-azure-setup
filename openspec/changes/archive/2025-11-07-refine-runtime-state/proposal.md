# Proposal: Refine Runtime State Management

## Summary
Rework the bespoke YAML state so it cleanly distinguishes infrastructure data (now owned by Terraform) from runtime deployment records, preventing optional subsystems (e.g., KOF) from leaking stale status into new runs.

## Motivation
- Current `deployment-state.yaml` mixes infrastructure facts, WireGuard data, phase marks, and per-run flags, leading to confusing warnings (“KOF regional install marked complete…”) when phases don’t apply.
- Multiple runs append to the same file; there is no run identifier, so audit and troubleshooting are difficult.
- As we shift infrastructure to Terraform, the remaining state should focus on runtime orchestration (WireGuard/k0s/k0rdent) and support clean resume/rollback semantics.

## Goals
- Introduce a runtime state model that records each deployment attempt separately (runs with timestamps, flags, and outcomes).
- Remove optional phase noise by rescoping phases to only the components requested for the current run.
- Provide a reconciliation step that checks actual resources (VM reachability, VPN status) against recorded state before proceeding.
- Offer operators an easy way to inspect recent runs.

## Non-Goals
- Implement Terraform remote state (handled by the Terraform migration proposal).
- Change WireGuard/k0s/k0rdent logic beyond the state-handling boundaries.

## Risks & Mitigations
- **Backwards compatibility**: Provide migration logic that archives the old `deployment-state.yaml` format and creates a new structure transparently.
- **Operator workflow changes**: Document how to inspect runs (new CLI command/flag) so existing workflows aren’t disrupted.
