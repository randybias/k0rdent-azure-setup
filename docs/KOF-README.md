# KOF (k0rdent Operations Framework) Documentation

## Overview

KOF (k0rdent Operations Framework) is an optional observability and FinOps platform that can be deployed on top of k0rdent-managed Kubernetes clusters. It provides comprehensive monitoring, metrics collection, and cost analysis capabilities using an Istio-based service mesh architecture.

## Architecture

KOF uses a hierarchical architecture with three main components:

1. **Mothership** - Deployed on the k0rdent management cluster, coordinates the entire KOF deployment
2. **Regional Clusters** - Separate k0rdent-managed clusters that aggregate metrics from child clusters
3. **Child Clusters** - Any k0rdent-managed cluster with KOF components for metrics collection

```
┌─────────────────────────┐
│   Management Cluster    │
│  ┌─────────────────┐   │
│  │ KOF Mothership  │   │
│  │   + Istio       │   │
│  └────────┬────────┘   │
└───────────┼─────────────┘
            │
    ┌───────┴────────┐
    │                │
┌───▼──────────┐ ┌──▼───────────┐
│  Regional 1  │ │  Regional 2  │
│   Cluster    │ │   Cluster    │
└───┬──────────┘ └──┬───────────┘
    │               │
┌───┴───┐       ┌───┴───┐
│Child 1│  ...  │Child N│
└───────┘       └───────┘
```

## Prerequisites

Before deploying KOF, ensure you have:

1. **k0rdent deployed** - A working k0rdent management cluster
2. **Azure child cluster capability** - Configured with `setup-azure-cluster-deployment.sh`
3. **VPN connectivity** - Active WireGuard connection to the management cluster
4. **Azure Disk CSI Driver** - Automatically installed when using `--with-kof`

## Quick Start

### Deploy KOF with k0rdent

The easiest way to deploy KOF is during initial k0rdent deployment:

```bash
./deploy-k0rdent.sh deploy --with-kof
```

This will:
1. Deploy the base k0rdent cluster
2. Configure Azure child cluster deployment capability
3. Install Azure Disk CSI Driver for persistent storage
4. Deploy KOF mothership with Istio
5. Create a KOF regional cluster in Azure
6. Configure observability and metrics collection

### Add KOF to Existing k0rdent

If you already have k0rdent deployed, you can add KOF:

```bash
# Step 1: Configure Azure child cluster capability (if not already done)
./bin/setup-azure-cluster-deployment.sh deploy

# Step 2: Install Azure Disk CSI Driver
./bin/install-k0s-azure-csi.sh deploy

# Step 3: Deploy KOF mothership
./bin/install-kof-mothership.sh deploy

# Step 4: Deploy KOF regional cluster
./bin/install-kof-regional.sh deploy
```

## Configuration

KOF configuration is integrated into the main k0rdent YAML configuration files. Here's an example:

```yaml
# config/k0rdent.yaml
kof:
  enabled: true  # Enable KOF deployment
  version: "1.1.0"
  
  # Istio configuration for KOF
  istio:
    version: "1.1.0"
    namespace: "istio-system"
  
  # Mothership configuration
  mothership:
    namespace: "kof"
    storage_class: "default"
    collectors:
      global: {}  # Custom global collectors can be added here
  
  # Regional cluster configuration
  regional:
    cluster_name: ""  # Will default to ${K0RDENT_CLUSTERID}-regional
    domain: "regional.example.com"  # Required for KOF regional cluster
    admin_email: "admin@example.com"  # Required for KOF certificates
    location: "southeastasia"  # Azure region for regional cluster
    template: "azure-standalone-cp-1-0-8"  # k0rdent cluster template
    credential: "azure-cluster-credential"  # Azure credential name
    cp_instance_size: "Standard_A4_v2"  # Control plane VM size
    worker_instance_size: "Standard_A4_v2"  # Worker node VM size
    root_volume_size: "32"  # Root volume size in GB
```

## Deployment Components

### 1. KOF Mothership

The mothership is deployed on the k0rdent management cluster and includes:

- **Istio Service Mesh** - Provides secure communication and traffic management
- **KOF Operators** - Manage KOF components across clusters
- **ClusterProfiles** - Define KOF configuration for different cluster types

```bash
# Deploy mothership
./bin/install-kof-mothership.sh deploy

# Check status
./bin/install-kof-mothership.sh status

# Uninstall if needed
./bin/install-kof-mothership.sh uninstall
```

### 2. KOF Regional Cluster

Regional clusters are separate k0rdent-managed clusters that:

- Aggregate metrics from multiple child clusters
- Provide centralized dashboards and alerting
- Store long-term metrics data

```bash
# Deploy regional cluster
./bin/install-kof-regional.sh deploy

# The script will:
# - Create a new Azure cluster via k0rdent
# - Apply KOF ClusterProfiles
# - Configure observability components
# - Retrieve and save the kubeconfig
```

The regional cluster kubeconfig is automatically saved to:
```
k0sctl-config/kof-regional-<deployment-id>-<location>-kubeconfig
```

### 3. KOF on Child Clusters

Child clusters can be created with KOF support using:

