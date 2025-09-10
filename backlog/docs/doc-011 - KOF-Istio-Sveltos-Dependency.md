# doc-011 - KOF Istio Sveltos Dependency

**Type**: troubleshooting  
**Created**: 2025-09-10  
**Status**: resolved

## Problem Description

When installing KOF (K0rdent Operations Framework) on a k0rdent cluster, the Istio installation step was failing with the error:

```
Error: unable to build kubernetes objects from release manifest: 
resource mapping not found for name: "kof-istio-namespaces" namespace: "" 
from "": no matches for kind "ClusterProfile" in version "config.projectsveltos.io/v1beta1"
ensure CRDs are installed first
```

## Root Cause

The `kof-istio` Helm chart (version 1.3.0) contains ClusterProfile resources from the Sveltos project. These CRDs are installed as part of k0rdent deployment but may not be immediately available when KOF installation begins. The original `install_istio_for_kof` function in `etc/kof-functions.sh` did not wait for these CRDs to be present before attempting the Helm installation.

## Solution

Modified the `install_istio_for_kof` function to:

1. **Wait for CRDs**: Added a retry loop that waits up to 10 minutes (configurable) for the ClusterProfile CRD to become available
2. **Check controller readiness**: Additionally verify that Sveltos controllers are running before proceeding
3. **Provide feedback**: Show progress messages during the wait period

### Code Changes

File: `etc/kof-functions.sh`

The function now includes:
- Timeout loop checking for `clusterprofiles.config.projectsveltos.io` CRD
- Secondary check for Sveltos controller deployment readiness
- Clear error messages if timeout occurs

## Configuration

Ensure the KOF version in `config/k0rdent.yaml` matches available chart versions:

```yaml
kof:
  enabled: true
  version: "1.3.0"  # Must match available chart version
  istio:
    version: "1.3.0"  # Should match KOF version for compatibility
```

## Testing

After implementing the fix:
1. Istio successfully installed after waiting for CRDs
2. KOF operators installed correctly
3. KOF mothership installation proceeded (may fail due to resource constraints on small clusters)

## Recommendations

1. **Cluster sizing**: Ensure adequate CPU resources on worker nodes for KOF components
2. **Version alignment**: Keep KOF and Istio chart versions aligned
3. **Deployment order**: Always deploy k0rdent fully before attempting KOF installation

## Related Files

- `etc/kof-functions.sh` - Contains the fixed `install_istio_for_kof` function
- `bin/install-kof-mothership.sh` - Calls the Istio installation function
- `config/k0rdent.yaml` - Configuration file with KOF versions