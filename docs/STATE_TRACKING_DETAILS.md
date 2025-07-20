# State Tracking Details - When and How State is Updated

## State Management Overview

The k0rdent Azure setup uses a centralized state tracking system managed by `etc/state-management.sh`. All state is persisted in `deployment-state.yaml` and updated at key points during deployment.

## State Update Timeline

### 1. Initial State Creation
**When**: Start of `prepare-deployment.sh`
**Function**: `init_state`
```yaml
deployment:
  id: "k0rdent-CLUSTERID"
  started_at: "2024-01-20T10:00:00Z"
phases:
  prepare_deployment: false
  setup_network: false
  create_vms: false
  setup_vpn: false
  connect_vpn: false
  install_k0s: false
  install_k0rdent: false
```

### 2. WireGuard Key Generation
**When**: During `prepare-deployment.sh` after generating keys
**Function**: `update_wireguard_peer`
```yaml
wireguard:
  peers:
    laptop:
      public_key: "generated-public-key"
      wireguard_ip: "192.168.100.1"
    k0rdent-vm1:
      public_key: "generated-public-key"
      wireguard_ip: "192.168.100.11"
```

### 3. Prepare Deployment Complete
**When**: End of `prepare-deployment.sh`
**Function**: `update_phase`
```yaml
phases:
  prepare_deployment: true  # Updated
```

### 4. Azure Resource Creation
**When**: During `setup-azure-network.sh` as each resource is created
**Function**: `update_resource`
```yaml
resources:
  resource_group: "k0rdent-rg-CLUSTERID"     # After RG creation
  vnet: "k0rdent-vnet-CLUSTERID"             # After VNet creation
  subnet: "k0rdent-subnet-CLUSTERID"         # After Subnet creation
  nsg: "k0rdent-nsg-CLUSTERID"               # After NSG creation
  ssh_key: "k0rdent-ssh-key-CLUSTERID"       # After SSH key import
```

### 5. Network Setup Complete
**When**: End of `setup-azure-network.sh`
**Function**: `update_phase`
```yaml
phases:
  setup_network: true  # Updated
```

### 6. VM Creation Updates
**When**: During `create-azure-vms.sh` for each VM
**Function**: `update_vm_state`

**Step 1 - VM Creation Started**:
```yaml
vms:
  k0rdent-vm1:
    name: "k0rdent-vm1-CLUSTERID"
    status: "creating"
```

**Step 2 - VM Running with IPs**:
```yaml
vms:
  k0rdent-vm1:
    name: "k0rdent-vm1-CLUSTERID"
    public_ip: "20.x.x.x"
    private_ip: "10.0.1.11"
    wireguard_ip: "192.168.100.11"
    status: "running"
```

### 7. All VMs Created
**When**: End of `create-azure-vms.sh`
**Function**: `update_phase`
```yaml
phases:
  create_vms: true  # Updated
```

### 8. VPN Configuration
**When**: During `manage-vpn.sh setup`
**Function**: `update_resource`
```yaml
resources:
  vpn_config_created: true
```

### 9. VPN Setup Complete
**When**: End of `manage-vpn.sh setup`
**Function**: `update_phase`
```yaml
phases:
  setup_vpn: true  # Updated
```

### 10. VPN Connection Status
**When**: During `manage-vpn.sh connect`
**Function**: `update_resource`
```yaml
resources:
  vpn_connected: true
```

### 11. VPN Connected
**When**: End of `manage-vpn.sh connect`
**Function**: `update_phase`
```yaml
phases:
  connect_vpn: true  # Updated
```

### 12. k0s Cluster Deployment
**When**: During `install-k0s.sh`
**Function**: `update_resource`

**After k0sctl config generation**:
```yaml
resources:
  k0sctl_config_generated: true
```

**After cluster deployment**:
```yaml
cluster:
  k0s_deployed: true
  kubeconfig_retrieved: false
```

**After kubeconfig retrieval**:
```yaml
cluster:
  k0s_deployed: true
  kubeconfig_retrieved: true
```

### 13. k0s Installation Complete
**When**: End of `install-k0s.sh`
**Function**: `update_phase`
```yaml
phases:
  install_k0s: true  # Updated
```

### 14. k0rdent Deployment
**When**: During `install-k0rdent.sh`
**Function**: `update_resource`

**After Helm installation**:
```yaml
resources:
  helm_installed: true
```

**After k0rdent deployment**:
```yaml
cluster:
  k0rdent_ready: true
```

### 15. Deployment Complete (Base k0rdent)
**When**: End of `install-k0rdent.sh` (if no optional components)
**Function**: `update_phase` and `backup_deployment`
```yaml
phases:
  install_k0rdent: true  # Updated
deployment:
  completed_at: "2024-01-20T11:30:00Z"
```

### 16. Azure Child Cluster Setup (Optional)
**When**: During `setup-azure-cluster-deployment.sh` (--with-azure-children)
**Function**: `update_state`
```yaml
azure_children:
  credentials_configured: true
  cluster_api_ready: true
  azure_provider_ready: true
```

