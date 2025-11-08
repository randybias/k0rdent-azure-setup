# Design: Refine Runtime State Management

## Problems Identified
1. **Single-file monolithic state** mixes infrastructure, runtime status, and history. Optional components (KOF, Azure children) linger as `completed` phases.
2. **No per-run context**: when a deployment is interrupted, we can’t tell which events belonged to which execution.
3. **Resume logic is noisy**: the orchestrator emits warnings when flags change between runs because stale phase status persists.

## Proposed Structure
- Replace `deployment-state.yaml` with two layers:
  1. `state/runtime.yaml` — holds the latest runtime snapshot (WireGuard peers, VPN status, current run ID, references to Terraform outputs).
  2. `state/runs/<run-id>.yaml` — append-only records for each deployment attempt, containing:
     - Run metadata (timestamp, operator, flags like `with_kof`)
     - Phase transitions and events (similar to today’s `deployment-events.yaml` but scoped to one run)
     - Outcome (`succeeded`, `failed`, `cancelled`)
- Deprecate `deployment-events.yaml`; instead, write per-run events next to the run file.

## Runtime Flow Changes
1. **Run Start**
   - Generate a new run ID (`YYYYMMDD-HHMMSS` or UUID).
   - Create `state/runs/<run-id>.yaml` with initial metadata.
   - Update `state/runtime.yaml` to set `current_run_id` and copy relevant flags.
   - Reconcile optional components: if `WITH_KOF` is false, do not carry forward KOF phases into the new run.
2. **Phase updates**
   - `phase_mark_*` becomes run-scoped, writing to the run file.
   - The runtime snapshot keeps only currently relevant booleans (VPN connected, kubeconfig path, etc.).
3. **Run Completion**
   - Mark outcome in the run file.
   - Update `state/runtime.yaml` with a summary (e.g., `last_successful_run`).
4. **Resume Logic**
   - Check `state/runtime.yaml`; if `current_run_id` exists and last outcome isn’t success, offer to resume that run or start a fresh one (archiving the incomplete run).

## CLI Enhancements
- Add `deploy-k0rdent.sh runs` (or `status --history`) to list recent runs from `state/runs/` with status and flags.
- Adjust `status` to read from the new files.

## Migration Strategy
- On first run after upgrade:
  - Archive existing `deployment-state.yaml` / `deployment-events.yaml` under `state/legacy/` for reference.
  - Seed `state/runtime.yaml` with minimal snapshot (WireGuard peers, VPN status) if present.
  - Create a run file summarising the legacy events (optional best-effort).

## Reconciliation Check
- Before proceeding with phases that assume infrastructure (e.g., k0s install), verify that required Terraform outputs or VM info exist and that the VPN is reachable. If not, prompt user to re-run Terraform or reset state.
