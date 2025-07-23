#!/usr/bin/env bash

# General-purpose monitoring script with pre-condition checks
# Usage: monitor-k0rdent.sh [mode] [cluster-name]
# Modes:
#   k0s (default) - Monitor k0s pods
#   child-clusters - Monitor child clusters
#   child-cluster - Monitor inside a specific child cluster (requires cluster name)
#   azure-vms - Monitor Azure VM creation

export KUBECONFIG=""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Function to display usage
usage() {
    echo "Usage: $0 [mode] [cluster-name]"
    echo "Modes:"
    echo "  k0s (default)    - Monitor k0s pods"
    echo "  child-clusters   - Monitor child clusters"
    echo "  child-cluster    - Monitor inside a specific child cluster (requires cluster name)"
    echo "  azure-vms        - Monitor Azure VM creation"
    echo ""
    echo "Examples:"
    echo "  $0 k0s                           # Monitor management cluster pods"
    echo "  $0 child-clusters                # List all child clusters"
    echo "  $0 child-cluster my-cluster      # Monitor pods/nodes in 'my-cluster'"
    echo ""
    echo "The script will wait for necessary pre-conditions before starting monitoring."
    exit 1
}

# Function to find the kubeconfig file with project suffix
find_kubeconfig() {
    local k0sctl_dir="$PROJECT_ROOT/k0sctl-config"
    local clusterid_file="$PROJECT_ROOT/.clusterid"
    
    # Check if k0sctl-config directory exists
    if [[ ! -d "$k0sctl_dir" ]]; then
        echo "Waiting for k0sctl-config directory to appear..."
        return 1
    fi
    
    # Check if .clusterid file exists
    if [[ ! -f "$clusterid_file" ]]; then
        echo "Waiting for .clusterid file to appear..."
        return 1
    fi
    
    # Read the cluster ID
    local clusterid=$(cat "$clusterid_file" 2>/dev/null | tr -d '\n\r')
    if [[ -z "$clusterid" ]]; then
        echo "Cluster ID file is empty, waiting..."
        return 1
    fi
    
    # Look for kubeconfig file with the cluster ID
    local kubeconfig_file="$k0sctl_dir/$clusterid-kubeconfig"
    
    if [[ ! -f "$kubeconfig_file" ]]; then
        echo "Waiting for kubeconfig file: $kubeconfig_file"
        return 1
    fi
    
    export KUBECONFIG="$kubeconfig_file"
    echo "Found kubeconfig: $kubeconfig_file"
    return 0
}

# Pre-conditions for k0s monitoring
check_k0s_preconditions() {
    echo "Checking pre-conditions for k0s monitoring..."
    
    while true; do
        if find_kubeconfig; then
            # Try to connect to the cluster
            if kubectl cluster-info &>/dev/null; then
                echo "Successfully connected to k0s cluster"
                return 0
            else
                echo "Waiting for k0s cluster to be accessible..."
            fi
        fi
        sleep 5
    done
}

# Pre-conditions for child-clusters monitoring
check_child_clusters_preconditions() {
    echo "Checking pre-conditions for child-clusters monitoring..."
    
    while true; do
        if find_kubeconfig; then
            # Check if kcm-system namespace exists
            if kubectl get namespace kcm-system &>/dev/null; then
                echo "kcm-system namespace exists"
                
                # Check if k0rdent is deployed by looking for capi providers in kcm-system
                if kubectl get pods -n kcm-system 2>/dev/null | grep -E "capi-controller-manager.*Running" | grep -q "Running"; then
                    echo "CAPI providers are running"
                    
                    # Check if list-child-clusters.sh exists
                    if [[ -x "$PROJECT_ROOT/bin/list-child-clusters.sh" ]]; then
                        echo "list-child-clusters.sh is available"
                        return 0
                    else
                        echo "Waiting for list-child-clusters.sh to be available..."
                    fi
                else
                    echo "Waiting for CAPI providers to be running in kcm-system..."
                fi
            else
                echo "Waiting for kcm-system namespace..."
            fi
        fi
        sleep 5
    done
}

# Monitor k0s pods
monitor_k0s() {
    check_k0s_preconditions
    echo "Starting viddy to monitor k0s pods..."
    viddy "kubectl get pods -A -o wide"
}

# Monitor child clusters
monitor_child_clusters() {
    check_child_clusters_preconditions
    echo "Starting viddy to monitor child clusters..."
    cd "$PROJECT_ROOT"
    viddy "bin/list-child-clusters.sh --namespace kcm-system --output wide"
}

# Function to get resource group name
get_resource_group_name() {
    local clusterid_file="$PROJECT_ROOT/.clusterid"
    
    if [[ -f "$clusterid_file" ]]; then
        local clusterid=$(cat "$clusterid_file" 2>/dev/null | tr -d '\n\r')
        if [[ -n "$clusterid" ]]; then
            echo "${clusterid}-resgrp"
            return 0
        fi
    fi
    return 1
}

