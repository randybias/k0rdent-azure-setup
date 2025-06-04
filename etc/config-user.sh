#!/usr/bin/env bash
# User-configurable settings for k0rdent Azure deployment

# ---- Azure Settings ----
AZURE_LOCATION="southeastasia"
AZURE_VM_IMAGE="Debian:debian-12:12-arm64:latest"
AZURE_VM_PRIORITY="Regular"  # Regular or Spot
AZURE_EVICTION_POLICY="Deallocate"  # For Spot VMs

# ---- VM Sizing ----
# Different instance types for controllers vs workers
AZURE_CONTROLLER_VM_SIZE="Standard_D2pls_v6"  # Size for k0s controller nodes
AZURE_WORKER_VM_SIZE="Standard_D8pls_v6"      # Size for k0s worker nodes

# ---- Cluster Topology ----
# Number of nodes (minimum 1 each)
K0S_CONTROLLER_COUNT=3  # Number of k0s controllers (minimum 1, odd number recommended for HA)
K0S_WORKER_COUNT=2      # Number of k0s workers (minimum 1)

# ---- Zone Distribution ----
# How to distribute nodes across availability zones
# Arrays should have at least as many elements as the corresponding node count
CONTROLLER_ZONES=(2 3 2)  # Zones for controllers (will cycle if more controllers than zones)
WORKER_ZONES=(3 2 3 2)    # Zones for workers (will cycle if more workers than zones)

# ---- SSH Settings ----
SSH_USERNAME="k0rdent"  # Username for VM access
SSH_KEY_COMMENT="k0rdent-azure-key"

# ---- k0rdent Settings ----
K0S_VERSION="v1.33.1+k0s.0"
K0RDENT_VERSION="1.0.0"
K0RDENT_OCI_REGISTRY="oci://ghcr.io/k0rdent/kcm/charts/kcm"
K0RDENT_NAMESPACE="kcm-system"

# ---- Network Settings ----
VNET_PREFIX="10.240.0.0/16"
SUBNET_PREFIX="10.240.1.0/24"
WG_NETWORK="172.24.24.0/24"

# ---- Timeouts and Intervals ----
SSH_CONNECT_TIMEOUT=30
SSH_COMMAND_TIMEOUT=300
K0S_INSTALL_WAIT=60
K0RDENT_INSTALL_WAIT=30
WIREGUARD_CONNECT_WAIT=5
VM_CREATION_TIMEOUT_MINUTES=15
VM_WAIT_CHECK_INTERVAL=30
