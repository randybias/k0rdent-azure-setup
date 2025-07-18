#!/usr/bin/env bash

# Script: sync-cluster-state.sh
# Purpose: Synchronize local cluster state files with actual Kubernetes ClusterDeployments
# Usage: bash sync-cluster-state.sh [--dry-run] [--namespace <ns>] [--all-namespaces]
# Prerequisites: k0rdent management cluster access

set -euo pipefail

# Load ALL existing k0rdent infrastructure
source ./etc/k0rdent-config.sh      # Loads CONFIG_YAML automatically
source ./etc/common-functions.sh     # All common functionality
source ./etc/state-management.sh     # State tracking

# Output directory (reuse from k0rdent)
K0SCTL_DIR="./k0sctl-config"
KUBECONFIG_FILE="$K0SCTL_DIR/${K0RDENT_CLUSTERID}-kubeconfig"

# Initialize variables
NAMESPACE=""
ALL_NAMESPACES="false"
DRY_RUN="false"

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  --namespace <ns>          Sync clusters in specific namespace (default: kcm-system)
  --all-namespaces         Sync clusters across all namespaces
  --dry-run                Show what would be cleaned up without making changes" \
        "  -h, --help               Show this help message" \
        "  $0                                    # Sync clusters in kcm-system namespace
  $0 --namespace my-namespace           # Sync clusters in specific namespace
  $0 --all-namespaces                   # Sync clusters across all namespaces
  $0 --all-namespaces --dry-run         # Preview sync actions across all namespaces"
}

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --all-namespaces)
                ALL_NAMESPACES="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Validate arguments
validate_arguments() {
    # Set default namespace if not specified and not all-namespaces
    if [[ "$ALL_NAMESPACES" != "true" && -z "$NAMESPACE" ]]; then
        NAMESPACE="kcm-system"
    fi
    
    # Validate namespace conflict
    if [[ "$ALL_NAMESPACES" == "true" && -n "$NAMESPACE" ]]; then
        print_error "Cannot specify both --namespace and --all-namespaces"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    # Check if k0rdent is installed
    if [[ "$(get_state "k0rdent_installed")" != "true" ]]; then
        print_error "k0rdent must be installed first"
        return 1
    fi
    
    # Check kubeconfig
    if [[ ! -f "$KUBECONFIG_FILE" ]]; then
        print_error "Kubeconfig not found at $KUBECONFIG_FILE"
        return 1
    fi
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    # Test kubectl connectivity
    if ! kubectl get nodes &>/dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    return 0
}

# Get all ClusterDeployments from Kubernetes
get_k8s_clusters() {
    local kubectl_args=()
    
    if [[ "$ALL_NAMESPACES" == "true" ]]; then
        kubectl_args+=("--all-namespaces")
        kubectl get clusterdeployment "${kubectl_args[@]}" -o json 2>/dev/null | \
            jq -r '.items[] | "\(.metadata.namespace):\(.metadata.name)"' 2>/dev/null || true
    else
        kubectl_args+=("-n" "$NAMESPACE")
        kubectl get clusterdeployment "${kubectl_args[@]}" -o json 2>/dev/null | \
            jq -r '.items[] | "'"$NAMESPACE"':\(.metadata.name)"' 2>/dev/null || true
    fi
}

# Get all local cluster state files
get_local_clusters() {
    if [[ ! -d "state" ]]; then
        return 0
    fi
    
    local state_files=(state/cluster-*-state.yaml)
    if [[ ! -e "${state_files[0]}" ]]; then
        return 0
    fi
    
    for state_file in "${state_files[@]}"; do
        if [[ -f "$state_file" ]]; then
            local cluster_name=$(basename "$state_file" | sed 's/cluster-\(.*\)-state\.yaml/\1/')
            echo "$cluster_name"
        fi
    done
}

