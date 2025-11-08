# Change Proposal: Ensure Azure Credential Cleanup During Reset

**Created**: 2025-11-07  
**Author**: Droid (droid@factory.ai)  
**Status:** Draft  

## Summary

The `bin/setup-azure-cluster-deployment.sh` script creates Azure service principal credentials for child cluster deployment, but these credentials are not automatically cleaned up during a general deployment reset. The credentials remain orphaned in Azure since they're not part of the resource group that gets deleted. This change ensures Azure credentials are properly cleaned up during any deployment reset operation.

## Problem Statement

Currently, when Azure credentials are configured using `setup-azure-cluster-deployment.sh setup`, the script:
1. Creates Azure Service Principal with contributor role
2. Stores credentials in local files and Kubernetes secrets
3. Records state tracking in azure-state.yaml
4. However, during `deploy-k0rdent.sh reset`, only network resources are deleted
5. The Azure Service Principal and associated credentials remain active in Azure
6. This leaves orphaned, potentially privileged credentials in the user's Azure subscription

## Proposed Solution

Integrate automatic Azure credential cleanup into the main deployment reset workflow by:
1. Detecting when Azure credentials have been configured via state tracking
2. Automatically calling the existing cleanup function during deployment reset
3. Ensuring cleanup occurs even if the Kubernetes cluster is no longer accessible
4. Providing clear cleanup status and error handling

## Scope

**In Scope:**
- Integration with existing `cleanup_azure_credentials()` function
- Automatic detection of Azure credential configuration
- Integration with main deployment reset workflow
- Graceful handling of cleanup failures
- Status reporting and logging

**Out of Scope:**
- Changes to the credential creation logic
 modifications to Azure resource group deletion
- Multi-tenant Azure account considerations
- Azure credential rotation policies

## Success Criteria

1. Azure Service Principal credentials are automatically deleted during deployment reset
2. Cleanup occurs regardless of cluster accessibility
3. Existing manual cleanup functionality remains available
4. Clear status reporting shows cleanup success/failure
5. Deployment reset does not fail due to credential cleanup issues

## Impact Analysis

- **Security**: Eliminates orphaned Azure credentials with contributor permissions
- **Cost**: No additional cost implications
- **User Experience**: Automatic credential cleanup reduces manual cleanup requirements
- **Risk**: Low - uses existing cleanup functions with enhanced integration

## Dependencies

- Existing `cleanup_azure_credentials()` function in `setup-azure-cluster-deployment.sh`
- Current Azure state tracking system
- Existing deployment reset workflow in `deploy-k0rdent.sh`

## Considerations

- **Offline Cleanup**: Credentials can be deleted even if Kubernetes cluster is unavailable
- **Permission Handling**: User must have sufficient Azure permissions to delete service principals
- **Error Resilience**: Reset should continue even if Azure cleanup fails
- **Visibility**: Clear logging shows what was cleaned up vs what failed
