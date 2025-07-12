#!/usr/bin/env bash

# Azure Cluster Deployment Functions
# Provides Azure-specific cluster deployment utilities with retry logic and failure detection

# Detect if a cluster deployment failure is transient and retryable
is_transient_cluster_failure() {
    local cluster_name="$1"
    local namespace="${2:-kcm-system}"
    
    print_info "Analyzing failure type for cluster: $cluster_name"
    
    # Check for CAPI/Azure sync issues
    if detect_capi_azure_sync_issue "$cluster_name"; then
        print_info "Detected CAPI/Azure sync issue - retryable"
        return 0
    fi
    
    # Check for Azure API throttling
    if kubectl get events -n "$namespace" --field-selector reason=ThrottlingError 2>/dev/null | grep -q "ThrottlingError"; then
        print_info "Detected Azure API throttling - retryable"  
        return 0
    fi
    
    # Check for quota issues (may resolve if other resources freed)
    if kubectl describe clusterdeployment "$cluster_name" -n "$namespace" 2>/dev/null | grep -q "exceeding approved.*quota"; then
        print_warning "Detected quota issue - may be retryable after cleanup"
        return 0
    fi
    
    # Check for timeout without progress (stuck state)
    if is_deployment_stuck "$cluster_name" "$namespace"; then
        print_info "Deployment appears stuck - retryable"
        return 0
    fi
    
    # Check for authentication/credential issues (not retryable)
    if kubectl describe clusterdeployment "$cluster_name" -n "$namespace" 2>/dev/null | grep -q -E "(authentication|credential|unauthorized)"; then
        print_info "Detected authentication/credential issue - not retryable"
        return 1
    fi
    
    # Default: don't retry for unknown failures
    print_info "Failure type unknown - not retryable to avoid infinite loops"
    return 1
}

# Detect CAPI/Azure synchronization issues
detect_capi_azure_sync_issue() {
    local cluster_name="$1"
    
    print_info "Checking for CAPI/Azure sync issues..."
    
    # Look for "has been deleted" errors when Azure resources exist
    local deleted_errors=$(kubectl get azuremachine -A -l cluster.x-k8s.io/cluster-name="$cluster_name" \
        -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].message}' 2>/dev/null | \
        grep -c "has been deleted" || echo "0")
    
    if [[ "$deleted_errors" -gt 0 ]]; then
        print_info "Found $deleted_errors CAPI machines reporting 'deleted' status"
        
        # Verify resources actually exist in Azure
        local resource_group="$cluster_name"
        local vm_count=$(az vm list -g "$resource_group" --query "length([?starts_with(name, '$cluster_name')])" -o tsv 2>/dev/null || echo "0")
        
        if [[ "$vm_count" -gt 0 ]]; then
            print_warning "CAPI reports VMs deleted but $vm_count VMs exist in Azure - sync issue detected"
            return 0
        else
            print_info "CAPI and Azure are in sync - VMs actually deleted"
        fi
    fi
    
    # Check for missing network resources that exist in Azure
    local missing_lb=$(kubectl get azuremachine -A -l cluster.x-k8s.io/cluster-name="$cluster_name" \
        -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].message}' 2>/dev/null | \
        grep -c "ResourceNotFound.*loadBalancers" || echo "0")
    
    if [[ "$missing_lb" -gt 0 ]]; then
        local resource_group="$cluster_name"
        local lb_count=$(az network lb list -g "$resource_group" --query "length([?starts_with(name, '$cluster_name')])" -o tsv 2>/dev/null || echo "0")
        
        if [[ "$lb_count" -gt 0 ]]; then
            print_warning "CAPI reports missing load balancers but $lb_count exist in Azure - sync issue detected"
            return 0
        fi
    fi
    
    return 1
}

# Check if deployment is stuck without progress
is_deployment_stuck() {
    local cluster_name="$1" 
    local namespace="${2:-kcm-system}"
    local stuck_threshold_minutes=15
    
    print_info "Checking if deployment is stuck..."
    
    # Check if deployment has made no progress in X minutes
    local last_transition=$(kubectl get clusterdeployment "$cluster_name" -n "$namespace" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)
    
    if [[ -n "$last_transition" ]]; then
        local transition_epoch=$(date -d "$last_transition" +%s 2>/dev/null || echo "0")
        local current_epoch=$(date +%s)
        local minutes_since=$((( current_epoch - transition_epoch ) / 60))
        
        if [[ "$minutes_since" -gt "$stuck_threshold_minutes" ]]; then
            print_warning "No progress for $minutes_since minutes (threshold: $stuck_threshold_minutes)"
            return 0
        else
            print_info "Last progress: $minutes_since minutes ago (within threshold)"
        fi
    else
        print_info "No Ready condition found - deployment may be initializing"
    fi
    
    return 1
}

