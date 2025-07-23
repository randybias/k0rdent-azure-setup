#!/usr/bin/env bash

# Script to setup port forwarding for KOF regional Grafana
# Usage: ./bin/utils/kof-proxy-regional-setup.sh [port]

set -euo pipefail

# Source the configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$BASE_DIR"

# Default port (can be overridden by argument)
local_port=${1:-3020}

# Validate port number
if ! [[ "$local_port" =~ ^[0-9]+$ ]] || [ "$local_port" -lt 1 ] || [ "$local_port" -gt 65535 ]; then
    echo "Error: Port must be a valid number between 1 and 65535" >&2
    exit 1
fi

# Find the KOF regional kubeconfig
echo "Looking for KOF regional kubeconfig..."
kubeconfig_pattern="k0sctl-config/kof-regional-*-kubeconfig"
kubeconfig_files=($kubeconfig_pattern)

if [ ${#kubeconfig_files[@]} -eq 0 ] || [ ! -f "${kubeconfig_files[0]}" ]; then
    echo "Error: No KOF regional kubeconfig found matching pattern: $kubeconfig_pattern" >&2
    exit 1
fi

if [ ${#kubeconfig_files[@]} -gt 1 ]; then
    echo "Warning: Multiple KOF regional kubeconfigs found. Using the first one: ${kubeconfig_files[0]}" >&2
fi

KUBECONFIG="${kubeconfig_files[0]}"
export KUBECONFIG

echo "Using kubeconfig: $KUBECONFIG"

# Get and display Grafana admin credentials
echo -e "\nRetrieving Grafana admin credentials..."
if kubectl get secret -n kof grafana-admin-credentials &>/dev/null; then
    echo -e "\nGrafana Admin Credentials:"
    kubectl get secret -n kof grafana-admin-credentials -o yaml | yq '{
      "user": .data.GF_SECURITY_ADMIN_USER | @base64d,
      "pass": .data.GF_SECURITY_ADMIN_PASSWORD | @base64d
    }'
else
    echo "Warning: Could not find Grafana admin credentials secret" >&2
fi

# Setup port forwarding
echo -e "\nStarting port forwarding..."
echo "Grafana will be available at: http://localhost:$local_port"
echo "Press Ctrl+C to stop port forwarding"

kubectl port-forward -n kof svc/grafana-vm-service $local_port:3000