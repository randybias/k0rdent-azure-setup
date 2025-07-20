---
id: doc-002
title: Troubleshooting KOF Child Cluster Not Deploying
type: troubleshooting
created_date: '2025-07-20'
---
# Troubleshooting: KOF Components Not Deploying to Child Cluster

## Problem
After creating a child cluster (test2) with the `k0rdent.mirantis.com/kof-cluster-role: child` label, the expected KOF components (cert-manager, kof-operators, kof-collectors) are not being deployed.

## Root Cause
The child cluster was missing the required `k0rdent.mirantis.com/istio-role: child` label. Without this label, the ClusterProfiles that deploy KOF components don't match the cluster.

## Investigation Steps

1. **Check cluster labels**:
```bash
kubectl get clusterdeployment test2 -n kcm-system -o yaml | yq '.metadata.labels'
```

2. **Verify ClusterProfiles requirements**:
```bash
# Check what labels are required for KOF child components
kubectl get clusterprofile kof-istio-child -o yaml | yq '.spec.clusterSelector'
kubectl get clusterprofile kof-istio-network -o yaml | yq '.spec.clusterSelector'
```

3. **Check deployed components**:
```bash
# Get test2 kubeconfig
kubectl get secret test2-kubeconfig -n kcm-system -o jsonpath='{.data.value}' | base64 -d > ./k0sctl-config/test2-kubeconfig

# Check namespaces
export KUBECONFIG=./k0sctl-config/test2-kubeconfig
kubectl get namespaces | grep -E "(kof|istio|cert-manager)"
```

## Solution

Add the missing `istio-role: child` label to the cluster:
```bash
kubectl label clusterdeployment test2 -n kcm-system k0rdent.mirantis.com/istio-role=child
```

## Required Labels for KOF Child Clusters

Based on the ClusterProfiles, child clusters need BOTH labels:
- `k0rdent.mirantis.com/kof-cluster-role: child`
- `k0rdent.mirantis.com/istio-role: child`

## ClusterProfile Mapping

| ClusterProfile | Required Labels | Components Installed |
|----------------|-----------------|---------------------|
| kof-istio-network | `istio-role: child` | cert-manager, Istio CNI |
| kof-istio-child | `istio-role: child` AND `kof-cluster-role: child` | kof-operators, kof-collectors |
| kof-storage-secrets | `kof-storage-secrets: true` | Storage credentials |

## Verification After Fix

After adding the label, wait for Sveltos to reconcile (can take 1-2 minutes), then verify:

1. **Check ClusterSummaries**:
```bash
kubectl get clustersummary -A | grep test2
```

2. **Check components on child cluster**:
```bash
export KUBECONFIG=./k0sctl-config/test2-kubeconfig
kubectl get pods -A | grep -E "(cert-manager|kof|istio)"
```

3. **Verify metrics flow to regional cluster**:
```bash
# On regional cluster
export KUBECONFIG=./k0sctl-config/kof-regional-<name>-kubeconfig
kubectl get pods -n kof-storage | grep vmagent
kubectl logs -n kof-storage deployment/vmagent | grep test2
```

## Additional Notes

- The documentation mentions a "MultiClusterService named kof-child-cluster" but in this deployment, components are deployed via ClusterProfiles instead
- Sveltos reconciliation can take 1-2 minutes after label changes
- If components still don't deploy after labels are correct, check Sveltos manager logs in the management cluster