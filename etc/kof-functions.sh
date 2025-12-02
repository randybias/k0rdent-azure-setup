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

# Wait for Victoria Metrics operator webhook to become ready
# This prevents race conditions where kof-mothership installation fails because
# the webhook is not yet accepting requests after kof-operators helm install completes.
#
# The webhook requires three components to be ready:
# 1. ValidatingWebhookConfiguration must exist
# 2. Webhook service must have endpoints
# 3. Webhook pod must be ready
#
# Parameters:
#   $1 - namespace (optional, defaults to "kof")
#   $2 - timeout in seconds (optional, defaults to 180)
#
# Returns:
#   0 - webhook is ready
#   1 - timeout or error
wait_for_victoria_metrics_webhook() {
    local namespace="${1:-kof}"
    local timeout_seconds="${2:-180}"
    local check_interval=10
    local progress_interval=30
    local elapsed=0
    local last_progress=0

    # Ensure minimum timeout of 30 seconds
    if [[ $timeout_seconds -lt 30 ]]; then
        timeout_seconds=30
    fi

    print_info "Waiting for Victoria Metrics operator webhook to be ready (timeout: ${timeout_seconds}s)..."

    while [[ $elapsed -lt $timeout_seconds ]]; do
        # Check 1: ValidatingWebhookConfiguration exists
        local webhook_config_exists=false
        if kubectl get validatingwebhookconfigurations -l app.kubernetes.io/name=victoria-metrics-operator &>/dev/null 2>&1; then
            local webhook_count
            webhook_count=$(kubectl get validatingwebhookconfigurations -l app.kubernetes.io/name=victoria-metrics-operator --no-headers 2>/dev/null | wc -l | tr -d ' ')
            if [[ $webhook_count -gt 0 ]]; then
                webhook_config_exists=true
            fi
        fi

        # Check 2: Webhook service has endpoints
        local endpoints_ready=false
        if [[ "$webhook_config_exists" == "true" ]]; then
            local endpoint_count
            endpoint_count=$(kubectl get endpoints -n "$namespace" -l app.kubernetes.io/name=victoria-metrics-operator --no-headers 2>/dev/null | awk '{print $2}' | grep -v '<none>' | head -1)
            if [[ -n "$endpoint_count" ]] && [[ "$endpoint_count" != "<none>" ]]; then
                endpoints_ready=true
            fi
        fi

        # Check 3: Webhook pod is ready
        local pod_ready=false
        if [[ "$endpoints_ready" == "true" ]]; then
            local ready_pods
            ready_pods=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=victoria-metrics-operator -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
            if [[ "$ready_pods" == *"True"* ]]; then
                pod_ready=true
            fi
        fi

        # All checks passed
        if [[ "$webhook_config_exists" == "true" ]] && [[ "$endpoints_ready" == "true" ]] && [[ "$pod_ready" == "true" ]]; then
            print_success "Victoria Metrics operator webhook is ready (${elapsed}s elapsed)"
            return 0
        fi

        # Progress reporting every 30 seconds
        if [[ $((elapsed - last_progress)) -ge $progress_interval ]] && [[ $elapsed -gt 0 ]]; then
            local status_msg="Webhook status: config=$webhook_config_exists, endpoints=$endpoints_ready, pod=$pod_ready"
            print_info "Still waiting for webhook... (${elapsed}s elapsed) - $status_msg"
            last_progress=$elapsed
        fi

        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    # Timeout - provide diagnostic information
    print_error "Timeout waiting for Victoria Metrics operator webhook after ${timeout_seconds} seconds"
    print_info ""
    print_info "Diagnostic Information:"
    print_info "========================"

    # Report ValidatingWebhookConfiguration status
    print_info "ValidatingWebhookConfigurations:"
    kubectl get validatingwebhookconfigurations -l app.kubernetes.io/name=victoria-metrics-operator 2>/dev/null || print_info "  (none found)"

    # Report service endpoints
    print_info ""
    print_info "Webhook Service Endpoints:"
    kubectl get endpoints -n "$namespace" -l app.kubernetes.io/name=victoria-metrics-operator 2>/dev/null || print_info "  (none found)"

    # Report pod status
    print_info ""
    print_info "Webhook Pod Status:"
    kubectl get pods -n "$namespace" -l app.kubernetes.io/name=victoria-metrics-operator 2>/dev/null || print_info "  (none found)"

    print_info ""
    print_info "Troubleshooting suggestions:"
    print_info "  1. Check operator logs: kubectl logs -n $namespace -l app.kubernetes.io/name=victoria-metrics-operator"
    print_info "  2. Check operator events: kubectl get events -n $namespace --sort-by='.lastTimestamp'"
    print_info "  3. Verify kof-operators helm release: helm status kof-operators -n $namespace"

    return 1
}

# All other functions (check_vpn_connectivity, execute_remote_command, etc.)
# are already available from common-functions.sh