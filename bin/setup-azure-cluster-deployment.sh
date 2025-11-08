#!/usr/bin/env bash

# Script: setup-azure-cluster-deployment.sh
# Purpose: Configure k0rdent management cluster with Azure credentials for child cluster deployment
# Usage: bash setup-azure-cluster-deployment.sh [setup|cleanup|status|help]
# Prerequisites: k0rdent installed, Azure CLI authenticated, kubectl access

set -euo pipefail

# Load ALL existing k0rdent infrastructure
source ./etc/k0rdent-config.sh      # Loads CONFIG_YAML automatically
source ./etc/common-functions.sh     # All common functionality
source ./etc/state-management.sh     # State tracking

# Output directory and file (reuse from k0rdent)
K0SCTL_DIR="./k0sctl-config"
KUBECONFIG_FILE="$K0SCTL_DIR/${K0RDENT_CLUSTERID}-kubeconfig"

# Constants from k0rdent documentation  
AZURE_SP_NAME="${K0RDENT_CLUSTERID}-cluster-deployment-sp"
AZURE_SECRET_NAME="azure-cluster-identity-secret"
AZURE_IDENTITY_NAME="azure-cluster-identity"
KCM_CREDENTIAL_NAME="azure-cluster-credential"
KCM_NAMESPACE="kcm-system"

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  setup      Configure k0rdent with Azure credentials
  cleanup    Remove Azure credential configuration
  cleanup    --azure-only  Remove only Azure Service Principal (skip Kubernetes)
  status     Show Azure credential status
  help       Show this help message" \
        "  -y, --yes        Skip confirmation prompts" \
        "  $0 setup         # Configure Azure credentials
  $0 status        # Check credential status
  $0 cleanup       # Remove Azure credentials
  $0 cleanup --azure-only  # Remove only Azure Service Principal"
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if k0rdent is installed
    if [[ "$(get_state "k0rdent_installed")" != "true" ]]; then
        print_error "k0rdent must be installed first"
        return 1
    fi
    
    # VPN connectivity not required for post-deployment operations
    # We only need kubectl access to the management cluster
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI not found. Please install Azure CLI."
        return 1
    fi
    
    # Check Azure CLI authentication
    if ! az account show &> /dev/null; then
        print_error "Azure CLI not authenticated. Run: az login"
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
    
    print_success "Prerequisites satisfied"
    return 0
}

wait_for_capz_ready() {
    print_info "Waiting for Cluster API Azure provider to be ready..."
    
    local max_attempts=60  # 5 minutes (60 * 5 seconds)
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        # Check if there are any pods with capz or azure in their name that are running
        local capz_pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep -E "(capz|azure)" | grep "Running" | wc -l | tr -d ' ')
        
        if [[ "$capz_pods" -gt 0 ]]; then
            # Check if the necessary CRDs exist
            if kubectl get crd azureclusteridentities.infrastructure.cluster.x-k8s.io &>/dev/null; then
                print_success "Cluster API Azure provider is ready"
                return 0
            fi
        fi
        
        attempt=$((attempt + 1))
        if [[ $((attempt % 12)) -eq 0 ]]; then
            print_info "Still waiting for CAPZ to be ready... ($((attempt * 5)) seconds elapsed)"
        fi
        sleep 5
    done
    
    print_error "Timeout waiting for Cluster API Azure provider to be ready"
    print_info "Current state:"
    kubectl get pods -A | grep -E "(capz|azure)" || echo "No CAPZ/Azure pods found"
    kubectl get crd | grep azure || echo "No Azure CRDs found"
    return 1
}

