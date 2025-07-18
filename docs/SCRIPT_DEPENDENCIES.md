# Script Dependencies and Interrelationships

## Script Dependency Matrix

| Script | Depends On | Called By | Primary Function |
|--------|------------|-----------|------------------|
| **deploy-k0rdent.sh** | - etc/k0rdent-config.sh<br>- etc/common-functions.sh<br>- All bin/ scripts | User (entry point) | Main orchestrator |
| **bin/prepare-deployment.sh** | - etc/common-functions.sh<br>- etc/state-management.sh | deploy-k0rdent.sh | Generate keys, cloud-init |
| **bin/setup-azure-network.sh** | - etc/common-functions.sh<br>- etc/state-management.sh | deploy-k0rdent.sh | Create Azure infrastructure |
| **bin/create-azure-vms.sh** | - etc/common-functions.sh<br>- etc/state-management.sh | deploy-k0rdent.sh | Provision VMs |
| **bin/manage-vpn.sh** | - etc/common-functions.sh<br>- etc/state-management.sh | deploy-k0rdent.sh | WireGuard VPN management |
| **bin/install-k0s.sh** | - etc/common-functions.sh<br>- etc/state-management.sh | deploy-k0rdent.sh | Deploy k0s cluster |
| **bin/install-k0rdent.sh** | - etc/common-functions.sh<br>- etc/state-management.sh | deploy-k0rdent.sh | Deploy k0rdent |
| **bin/setup-azure-cluster-deployment.sh** | - etc/common-functions.sh<br>- etc/state-management.sh<br>- etc/azure-cluster-functions.sh | deploy-k0rdent.sh (--with-azure-children) | Setup Azure child cluster capability |
| **bin/setup-aws-cluster-deployment.sh** | - etc/common-functions.sh<br>- etc/state-management.sh | User (manual) | Setup AWS child cluster capability |
| **bin/install-k0s-azure-csi.sh** | - etc/common-functions.sh<br>- etc/state-management.sh | deploy-k0rdent.sh (--with-kof) | Install Azure Disk CSI Driver |
| **bin/install-kof-mothership.sh** | - etc/common-functions.sh<br>- etc/state-management.sh<br>- etc/kof-functions.sh | deploy-k0rdent.sh (--with-kof) | Deploy KOF mothership |
| **bin/install-kof-regional.sh** | - etc/common-functions.sh<br>- etc/state-management.sh<br>- etc/kof-functions.sh<br>- etc/azure-cluster-functions.sh | deploy-k0rdent.sh (--with-kof) | Deploy KOF regional cluster |
| **bin/lockdown-ssh.sh** | - etc/common-functions.sh | User (optional) | Security hardening |
| **bin/create-azure-child.sh** | - etc/common-functions.sh<br>- etc/state-management.sh | User (manual) | Create Azure k0rdent child clusters |
| **bin/create-aws-child.sh** | - etc/common-functions.sh<br>- etc/state-management.sh | User (manual) | Create AWS k0rdent child clusters |
| **bin/configure.sh** | None | etc/k0rdent-config.sh | YAML config parser |
| **etc/k0rdent-config.sh** | - bin/configure.sh<br>- etc/config-internal.sh | All scripts | Configuration loader |
| **etc/config-internal.sh** | None | etc/k0rdent-config.sh | Dynamic value computation |
| **etc/common-functions.sh** | None | All scripts | Shared utilities |
| **etc/state-management.sh** | - etc/common-functions.sh | Most bin/ scripts | State tracking |
| **etc/azure-cluster-functions.sh** | - etc/common-functions.sh | Azure cluster scripts | Azure child cluster utilities |
| **etc/kof-functions.sh** | - etc/common-functions.sh | KOF scripts | KOF-specific utilities |

## Data Flow Between Scripts