# Update local state file with current Kubernetes status
update_local_state_from_k8s() {
    local cluster_name="$1"
    local namespace="$2"
    
    # Get cluster deployment info from Kubernetes
    local cluster_json
    cluster_json=$(kubectl get clusterdeployment "$cluster_name" -n "$namespace" -o json 2>/dev/null || echo '{}')
    
    if [[ "$cluster_json" == '{}' ]]; then
        return 1
    fi
    
    # Extract key information
    local ready=$(echo "$cluster_json" | jq -r '.status.conditions[]? | select(.type=="Ready") | .status' 2>/dev/null || echo "Unknown")
    local template=$(echo "$cluster_json" | jq -r '.spec.template' 2>/dev/null || echo "unknown")
    local credential=$(echo "$cluster_json" | jq -r '.spec.credential' 2>/dev/null || echo "unknown")
    local dry_run=$(echo "$cluster_json" | jq -r '.spec.dryRun' 2>/dev/null || echo "false")
    local location=$(echo "$cluster_json" | jq -r '.spec.config.location' 2>/dev/null || echo "unknown")
    
    # Update cluster state
    update_cluster_state "$cluster_name" "cluster_status" "$(echo "$ready" | tr '[:upper:]' '[:lower:]')"
    update_cluster_state "$cluster_name" "template" "$template"
    update_cluster_state "$cluster_name" "credential" "$credential"
    update_cluster_state "$cluster_name" "dry_run" "$dry_run"
    update_cluster_state "$cluster_name" "location" "$location"
    update_cluster_state "$cluster_name" "kubernetes_namespace" "$namespace"
    add_cluster_event "$cluster_name" "state_synced_from_kubernetes" "Local state synchronized with Kubernetes cluster status"
    
    return 0
}

# Clean up orphaned local state file
cleanup_orphaned_state() {
    local cluster_name="$1"
    local cluster_state_file=$(get_cluster_state_file "$cluster_name")
    local cluster_events_file=$(get_cluster_events_file "$cluster_name")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "  [DRY-RUN] Would remove: $cluster_state_file"
        if [[ -f "$cluster_events_file" ]]; then
            print_info "  [DRY-RUN] Would remove: $cluster_events_file"
        fi
    else
        if [[ -f "$cluster_state_file" ]]; then
            rm -f "$cluster_state_file"
            print_info "  Removed: $cluster_state_file"
        fi
        
        if [[ -f "$cluster_events_file" ]]; then
            rm -f "$cluster_events_file"
            print_info "  Removed: $cluster_events_file"
        fi
    fi
}

# Create missing local state for Kubernetes cluster
create_missing_state() {
    local cluster_name="$1"
    local namespace="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "  [DRY-RUN] Would create local state for: $cluster_name"
    else
        # Initialize cluster state
        init_cluster_state "$cluster_name"
        
        # Update with current Kubernetes information
        if update_local_state_from_k8s "$cluster_name" "$namespace"; then
            print_info "  Created local state for: $cluster_name"
        else
            print_warning "  Failed to sync state for: $cluster_name"
        fi
    fi
}

