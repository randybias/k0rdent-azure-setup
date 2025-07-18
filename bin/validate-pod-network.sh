#!/usr/bin/env bash

# Script: validate-pod-network.sh
# Purpose: Validate pod-to-pod network connectivity across k0s cluster nodes
# Usage: bash validate-pod-network.sh [validate|cleanup]
# Prerequisites: k0s cluster deployed with kubeconfig available

set -euo pipefail

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh
source ./etc/state-management.sh

# Output directory and file
K0SCTL_DIR="./k0sctl-config"
KUBECONFIG_FILE="$K0SCTL_DIR/${K0RDENT_CLUSTERID}-kubeconfig"

# Test configuration
TEST_NAMESPACE="network-validation"
TEST_POD_PREFIX="nettest"
TEST_TIMEOUT=300  # 5 minutes for all tests

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  validate   Run pod-to-pod network connectivity tests
  cleanup    Remove test pods and namespace
  help       Show this help message" \
        "  -y, --yes        Skip confirmation prompts
  --timeout SEC    Test timeout in seconds (default: 300)" \
        "  $0 validate      # Run network validation tests
  $0 cleanup       # Clean up test resources"
}

check_prerequisites() {
    # Check for kubeconfig
    if [[ ! -f "$KUBECONFIG_FILE" ]]; then
        print_error "Kubeconfig not found at $KUBECONFIG_FILE"
        print_info "Please run ./bin/install-k0s.sh deploy first"
        return 1
    fi
    
    # Check VPN connectivity
    if ! check_vpn_connectivity; then
        print_error "VPN connectivity required for cluster operations"
        print_info "Connect to VPN first: ./bin/manage-vpn.sh connect"
        return 1
    fi
    
    # Check kubectl connectivity
    export KUBECONFIG="$KUBECONFIG_FILE"
    if ! kubectl get nodes &>/dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    return 0
}

get_worker_nodes() {
    # k0s doesn't label workers by default, so we identify them by absence of control-plane role
    kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}' | \
        grep -v "true$" | awk '{print $1}'
}

