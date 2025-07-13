# Kubeconfig Retrieval from k0rdent-Managed Clusters

This document describes how to retrieve kubeconfig files for clusters managed by k0rdent.

## Overview

When k0rdent creates a managed cluster (child cluster), it stores the kubeconfig as a Kubernetes Secret in the management cluster. These secrets follow a predictable naming pattern and can be retrieved using kubectl.

## Kubeconfig Secret Location

- **Namespace**: `kcm-system` (k0rdent's management namespace)
- **Secret Name Pattern**: `<cluster-name>-kubeconfig`
- **Secret Type**: `cluster.x-k8s.io/secret`

## Retrieval Process

### 1. List Available Kubeconfig Secrets

```bash
# Set kubeconfig to management cluster
export KUBECONFIG=./k0sctl-config/k0rdent-<deployment-id>-kubeconfig

# List all kubeconfig secrets
kubectl get secrets -n kcm-system | grep kubeconfig
```

### 2. Retrieve a Specific Kubeconfig

```bash
# Basic retrieval command
kubectl get secret <cluster-name>-kubeconfig -n kcm-system -o jsonpath='{.data.value}' | base64 -d > ./k0sctl-config/<cluster-name>-kubeconfig

# Example for KOF regional cluster
kubectl get secret kof-regional-jew408t3-southeastasia-kubeconfig -n kcm-system -o jsonpath='{.data.value}' | base64 -d > ./k0sctl-config/kof-regional-jew408t3-southeastasia-kubeconfig

# Set proper permissions
chmod 600 ./k0sctl-config/<cluster-name>-kubeconfig
```

### 3. Verify the Kubeconfig

```bash
# Test connectivity
export KUBECONFIG=./k0sctl-config/<cluster-name>-kubeconfig
kubectl get nodes
```

## Automated Retrieval in Scripts

The pattern for automated retrieval in bash scripts:

```bash
# Variables
local cluster_name="your-cluster-name"
local kubeconfig_file="./k0sctl-config/${cluster_name}-kubeconfig"

# Retrieve kubeconfig
if kubectl get secret "${cluster_name}-kubeconfig" -n kcm-system -o jsonpath='{.data.value}' | base64 -d > "$kubeconfig_file" 2>/dev/null; then
    chmod 600 "$kubeconfig_file"
    echo "Kubeconfig saved to: $kubeconfig_file"
    
    # Test connectivity
    if KUBECONFIG="$kubeconfig_file" kubectl get nodes &>/dev/null; then
        echo "Kubeconfig verified successfully"
    else
        echo "Warning: Kubeconfig saved but connectivity test failed"
    fi
else
    echo "Failed to retrieve kubeconfig for cluster: $cluster_name"
fi
```

## Common Cluster Types

### KOF Regional Clusters
- **Pattern**: `kof-regional-<suffix>-<location>`
- **Example**: `kof-regional-jew408t3-southeastasia`

### Generic Child Clusters
- **Pattern**: `<custom-cluster-name>`
- **Created via**: `create-child.sh` or k0rdent UI

## Troubleshooting

### Secret Not Found
If the secret doesn't exist immediately after cluster creation:
1. Wait a few minutes for k0rdent to complete cluster provisioning
2. Check cluster deployment status: `kubectl get clusterdeployment <cluster-name> -n kcm-system`
3. Verify the cluster is in Ready state

### Permission Denied
Ensure you have proper RBAC permissions to read secrets in the `kcm-system` namespace.

### Invalid Kubeconfig
If the retrieved kubeconfig doesn't work:
1. Verify the cluster is fully provisioned and running
2. Check if the cluster's API server is accessible (network/firewall issues)
3. Ensure the cluster hasn't been deleted or is in a failed state

## Integration with Scripts

The following scripts in this project handle kubeconfig retrieval:

1. **install-kof-regional.sh**: Automatically retrieves kubeconfig after deploying KOF regional clusters (Step 4)
2. **Future scripts**: Can follow the same pattern for any k0rdent-managed cluster

## Best Practices

1. **Storage Location**: Always store kubeconfigs in `./k0sctl-config/` directory
2. **File Permissions**: Set 600 permissions on kubeconfig files for security
3. **Naming Convention**: Use descriptive names that include cluster type and identifier
4. **Verification**: Always test the kubeconfig after retrieval
5. **Documentation**: Update deployment state or events when kubeconfig is retrieved

## Quick Reference

```bash
# One-liner to retrieve any cluster's kubeconfig
CLUSTER_NAME="your-cluster-name" && kubectl get secret ${CLUSTER_NAME}-kubeconfig -n kcm-system -o jsonpath='{.data.value}' | base64 -d > ./k0sctl-config/${CLUSTER_NAME}-kubeconfig && chmod 600 ./k0sctl-config/${CLUSTER_NAME}-kubeconfig
```