verify_azure_credentials() {
    print_info "Verifying Azure credentials..."
    
    # Test basic authentication
    if ! az account show &>/dev/null; then
        print_error "Failed to authenticate with Azure"
        print_error "Please verify your Azure CLI authentication with: az login"
        return 1
    fi
    
    # Get subscription info to verify access
    local subscription_info
    subscription_info=$(az account show --output json)
    local subscription_id=$(echo "$subscription_info" | jq -r '.id')
    
    # Test basic permissions - try to list resource groups
    if ! az group list --subscription "$subscription_id" --output table &>/dev/null; then
        print_warning "Unable to list resource groups - credentials may lack necessary permissions"
    else
        print_success "Successfully verified access to subscription"
    fi
    
    # Test VM permissions - try to list VM sizes in the target location
    local test_location="${AZURE_LOCATION:-eastus}"
    if ! az vm list-sizes --location "$test_location" --subscription "$subscription_id" --output table &>/dev/null; then
        print_warning "Unable to list VM sizes - credentials may lack VM creation permissions"
    else
        print_success "Successfully verified VM permissions in $test_location"
    fi
    
    print_success "Azure credentials verification completed"
    return 0
}

setup_azure_credentials() {
    print_header "Setting up Azure Credentials for k0rdent"

    if state_file_exists && phase_is_completed "setup_azure_children"; then
        if [[ "$(get_azure_state "azure_credentials_configured")" == "true" ]]; then
            print_success "Azure credentials already configured for child deployments."
            return 0
        fi
        print_warning "Azure credential phase recorded as complete but validation failed. Reconfiguring credentials."
        phase_reset_from "setup_azure_children"
    fi
    phase_mark_in_progress "setup_azure_children"
    
    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi
    
    # Verify Azure credentials before proceeding
    if ! verify_azure_credentials; then
        print_error "Azure credential verification failed"
        return 1
    fi
    
    # Wait for CAPZ to be ready
    if ! wait_for_capz_ready; then
        print_error "Cannot proceed without Cluster API Azure provider"
        return 1
    fi
    
    # Get Azure subscription info
    print_info "Getting Azure subscription information..."
    local subscription_info
    subscription_info=$(az account show --output json)
    
    local subscription_id=$(echo "$subscription_info" | jq -r '.id')
    local tenant_id=$(echo "$subscription_info" | jq -r '.tenantId')
    
    print_info "Subscription ID: $subscription_id"
    print_info "Tenant ID: $tenant_id"
    
    # Create Service Principal
    print_info "Creating Service Principal..."
    local sp_result
    sp_result=$(az ad sp create-for-rbac \
        --name "$AZURE_SP_NAME" \
        --role contributor \
        --scopes "/subscriptions/$subscription_id" \
        --output json)
    
    local client_id=$(echo "$sp_result" | jq -r '.appId')
    local client_secret=$(echo "$sp_result" | jq -r '.password')
    
    print_success "Service Principal created: $client_id"
    
    # Verify the Service Principal propagated successfully
    print_info "Verifying Service Principal propagation..."

    local max_wait_seconds=300  # 5 minutes total timeout
    local check_interval=10      # Check every 10 seconds
    local elapsed=0
    local sp_verified=false

    while [[ $elapsed -lt $max_wait_seconds ]]; do
        # Verify SP exists and is accessible without switching authentication
        if az ad sp show --id "$client_id" &>/dev/null; then
            print_success "Service Principal verified and propagated"
            sp_verified=true
            break
        fi

        # Show progress every 30 seconds
        if [[ $((elapsed % 30)) -eq 0 ]] && [[ $elapsed -gt 0 ]]; then
            print_info "Still waiting for Service Principal propagation... (${elapsed}s elapsed)"
        fi

        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done

    if [[ "$sp_verified" != "true" ]]; then
        print_error "Service Principal verification timed out after ${max_wait_seconds}s"
        print_error "The Service Principal may need more time to propagate, or there may be a permissions issue"
        print_info "Manual verification: az ad sp show --id $client_id"
        # Clean up the failed SP
        az ad sp delete --id "$client_id" 2>/dev/null || true
        return 1
    fi

    # Additional wait for Azure RBAC propagation
    print_info "Waiting 10 seconds for Azure RBAC propagation..."
    sleep 10
    
    # Save credentials to local file
    print_info "Saving Azure credentials to config/azure-credentials.yaml..."
    cat > config/azure-credentials.yaml << EOF
# Azure credentials for k0rdent cluster deployment
# Generated on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# WARNING: This file contains sensitive credentials. Do not commit to version control.

azure:
  subscription_id: "$subscription_id"
  tenant_id: "$tenant_id"
  client_id: "$client_id"
  client_secret: "$client_secret"
  service_principal_name: "$AZURE_SP_NAME"
EOF
    chmod 600 config/azure-credentials.yaml
    print_success "Azure credentials saved to config/azure-credentials.yaml"
    
    # Create or update Kubernetes secret
    print_info "Checking for existing Kubernetes secret..."
    
    # Check if secret already exists
    if kubectl get secret "$AZURE_SECRET_NAME" -n "$KCM_NAMESPACE" &>/dev/null; then
        print_info "Secret already exists, reusing it"
    else
        print_info "Creating new Kubernetes secret..."
        kubectl create secret generic "$AZURE_SECRET_NAME" \
            --from-literal=clientSecret="$client_secret" \
            -n "$KCM_NAMESPACE"
    fi
    
    kubectl label secret "$AZURE_SECRET_NAME" \
        -n "$KCM_NAMESPACE" \
        k0rdent.mirantis.com/component=kcm
    
    # Create AzureClusterIdentity
    print_info "Checking AzureClusterIdentity..."
    
    # Double-check CRDs are available before creating resources
    if ! kubectl get crd azureclusteridentities.infrastructure.cluster.x-k8s.io &>/dev/null; then
        print_error "AzureClusterIdentity CRD not found. CAPZ may not be fully installed."
        return 1
    fi
    
    # Check if AzureClusterIdentity already exists
    if kubectl get azureclusteridentity "$AZURE_IDENTITY_NAME" -n "$KCM_NAMESPACE" &>/dev/null; then
        print_info "AzureClusterIdentity already exists, reusing it"
    else
        print_info "Creating new AzureClusterIdentity..."
        cat <<EOF | kubectl apply -f -
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: AzureClusterIdentity
metadata:
  name: $AZURE_IDENTITY_NAME
  namespace: $KCM_NAMESPACE
spec:
  type: ServicePrincipal
  tenantID: $tenant_id
  clientID: $client_id
  clientSecret:
    name: $AZURE_SECRET_NAME
    namespace: $KCM_NAMESPACE
  allowedNamespaces: {}
EOF
    fi
    
    # Create KCM Credential
    print_info "Checking KCM Credential..."
    
    if kubectl get credential "$KCM_CREDENTIAL_NAME" -n "$KCM_NAMESPACE" &>/dev/null; then
        print_info "KCM Credential already exists, reusing it"
    else
        print_info "Creating new KCM Credential..."
        cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  name: $KCM_CREDENTIAL_NAME
  namespace: $KCM_NAMESPACE
spec:
  description: "Azure credentials for cluster deployment"
  identityRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: AzureClusterIdentity
    name: $AZURE_IDENTITY_NAME
    namespace: $KCM_NAMESPACE
EOF
    fi
    
    # Create Azure Resource Template ConfigMap
    print_info "Creating Azure Resource Template ConfigMap..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: azure-cluster-identity-resource-template
  namespace: $KCM_NAMESPACE
  labels:
    k0rdent.mirantis.com/component: "kcm"
  annotations:
    projectsveltos.io/template: "true"
data:
  configmap.yaml: |
    {{- \$cluster := .InfrastructureProvider -}}
    {{- \$identity := (getResource "InfrastructureProviderIdentity") -}}
    {{- \$secret := (getResource "InfrastructureProviderIdentitySecret") -}}
    {{- \$subnetName := "" -}}
    {{- \$securityGroupName := "" -}}
    {{- \$routeTableName := "" -}}
    {{- range \$cluster.spec.networkSpec.subnets -}}
      {{- if eq .role "node" -}}
        {{- \$subnetName = .name -}}
        {{- \$securityGroupName = .securityGroup.name -}}
        {{- \$routeTableName = .routeTable.name -}}
        {{- break -}}
      {{- end -}}
    {{- end -}}
    {{- \$cloudConfig := dict
      "aadClientId" \$identity.spec.clientID
      "aadClientSecret" (index \$secret.data "clientSecret" | b64dec)
      "cloud" \$cluster.spec.azureEnvironment
      "loadBalancerName" ""
      "loadBalancerSku" "Standard"
      "location" \$cluster.spec.location
      "maximumLoadBalancerRuleCount" 250
      "resourceGroup" \$cluster.spec.resourceGroup
      "routeTableName" \$routeTableName
      "securityGroupName" \$securityGroupName
      "securityGroupResourceGroup" \$cluster.spec.networkSpec.vnet.resourceGroup
      "subnetName" \$subnetName
      "subscriptionId" \$cluster.spec.subscriptionID
      "tenantId" \$identity.spec.tenantID
      "useManagedIdentityExtension" false
      "userAssignedIdentityId" ""
      "useInstanceMetadata" true
      "vmType" "standard"
      "vnetName" \$cluster.spec.networkSpec.vnet.name
      "vnetResourceGroup" \$cluster.spec.networkSpec.vnet.resourceGroup -}}
    apiVersion: v1
    kind: Secret
    metadata:
      name: azure-cloud-provider
      namespace: kube-system
    type: Opaque
    stringData:
      cloud-config: |
        {{ \$cloudConfig | toYaml | nindent 8 }}
      azure.json: |
        {{ \$cloudConfig | toYaml | nindent 8 }}
  storageclass.yaml: |
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: managed-csi
      annotations:
        storageclass.kubernetes.io/is-default-class: "true"
    provisioner: disk.csi.azure.com
    parameters:
      skuName: StandardSSD_LRS
    reclaimPolicy: Delete
    volumeBindingMode: WaitForFirstConsumer
    allowVolumeExpansion: true
EOF
    
    # Update Azure state
    update_azure_state "azure_credentials_configured" "true"
    update_azure_state "azure_subscription_id" "$subscription_id"
    update_azure_state "azure_tenant_id" "$tenant_id"
    update_azure_state "azure_client_id" "$client_id"
    add_azure_event "azure_credentials_configured" "Azure credentials configured for cluster deployment"
    
    print_success "Azure credentials configured successfully!"
    phase_mark_completed "setup_azure_children"
}

