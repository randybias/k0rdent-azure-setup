# Design: Azure Credential Cleanup During Reset

## Architecture Overview

The solution builds upon the existing cleanup functionality and integrates automatic Azure credential cleanup into the deployment reset workflow. The approach uses state detection to trigger cleanup when appropriate.

## Current State Analysis

### Existing Infrastructure
- **cleanup_azure_credentials()**: Comprehensive cleanup function that handles:
  - Kubernetes resources (secrets, credentials, identities, configmaps)
  - Azure Service Principal deletion
  - Local credential file removal
  - State management updates
- **Azure State Tracking**: azure-state.yaml tracks credential configuration status
- **Manual Cleanup**: Available via `./setup-azure-cluster-deployment.sh cleanup`

### Current Gap
- **Main Deployment Reset**: `deploy-k0rdent.sh reset` does NOT call Azure credential cleanup
- **Orphaned Credentials**: Service principals remain active in Azure subscription
- **Manual Intervention Required**: Users must manually run cleanup or delete credentials

## Implementation Strategy

### 1. State-Driven Cleanup Detection

**Detection Logic:**
```bash
integrate_azure_cleanup_if_needed() {
    # Check if Azure credentials were configured
    if [[ "$(get_azure_state "azure_credentials_configured")" == "true" ]]; then
        print_info "Cleaning up Azure credentials..."
        ./bin/setup-azure-cluster-deployment.sh cleanup -y
    fi
}
```

**Integration Points:**
- Main deployment reset workflow in `deploy-k0rdent.sh`
- Phase reset logic using existing state tracking
- Conditional cleanup only when credentials exist

### 2. Cleanup Lifecycle Management

**Cleanup Categories:**
1. **Kubernetes Resources** (if cluster accessible):
   - Service principal secrets
   - AzureClusterIdentity resources
   - KCM Credential objects
   - ConfigMap templates

2. **Azure Resources** (always attempted):
   - Service Principal deletion via Azure CLI
   - Local credential file removal

3. **State Cleanup** (always):
   - Azure state file updates
   - Phase reset markers
   - Event logging

### 3. Error Handling and Resilience

**Error Categories:**
- **Azure Permission Errors**: Cannot delete Service Principal
- **Cluster Unreachable**: Kubernetes cleanup not possible
- **State File Corruption**: Cannot read/write Azure state

**Error Response Strategy:**
- **Continue Reset**: Main deployment reset continues regardless of cleanup failures
- **Clear Logging**: Explicit messages about what succeeded/failed
- **Manual Cleanup Guidance**: Instructions for manual completion if needed

## Technical Implementation Details

### Integration with Deployment Reset

**Current Reset Flow:**
```
deploy-k0rdent.sh reset
├── Archive existing state
├── Reset k0rdent components
├── Reset k0s cluster
├── Reset VPN
├── Reset VMs
├── Reset network
└── Archive deployment files
```

**Enhanced Reset Flow:**
```
deploy-k0rdent.sh reset
├── Archive existing state
├── Reset k0rdent components
├── Reset k0s cluster
├── Reset VPN
├── Reset VMs
├── Reset network
├── NEW: Clean up Azure credentials (if configured)
│   ├── Check azure state for credential configuration
│   ├── Call setup-azure-cluster-deployment.sh cleanup -y
│   └── Log cleanup results
└── Archive deployment files
```

### Function Implementation

**Main Integration Function:**
```bash
integrate_azure_cleanup_in_reset() {
    print_header "Checking for Azure Credentials Cleanup"
    
    # Check local state first
    if [[ -f "$AZURE_STATE_FILE" ]]; then
        local credentials_configured=$(get_azure_state "azure_credentials_configured" 2>/dev/null || echo "false")
        
        if [[ "$credentials_configured" == "true" ]]; then
            print_info "Azure credentials were configured - initiating cleanup..."
            
            # Call existing cleanup function with auto-confirm
            export SKIP_CONFIRMATION="true"
            if bash ./bin/setup-azure-cluster-deployment.sh cleanup; then
                print_success "Azure credentials cleaned up successfully"
                add_event "azure_credentials_auto_cleanup" "Azure credentials automatically cleaned up during reset"
            else
                print_warning "Azure credentials cleanup encountered issues"
                print_info "Manual cleanup may be required with: ./setup-azure-cluster-deployment.sh cleanup"
                add_event "azure_credentials_cleanup_partial" "Azure credentials cleanup partially failed during reset"
            fi
        else
            print_info "No Azure credentials to clean up"
        fi
    else
        print_info "Azure state file not found - no credentials to clean up"
    fi
    
    unset SKIP_CONFIRMATION
}
```

### State Management Integration

**State File Updates:**
- Cleanup results recorded in azure-events.yaml
- Phase reset markers updated appropriately
- Automatic cleanup events logged for audit trail

**Cleanup Validation:**
- Verify Azure service principal deletion (if possible)
- Confirm local credential file removal
- Check Kubernetes resource deletion (if cluster accessible)

## Backward Compatibility

**No Breaking Changes:**
- Manual cleanup functionality remains unchanged
- State file format remains compatible
- Existing deployment workflows unaffected

**New Behaviors:**
- Automatic cleanup triggers during reset when needed
- Additional logging for cleanup operations
- Enhanced status reporting

## Testing Strategy

### Automated Tests
- **Mock Azure CLI**: Simulate credential cleanup scenarios
- **State File Scenarios**: Test with various Azure state configurations
- **Reset Integration**: Verify cleanup triggers during reset
- **Error Handling**: Test failure scenarios and recovery

### Integration Tests
- **Full Deployment + Reset**: Complete lifecycle testing
- **Cleanup Validation**: Verify service principals actually deleted
- **Cluster Unavailable**: Test cleanup when Kubernetes not accessible
- **Permission Issues**: Test with insufficient Azure permissions

### Manual Testing Scenarios
1. **Normal Flow**: Deploy credentials → Reset → Verify cleanup
2. **Offline Cleanup**: Reset without cluster access
3. **Permission Denied**: Reset without Azure SP delete permissions
4. **Corrupted State**: Reset with missing azure-state.yaml
5. **Multiple Deployments**: Reset after multiple credential configurations

## Security Considerations

**Credential Exposure Mitigation:**
- Automatic cleanup reduces credential lifetime
- Local credential files are always removed
- Service principal permissions are revoked

**Permission Requirements:**
- User needs Azure permissions to delete service principals
- Cleanup continues regardless of permission failures
- Clear error messages indicate manual cleanup needs

**Audit Trail:**
- All cleanup attempts logged in deployment events
- Azure service principal deletion can be audited via Azure CLI
- State file updates provide local audit record

## Performance Impact

**Minimal Overhead:**
- State file check is O(1) operation
- Cleanup only runs when credentials exist
- Azure API calls limited to service principal deletion
- No impact on deployments without Azure credentials

**Timeout Considerations:**
- Azure SP deletion typically quick (<30 seconds)
- Kubernetes cleanup may take longer if cluster is slow
- Main reset continues regardless of cleanup completion time