# Clean up failed cluster deployment
cleanup_failed_cluster_deployment() {
    local cluster_name="$1"
    local namespace="${2:-kcm-system}"
    
    print_info "Cleaning up failed cluster deployment: $cluster_name"
    
    # Delete cluster deployment (this should trigger Azure resource cleanup)
    if kubectl get clusterdeployment "$cluster_name" -n "$namespace" &>/dev/null; then
        print_info "Deleting ClusterDeployment $cluster_name..."
        kubectl delete clusterdeployment "$cluster_name" -n "$namespace" --timeout=300s || {
            print_warning "ClusterDeployment deletion timed out, continuing..."
        }
    fi
    
    # Wait for Azure resource group cleanup
    local resource_group="$cluster_name"
    local cleanup_timeout=300
    local elapsed=0
    
    print_info "Waiting for Azure resource group cleanup..."
    while az group show --name "$resource_group" &>/dev/null && [[ $elapsed -lt $cleanup_timeout ]]; do
        print_info "Waiting for resource group deletion... (${elapsed}s/${cleanup_timeout}s)"
        sleep 30
        elapsed=$((elapsed + 30))
    done
    
    if az group show --name "$resource_group" &>/dev/null; then
        print_warning "Resource group still exists after ${cleanup_timeout}s, forcing deletion..."
        az group delete --name "$resource_group" --yes --no-wait || {
            print_error "Failed to initiate resource group deletion"
        }
    else
        print_success "Resource group cleanup completed"
    fi
}

# Generic cluster deployment with retry logic
deploy_cluster_with_retry() {
    local cluster_name="$1"
    local deploy_function="$2"  # Function to call for actual deployment
    local max_retries="${3:-2}"
    local namespace="${4:-kcm-system}"
    local wait_timeout="${5:-1800}"  # 30 minutes default
    
    local retry_count=0
    
    print_info "Starting cluster deployment with retry: $cluster_name"
    print_info "Max retries: $max_retries, Wait timeout: ${wait_timeout}s"
    
    while [[ $retry_count -lt $max_retries ]]; do
        print_header "Deploying cluster $cluster_name (attempt $((retry_count + 1))/$max_retries)"
        
        # Call the actual deployment function
        if $deploy_function "$cluster_name" "$wait_timeout"; then
            print_success "Cluster deployment succeeded on attempt $((retry_count + 1))"
            return 0
        fi
        
        ((retry_count++))
        
        if [[ $retry_count -lt $max_retries ]]; then
            print_warning "Deployment attempt $retry_count failed"
            
            if is_transient_cluster_failure "$cluster_name" "$namespace"; then
                print_info "Transient failure detected, cleaning up and retrying..."
                cleanup_failed_cluster_deployment "$cluster_name" "$namespace"
                
                local retry_delay=120
                print_info "Waiting ${retry_delay}s before retry..."
                sleep $retry_delay
            else
                print_error "Permanent failure detected, aborting retries"
                return 1
            fi
        fi
    done
    
    print_error "Cluster deployment failed after $max_retries attempts"
    return 1
}

# Validate Azure cluster deployment readiness
validate_azure_cluster_ready() {
    local cluster_name="$1"
    local namespace="${2:-kcm-system}"
    
    print_info "Validating cluster readiness: $cluster_name"
    
    # Check ClusterDeployment status
    local ready_status=$(kubectl get clusterdeployment "$cluster_name" -n "$namespace" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    
    if [[ "$ready_status" != "True" ]]; then
        print_error "ClusterDeployment Ready status is not True: $ready_status"
        return 1
    fi
    
    # For k0rdent-managed clusters, we cannot reliably determine the resource group name
    # as it's generated by k0rdent. Skip Azure VM validation and rely on k0rdent's Ready status.
    print_info "Note: Azure VM validation skipped for k0rdent-managed cluster"
    print_success "Cluster validation passed based on k0rdent Ready status"
    return 0
}