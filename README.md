# k0rdent Azure Setup

Automated infrastructure deployment for k0rdent Kubernetes clusters with WireGuard networking and intelligent state tracking. Only works for Azure for now.

## Overview

A set of simple Bash scripts to assist with spinning up infrastructure on Azure for deploying a production-style [k0rdent](https://k0rdent.io) cluster.  Not intended for production deployments.  This is mostly to assist in setting up test and development environments.  May have idioms and quirks specific to my needs.

This project provides shell scripts to automatically deploy a complete Azure infrastructure for running k0rdent Kubernetes clusters. It creates:

- Configurable number of VMs with flexible controller/worker topology
- Debian 12 ARM64 VMs with different sizes for controllers vs workers
- WireGuard mesh network for secure connectivity
- SSH key management with local key storage
- Network security groups with proper firewall rules
- Parallel VM deployment with HA zone distribution
- Intelligent deployment state tracking with 80-85% reduction in Azure API calls

## Architecture

Default HA topology (3 controllers + 2 workers):

```
┌─────────────────┐    ┌───────────────────────────────────────┐
│   Your Laptop   │    │              Azure Cloud              │
│  172.24.24.1    │◄──►│                                       │
│  (WireGuard     │    │  ┌──────────────┐  ┌────────────────┐ │
│   Hub)          │    │  │k0s-controller│  │k0s-controller-2│ │
└─────────────────┘    │  │172.24.24.11  │  │172.24.24.12    │ │
                       │  │   Zone 2     │  │   Zone 3       │ │
                       │  └──────────────┘  └────────────────┘ │
                       │                                       │
                       │  ┌────────────────┐                   │
                       │  │k0s-controller-3│                   │
                       │  │172.24.24.13    │                   │
                       │  │   Zone 2       │                   │
                       │  └────────────────┘                   │
                       │                                       │
                       │  ┌─────────────┐  ┌─────────────┐     │
                       │  │k0s-worker-1 │  │k0s-worker-2 │     │
                       │  │172.24.24.14 │  │172.24.24.15 │     │
                       │  │   Zone 3    │  │   Zone 2    │     │
                       │  └─────────────┘  └─────────────┘     │
                       └───────────────────────────────────────┘
```

This HA setup provides controller redundancy across zones for high availability.

## Video Demonstration

[![Watch the video](demos/k0rdent-azure-script-setup.png)](demos/k0rdent-azure-script-setup.mp4)

## Quick Start

1. **Clone the repository**:
   ```bash
   git clone <repo>
   cd k0rdent-azure-setup
   ```

2. **Create configuration**:
   ```bash
   # Use minimal template (single controller + worker)
   ./bin/configure.sh init
   
   # Or choose from available templates
   ./bin/configure.sh templates
   ./bin/configure.sh init --template production
   ```

3. **Deploy the cluster**:
   ```bash
   ./deploy-k0rdent.sh deploy
   ```

### Prerequisites

All prerequisites are automatically checked at the beginning of the deployment process. You can also verify them manually:

```bash
./deploy-k0rdent.sh check
```

Required tools:

1. **yq** - YAML processor (version 4.x):
   ```bash
   # macOS
   brew install yq
   
   # Ubuntu/Debian
   sudo snap install yq
   # or
   sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
   sudo chmod +x /usr/local/bin/yq
   ```

2. **Azure CLI** installed and authenticated:
   ```bash
   # Install Azure CLI (if needed)
   # macOS: brew install azure-cli
   # Linux: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   
   # Login to Azure
   az login
   ```

3. **WireGuard tools** installed:
   ```bash
   # macOS
   brew install wireguard-tools
   
   # Ubuntu/Debian
   sudo apt install wireguard
   
   # CentOS/RHEL
   sudo yum install wireguard-tools
   ```

4. **k0sctl** - k0s cluster management tool:
   ```bash
   # Download latest release
   # macOS/Linux
   curl -sSLf https://github.com/k0sproject/k0sctl/releases/latest/download/k0sctl-$(uname -s)-$(uname -m) -o k0sctl
   chmod +x k0sctl
   sudo mv k0sctl /usr/local/bin/
   ```

5. **netcat (nc)** - Network connectivity tool:
   ```bash
   # Usually pre-installed, but if missing:
   # macOS: brew install netcat
   # Ubuntu/Debian: sudo apt install netcat
   # CentOS/RHEL: sudo yum install nc
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
# Step 1: Prepare deployment (WireGuard keys and cloud-init)
./bin/prepare-deployment.sh deploy

# Step 2: Setup Azure network infrastructure
./bin/setup-azure-network.sh deploy

# Step 3: Create VMs in parallel with verification
./bin/create-azure-vms.sh deploy

# Step 4: Setup and connect to WireGuard VPN
./bin/manage-vpn.sh setup
./bin/manage-vpn.sh connect

# Step 5: Install k0s cluster
./bin/install-k0s.sh deploy

# Step 6: Install k0rdent on cluster  
./bin/install-k0rdent.sh deploy
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

k0rdent uses a YAML-based configuration system for easy customization:

### Quick Configuration

```bash
# List available templates
./bin/configure.sh templates

# Create configuration from template
./bin/configure.sh init --template minimal      # Single node (default)
./bin/configure.sh init --template development  # Dev environment
./bin/configure.sh init --template production   # HA production setup

# View current configuration
./bin/configure.sh show

# Validate VM availability for configuration
./bin/configure.sh validate

# Skip validation during configuration creation
./bin/configure.sh init --template production --skip-validation

# Edit configuration manually
vim ./config/k0rdent.yaml
```

### Available Templates

- **minimal** - Single controller + worker (default, cost-effective)
- **development** - 1 controller + 2 workers across zones
- **production** - 3 controllers + 3 workers (HA setup)
- **production-arm64-southeastasia** - ARM64 optimized for Southeast Asia
- **production-arm64-southeastasia-spot** - ARM64 with Spot VMs for cost savings

#### Example YAML Configuration
```yaml
# Cluster Topology
cluster:
  controllers:
    count: 3  # Number of k0s controllers (1, 3, 5, etc.)
  workers:
    count: 2  # Number of k0s workers

# VM Sizing
vm_sizing:
  controller:
    size: "Standard_D4pls_v6"  # Controllers (4 vCPUs, 8GB ARM64)
  worker:
    size: "Standard_D4pls_v6"  # Workers (4 vCPUs, 8GB ARM64)

# Azure Settings
azure:
  location: "southeastasia"  # Azure region
  vm_image: "Debian:debian-12:12-arm64:latest"
  vm_priority: "Regular"  # Regular or Spot
  eviction_policy: "Deallocate"  # For Spot VMs
```

See `config/examples/` for more configuration templates:
- `minimal.yaml` - Single controller + worker setup  
- `production.yaml` - HA setup with 3 controllers
- `development.yaml` - Optimized for development/testing

### Configuration Examples

#### HA Setup with 3 Controllers
```yaml
cluster:
  controllers:
    count: 3
  workers:
    count: 2
```
Creates: `k0s-controller`, `k0s-controller-2`, `k0s-controller-3`, `k0s-worker-1`, `k0s-worker-2`

#### Single Controller Setup
```yaml
cluster:
  controllers:
    count: 1
  workers:
    count: 4
```
Creates: `k0s-controller`, `k0s-worker-1`, `k0s-worker-2`, `k0s-worker-3`, `k0s-worker-4`

#### Small Development Setup
```yaml
cluster:
  controllers:
    count: 1
  workers:
    count: 2
vm_sizing:
  controller:
    size: "Standard_B2s"     # Smaller/cheaper
  worker:
    size: "Standard_B2ms"
```

#### Large Production Setup
```yaml
cluster:
  controllers:
    count: 3
  workers:
    count: 10
vm_sizing:
  controller:
    size: "Standard_D4s_v3"
  worker:
    size: "Standard_D8s_v3"      # Larger workers
```

### Internal Configuration (`etc/config-internal.sh`)

Automatically computed values (do not edit):

- **VM Arrays**: Dynamically generated based on counts
- **Resource Naming**: Uses random suffix for uniqueness
- **IP Mapping**: WireGuard IPs assigned automatically
- **Validation**: Ensures minimum requirements and HA best practices

## Deployment State Tracking

The project includes an intelligent state tracking system that significantly optimizes Azure deployments:

### Key Benefits

- **80-85% Reduction in Azure API Calls**: From 125-140 calls down to 20-25 per deployment
- **Centralized State Management**: Single YAML-based state file replaces scattered CSV manifests
- **Event-Driven Lifecycle**: Complete audit trail of all deployment actions
- **Resume Capability**: Can resume deployments from any point in the process
- **Backup and Recovery**: Automatic state backup on completion with cleanup on reset

### State Files

- **`deployment-state.yaml`**: Current deployment state with VM status, configuration snapshot, and progress tracking
- **`deployment-events.yaml`**: Complete event log with timestamps and detailed action history
- **`old_deployments/`**: Backup directory for completed deployment states

### State Tracking Features

```bash
# View current deployment state
yq eval '.' deployment-state.yaml

# Check deployment events
yq eval '.events[] | select(.action == "vm_deployment_completed")' deployment-events.yaml

# Resume deployment from any point
./deploy-k0rdent.sh deploy  # Automatically detects and continues from current state
```

The state system tracks:
- Azure resource creation status (RG, VNet, SSH keys)
- VM deployment with IP addresses and provisioning state
- WireGuard key generation and VPN connectivity
- k0s cluster deployment progress
- k0rdent installation and readiness verification

## File Structure

```
k0rdent-azure-setup/
├── README.md                    # This file
├── deploy-k0rdent.sh           # Main orchestration script
├── deployment-state.yaml       # Current deployment state (auto-generated)
├── deployment-events.yaml      # Deployment event log (auto-generated)
├── etc/                        # Configuration files
│   ├── config-user.sh          # DEPRECATED (use YAML config instead)
│   ├── config-internal.sh      # Computed configuration (do not edit)
│   ├── k0rdent-config.sh       # Central configuration loader
│   ├── state-management.sh     # State tracking functions
│   └── common-functions.sh     # Shared utility functions (1,500+ lines)
├── bin/                        # Action scripts (6 consolidated scripts)
│   ├── prepare-deployment.sh   # Deployment preparation (keys & cloud-init)
│   ├── setup-azure-network.sh  # Azure infrastructure setup
│   ├── create-azure-vms.sh     # VM creation with parallel deployment
│   ├── manage-vpn.sh           # Comprehensive VPN management
│   ├── install-k0s.sh          # k0s cluster installation
│   └── install-k0rdent.sh      # k0rdent installation on cluster
├── azure-resources/            # Generated Azure resources  
│   ├── k0rdent-XXXXXXXX-ssh-key     # Private SSH key
│   └── k0rdent-XXXXXXXX-ssh-key.pub # Public SSH key
├── wireguard/                  # WireGuard configuration and keys
│   ├── *_privkey and *_pubkey files # WireGuard keys per host
│   └── wgk0XXXXXXXX.conf           # Laptop WireGuard config
├── cloud-inits/               # VM cloud-init configurations
│   ├── k0s-controller-cloud-init.yaml
│   ├── k0s-controller-2-cloud-init.yaml
│   ├── k0s-controller-3-cloud-init.yaml
│   ├── k0s-worker-1-cloud-init.yaml
│   └── k0s-worker-2-cloud-init.yaml
├── laptop-wg-config/          # Generated laptop WireGuard config
│   └── k0rdent-laptop.conf
├── k0sctl-config/             # k0s cluster configuration and kubeconfig
│   ├── <prefix>-k0sctl.yaml
│   └── <prefix>-kubeconfig
└── old_deployments/           # Backup directory for completed deployments
    ├── k0rdent-XXXXXXXX_deployment-state_YYYY-MM-DD.yaml
    └── k0rdent-XXXXXXXX_deployment-events_YYYY-MM-DD.yaml
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

**prepare-deployment.sh**: Consolidated deployment preparation handling:
- WireGuard key generation for all hosts
- WireGuard port selection (30000-64000)
- Cloud-init file generation with keys and configuration
- Commands: `keys`, `cloudinit`, `deploy`, `reset`, `status`

**setup-azure-network.sh**: Creates Azure infrastructure:
- Resource group, VNet, subnet, and NSG
- SSH key generation and import to Azure
- Security rules for SSH and WireGuard
- Tracks all resources in manifest for cleanup

**create-azure-vms.sh**: Asynchronous VM deployment with intelligent failure recovery:
- **Async VM Creation**: VMs launched in parallel background processes with PID tracking
- **Automatic Failure Recovery**: Detects failed VMs and cloud-init errors, automatically recreates
- **Single Monitoring Loop**: Efficient Azure API usage with single bulk calls every 30 seconds
- **Cattle-not-Pets Methodology**: Failed VMs are immediately deleted and recreated
- **Retry Management**: Tracks retry attempts per VM (max 3 retries) with intelligent exit conditions
- **Cloud-init Validation**: Monitors cloud-init status and triggers VM replacement on errors
- **SSH Connectivity Testing**: Verifies SSH access before marking VMs as operational
- **State-based Monitoring**: Tracks VM provisioning states (Creating → Succeeded → Operational)
- **Optimized Verification**: Skip rechecking already verified VMs, cleaner logs for VMs without state
- **Process Health Monitoring**: Detects dead VM creation processes and automatically retries
- Support for `--no-wait` to skip verification and `reset` for bulk VM cleanup

**manage-vpn.sh**: Comprehensive VPN management with enhanced workflow:
- **Two-step process**: `setup` (one-time configuration) and `connect` (fast, repeatable)
- WireGuard configuration generation for laptop
- Connection management (CLI and GUI support)
- Connectivity testing and troubleshooting
- Commands: `setup`, `connect`, `disconnect`, `test`, `status`, `cleanup`, `reset`
- Backwards compatibility with `generate` command

**lockdown-ssh.sh**: Optional SSH security management:
- Remove SSH access from internet after VPN is working
- Restore SSH access when needed
- Simple rule-based approach (no backup/restore complexity)
- Commands: `lockdown`, `unlock`, `status`

**install-k0s.sh**: Installs and configures k0s Kubernetes cluster with:
- k0sctl configuration generation
- Support for single controller or HA multi-controller setups
- SSH connectivity testing
- Kubeconfig retrieval and validation
- State tracking for cluster deployment progress
- `config` command for step-by-step deployment support

**install-k0rdent.sh**: Installs k0rdent on the k0s cluster with:
- Helm-based installation using OCI registry
- Automatic cluster detection and configuration
- Installation status verification
- k0rdent readiness verification with pod status checking
- State tracking for installation progress and component readiness

Each script supports standardized arguments and reset functionality:

```bash
# Reset individual components
./bin/prepare-deployment.sh reset -y     # Remove keys and cloud-init files
./bin/setup-azure-network.sh reset -y    # Delete Azure resources
./bin/create-azure-vms.sh reset -y       # Delete VMs (prompts for each)
./bin/manage-vpn.sh reset -y             # Remove VPN configuration
./bin/lockdown-ssh.sh unlock -y          # Restore SSH access if locked down
./bin/install-k0s.sh uninstall -y        # Remove k0s cluster
./bin/install-k0rdent.sh uninstall -y    # Uninstall k0rdent

# Or use the main script to reset everything
./deploy-k0rdent.sh reset -y
```

## Script Features

### Logging and Output Management

Azure commands generate verbose output that can clutter the console. The scripts now include:

- **Timestamped log files**: Azure command output is captured in `logs/` directory with timestamps
- **Clean console output**: Only essential progress messages and results are shown on screen
- **Automatic log cleanup**: The `logs/` directory is removed during reset operations
- **Git ignore**: Log files are automatically excluded from version control

Example log file: `logs/setup-azure-network_20241204_143052.log`

### Robust VM Creation

The VM creation process has been enhanced for reliability:

- **Existing VM detection**: Scripts continue gracefully if VMs already exist instead of failing
- **Partial deployment support**: Only creates missing VMs, skips existing ones
- **Retry-friendly**: Allows re-running deployment scripts without conflicts
- **Clear status reporting**: Shows which VMs exist vs. which will be created

### WireGuard Configuration Improvements

- **Compatible file naming**: Configuration files use format `wgk0XXXXXXXX.conf` for compatibility with `wg-quick`
- **Secure permissions**: Configuration files are automatically set to 600 permissions
- **Interface name validation**: Ensures WireGuard interface names are valid and don't contain special characters

## SSH Access

After deployment, SSH to any VM using the generated key:

```bash
ssh -i ./azure-resources/k0rdent-XXXXXXXX-ssh-key k0rdent@<PUBLIC_IP>
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
1. Uninstall k0rdent from cluster
2. Remove k0s cluster
3. Disconnect WireGuard VPN
4. Remove laptop WireGuard configuration
5. Azure VMs and network resources
6. Cloud-init files  
7. WireGuard keys
8. Backup deployment state to `old_deployments/` directory
9. Clean up current deployment state files
10. Project suffix file (for completely fresh deployments)

The cleanup process preserves deployment history by backing up state files before removal, allowing you to review past deployments if needed.

For individual component cleanup, you can also run:

```bash
./bin/install-k0rdent.sh uninstall    # Uninstall k0rdent only
./bin/install-k0s.sh uninstall        # Remove k0s cluster only
./bin/setup-azure-network.sh reset    # Remove Azure resources only
./bin/prepare-deployment.sh reset     # Remove WireGuard keys and cloud-init files
./bin/create-azure-vms.sh reset       # Delete k0rdent VMs and OS disks individually
```

**Note**: The project suffix file is only removed when using `./deploy-k0rdent.sh reset` to ensure a completely fresh deployment. Individual script resets preserve the project identifier.

## Troubleshooting

### Common Issues

1. **Quota Exceeded**: Reduce VM size in your YAML configuration
2. **Zone Availability**: Check ARM64 VM availability in your region
3. **Network Conflicts**: Ensure no existing resources conflict with names

### Debug Commands

```bash
# Check Azure resources
az group list --query "[?contains(name, 'k0rdent-')]"

# Check VM status
az vm list --resource-group <resource-group> --show-details

# View cloud-init logs
ssh -i ./azure-resources/k0rdent-*-ssh-key k0rdent@<vm-ip> 'sudo cat /var/log/cloud-init-output.log'
```

## Security Features

- SSH keys generated locally and securely stored
- WireGuard for encrypted communication
- Network Security Groups with minimal required access
- Private key files with proper permissions (600)
- Resource naming with random suffixes for uniqueness
- **Optional SSH lockdown**: Remove internet SSH access after VPN is working

### SSH Lockdown (Optional)

After WireGuard VPN is working, you can optionally remove SSH access from the internet:

```bash
# Remove SSH access from internet (VPN access still works)
./bin/lockdown-ssh.sh lockdown

# Check current SSH access status
./bin/lockdown-ssh.sh status

# Restore SSH access from internet if needed
./bin/lockdown-ssh.sh unlock
```

This provides an additional security layer by ensuring all VM access goes through the encrypted WireGuard VPN.

## Next Steps

After successful deployment:

1. **Verify WireGuard connectivity**: Test connection between laptop and VMs
2. **Install k0s cluster**: Run `./install-k0s.sh deploy` to set up Kubernetes
3. **Install k0rdent**: Run `./install-k0rdent.sh deploy` to install k0rdent on the cluster
4. **Access your cluster**: Export kubeconfig and verify with `kubectl get nodes`
5. **Optional security**: Consider using `./bin/lockdown-ssh.sh lockdown` for additional security
6. **Deploy your applications**: Your k0rdent cluster is ready for workloads

### Manual Installation Steps

If you prefer to run installation steps manually:

```bash
# After infrastructure is deployed and WireGuard is connected...

# Install k0s cluster
./bin/install-k0s.sh deploy

# Install k0rdent on the cluster
./bin/install-k0rdent.sh deploy

# Export kubeconfig for cluster access
export KUBECONFIG=$PWD/k0sctl-config/<prefix>-kubeconfig

# Verify cluster is working
kubectl get nodes
kubectl get all -A
```

---

**Generated with [Claude Code](https://claude.ai/code)**