cleanup_azure_credentials() {
    local azure_only=false
    # Check for --azure-only flag in remaining arguments
    for arg in "${ORIGINAL_ARGS[@]}"; do
        case "$arg" in
            --azure-only)
                azure_only=true
                break
                ;;
        esac
    done
    
    if [[ "$azure_only" == "true" ]]; then
        print_header "Cleaning up Azure Service Principal (Azure-only mode)"
        print_info "Skipping Kubernetes resource cleanup (cluster not available)"
    else
        print_header "Cleaning up Azure Credentials"
    fi
    
    # Check if configured
    if [[ "$(get_azure_state "azure_credentials_configured")" != "true" ]]; then
        print_info "Azure credentials not configured"
        return 0
    fi
    
    # Confirm cleanup
    if [[ "${SKIP_CONFIRMATION:-false}" != "true" ]]; then
        print_warning "This will remove Azure credentials and Service Principal"
        if ! confirm_action "Proceed with cleanup?"; then
            print_info "Cleanup cancelled"
            return 0
        fi
    fi
    
    # Skip Kubernetes resource cleanup in azure-only mode
    if [[ "$azure_only" != "true" ]]; then
        export KUBECONFIG="$KUBECONFIG_FILE"
        
        # Remove KCM Credential
        kubectl delete credential "$KCM_CREDENTIAL_NAME" -n "$KCM_NAMESPACE" --ignore-not-found
        
        # Remove AzureClusterIdentity
        kubectl delete azureclusteridentity "$AZURE_IDENTITY_NAME" -n "$KCM_NAMESPACE" --ignore-not-found
        
        # Remove Kubernetes secret
        kubectl delete secret "$AZURE_SECRET_NAME" -n "$KCM_NAMESPACE" --ignore-not-found
        
        # Remove Azure Resource Template ConfigMap
        kubectl delete configmap azure-cluster-identity-resource-template -n "$KCM_NAMESPACE" --ignore-not-found
    else
        print_info "Skipping Kubernetes resource cleanup (cluster being deleted in fast reset)"
    fi
    
    # Remove Service Principal
    local client_id=$(get_azure_state "azure_client_id")
    if [[ -n "$client_id" ]]; then
        # Check if we're authenticated as the Service Principal itself
        local current_user=$(az account show --query user.type -o tsv 2>/dev/null || echo "unknown")
        if [[ "$current_user" == "servicePrincipal" ]]; then
            print_warning "Cannot delete Service Principal - authenticated as Service Principal"
            print_info "To delete the Service Principal manually:"
            print_info "  1. Re-authenticate as another user: az login"
            print_info "  2. Delete with: az ad sp delete --id $client_id"
        else
            if az ad sp delete --id "$client_id" 2>/dev/null; then
                print_success "Removed Azure Service Principal"
            else
                print_warning "Failed to remove Azure Service Principal (permission issue?)"
                print_info "Manual deletion may be required: az ad sp delete --id $client_id"
            fi
        fi
    fi
    
    # Remove local credentials file
    if [[ -f "config/azure-credentials.yaml" ]]; then
        rm -f config/azure-credentials.yaml
        print_info "Removed config/azure-credentials.yaml"
    fi
    
    # Update Azure state
    update_azure_state "azure_credentials_configured" "false"
    remove_azure_state_key "azure_subscription_id"
    remove_azure_state_key "azure_tenant_id"
    remove_azure_state_key "azure_client_id"
    add_azure_event "azure_credentials_cleanup" "Azure credentials cleanup completed (auto-mode: $([ "${SKIP_CONFIRMATION:-false}" = "true" ] && echo "yes" || echo "no"))"
    phase_reset_from "setup_azure_children"
    
    if [[ "$azure_only" == "true" ]]; then
        print_success "Azure Service Principal cleanup completed!"
    else
        print_success "Azure credentials cleanup completed!"
    fi
}

