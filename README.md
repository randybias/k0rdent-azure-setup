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

For a complete walkthrough of the deployment process, watch this demonstration:

[![k0rdent Azure Deployment Demo](https://img.youtube.com/vi/aT4YqmcEQj0/maxresdefault.jpg)](https://www.youtube.com/watch?v=aT4YqmcEQj0)

*Click the image above to watch the deployment demonstration on YouTube*

## Quick Start

```bash
# Clone the repository
git clone https://github.com/randybias/k0rdent-azure-setup
cd k0rdent-azure-setup

# Initialize configuration
./bin/configure.sh init

# Deploy everything
./deploy-k0rdent.sh deploy

# When done, clean up everything
./deploy-k0rdent.sh reset
```

### Super Quick Start

1. **Prerequisites check** (automatic):
   ```bash
   ./deploy-k0rdent.sh check
   ```

2. **Initialize configuration**:
   ```bash
   ./bin/configure.sh init --template production
   ```

3. **Deploy the cluster**:
   ```bash
   ./deploy-k0rdent.sh deploy
   ```

4. **Fast reset for development** (Azure-specific):
   ```bash
   # Quickly delete Azure resources and clean up local files
   ./deploy-k0rdent.sh reset --fast -y
   ```

### Prerequisites

All prerequisites are automatically checked at the beginning of the deployment process. You can also verify them manually:

```bash
# Check prerequisites using the main script
./deploy-k0rdent.sh check

# Or use the dedicated script
./bin/check-prerequisites.sh
```

**Required tools and versions:**
- **Azure CLI**: >= 2.40.0
- **jq**: >= 1.6 (JSON processor)
- **yq**: >= 4.0 (YAML processor)
- **kubectl**: >= 1.27.0
- **WireGuard**: Any recent version
- **k0sctl**: 0.19.4 (auto-downloaded if missing)
- **nc (netcat)**: For network connectivity testing
- **Homebrew** (macOS): For installing missing dependencies

**macOS-specific tools** (auto-installed):
- GNU grep (ggrep)
- GNU sed (gsed)
- GNU getopt

**Azure requirements:**
- Active Azure subscription
- Logged in via `az login`
- Subscription selected (if you have multiple)

## Features

### Intelligent Orchestration

The project includes a master orchestration script that handles the entire deployment lifecycle:

```bash
# Full deployment
./deploy-k0rdent.sh deploy

# Check status
./deploy-k0rdent.sh status

# Reset everything
./deploy-k0rdent.sh reset

# Fast reset (Azure-specific)
./deploy-k0rdent.sh reset --fast
```

### Configuration System

YAML-based configuration with multiple deployment sizes:

```bash
# Initialize with production configuration
./bin/configure.sh init --template production

# View available templates
./bin/configure.sh list-templates

# Validate configuration
./bin/configure.sh validate
```

#### Available Configuration Templates

- **minimal**: 1 controller, 1 worker (development)
- **small**: 1 controller, 2 workers (testing)
- **production**: 3 controllers, 2 workers (HA setup)
- **production-spot**: Same as production but using Azure Spot instances
- **single-node**: 1 controller only (minimal testing)
- **large**: 3 controllers, 5 workers (larger deployments)

### State Management

The deployment process tracks state comprehensively:

- **State persistence**: All deployment state saved to `state/deployment-state.yaml`
- **Event tracking**: Detailed event log in `state/deployment-events.yaml`
- **Resume capability**: Interrupted deployments can be resumed
- **Resource verification**: Continuous validation of resource state

### Enhanced VM Deployment

- **Parallel creation**: All VMs created simultaneously
- **Zone distribution**: Automatic HA zone assignment
- **Failure recovery**: Automatic retry on VM creation failures
- **Cloud-init validation**: Ensures proper VM initialization
- **Progress tracking**: Real-time status updates

### Network Security

- **WireGuard VPN**: Secure mesh network for all communications
- **Firewall rules**: Proper NSG configuration
- **SSH lockdown**: Optional SSH access restriction to VPN only
- **Private networking**: All cluster communication over private IPs

## Deployment Workflow

### Option 1: Automated Full Deployment

The recommended approach using the orchestration script:

```bash
# Initialize configuration
./bin/configure.sh init

# Run full deployment
./deploy-k0rdent.sh deploy

# Deploy with optional features
./deploy-k0rdent.sh deploy --with-azure-children

# Deploy with KOF (k0rdent Observability and FinOps)
./deploy-k0rdent.sh deploy --with-kof

# Deploy with all optional components
./deploy-k0rdent.sh deploy --with-azure-children --with-kof -y

# Deploy with desktop notifications (macOS)
./deploy-k0rdent.sh deploy --with-desktop-notifications
```

#### Option 2: Manual Step-by-Step Deployment

If you prefer to run each stage of the deployment manually, first check prerequisites:

```bash
# Check all prerequisites before starting
./bin/check-prerequisites.sh
```

Then run each step:

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
- `--with-desktop-notifications` - Enable desktop notifications (macOS)
- `-h, --help` - Show help message

Examples:
```bash
# Skip all confirmations
./deploy-k0rdent.sh deploy -y

# Deploy with desktop notifications
./deploy-k0rdent.sh deploy --with-desktop-notifications

# Reset without confirmations
./deploy-k0rdent.sh reset --yes

# Fast reset for development
./deploy-k0rdent.sh reset --fast -y
```

## Post-Deployment Operations

### Accessing the Cluster

After successful deployment:

```bash
# Set kubeconfig
export KUBECONFIG=$PWD/k0sctl-config/k0rdent-<deployment-id>-kubeconfig

# Verify cluster access
kubectl get nodes
kubectl get all -A
```

### Managing WireGuard VPN

```bash
# Check VPN status
./bin/manage-vpn.sh status

# Disconnect VPN
./bin/manage-vpn.sh disconnect

# Reconnect VPN
./bin/manage-vpn.sh connect

# View detailed VPN information
./bin/manage-vpn.sh info
```

### Deploying k0rdent Applications

k0rdent is a comprehensive platform that provides:
- Multi-cluster management capabilities
- Infrastructure provisioning across cloud providers
- Application lifecycle management
- Built-in observability and monitoring

After k0rdent is installed, you can:

1. **Deploy child clusters**:
   ```bash
   # Setup Azure for child cluster deployments
   ./bin/setup-azure-cluster-deployment.sh setup
   
   # Create a child cluster
   ./bin/create-azure-child.sh --cluster-name my-child --location eastus
   ```

2. **Access the k0rdent UI**:
   ```bash
   # Port-forward to access k0rdent dashboard
   kubectl port-forward -n kcm-system svc/kcm-gateway 8080:80
   # Open http://localhost:8080 in your browser
   ```

3. **Install applications**:
   - Use k0rdent's application catalog
   - Deploy custom applications via GitOps
   - Manage multi-cluster deployments

### Optional: KOF (k0rdent Operations Framework)

KOF provides centralized observability for k0rdent-managed clusters:

```bash
# Deploy k0rdent with KOF enabled
./deploy-k0rdent.sh deploy --with-kof

# Or install KOF on existing deployment
./bin/install-kof-mothership.sh deploy
./bin/install-kof-regional.sh deploy
```

KOF includes:
- **Mothership cluster**: Central observability hub with Grafana dashboards
- **Regional clusters**: Metrics aggregation points for child clusters
- **Automatic integration**: Child clusters automatically send metrics when labeled appropriately

### Child Cluster Management

k0rdent can manage child clusters across different cloud providers:

```bash
# Azure child clusters
./bin/create-azure-child.sh --cluster-name prod-app --location westus2

# AWS child clusters (requires AWS credentials setup)
./bin/setup-aws-cluster-deployment.sh setup
./bin/create-aws-child.sh --cluster-name dev-app --region us-east-1
```

### Retrieving Kubeconfigs

For any k0rdent-managed cluster:

```bash
# List available cluster kubeconfigs
kubectl get secrets -n kcm-system | grep kubeconfig

# Retrieve a specific cluster's kubeconfig
kubectl get secret <cluster-name>-kubeconfig -n kcm-system -o jsonpath='{.data.value}' | base64 -d > ./k0sctl-config/<cluster-name>-kubeconfig
```

See `backlog/docs/doc-004 - Kubeconfig-Retrieval.md` for detailed kubeconfig retrieval documentation.

For complete KOF deployment instructions, troubleshooting, and advanced usage, refer to the [KOF Documentation](docs/KOF-README.md).

### Configuration Examples

#### Small Development Setup

`config/deployments/dev.yaml`:
```yaml
name: "dev"
size: "small"
k0s:
  controller:
    count: 1
    size: "Standard_B2s"
  worker:
    count: 2
    size: "Standard_B2s"
```

#### Production HA Setup

`config/deployments/prod.yaml`:
```yaml
name: "prod"
size: "production"
azure:
  location: "westus2"
k0s:
  controller:
    count: 3
    size: "Standard_D4s_v5"
  worker:
    count: 5
    size: "Standard_D8s_v5"
```

### Recovery and Cleanup

#### Fast Reset (Development)

For quick iteration during development:

```bash
# Fast reset - deletes Azure resource group and cleans up
./deploy-k0rdent.sh reset --fast -y
```

This:
- Skips individual resource deletion
- Deletes entire Azure resource group
- Cleans up all local files
- Takes seconds instead of minutes

#### Full Reset

For complete cleanup:

```bash
# Full reset with confirmations
./deploy-k0rdent.sh reset

# Skip confirmations
./deploy-k0rdent.sh reset -y
```

#### Resume Interrupted Deployment

If deployment is interrupted:

```bash
# Resume from where it left off
./deploy-k0rdent.sh deploy --resume
```

### Advanced VM Management

The project supports flexible VM configurations:

#### Zone Distribution

VMs are automatically distributed across availability zones:
- Controllers spread across zones 2, 3, 2 (for 3 controllers)
- Workers distributed to maintain balance
- Ensures HA during zone failures

#### Parallel VM Operations

```bash
# Create all VMs in parallel
./bin/create-azure-vms.sh deploy

# Delete all VMs (parallel with --no-wait)
./bin/create-azure-vms.sh reset --no-wait

# Check VM status
./bin/create-azure-vms.sh status
```

#### SSH Access Management

```bash
# List SSH commands for all VMs
./bin/create-azure-vms.sh ssh-info

# Connect to specific VM
ssh -i ./azure-resources/ssh_key azureuser@<public-ip>
```

### Monitoring and Observability

#### Native Kubernetes Monitoring

```bash
# View cluster resources
kubectl top nodes
kubectl top pods -A

# Check cluster health
kubectl get componentstatuses
kubectl get events -A --sort-by='.lastTimestamp'
```

#### KOF Observability Stack

When deployed with `--with-kof`, access Grafana dashboards:

```bash
# Port-forward to Grafana (in KOF mothership)
kubectl port-forward -n kof-monitoring svc/kof-mothership-grafana 3000:80

# Access at http://localhost:3000
# Default credentials are in the deployment
```

### Networking Details

#### WireGuard VPN Topology

```
Laptop (172.24.24.1) ← Hub-and-Spoke → All VMs
         ↓
   Controllers (172.24.24.11-13)
   Workers (172.24.24.14+)
```

#### Network Security Groups

Automatic NSG rules:
- SSH (22): Configurable access
- WireGuard (51820): Public access
- VXLAN (8472): Internal only
- Kubernetes APIs: Internal only
- kubelet (10250): Internal only

#### Private Networking

All cluster communication happens over WireGuard:
- No public endpoints for Kubernetes
- Encrypted node-to-node communication
- Secure laptop-to-cluster access

## Troubleshooting

### Troubleshooting Guides

Detailed troubleshooting guides are available in `backlog/docs/` (filter by type: troubleshooting):
- **KOF Child Cluster Issues**: See `kof-child-cluster-not-deploying.md`

### Common Issues

#### WireGuard Connection Issues

```bash
# Check WireGuard status
./bin/manage-vpn.sh status

# View detailed logs
./bin/manage-vpn.sh info

# Reset WireGuard completely
./bin/manage-vpn.sh reset
```

#### VM Creation Failures

The system automatically retries failed VMs, but if issues persist:

```bash
# Check VM status
./bin/create-azure-vms.sh status

# View Azure logs
az vm list -g <resource-group> -o table

# Manual retry
./bin/create-azure-vms.sh deploy
```

#### State Recovery

If state becomes corrupted:

```bash
# Backup current state
cp -r state/ state.backup/

# Reset and start fresh
./deploy-k0rdent.sh reset --force
```

### Logging and Debugging

All scripts support verbose output:

```bash
# Run any script with verbose logging
DEBUG=1 ./deploy-k0rdent.sh deploy

# Check state files
cat state/deployment-state.yaml
cat state/deployment-events.yaml
```

## Security Considerations

### SSH Access Lockdown

After deployment, you can restrict SSH access to VPN only:

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
export KUBECONFIG=$PWD/k0sctl-config/<cluster-id>-kubeconfig

# Verify cluster is working
kubectl get nodes
kubectl get all -A
```

## Recent Improvements

### January 2025 Updates

- **Unified Naming Convention**: All resource naming now uses a consistent `K0RDENT_CLUSTERID` pattern instead of mixed PREFIX/SUFFIX terminology
- **State Archival**: Deployment state files are automatically archived to `old_deployments/` on reset with descriptive timestamps and reasons
- **Fast Reset**: New `--fast` flag for quick Azure resource cleanup during development iterations (Azure-specific feature)
- **Improved Help**: Enhanced `print_usage()` function with better formatting across all scripts
- **VM Compatibility**: Default VM size changed to `Standard_D2ds_v4` for Gen2 image compatibility
- **WireGuard Config**: Simplified config file naming pattern (`wgk0<suffix>.conf`) for better interface compatibility
- **Monitoring Tools**: Fixed cluster ID detection in monitoring scripts for proper kubeconfig discovery

### State Management Enhancements

- **Archive on Reset**: State files are now archived only during reset operations, not on deployment start
- **Reason Tracking**: Archive function tracks why archives were created (e.g., "fast-reset", "full-reset")
- **Complete Cleanup**: Reset operations now properly clean up all local state files

### Bug Fixes

- Fixed WireGuard VPN disconnection before Azure resource deletion in fast reset
- Fixed network validation for single-worker deployments
- Fixed hardcoded controller names in k0rdent installation script
- Fixed `populate_wg_ips_array()` to handle missing wireguard_peers gracefully

## Development and Project Management

This project uses [Backlog.md](https://github.com/MrLesk/Backlog.md) for task management and documentation. Backlog.md is a markdown-native task management system built specifically for Git repositories.

### Project Structure

```
backlog/
├── tasks/          # Project tasks and feature requests
├── docs/           # Design documents, troubleshooting guides, and technical references
├── decisions/      # Architecture Decision Records (ADRs)
└── completed/      # Archived completed implementation plans
```

### Task Management

```bash
# View all tasks
backlog task list --plain

# View high-priority tasks
backlog task list --plain | grep HIGH

# Work on a task
backlog task edit <task-id> -s "In Progress" -a @yourname

# Create a new task
backlog task create "Task Title" -d "Description" -l "bug,high-priority"

# View task details
backlog task <task-id> --plain
```

### Documentation

- **Design Documents**: Find architecture and design specs in `backlog/docs/` (type: design)
- **Troubleshooting**: Find guides in `backlog/docs/` (type: troubleshooting)
- **Technical References**: API docs and integration guides in `backlog/docs/` (type: reference)
- **Architecture Decisions**: Find ADRs in `backlog/decisions/`

### Contributing

**Prerequisites**: Install [Backlog.md](https://github.com/MrLesk/Backlog.md#installation) for task management:
```bash
# macOS
brew install backlog-md

# Linux/Windows
# See installation instructions at https://github.com/MrLesk/Backlog.md
```

1. Check existing tasks: `backlog task list --plain`
2. Pick or create a task for your work
3. Move task to "In Progress" status
4. Follow the development guidelines in `CLAUDE.md`
5. Update task with implementation notes when complete

For more details on using Backlog.md, see the [official documentation](https://github.com/MrLesk/Backlog.md).

---

**Generated with [Claude Code](https://claude.ai/code)**