#!/usr/bin/env bash

# k0rdent-config.sh
# Central configuration file for k0rdent Azure setup scripts
# Source this file in other scripts: source ./k0rdent-config.sh

# ---- Deployment Configuration ----

# Generate or load persistent random suffix for deployment uniqueness
SUFFIX_FILE="./.k0rdent-suffix"

if [[ -f "$SUFFIX_FILE" ]]; then
    RANDOM_SUFFIX=$(cat "$SUFFIX_FILE")
else
    RANDOM_SUFFIX=$(head /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 8; echo)
    echo "$RANDOM_SUFFIX" > "$SUFFIX_FILE"
fi

# Deployment identifier - automatically includes random suffix for uniqueness
K0RDENT_PREFIX="k2-${RANDOM_SUFFIX}"

# ---- Azure Configuration ----

# Azure location and resource naming
LOCATION="southeastasia"
RG="${K0RDENT_PREFIX}-resgrp"

# Network configuration
VNET_NAME="${K0RDENT_PREFIX}-vnet"
VNET_PREFIX="10.240.0.0/16"
SUBNET_NAME="${K0RDENT_PREFIX}-subnet"
SUBNET_PREFIX="10.240.1.0/24"
NSG_NAME="${K0RDENT_PREFIX}-nsg"

# SSH key configuration
SSH_KEY_NAME="${K0RDENT_PREFIX}-admin"
ADMIN_USER="k0rdent"

# VM configuration
VM_SIZE="Standard_D4pls_v6"
IMAGE="Debian:debian-12:12-arm64:latest"
PRIORITY="Regular"
# EVICTION_POLICY only applies to Spot instances
# EVICTION_POLICY="Deallocate"

# Available zones for ARM64 in Southeast Asia
ZONES="2 3"

# VM deployment configuration
VM_WAIT_TIMEOUT_MINUTES=15
VM_CHECK_INTERVAL_SECONDS=30

# VM verification configuration
SSH_TIMEOUT_SECONDS=10
CLOUD_INIT_TIMEOUT_MINUTES=10
CLOUD_INIT_CHECK_INTERVAL_SECONDS=30
VERIFICATION_RETRY_COUNT=3
VERIFICATION_RETRY_DELAY_SECONDS=10

# ---- WireGuard Configuration ----

# WireGuard network range
WG_NETWORK="172.24.24.0/24"

# Hostname to WireGuard IP mapping
declare -A WG_IPS=(
    ["mylaptop"]="172.24.24.1"
    ["k0rdcp1"]="172.24.24.11"
    ["k0rdcp2"]="172.24.24.12"
    ["k0rdcp3"]="172.24.24.13"
    ["k0rdwood1"]="172.24.24.21"
    ["k0rdwood2"]="172.24.24.22"
)

# ---- VM Host Configuration ----

# List of VM hosts to create
VM_HOSTS=("k0rdcp1" "k0rdcp2" "k0rdcp3" "k0rdwood1" "k0rdwood2")

# Host to zone assignment (alternate zones for HA)
declare -A VM_ZONES=(
    ["k0rdcp1"]="2"
    ["k0rdcp2"]="3"
    ["k0rdcp3"]="2"
    ["k0rdwood1"]="3"
    ["k0rdwood2"]="2"
)

# ---- Directory Configuration ----

# Working directories
KEYDIR="./wg-keys"
MANIFEST_DIR="./azure-resources"
CLOUDINITS="./cloud-init-yaml"

# File paths
WG_MANIFEST="$KEYDIR/wg-key-manifest.csv"
AZURE_MANIFEST="$MANIFEST_DIR/azure-resource-manifest.csv"
WG_PORT_FILE="$MANIFEST_DIR/wireguard-port.txt"

# ---- Script Dependencies ----

# Script execution order for reference
SCRIPT_ORDER=(
    "generate-wg-keys.sh"
    "setup-azure-network.sh" 
    "generate-cloud-init.sh"
    "create-azure-vms.sh"
)

echo "==> k0rdent configuration loaded (prefix: $K0RDENT_PREFIX, region: $LOCATION)" 