# Main sync function
sync_cluster_state() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_header "Cluster State Sync (Dry Run)"
    else
        print_header "Cluster State Sync"
    fi
    
    if [[ "$ALL_NAMESPACES" == "true" ]]; then
        print_info "Scope: All namespaces"
    else
        print_info "Scope: Namespace '$NAMESPACE'"
    fi
    
    # Get current state
    print_info "Gathering cluster information..."
    
    local k8s_clusters=()
    local local_clusters=()
    
    # Read Kubernetes clusters
    while IFS= read -r cluster_info; do
        if [[ -n "$cluster_info" ]]; then
            k8s_clusters+=("$cluster_info")
        fi
    done < <(get_k8s_clusters)
    
    # Read local clusters
    while IFS= read -r cluster_name; do
        if [[ -n "$cluster_name" ]]; then
            local_clusters+=("$cluster_name")
        fi
    done < <(get_local_clusters)
    
    print_info "Found ${#k8s_clusters[@]} clusters in Kubernetes"
    print_info "Found ${#local_clusters[@]} local state files"
    
    # Create associative arrays for easier lookup
    declare -A k8s_lookup
    declare -A local_lookup
    
    # Build Kubernetes lookup (namespace:cluster_name -> namespace)
    for cluster_info in "${k8s_clusters[@]}"; do
        local namespace_name="${cluster_info%:*}"
        local cluster_name="${cluster_info#*:}"
        k8s_lookup["$cluster_name"]="$namespace_name"
    done
    
    # Build local lookup
    for cluster_name in "${local_clusters[@]}"; do
        local_lookup["$cluster_name"]=1
    done
    
    # Find orphaned local state files (exist locally but not in Kubernetes)
    local orphaned_count=0
    print_info ""
    print_info "=== Checking for Orphaned Local State Files ==="
    
    for cluster_name in "${local_clusters[@]}"; do
        if [[ -z "${k8s_lookup[$cluster_name]:-}" ]]; then
            # Check if this cluster should be in scope
            local should_clean="false"
            
            if [[ "$ALL_NAMESPACES" == "true" ]]; then
                should_clean="true"
            else
                # For specific namespace, check if the local state indicates it was in that namespace
                local stored_namespace=$(get_cluster_state "$cluster_name" "kubernetes_namespace" 2>/dev/null || echo "")
                if [[ "$stored_namespace" == "$NAMESPACE" || -z "$stored_namespace" ]]; then
                    should_clean="true"
                fi
            fi
            
            if [[ "$should_clean" == "true" ]]; then
                print_warning "Orphaned local state: $cluster_name"
                cleanup_orphaned_state "$cluster_name"
                ((orphaned_count++))
            fi
        fi
    done
    
    if [[ $orphaned_count -eq 0 ]]; then
        print_info "No orphaned local state files found"
    else
        print_info "Processed $orphaned_count orphaned state files"
    fi
    
    # Find missing local state files (exist in Kubernetes but not locally)
    local missing_count=0
    print_info ""
    print_info "=== Checking for Missing Local State Files ==="
    
    for cluster_info in "${k8s_clusters[@]}"; do
        local namespace_name="${cluster_info%:*}"
        local cluster_name="${cluster_info#*:}"
        
        if [[ -z "${local_lookup[$cluster_name]:-}" ]]; then
            print_warning "Missing local state: $cluster_name (namespace: $namespace_name)"
            create_missing_state "$cluster_name" "$namespace_name"
            ((missing_count++))
        fi
    done
    
    if [[ $missing_count -eq 0 ]]; then
        print_info "No missing local state files found"
    else
        print_info "Processed $missing_count missing state files"
    fi
    
    # Update existing state files with current Kubernetes status
    local updated_count=0
    print_info ""
    print_info "=== Updating Existing State Files ==="
    
    for cluster_info in "${k8s_clusters[@]}"; do
        local namespace_name="${cluster_info%:*}"
        local cluster_name="${cluster_info#*:}"
        
        if [[ -n "${local_lookup[$cluster_name]:-}" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                print_info "  [DRY-RUN] Would update state for: $cluster_name"
            else
                if update_local_state_from_k8s "$cluster_name" "$namespace_name"; then
                    print_info "  Updated state for: $cluster_name"
                    ((updated_count++))
                else
                    print_warning "  Failed to update state for: $cluster_name"
                fi
            fi
        fi
    done
    
    print_info "Updated $updated_count existing state files"
    
    # Summary
    print_info ""
    print_info "=== Sync Summary ==="
    print_info "  Orphaned state files: $orphaned_count"
    print_info "  Missing state files: $missing_count"
    print_info "  Updated state files: $updated_count"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_success "Dry run completed - no changes made"
        print_info "Run without --dry-run to apply these changes"
    else
        print_success "Cluster state synchronization completed"
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    validate_arguments
    
    if ! check_prerequisites; then
        exit 1
    fi
    
    sync_cluster_state
}

# Run main function with all arguments
main "$@"