create_test_namespace() {
    print_info "Creating test namespace: $TEST_NAMESPACE"
    kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

create_test_pod() {
    local pod_name="$1"
    local node_name="$2"
    
    print_info "Applying pod manifest for $pod_name..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  namespace: $TEST_NAMESPACE
  labels:
    app: network-test
spec:
  nodeSelector:
    kubernetes.io/hostname: $node_name
  restartPolicy: Never
  containers:
  - name: test
    image: busybox:latest
    command: ["/bin/sh", "-c", "sleep 3600"]
    resources:
      requests:
        cpu: 10m
        memory: 16Mi
      limits:
        cpu: 50m
        memory: 64Mi
EOF
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create pod $pod_name"
        return 1
    fi
}

wait_for_pods_ready() {
    local timeout="${1:-60}"
    local namespace="$TEST_NAMESPACE"
    
    print_info "Waiting for test pods to be ready..."
    if kubectl wait --for=condition=ready pod -l app=network-test -n "$namespace" --timeout="${timeout}s"; then
        return 0
    else
        print_error "Pods did not become ready within ${timeout} seconds"
        kubectl get pods -n "$namespace" -o wide
        return 1
    fi
}

test_pod_connectivity() {
    local source_pod="$1"
    local target_pod="$2"
    local target_ip="$3"
    
    print_info "Testing connectivity from $source_pod to $target_pod ($target_ip)"
    
    # Run ping test
    if kubectl exec "$source_pod" -n "$TEST_NAMESPACE" -- ping -c 3 -W 2 "$target_ip" &>/dev/null; then
        print_success "✓ Connectivity test passed: $source_pod → $target_pod"
        return 0
    else
        print_error "✗ Connectivity test failed: $source_pod → $target_pod"
        return 1
    fi
}

run_connectivity_tests() {
    local test_pods=()
    local pod_ips=()
    local failed_tests=0
    local total_tests=0
    
    # Get all test pods and their IPs
    while IFS= read -r line; do
        local pod_name=$(echo "$line" | awk '{print $1}')
        local pod_ip=$(echo "$line" | awk '{print $2}')
        local node_name=$(echo "$line" | awk '{print $3}')
        
        test_pods+=("$pod_name:$pod_ip:$node_name")
        pod_ips+=("$pod_ip")
    done < <(kubectl get pods -n "$TEST_NAMESPACE" -o custom-columns=NAME:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName --no-headers)
    
    print_info "Found ${#test_pods[@]} test pods across nodes"
    
    # Test connectivity between all pod pairs
    for i in "${!test_pods[@]}"; do
        IFS=':' read -r source_pod source_ip source_node <<< "${test_pods[$i]}"
        
        for j in "${!test_pods[@]}"; do
            if [[ $i -ne $j ]]; then
                IFS=':' read -r target_pod target_ip target_node <<< "${test_pods[$j]}"
                
                # Only test pods on different nodes
                if [[ "$source_node" != "$target_node" ]]; then
                    total_tests=$((total_tests + 1))
                    if ! test_pod_connectivity "$source_pod" "$target_pod" "$target_ip"; then
                        failed_tests=$((failed_tests + 1))
                    fi
                fi
            fi
        done
    done
    
    # Summary
    echo ""
    if [[ $failed_tests -eq 0 ]]; then
        print_success "All $total_tests cross-node connectivity tests passed!"
        return 0
    else
        print_error "$failed_tests out of $total_tests cross-node connectivity tests failed"
        return 1
    fi
}

validate_network() {
    print_header "Validating Pod-to-Pod Network Connectivity"
    
    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi
    
    # Get worker nodes
    local worker_nodes_output=$(get_worker_nodes)
    local worker_nodes=()
    while IFS= read -r node; do
        [[ -n "$node" ]] && worker_nodes+=("$node")
    done <<< "$worker_nodes_output"
    
    if [[ ${#worker_nodes[@]} -eq 0 ]]; then
        print_error "No worker nodes found in the cluster"
        return 1
    fi
    
    if [[ ${#worker_nodes[@]} -eq 1 ]]; then
        print_warning "Only 1 worker node found - skipping network validation"
        print_info "Cross-node network testing requires at least 2 worker nodes"
        print_success "Single-node deployment validated"
        return 0
    fi
    
    print_info "Found ${#worker_nodes[@]} worker nodes: ${worker_nodes[*]}"
    
    # Create test namespace
    create_test_namespace
    
    # Create test pods on each worker node
    local pod_count=0
    for node in "${worker_nodes[@]}"; do
        local pod_name="${TEST_POD_PREFIX}-${pod_count}"
        print_info "Creating test pod $pod_name on node $node"
        create_test_pod "$pod_name" "$node"
        pod_count=$((pod_count + 1))
    done
    
    # Wait for pods to be ready
    if ! wait_for_pods_ready 120; then
        print_error "Test pods failed to start"
        cleanup_resources
        return 1
    fi
    
    # Run connectivity tests
    echo ""
    print_info "Running cross-node connectivity tests..."
    
    if run_connectivity_tests; then
        print_success "Network validation completed successfully!"
        cleanup_resources
        return 0
    else
        print_error "Network validation failed!"
        print_info "Leaving test resources for debugging. Run '$0 cleanup' to remove them."
        return 1
    fi
}

cleanup_resources() {
    print_info "Cleaning up test resources..."
    
    # Check prerequisites
    if [[ -f "$KUBECONFIG_FILE" ]]; then
        export KUBECONFIG="$KUBECONFIG_FILE"
        
        # Delete namespace (will delete all pods within it)
        if kubectl get namespace "$TEST_NAMESPACE" &>/dev/null; then
            kubectl delete namespace "$TEST_NAMESPACE" --timeout=60s || true
            print_success "Test namespace and pods removed"
        else
            print_info "Test namespace not found"
        fi
    else
        print_warning "Kubeconfig not found, skipping cleanup"
    fi
}

# Main execution
main() {
    local command="${1:-help}"
    shift || true
    
    # Parse additional options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                SKIP_CONFIRMATION=true
                ;;
            --timeout)
                TEST_TIMEOUT="$2"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
        shift
    done
    
    case "$command" in
        validate)
            validate_network
            ;;
        cleanup)
            cleanup_resources
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
exit $?