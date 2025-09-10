#!/usr/bin/env bash

# kof-functions.sh
# KOF-specific shared functions
# This file contains ONLY functions specific to KOF that don't exist in common-functions.sh
# All general functions (error handling, logging, etc.) are reused from common-functions.sh

# Check if KOF is enabled in configuration
# Uses existing CONFIG_YAML loaded by k0rdent-config.sh
check_kof_enabled() {
    local kof_enabled
    kof_enabled=$(yq '.kof.enabled // false' "$CONFIG_YAML" 2>/dev/null || echo "false")
    [[ "$kof_enabled" == "true" ]]
}

# Get KOF configuration value
# Reuses existing CONFIG_YAML variable
get_kof_config() {
    local key="$1"
    local default="${2:-}"
    local value
    value=$(yq eval ".kof.$key" "$CONFIG_YAML" 2>/dev/null || echo "null")
    if [[ "$value" == "null" ]] || [[ -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Check Istio installation
check_istio_installed() {
    kubectl get namespace istio-system &>/dev/null
}

# Install Istio for KOF
# Uses existing error handling from common-functions.sh
install_istio_for_kof() {
    local istio_version=$(get_kof_config "istio.version" "1.1.0")
    local istio_namespace=$(get_kof_config "istio.namespace" "istio-system")
    local timeout_seconds=600  # 10 minutes default timeout
    local check_interval=10    # Check every 10 seconds
    local elapsed=0

    print_info "Installing Istio for KOF (version: $istio_version)"
    
    # Wait for Sveltos CRDs to be available (required by kof-istio chart)
    print_info "Waiting for required Sveltos CRDs to be available (timeout: ${timeout_seconds}s)..."
    
    while [[ $elapsed -lt $timeout_seconds ]]; do
        if kubectl get crd clusterprofiles.config.projectsveltos.io &>/dev/null; then
            print_success "Required ClusterProfile CRD is available"
            break
        fi
        
        if [[ $elapsed -eq 0 ]]; then
            print_info "ClusterProfile CRD not yet available, waiting..."
        elif [[ $((elapsed % 30)) -eq 0 ]]; then
            print_info "Still waiting for ClusterProfile CRD... (${elapsed}s elapsed)"
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    # Check if we timed out
    if [[ $elapsed -ge $timeout_seconds ]]; then
        print_error "Timeout waiting for ClusterProfile CRD after ${timeout_seconds} seconds"
        print_info "Ensure k0rdent is fully deployed before installing KOF"
        return 1
    fi
    
    # Additional check for Sveltos controller readiness
    print_info "Checking Sveltos controller readiness..."
    if kubectl get namespace projectsveltos &>/dev/null; then
        # Wait for at least one Sveltos deployment to be ready
        local sveltos_ready=false
        local wait_time=0
        while [[ $wait_time -lt 60 ]]; do
            if kubectl get deployment -n projectsveltos sc-manager &>/dev/null && \
               [[ $(kubectl get deployment -n projectsveltos sc-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null) -ge 1 ]]; then
                sveltos_ready=true
                print_success "Sveltos controllers are ready"
                break
            fi
            sleep 5
            wait_time=$((wait_time + 5))
        done
        
        if [[ "$sveltos_ready" != "true" ]]; then
            print_warning "Sveltos controllers may not be fully ready, proceeding with Istio installation..."
        fi
    fi
    
    print_info "Installing Istio Helm chart..."
    
    # Install the Istio chart
    if helm upgrade -i --reset-values --wait \
        --create-namespace -n "$istio_namespace" kof-istio \
        oci://ghcr.io/k0rdent/kof/charts/kof-istio --version "$istio_version"; then
        print_success "Istio installed successfully"
        return 0
    else
        print_error "Failed to install Istio"
        return 1
    fi
}

# Create and label KOF namespace
# Reuses print functions from common-functions.sh
prepare_kof_namespace() {
    local namespace="${1:-kof}"
    print_info "Preparing KOF namespace: $namespace"
    
    if kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - && \
       kubectl label namespace "$namespace" istio-injection=enabled --overwrite; then
        print_success "KOF namespace prepared and labeled"
        return 0
    else
        print_error "Failed to prepare KOF namespace"
        return 1
    fi
}

# Check if KOF mothership is installed
check_kof_mothership_installed() {
    local namespace=$(get_kof_config "mothership.namespace" "kof")
    helm list -n "$namespace" | grep -q "kof-mothership"
}

# Check if KOF operators are installed
check_kof_operators_installed() {
    local namespace=$(get_kof_config "mothership.namespace" "kof")
    helm list -n "$namespace" | grep -q "kof-operators"
}

# All other functions (check_vpn_connectivity, execute_remote_command, etc.) 
# are already available from common-functions.sh