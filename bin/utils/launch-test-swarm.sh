#!/usr/bin/env bash

# Script to launch multiple test child clusters for testing purposes
# Usage: ./bin/utils/launch-test-swarm.sh [iterations]

set -euo pipefail

# Source the configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$BASE_DIR"

# Get the number of iterations (default: 5)
iterations=5
message="Launching Child Clusters"

# Validate that iterations is a positive number
if ! [[ "$iterations" =~ ^[0-9]+$ ]] || [ "$iterations" -lt 1 ]; then
    echo "Error: Iterations must be a positive number" >&2
    exit 1
fi

echo "Launching $iterations test clusters..."

# Run the loop to create child clusters
for ((i=1; i<=iterations; i++)); do
    echo "[$i/$iterations] $message"
    bin/create-child.sh \
        --cluster-name test${i} \
        --cloud azure \
        --location southeastasia \
        --cp-instance-size Standard_A4_v2 \
        --worker-instance-size Standard_A4_v2 \
        --root-volume-size 64 \
        --namespace kcm-system \
        --template azure-standalone-cp-1-0-8 \
        --credential azure-cluster-credential \
        --cp-number 1 \
        --worker-number 1 \
        --cluster-identity-name azure-cluster-identity \
        --cluster-identity-namespace kcm-system \
        --cluster-labels k0rdent.mirantis.com/kof-storage-secrets=true,k0rdent.mirantis.com/kof-cluster-role=child,k0rdent.mirantis.com/istio-role=child
done

echo "Test swarm launch complete!"