### 17. Azure CSI Installation (Optional)
**When**: During `install-k0s-azure-csi.sh` (--with-kof)
**Function**: `update_state`
```yaml
azure_csi_installed: true
storage_class: "azure-disk-csi"
```

### 18. KOF Mothership Deployment (Optional)
**When**: During `install-kof-mothership.sh` (--with-kof)
**Function**: `update_state`

**After Istio installation**:
```yaml
kof_istio_installed: true
```

**After KOF operators**:
```yaml
kof_operators_installed: true
```

**After mothership deployment**:
```yaml
kof_mothership_installed: true
kof_mothership_version: "1.1.0"
kof_mothership_namespace: "kof"
```

### 19. KOF Regional Cluster (Optional)
**When**: During `install-kof-regional.sh` (--with-kof)
**Function**: `update_state` and `update_cluster_state`

**Cluster creation tracking**:
```yaml
kof_regional_deployed: true
kof_regional_cluster_name: "kof-regional-CLUSTERID-southeastasia"
kof_regional_domain: "regional.example.com"
```

**Separate cluster state file**: `state/cluster-<cluster-name>-events.yaml`
```yaml
cluster_name: "kof-regional-CLUSTERID-southeastasia"
events:
  - timestamp: "2024-01-20T11:45:00Z"
    action: cluster_deployment_created
    message: "ClusterDeployment created for azure cluster"
```

### 20. Final Deployment Complete
**When**: After all optional components
**Function**: `update_phase` and `backup_deployment`
```yaml
phases:
  install_k0rdent: true
  setup_azure_children: true     # If --with-azure-children
  install_kof: true               # If --with-kof
deployment:
  completed_at: "2024-01-20T12:00:00Z"
```

## State Management Functions

### Core State Functions

| Function | Purpose | When Called |
|----------|---------|-------------|
| `init_state` | Creates initial state file | Start of deployment |
| `update_phase` | Marks deployment phase complete | End of each script |
| `update_resource` | Updates resource status | After resource creation |
| `update_vm_state` | Updates VM information | During VM operations |
| `update_wireguard_peer` | Saves WireGuard configs | After key generation |
| `get_state_value` | Reads state values | Throughout scripts |
| `backup_deployment` | Archives completed state | End of deployment |

### State Caching Mechanism

**Purpose**: Reduce Azure API calls by caching VM information

```bash
# Cache implementation in state-management.sh
declare -A VM_CACHE
declare -A VM_CACHE_TIME

# Cache expires after 300 seconds (5 minutes)
CACHE_TTL=300

# Function checks cache before querying Azure
get_vm_ips() {
    local vm_name=$1
    local cache_key="${vm_name}_ips"
    
    # Check if cache is valid
    if [[ -n "${VM_CACHE[$cache_key]}" ]]; then
        local cache_age=$(($(date +%s) - ${VM_CACHE_TIME[$cache_key]}))
        if [[ $cache_age -lt $CACHE_TTL ]]; then
            echo "${VM_CACHE[$cache_key]}"
            return 0
        fi
    fi
    
    # Cache miss - query Azure and update cache
    local ips=$(query_azure_for_ips "$vm_name")
    VM_CACHE[$cache_key]="$ips"
    VM_CACHE_TIME[$cache_key]=$(date +%s)
}
```

## State File Locations

| File | Purpose | Persistence |
|------|---------|-------------|
| `deployment-state.yaml` | Active deployment state | Current deployment |
| `old_deployments/k0rdent-CLUSTERID/` | Archived deployments | Historical record |
| `wireguard-keys/` | WireGuard keys | Deployment lifetime |
| `cloud-init-files/` | VM provisioning data | Deployment lifetime |

## State-Driven Decision Making

Scripts use state to determine actions:

```bash
# Example: Skip if already completed
if [[ $(get_state_value "phases.setup_network") == "true" ]]; then
    log_info "Network already set up, skipping..."
    return 0
fi

# Example: Verify prerequisites
if [[ $(get_state_value "phases.create_vms") != "true" ]]; then
    log_error "VMs must be created before installing k0s"
    exit 1
fi

# Example: Get resource information
RESOURCE_GROUP=$(get_state_value "resources.resource_group")
if [[ -z "$RESOURCE_GROUP" ]]; then
    log_error "Resource group not found in state"
    exit 1
fi
```

## State Cleanup and Reset

During reset operations, state is cleaned in reverse order:

1. Mark k0rdent as uninstalled
2. Mark k0s as undeployed  
3. Clear VPN connection status
4. Remove VM entries
5. Clear Azure resources
6. Reset phase flags
7. Archive final state

## Best Practices for State Management

1. **Always update state after successful operations**
2. **Check state before destructive operations**
3. **Use state for idempotency checks**
4. **Cache expensive queries when appropriate**
5. **Backup state after major milestones**
6. **Never manually edit state files**
7. **Use provided state management functions**