```
User Input → deploy-k0rdent.sh
    ↓
Configuration Loading:
    → etc/k0rdent-config.sh
        → bin/configure.sh (YAML parsing)
        → etc/config-internal.sh (compute values)
    ↓
Deployment Steps (sequential):
    → bin/prepare-deployment.sh
        - Generates WireGuard keys
        - Creates cloud-init files
        - Updates state with keys
    ↓
    → bin/setup-azure-network.sh
        - Creates resource group, VNet, subnet, NSG
        - Generates SSH keys
        - Updates state with Azure resources
    ↓
    → bin/create-azure-vms.sh
        - Provisions VMs in parallel
        - Monitors creation status
        - Updates state with VM IPs
    ↓
    → bin/manage-vpn.sh (setup)
        - Generates laptop WireGuard config
        - Updates state with VPN config
    ↓
    → bin/manage-vpn.sh (connect)
        - Establishes VPN connection
        - Tests connectivity
        - Updates connection state
    ↓
    → bin/install-k0s.sh
        - Generates k0sctl config
        - Deploys k0s cluster
        - Updates state with cluster info
    ↓
    → bin/install-k0rdent.sh
        - Installs Helm
        - Deploys k0rdent
        - Updates final state
    ↓
Optional Components (if enabled):
    → bin/setup-azure-cluster-deployment.sh (--with-azure-children)
        - Configures Azure credentials
        - Sets up k0rdent for Azure child clusters
    ↓
    → bin/install-k0s-azure-csi.sh (--with-kof)
        - Installs Azure Disk CSI Driver
        - Required for KOF persistent storage
    ↓
    → bin/install-kof-mothership.sh (--with-kof)
        - Deploys Istio service mesh
        - Installs KOF operators
        - Deploys KOF mothership
    ↓
    → bin/install-kof-regional.sh (--with-kof)
        - Creates KOF regional cluster
        - Configures observability/FinOps collection
    ↓
State Backup → old_deployments/
```

## Shared Resources and Communication

### 1. Configuration Variables
- **Source**: YAML files → shell variables
- **Propagation**: Via sourcing etc/k0rdent-config.sh
- **Key Variables**:
  - `CLUSTER_NAME`
  - `RESOURCE_GROUP`
  - `VM_COUNT`, `CONTROLLER_COUNT`, `WORKER_COUNT`
  - `LOCATION`, `VM_SIZE`, `OS_DISK_SIZE`
  - `VNET_NAME`, `SUBNET_NAME`, `NSG_NAME`

### 2. State File (deployment-state.yaml)
- **Managed by**: etc/state-management.sh
- **Updated by**: All deployment scripts
- **Contains**:
  - Deployment metadata
  - Phase completion status
  - Resource identifiers
  - VM information
  - WireGuard configurations
  - Cluster status

### 3. File System Artifacts
- **WireGuard Keys**: `wireguard-keys/` directory
- **Cloud-init Files**: `cloud-init-files/` directory
- **k0sctl Config**: `./k0sctl-config/${K0RDENT_PREFIX}-k0sctl.yaml`
- **Kubeconfig**: `./k0sctl-config/${K0RDENT_PREFIX}-kubeconfig`
- **Laptop WireGuard Config**: `./wireguard/wgk0${RANDOM_SUFFIX}.conf`

### 4. Function Libraries

#### etc/common-functions.sh provides:
- `log_*` functions (info, success, error, warning)
- `check_prerequisites`
- `check_az_logged_in`
- `generate_random_suffix`
- `test_ssh_connectivity`
- `execute_on_vm`
- `manage_wireguard_interface` (macOS specific)
- `get_vm_ips`
- `display_status`

#### etc/state-management.sh provides:
- `init_state`
- `update_phase`
- `update_resource`
- `update_vm_state`
- `get_vm_state`
- `update_wireguard_peer`
- `backup_deployment`
- `cleanup_old_deployments`

## Script Interaction Patterns

### 1. Sequential Dependency
Each script depends on the successful completion of the previous:
- Network setup requires prepared deployment
- VM creation requires network infrastructure
- VPN setup requires running VMs
- k0s installation requires VPN connectivity
- k0rdent installation requires k0s cluster

### 2. State-Driven Execution
Scripts check state before executing:
```bash
# Example from install-k0s.sh
if [[ $(get_state_value "phases.create_vms") != "true" ]]; then
    log_error "VMs not created yet"
    exit 1
fi
```

### 3. Error Propagation
Errors cause immediate exit, preventing subsequent steps:
```bash
# In deploy-k0rdent.sh
execute_step "prepare-deployment" || handle_error
execute_step "setup-network" || handle_error
# etc...
```

### 4. Reset Cascade
Reset operations work in reverse order:
- Uninstall k0rdent → Uninstall k0s → Disconnect VPN → Delete VMs → Delete Network

## Key Design Principles

1. **Loose Coupling**: Scripts communicate via state file, not direct calls
2. **Single Responsibility**: Each script handles one specific task
3. **Idempotency**: Scripts can be run multiple times safely
4. **State Persistence**: All important data saved to state file
5. **Error Recovery**: State enables resumption after failures
6. **Modularity**: Easy to add/modify individual components