```bash
# Create a child cluster with KOF enabled
./bin/create-child.sh --cluster-name my-child --with-kof

# List all child clusters
./bin/list-child-clusters.sh
```

## Managing KOF Clusters

### Accessing the Regional Cluster

After deployment, access the regional cluster:

```bash
# Set kubeconfig
export KUBECONFIG=$PWD/k0sctl-config/kof-regional-*-kubeconfig

# Verify access
kubectl get nodes
kubectl get pods -n kof
```

### Viewing KOF Components

Check KOF components across namespaces:

```bash
# On management cluster
kubectl get pods -n kof
kubectl get pods -n istio-system

# Check ClusterProfiles
kubectl get clusterprofiles -A

# View KOF CRDs
kubectl get kofs -A
```

### Monitoring Child Clusters

Verify child clusters are properly connected:

```bash
# Check cluster labels
kubectl get clusters -A --show-labels | grep istio-role

# Verify ClusterProfile application
kubectl get clusterprofiles -A
```

## Troubleshooting

### Common Issues

1. **PVCs Not Binding**
   - Ensure Azure Disk CSI Driver is installed
   - Check storage class exists: `kubectl get storageclass`

2. **Child Cluster Not Receiving KOF**
   - Verify cluster has label: `k0rdent.mirantis.com/istio-role: child`
   - Check ClusterProfile status: `kubectl get clusterprofile -n <namespace>`

3. **Regional Cluster Creation Fails**
   - Check Azure credentials: `kubectl get secret -n kcm-system | grep azure`
   - Verify ClusterDeployment status: `kubectl get clusterdeployments -A`

### Debug Commands

```bash
# Check Istio installation
kubectl get pods -n istio-system

# Verify KOF operators
kubectl get pods -n kof | grep operator

# Check cluster provisioning logs
kubectl logs -n kcm-system deploy/kcm-controller-manager

# View ClusterDeployment events
kubectl describe clusterdeployment -n <namespace> <cluster-name>
```

## Advanced Usage

### Custom Collectors

Add custom Prometheus collectors to the configuration:

```yaml
kof:
  mothership:
    collectors:
      global:
        custom-exporter:
          image: "prom/node-exporter:latest"
          port: 9100
```

### Multi-Regional Deployment

Deploy multiple regional clusters in different Azure regions:

```bash
# Modify config for different region
yq eval '.kof.regional.location = "westus2"' -i config/k0rdent.yaml

# Deploy additional regional cluster
./bin/install-kof-regional.sh deploy
```

### Backup and Restore

Currently, backup is a manual process:

```bash
# Backup KOF CRDs and configurations
kubectl get clusterprofiles -A -o yaml > kof-clusterprofiles-backup.yaml
kubectl get kofs -A -o yaml > kof-resources-backup.yaml
```

## Architecture Details

### Label Requirements

KOF uses specific labels to identify cluster roles:

- **Management cluster**: No special labels required
- **Regional clusters**: `k0rdent.mirantis.com/istio-role: child`
- **Child clusters**: `k0rdent.mirantis.com/istio-role: child`

Note: Both regional and child clusters use the "child" label - this is intentional in the Istio deployment model.

### ClusterProfile Application

KOF uses ClusterProfiles to deploy components based on cluster labels:

1. **kof-clusterprofile-kof-child** - Applied to clusters with `kof-cluster-role: child`
2. **kof-clusterprofile-istio-child** - Applied to clusters with `istio-role: child`

### Data Flow

1. Child clusters collect metrics using Prometheus exporters
2. Metrics are forwarded to regional clusters via Istio mesh
3. Regional clusters aggregate and store data in VictoriaMetrics
4. Grafana dashboards provide visualization
5. Alertmanager handles alert routing

## Uninstalling KOF

To remove KOF components:

```bash
# Remove from child clusters first
kubectl delete clusterprofile -A kof-clusterprofile-kof-child
kubectl delete clusterprofile -A kof-clusterprofile-istio-child

# Delete regional cluster
./bin/install-kof-regional.sh uninstall

# Remove mothership
./bin/install-kof-mothership.sh uninstall

# Optionally remove CSI driver
./bin/install-k0s-azure-csi.sh uninstall
```

## Integration with k0rdent

KOF is designed to integrate seamlessly with k0rdent's cluster management:

- Uses k0rdent's ClusterDeployment for regional clusters
- Leverages k0rdent's credential management
- Integrates with k0rdent's state tracking
- Follows k0rdent's modular script approach

## Next Steps

1. **Deploy test workloads** on child clusters to generate metrics
2. **Access Grafana** on the regional cluster to view dashboards
3. **Configure alerts** based on your monitoring requirements
4. **Scale out** by adding more child clusters as needed

## Additional Resources

- [Official KOF Documentation](https://docs.k0rdent.io/latest/admin/kof/kof-install/)
- [Istio Documentation](https://istio.io/latest/docs/)
- [k0rdent Documentation](https://docs.k0rdent.io/)

---

For related tasks and implementation details, see KOF-related tasks in `backlog/tasks/` (use `backlog task list --plain | grep -i kof`)