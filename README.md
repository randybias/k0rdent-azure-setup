# k0rdent Azure Setup

Automated infrastructure deployment for k0rdent Kubernetes clusters with WireGuard networking. Only works for Azure for now.

## Overview

A set of simple Bash scripts to assist with spinning up infrastructure on Azure for deploying a production-style [k0rdent](https://k0rdent.io) cluster.  Not intended for production deployments.  This is mostly to assist in setting up test and development environments.  May have idioms and quirks specific to my needs.

This project provides shell scripts to automatically deploy a complete Azure infrastructure for running k0rdent Kubernetes clusters. It creates:

- Configurable number of VMs with flexible controller/worker topology
- Ubuntu 24.04 LTS VMs with different sizes for controllers vs workers
- WireGuard mesh network for secure connectivity
- SSH key management with local key storage
- Network security groups with proper firewall rules
- Parallel VM deployment with HA zone distribution

## Architecture

Default HA topology (3 controllers + 2 workers):

```
┌─────────────────┐    ┌──────────────────────────────────────┐
│   Your Laptop   │    │              Azure Cloud             │
│  172.24.24.1    │◄──►│                                      │
│  (WireGuard     │    │  ┌─────────────┐  ┌─────────────┐    │
│   Hub)          │    │  │k0s-controller│ │k0s-controller-2│ │
└─────────────────┘    │  │172.24.24.11 │  │172.24.24.12 │    │
                       │  │   Zone 2    │  │   Zone 3    │    │
                       │  └─────────────┘  └─────────────┘    │
                       │                                      │
                       │  ┌─────────────┐                     │
                       │  │k0s-controller-3│                  │
                       │  │172.24.24.13 │                     │
                       │  │   Zone 2    │                     │
                       │  └─────────────┘                     │
                       │                                      │
                       │  ┌─────────────┐  ┌─────────────┐    │
                       │  │k0s-worker-1 │  │k0s-worker-2 │    │
                       │  │172.24.24.14 │  │172.24.24.15 │    │
                       │  │   Zone 3    │  │   Zone 2    │    │
                       │  └─────────────┘  └─────────────┘    │
                       └──────────────────────────────────────┘
```

This HA setup provides controller redundancy across zones for high availability.

## Quick Start

### Prerequisites

1. **Azure CLI** installed and authenticated:
   ```bash
   az login
   ```

2. **WireGuard tools** installed:
   ```bash
   # macOS
   brew install wireguard-tools
   
   # Ubuntu/Debian
   sudo apt install wireguard
   
   # CentOS/RHEL
   sudo yum install wireguard-tools
   ```

### Deployment

Run the complete deployment process:

```bash
./deploy-k0rdent.sh deploy
```

For automated deployments without prompts:

```bash
./deploy-k0rdent.sh deploy -y
```

Or step-by-step:

```bash
# Step 1: Generate WireGuard keys
./generate-wg-keys.sh

# Step 2: Setup Azure network infrastructure
./setup-azure-network.sh

# Step 3: Generate cloud-init configurations
./generate-cloud-init.sh

# Step 4: Create VMs in parallel with verification
./create-azure-vms.sh

# Step 5: Generate laptop WireGuard configuration
./generate-laptop-wg-config.sh

# Step 6: Connect laptop to WireGuard VPN
./connect-laptop-wireguard.sh
```

### Command-Line Options

All scripts support standardized arguments:

- `-y, --yes` - Skip confirmation prompts for automated deployments
- `--no-wait` - Skip waiting for resources (where applicable)
- `-h, --help` - Show help message

Examples:

```bash
# Automated deployment without prompts
./deploy-k0rdent.sh deploy -y

# Create VMs without waiting for provisioning
./create-azure-vms.sh --no-wait

# Reset everything without confirmation
./deploy-k0rdent.sh reset -y
```

### Check Status

```bash
# Show deployment configuration
./deploy-k0rdent.sh config

# Check prerequisites
./deploy-k0rdent.sh check
```

## Configuration

Configuration is split into user-configurable settings and internal computed values:

### User Configuration (`config-user.sh`)

Modify `config-user.sh` to customize your deployment:

#### Cluster Topology
```bash
K0S_CONTROLLER_COUNT=3    # Number of k0s controllers (1, 3, 5, etc.)
K0S_WORKER_COUNT=2        # Number of k0s workers
```

#### VM Sizing
```bash
AZURE_CONTROLLER_VM_SIZE="Standard_D4pls_v6"  # Controllers (4 vCPUs, 8GB ARM64)
AZURE_WORKER_VM_SIZE="Standard_D4pls_v6"      # Workers (4 vCPUs, 8GB ARM64)
```

#### Azure Settings
```bash
AZURE_LOCATION="southeastasia"               # Azure region
AZURE_VM_IMAGE="Debian:debian-12:12-arm64:latest"
AZURE_VM_PRIORITY="Regular"                  # Regular or Spot
AZURE_EVICTION_POLICY="Deallocate"          # For Spot VMs
```

#### Zone Distribution
```bash
CONTROLLER_ZONES=(2 3 2)   # Zones for controllers
WORKER_ZONES=(3 2 3 2)     # Zones for workers (cycles if needed)
```

#### Network Settings
```bash
VNET_PREFIX="10.240.0.0/16"
SUBNET_PREFIX="10.240.1.0/24"
WG_NETWORK="172.24.24.0/24"
```

#### k0rdent Settings
```bash
K0S_VERSION="v1.33.1+k0s.0"
K0RDENT_VERSION="1.0.0"
K0RDENT_OCI_REGISTRY="oci://ghcr.io/k0rdent/kcm/charts/kcm"
K0RDENT_NAMESPACE="kcm-system"
```

### Configuration Examples

#### HA Setup with 3 Controllers (Default)
```bash
K0S_CONTROLLER_COUNT=3
K0S_WORKER_COUNT=2
```
Creates: `k0s-controller`, `k0s-controller-2`, `k0s-controller-3`, `k0s-worker-1`, `k0s-worker-2`

#### Single Controller Setup
```bash
K0S_CONTROLLER_COUNT=1
K0S_WORKER_COUNT=4
```
Creates: `k0s-controller`, `k0s-worker-1`, `k0s-worker-2`, `k0s-worker-3`, `k0s-worker-4`

#### Small Development Setup
```bash
K0S_CONTROLLER_COUNT=1
K0S_WORKER_COUNT=2
AZURE_CONTROLLER_VM_SIZE="Standard_B2s"     # Smaller/cheaper
AZURE_WORKER_VM_SIZE="Standard_B2ms"
```

#### Large Production Setup
```bash
K0S_CONTROLLER_COUNT=3
K0S_WORKER_COUNT=10
AZURE_CONTROLLER_VM_SIZE="Standard_D4s_v3"
AZURE_WORKER_VM_SIZE="Standard_D8s_v3"      # Larger workers
```

### Internal Configuration (`config-internal.sh`)

Automatically computed values (do not edit):

- **VM Arrays**: Dynamically generated based on counts
- **Resource Naming**: Uses random suffix for uniqueness
- **IP Mapping**: WireGuard IPs assigned automatically
- **Validation**: Ensures minimum requirements and HA best practices

## File Structure

```
k0rdent-azure-setup/
├── README.md                    # This file
├── common-functions.sh          # Shared utility functions
├── config-user.sh              # User-configurable settings
├── config-internal.sh          # Computed configuration (do not edit)
├── k0rdent-config.sh           # Central configuration loader
├── deploy-k0rdent.sh           # Main orchestration script
├── generate-wg-keys.sh         # WireGuard key generation
├── setup-azure-network.sh     # Azure infrastructure setup
├── generate-cloud-init.sh      # Cloud-init file generation
├── create-azure-vms.sh         # VM creation with parallel deployment
├── azure-resources/            # Generated Azure resources
│   ├── azure-resource-manifest.csv
│   ├── wireguard-port.txt
│   ├── k2-XXXXXXXX-ssh-key     # Private SSH key
│   └── k2-XXXXXXXX-ssh-key.pub # Public SSH key
├── wg-keys/                    # WireGuard keys
│   ├── wg-key-manifest.csv
│   ├── *_privkey
│   └── *_pubkey
└── cloud-init-yaml/           # VM cloud-init configurations
    ├── k0rdcp1-cloud-init.yaml
    ├── k0rdcp2-cloud-init.yaml
    ├── k0rdcp3-cloud-init.yaml
    ├── k0rdwood1-cloud-init.yaml
    └── k0rdwood2-cloud-init.yaml
```

## Scripts Reference

### deploy-k0rdent.sh

Main orchestration script with commands:
- `deploy` - Run full deployment with confirmation
- `reset` - Remove all k0rdent resources in proper order
- `config` - Show deployment configuration
- `check` - Verify prerequisites only
- `help` - Show usage information

Options:
- `-y, --yes` - Skip confirmation prompts
- `--no-wait` - Pass to child scripts to skip resource waiting
- `-h, --help` - Show help message

The orchestrator automatically passes flags to all child scripts for consistent behavior.

### Individual Scripts

**create-azure-vms.sh**: Creates VMs in parallel and verifies deployment with:
- SSH connectivity testing
- Cloud-init completion monitoring  
- WireGuard configuration verification
- Support for `--no-wait` to skip verification

**generate-laptop-wg-config.sh**: Generates WireGuard configuration for laptop connectivity

**connect-laptop-wireguard.sh**: Sets up and tests WireGuard VPN connection with options for:
- GUI app import (recommended for macOS)
- Command-line wg-quick setup
- Connection testing and verification

Each script supports standardized arguments and a `reset` option to clean up its resources:

```bash
# Reset with confirmation
./generate-wg-keys.sh reset      # Remove WireGuard keys
./setup-azure-network.sh reset  # Delete Azure resources
./generate-cloud-init.sh reset  # Remove cloud-init files
./create-azure-vms.sh reset     # Delete k0rdent VMs and OS disks individually

# Reset without confirmation
./generate-wg-keys.sh reset -y
./setup-azure-network.sh reset -y
```

## SSH Access

After deployment, SSH to any VM using the generated key:

```bash
ssh -i ./azure-resources/k2-XXXXXXXX-ssh-key k0rdent@<PUBLIC_IP>
```

## WireGuard Setup

### VM Configuration

Each VM is automatically configured with:
- WireGuard interface `wg0`
- Unique private key and IP address
- Peer configuration for laptop hub
- Auto-start on boot

### Laptop Configuration

Create a WireGuard configuration on your laptop using the generated keys:

```ini
[Interface]
PrivateKey = <mylaptop_private_key_from_manifest>
Address = 172.24.24.1/32
ListenPort = <port_from_wireguard-port.txt>

[Peer]
PublicKey = <vm_public_key_from_manifest>
AllowedIPs = <vm_wg_ip>/32
Endpoint = <vm_public_ip>:<wireguard_port>
PersistentKeepalive = 25
```

## Monitoring Cloud-Init

Check cloud-init progress on VMs:

```bash
# Check status
sudo cloud-init status

# View logs
sudo journalctl -u cloud-init-final

# Check WireGuard status
sudo systemctl status wg-quick@wg0
sudo wg show
```

## Cleanup

To completely remove all k0rdent resources:

```bash
./deploy-k0rdent.sh reset
```

This will remove resources in the proper order:
1. Azure VMs and network resources
2. Cloud-init files  
3. WireGuard keys
4. Project suffix file (for completely fresh deployments)

For individual component cleanup, you can also run:

```bash
./setup-azure-network.sh reset    # Remove Azure resources only
./generate-cloud-init.sh reset    # Remove cloud-init files only
./generate-wg-keys.sh reset       # Remove WireGuard keys only
./create-azure-vms.sh reset       # Delete k0rdent VMs and OS disks individually
```

**Note**: The project suffix file is only removed when using `./deploy-k0rdent.sh reset` to ensure a completely fresh deployment. Individual script resets preserve the project identifier.

## Troubleshooting

### Common Issues

1. **Quota Exceeded**: Reduce VM size in `k0rdent-config.sh`
2. **Zone Availability**: Check ARM64 VM availability in your region
3. **Network Conflicts**: Ensure no existing resources conflict with names

### Debug Commands

```bash
# Check Azure resources
az group list --query "[?contains(name, 'k2-')]"

# Check VM status
az vm list --resource-group <resource-group> --show-details

# View cloud-init logs
ssh -i ./azure-resources/k2-*-ssh-key k0rdent@<vm-ip> 'sudo cat /var/log/cloud-init-output.log'
```

## Security Features

- SSH keys generated locally and securely stored
- WireGuard for encrypted communication
- Network Security Groups with minimal required access
- Private key files with proper permissions (600)
- Resource naming with random suffixes for uniqueness

## Next Steps

After successful deployment:

1. Verify WireGuard connectivity between laptop and VMs
2. Install k0rdent on the control plane nodes
3. Join worker nodes to the cluster
4. Deploy your applications

---

**Generated with [Claude Code](https://claude.ai/code)**