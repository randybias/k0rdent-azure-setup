# k0rdent Azure Setup

Automated Azure infrastructure deployment for k0rdent Kubernetes clusters with WireGuard networking.

## Overview

This project provides shell scripts to automatically deploy a complete Azure infrastructure for running k0rdent Kubernetes clusters. It creates:

- 5 ARM64 Debian 12 VMs (3 control plane + 2 worker nodes)
- WireGuard mesh network for secure connectivity
- SSH key management with local key storage
- Network security groups with proper firewall rules
- Parallel VM deployment for faster provisioning

## Architecture

```
┌─────────────────┐    ┌──────────────────────────────────────┐
│   Your Laptop   │    │              Azure Cloud             │
│  172.24.24.1    │◄──►│                                      │
│  (WireGuard     │    │  ┌─────────────┐  ┌─────────────┐    │
│   Hub)          │    │  │  k0rdcp1    │  │  k0rdcp2    │    │
└─────────────────┘    │  │172.24.24.11 │  │172.24.24.12 │    │
                       │  │   Zone 2    │  │   Zone 3    │    │
                       │  └─────────────┘  └─────────────┘    │
                       │                                      │
                       │  ┌─────────────┐  ┌─────────────┐    │
                       │  │  k0rdcp3    │  │ k0rdwood1   │    │
                       │  │172.24.24.13 │  │172.24.24.21 │    │
                       │  │   Zone 2    │  │   Zone 3    │    │
                       │  └─────────────┘  └─────────────┘    │
                       │                                      │
                       │  ┌─────────────┐                     │
                       │  │ k0rdwood2   │                     │
                       │  │172.24.24.22 │                     │
                       │  │   Zone 2    │                     │
                       │  └─────────────┘                     │
                       └──────────────────────────────────────┘
```

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

### Check Status

```bash
# Show deployment configuration
./deploy-k0rdent.sh config

# Check prerequisites
./deploy-k0rdent.sh check
```

## Configuration

All configuration is centralized in `k0rdent-config.sh`:

### Key Settings

- **VM Size**: `Standard_D4pls_v6` (4 vCPUs, 8GB RAM)
- **Region**: `southeastasia`
- **Image**: `Debian:debian-12:12-arm64:latest`
- **Priority**: `Regular` (not Spot instances)
- **Zones**: Alternates between zones 2 and 3 for HA

### Network Configuration

- **Azure VNet**: `10.240.0.0/16`
- **Subnet**: `10.240.1.0/24`
- **WireGuard Network**: `172.24.24.0/24`
- **WireGuard Port**: Randomly generated (30000-64000)

### VM Deployment Settings

- **Wait Timeout**: 15 minutes
- **Check Interval**: 30 seconds

### VM Verification Settings

- **SSH Timeout**: 10 seconds
- **Cloud-Init Timeout**: 10 minutes
- **Verification Retries**: 3 attempts
- **Retry Delay**: 10 seconds

## File Structure

```
k0rdent-azure-setup/
├── README.md                    # This file
├── common-functions.sh          # Shared utility functions
├── k0rdent-config.sh           # Central configuration
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

### Individual Scripts

**create-azure-vms.sh**: Creates VMs in parallel and verifies deployment with:
- SSH connectivity testing
- Cloud-init completion monitoring  
- WireGuard configuration verification

**generate-laptop-wg-config.sh**: Generates WireGuard configuration for laptop connectivity

**connect-laptop-wireguard.sh**: Sets up and tests WireGuard VPN connection with options for:
- GUI app import (recommended for macOS)
- Command-line wg-quick setup
- Connection testing and verification

Each script supports a `reset` option to clean up its resources:

```bash
./generate-wg-keys.sh reset      # Remove WireGuard keys
./setup-azure-network.sh reset  # Delete Azure resources
./generate-cloud-init.sh reset  # Remove cloud-init files
./create-azure-vms.sh reset     # Delete k0rdent VMs and OS disks individually
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