# Pre-conditions for Azure VMs monitoring
check_azure_vms_preconditions() {
    echo "Checking pre-conditions for Azure VMs monitoring..."
    
    while true; do
        # Check if az CLI is available
        if ! command -v az &>/dev/null; then
            echo "Waiting for Azure CLI to be available..."
            sleep 5
            continue
        fi
        
        # Check if logged in to Azure
        if ! az account show &>/dev/null; then
            echo "Waiting for Azure login..."
            sleep 5
            continue
        fi
        
        # Wait for cluster ID file
        if [[ ! -f "$PROJECT_ROOT/.clusterid" ]]; then
            echo "Waiting for .clusterid file to appear..."
            sleep 5
            continue
        fi
        
        # Get resource group name
        local rg=$(get_resource_group_name)
        if [[ -z "$rg" ]]; then
            echo "Unable to determine resource group name..."
            sleep 5
            continue
        fi
        
        # Check if resource group exists
        if az group show --name "$rg" &>/dev/null; then
            echo "Resource group '$rg' exists"
            export K0RDENT_RG="$rg"
            return 0
        else
            echo "Waiting for resource group '$rg' to be created..."
        fi
        
        sleep 5
    done
}

# Monitor Azure VMs
monitor_azure_vms() {
    check_azure_vms_preconditions
    echo "Starting viddy to monitor Azure VMs in resource group: $K0RDENT_RG"
    viddy "az vm list -g $K0RDENT_RG --show-details --output table"
}

# Pre-conditions for specific child cluster monitoring
check_child_cluster_preconditions() {
    local cluster_name="$1"
    echo "Checking pre-conditions for monitoring child cluster: $cluster_name"
    
    while true; do
        if find_kubeconfig; then
            # Check if child cluster exists
            if kubectl get clusterdeployment "$cluster_name" -n kcm-system &>/dev/null; then
                echo "Child cluster '$cluster_name' exists"
                
                # Check if kubeconfig secret exists
                if kubectl get secret "${cluster_name}-kubeconfig" -n kcm-system &>/dev/null; then
                    echo "Kubeconfig secret found for '$cluster_name'"
                    
                    # Extract child cluster kubeconfig
                    local child_kubeconfig="$PROJECT_ROOT/k0sctl-config/${cluster_name}-kubeconfig"
                    if kubectl get secret "${cluster_name}-kubeconfig" -n kcm-system -o jsonpath='{.data.value}' | base64 -d > "$child_kubeconfig" 2>/dev/null; then
                        echo "Child cluster kubeconfig extracted"
                        
                        # Test connectivity to child cluster
                        if KUBECONFIG="$child_kubeconfig" kubectl cluster-info &>/dev/null; then
                            echo "Successfully connected to child cluster '$cluster_name'"
                            export CHILD_KUBECONFIG="$child_kubeconfig"
                            return 0
                        else
                            echo "Waiting for child cluster '$cluster_name' to be accessible..."
                        fi
                    else
                        echo "Failed to extract kubeconfig for '$cluster_name'"
                    fi
                else
                    echo "Waiting for kubeconfig secret for cluster '$cluster_name'..."
                fi
            else
                echo "Child cluster '$cluster_name' not found in kcm-system namespace"
                echo "Available clusters:"
                kubectl get clusterdeployment -n kcm-system -o name | sed 's|clusterdeployment.cluster.x-k8s.io/||' || true
                return 1
            fi
        fi
        sleep 5
    done
}

# Monitor specific child cluster
monitor_child_cluster() {
    local cluster_name="$1"
    
    if [[ -z "$cluster_name" ]]; then
        echo "Error: Cluster name required for child-cluster mode"
        usage
    fi
    
    check_child_cluster_preconditions "$cluster_name"
    echo "Starting viddy to monitor child cluster '$cluster_name' (pods and nodes)..."
    viddy "KUBECONFIG='$CHILD_KUBECONFIG' bash -c 'echo \"=== CLUSTER: $cluster_name - PODS ===\" && kubectl get pods -A -o wide && echo && echo \"=== CLUSTER: $cluster_name - NODES ===\" && kubectl get nodes -o wide'"
}

# Main function
main() {
    local mode="${1:-k0s}"
    local cluster_name="${2:-}"
    
    case "$mode" in
        k0s)
            echo "Starting k0s monitoring..."
            ;;
        child-clusters)
            echo "Starting child-clusters monitoring..."
            ;;
        child-cluster)
            echo "Starting monitoring for child cluster: $cluster_name"
            ;;
        azure-vms)
            echo "Starting Azure VMs monitoring..."
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            echo "Error: Unknown mode '$mode'"
            usage
            ;;
    esac
    
    # Main monitoring loop
    while true; do
        case "$mode" in
            k0s)
                monitor_k0s
                ;;
            child-clusters)
                monitor_child_clusters
                ;;
            child-cluster)
                monitor_child_cluster "$cluster_name"
                ;;
            azure-vms)
                monitor_azure_vms
                ;;
        esac
        
        # If viddy exits (user presses q or Ctrl+C), restart the monitoring
        echo "viddy exited, restarting monitoring in 2 seconds..."
        sleep 2
    done
}

# Handle Ctrl+C gracefully
trap 'echo -e "\nExiting monitoring script..."; exit 0' SIGINT SIGTERM

# Start the main function
main "$@"