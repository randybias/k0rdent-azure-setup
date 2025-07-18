#!/usr/bin/env bash

# Script: list-child-clusters.sh
# Purpose: List k0rdent child cluster deployments by namespace
# Usage: bash list-child-clusters.sh [--namespace <ns>] [--all-namespaces] [--output <format>]
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
OUTPUT_FORMAT="table"

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  --namespace <ns>          Show clusters in specific namespace
  --all-namespaces         Show clusters across all namespaces
  --output <format>        Output format: table, yaml, json, wide (default: table)" \
        "  -h, --help               Show this help message" \
        "  $0                                    # List clusters in kcm-system namespace
  $0 --namespace my-namespace           # List clusters in specific namespace
  $0 --all-namespaces                   # List clusters in all namespaces
  $0 --all-namespaces --output wide     # Detailed view across all namespaces
  $0 --namespace kcm-system --output yaml  # YAML output for specific namespace"
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
            --output)
                OUTPUT_FORMAT="$2"
                shift 2
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
    
    # Validate output format
    case "$OUTPUT_FORMAT" in
        table|yaml|json|wide)
            ;;
        *)
            print_error "Invalid output format: $OUTPUT_FORMAT (valid: table, yaml, json, wide)"
            exit 1
            ;;
    esac
    
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

# Get cluster deployments with kubectl
get_cluster_deployments() {
    local kubectl_args=()
    
    if [[ "$ALL_NAMESPACES" == "true" ]]; then
        kubectl_args+=("--all-namespaces")
    else
        kubectl_args+=("-n" "$NAMESPACE")
    fi
    
    case "$OUTPUT_FORMAT" in
        table)
            kubectl get clusterdeployment "${kubectl_args[@]}" 2>/dev/null || true
            ;;
        wide)
            kubectl get clusterdeployment "${kubectl_args[@]}" -o wide 2>/dev/null || true
            ;;
        yaml)
            kubectl get clusterdeployment "${kubectl_args[@]}" -o yaml 2>/dev/null || true
            ;;
        json)
            kubectl get clusterdeployment "${kubectl_args[@]}" -o json 2>/dev/null || true
            ;;
    esac
}

# Show local cluster events (state is in k0rdent)
show_local_events() {
    if [[ ! -d "state" ]]; then
        return 0
    fi
    
    local events_files=(state/cluster-*-events.yaml)
    if [[ ! -e "${events_files[0]}" ]]; then
        return 0
    fi
    
    print_info ""
    print_info "=== Local Cluster Events ==="
    print_info "(State is tracked in k0rdent - these are local operation events only)"
    
    for events_file in "${events_files[@]}"; do
        if [[ -f "$events_file" ]]; then
            local cluster_name=$(basename "$events_file" | sed 's/cluster-\(.*\)-events\.yaml/\1/')
            local created=$(yq eval '.created_at' "$events_file" 2>/dev/null || echo "unknown")
            local last_event=$(yq eval '.events[-1].action' "$events_file" 2>/dev/null || echo "none")
            local event_time=$(yq eval '.events[-1].timestamp' "$events_file" 2>/dev/null || echo "unknown")
            
            echo "  $cluster_name:"
            echo "    Local events since: $created"
            echo "    Last event: $last_event ($event_time)"
        fi
    done
}

# Main listing function
list_child_clusters() {
    if [[ "$ALL_NAMESPACES" == "true" ]]; then
        print_header "Child Clusters (All Namespaces)"
    else
        print_header "Child Clusters (Namespace: $NAMESPACE)"
    fi
    
    # Get cluster deployments from Kubernetes
    local deployments_output
    deployments_output=$(get_cluster_deployments)
    
    if [[ -z "$deployments_output" ]]; then
        if [[ "$ALL_NAMESPACES" == "true" ]]; then
            print_info "No cluster deployments found in any namespace"
        else
            print_info "No cluster deployments found in namespace '$NAMESPACE'"
        fi
    else
        echo "$deployments_output"
    fi
    
    # Show local events for table output
    if [[ "$OUTPUT_FORMAT" == "table" || "$OUTPUT_FORMAT" == "wide" ]]; then
        show_local_events
    fi
}

# Show summary statistics
show_summary() {
    if [[ "$OUTPUT_FORMAT" != "table" && "$OUTPUT_FORMAT" != "wide" ]]; then
        return 0
    fi
    
    print_info ""
    print_info "=== Summary ==="
    
    # Count cluster deployments
    local total_deployments=0
    local ready_deployments=0
    
    if [[ "$ALL_NAMESPACES" == "true" ]]; then
        local deployments_json
        deployments_json=$(kubectl get clusterdeployment --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')
        total_deployments=$(echo "$deployments_json" | jq '.items | length' 2>/dev/null || echo 0)
        ready_deployments=$(echo "$deployments_json" | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length' 2>/dev/null || echo 0)
    else
        local deployments_json
        deployments_json=$(kubectl get clusterdeployment -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
        total_deployments=$(echo "$deployments_json" | jq '.items | length' 2>/dev/null || echo 0)
        ready_deployments=$(echo "$deployments_json" | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length' 2>/dev/null || echo 0)
    fi
    
    # Count local state files
    local local_clusters=0
    if [[ -d "state" ]]; then
        local state_files=(state/cluster-*-state.yaml)
        if [[ -e "${state_files[0]}" ]]; then
            local_clusters=${#state_files[@]}
        fi
    fi
    
    print_info "  Total Cluster Deployments: $total_deployments"
    print_info "  Ready Deployments: $ready_deployments"
    print_info "  Local State Files: $local_clusters"
    
    if [[ "$ALL_NAMESPACES" == "true" ]]; then
        # Show namespaces with clusters
        local namespaces
        namespaces=$(kubectl get clusterdeployment --all-namespaces -o json 2>/dev/null | jq -r '.items[].metadata.namespace' 2>/dev/null | sort | uniq || true)
        if [[ -n "$namespaces" ]]; then
            print_info "  Namespaces with clusters: $(echo "$namespaces" | tr '\n' ', ' | sed 's/,$//')"
        fi
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    validate_arguments
    
    if ! check_prerequisites; then
        exit 1
    fi
    
    list_child_clusters
    show_summary
}

# Run main function with all arguments
main "$@"