show_azure_credential_status() {
    print_header "Azure Credential Status"
    
    # Check configuration state
    local configured=$(get_azure_state "azure_credentials_configured")
    if [[ "$configured" != "true" ]]; then
        print_info "Azure credentials not configured"
        return 0
    fi
    
    # Show configuration
    print_info "Azure Credential Information:"
    print_info "  Subscription ID: $(get_azure_state "azure_subscription_id")"
    print_info "  Tenant ID: $(get_azure_state "azure_tenant_id")"
    print_info "  Client ID: $(get_azure_state "azure_client_id")"
    
    # Check if local credentials file exists
    if [[ -f "config/azure-credentials.yaml" ]]; then
        print_info "  Credentials file: config/azure-credentials.yaml (exists)"
    else
        print_warning "  Credentials file: config/azure-credentials.yaml (missing)"
    fi
    
    # Check Kubernetes resources if connected
    if [[ -f "$KUBECONFIG_FILE" ]]; then
        export KUBECONFIG="$KUBECONFIG_FILE"
        
        if kubectl get nodes &>/dev/null; then
            print_info ""
            print_info "Kubernetes Resources:"
            kubectl get azureclusteridentity,credential,secret \
                -n "$KCM_NAMESPACE" \
                --selector=k0rdent.mirantis.com/component=kcm 2>/dev/null || true
        fi
    fi
}

# Store original arguments for handle_standard_commands
ORIGINAL_ARGS=("$@")

# Parse standard arguments to get COMMAND
PARSED_ARGS=$(parse_standard_args "$@")
eval "$PARSED_ARGS"

# Get the command from positional arguments
COMMAND="${POSITIONAL_ARGS[0]:-}"

# Use consolidated command handling
handle_standard_commands "$0" "setup cleanup status help" \
    "setup" "setup_azure_credentials" \
    "cleanup" "cleanup_azure_credentials" \
    "status" "show_azure_credential_status" \
    "usage" "show_usage"
