#!/usr/bin/env bash

# Simple smoke test for state phase helpers introduced in the resume/rollback work.
# Runs entirely in a scratch directory to avoid touching real state.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${ROOT_DIR}/tests/tmp-state-XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT

pushd "${WORK_DIR}" >/dev/null

# Minimal configuration variables required by state-management helpers
export AZURE_LOCATION="test-location"
export K0S_CONTROLLER_COUNT=1
export K0S_WORKER_COUNT=1
export WG_NETWORK="172.24.24.0/24"

# Shared formatting helpers
source "${ROOT_DIR}/etc/common-functions.sh"
source "${ROOT_DIR}/etc/state-management.sh"

echo "▶ Initialising deployment state in ${STATE_DIR}"
init_deployment_state "k0rdent-smoke"

echo "▶ Verifying initial phase status"
if ! phase_needs_run "prepare_deployment"; then
    echo "ERROR: prepare_deployment should require execution on fresh state" >&2
    exit 1
fi

echo "▶ Marking prepare_deployment as in-progress and completed"
phase_mark_in_progress "prepare_deployment"
phase_mark_completed "prepare_deployment"

if phase_needs_run "prepare_deployment"; then
    echo "ERROR: prepare_deployment should be marked completed" >&2
    exit 1
fi

echo "▶ Recording an artifact and validating existence check"
touch "${WORK_DIR}/dummy-artifact.txt"
record_artifact "dummy" "${WORK_DIR}/dummy-artifact.txt"
if ! artifact_exists "dummy"; then
    echo "ERROR: artifact registry did not capture dummy artifact" >&2
    exit 1
fi

echo "▶ Resetting from setup_network and ensuring downstream phases pending"
phase_mark_completed "setup_network"
phase_reset_from "setup_network"

if ! phase_needs_run "setup_network"; then
    echo "ERROR: setup_network should have been reset to pending" >&2
    exit 1
fi

if ! phase_needs_run "prepare_deployment"; then
    echo "ERROR: prepare_deployment should also reset to pending when downstream phases are rewound" >&2
    exit 1
fi

echo "▶ Smoke test completed successfully"
popd >/dev/null
