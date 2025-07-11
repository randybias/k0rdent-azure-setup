#!/usr/bin/env bash

# Script: create-child.sh
# Purpose: Create a k0rdent child cluster deployment
# Usage: bash create-child.sh --cluster-name <name> --cloud <cloud> --location <location> [options]
# Prerequisites: k0rdent management cluster with configured credentials

set -euo pipefail

# Load ALL existing k0rdent infrastructure
source ./etc/k0rdent-config.sh      # Loads CONFIG_YAML automatically
source ./etc/common-functions.sh     # All common functionality
source ./etc/state-management.sh     # State tracking

# Output directory (reuse from k0rdent)
K0SCTL_DIR="./k0sctl-config"
KUBECONFIG_FILE="$K0SCTL_DIR/${K0RDENT_PREFIX}-kubeconfig"

# Initialize variables
CLUSTER_NAME=""
CLOUD=""
LOCATION=""
NAMESPACE=""
TEMPLATE=""
CREDENTIAL=""
CP_INSTANCE_SIZE=""
WORKER_INSTANCE_SIZE=""
ROOT_VOLUME_SIZE=""
DRY_RUN="false"
CLUSTER_LABELS=""

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  --cluster-name <name>     Name of the child cluster to create (required)
  --cloud <provider>        Cloud provider: azure (required)
  --location <region>       Cloud region/location (required)
  --cp-instance-size <size> Control plane instance size (required)
  --worker-instance-size <size> Worker node instance size (required)
  --root-volume-size <gb>   Root volume size in GB (required)
  --namespace <ns>          Kubernetes namespace (required)
  --template <name>         Cluster template to use (required)
  --credential <name>       Credential name to use (required)
  --dry-run                 Create deployment in dry-run mode (simulation)
  --cluster-labels <labels> Cluster labels in key=value,key2=value2 format" \
        "  -h, --help               Show this help message" \
        "  $0 --cluster-name my-cluster --cloud azure --location eastus \\
     --cp-instance-size Standard_A4_v2 --worker-instance-size Standard_A4_v2 \\
     --root-volume-size 32 --namespace kcm-system \\
     --template azure-standalone-cp-1-0-8 --credential azure-cluster-credential
  $0 --cluster-name prod-cluster --cloud azure --location westus2 \\
     --cp-instance-size Standard_D4s_v3 --worker-instance-size Standard_D2s_v3 \\
     --root-volume-size 50 --namespace kcm-system \\
     --template azure-standalone-cp-1-0-8 --credential azure-cluster-credential
  $0 --cluster-name test-cluster --cloud azure --location eastus \\
     --cp-instance-size Standard_A4_v2 --worker-instance-size Standard_A4_v2 \\
     --root-volume-size 32 --namespace kcm-system \\
     --template azure-standalone-cp-1-0-8 --credential azure-cluster-credential \\
     --dry-run"
}

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --cloud)
                CLOUD="$2"
                shift 2
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --cp-instance-size)
                CP_INSTANCE_SIZE="$2"
                shift 2
                ;;
            --worker-instance-size)
                WORKER_INSTANCE_SIZE="$2"
                shift 2
                ;;
            --root-volume-size)
                ROOT_VOLUME_SIZE="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --template)
                TEMPLATE="$2"
                shift 2
                ;;
            --credential)
                CREDENTIAL="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --cluster-labels)
                CLUSTER_LABELS="$2"
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

# Validate required arguments
validate_arguments() {
    local errors=0
    
    if [[ -z "$CLUSTER_NAME" ]]; then
        print_error "Cluster name is required (--cluster-name)"
        ((errors++))
    fi
    
    if [[ -z "$CLOUD" ]]; then
        print_error "Cloud provider is required (--cloud)"
        ((errors++))
    fi
    
    if [[ -z "$LOCATION" ]]; then
        print_error "Location is required (--location)"
        ((errors++))
    fi
    
    if [[ -z "$CP_INSTANCE_SIZE" ]]; then
        print_error "Control plane instance size is required (--cp-instance-size)"
        ((errors++))
    fi
    
    if [[ -z "$WORKER_INSTANCE_SIZE" ]]; then
        print_error "Worker instance size is required (--worker-instance-size)"
        ((errors++))
    fi
    
    if [[ -z "$ROOT_VOLUME_SIZE" ]]; then
        print_error "Root volume size is required (--root-volume-size)"
        ((errors++))
    fi
    
    if [[ -z "$NAMESPACE" ]]; then
        print_error "Namespace is required (--namespace)"
        ((errors++))
    fi
    
    if [[ -z "$TEMPLATE" ]]; then
        print_error "Template is required (--template)"
        ((errors++))
    fi
    
    if [[ -z "$CREDENTIAL" ]]; then
        print_error "Credential is required (--credential)"
        ((errors++))
    fi
    
    # Validate cloud provider
    case "$CLOUD" in
        azure)
            # No defaults, all parameters are required
            ;;
        *)
            print_error "Unsupported cloud provider: $CLOUD (currently only 'azure' is supported)"
            ((errors++))
            ;;
    esac
    
    if [[ $errors -gt 0 ]]; then
        print_error "Please fix the above errors and try again"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
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
    
    # Check if credentials are configured for the specified cloud
    case "$CLOUD" in
        azure)
            if [[ "$(get_azure_state "azure_credentials_configured")" != "true" ]]; then
                print_error "Azure credentials not configured. Run: bash bin/setup-azure-cluster-deployment.sh setup"
                return 1
            fi
            
            # Verify credential exists
            if ! kubectl get credential "$CREDENTIAL" -n "$NAMESPACE" &>/dev/null; then
                print_error "Azure credential '$CREDENTIAL' not found in namespace '$NAMESPACE'"
                return 1
            fi
            ;;
    esac
    
    # Check if cluster template exists
    if ! kubectl get clustertemplate "$TEMPLATE" -n "$NAMESPACE" &>/dev/null; then
        print_error "Cluster template '$TEMPLATE' not found in namespace '$NAMESPACE'"
        print_info "Available templates:"
        kubectl get clustertemplate -n "$NAMESPACE" --no-headers -o custom-columns=NAME:.metadata.name || true
        return 1
    fi
    
    print_success "Prerequisites satisfied"
    return 0
}

# Get cloud-specific configuration
get_cloud_config() {
    case "$CLOUD" in
        azure)
            # Get subscription ID from Azure credentials
            local subscription_id=$(get_azure_state "azure_subscription_id")
            if [[ -z "$subscription_id" || "$subscription_id" == "null" ]]; then
                print_error "Azure subscription ID not found in state"
                return 1
            fi
            echo "$subscription_id"
            ;;
        *)
            print_error "Unsupported cloud provider: $CLOUD"
            return 1
            ;;
    esac
}

# Convert cluster labels to YAML format
format_cluster_labels() {
    if [[ -z "$CLUSTER_LABELS" ]]; then
        echo "{}"
        return
    fi
    
    # Convert key=value,key2=value2 to YAML
    echo ""
    IFS=',' read -ra LABEL_PAIRS <<< "$CLUSTER_LABELS"
    for pair in "${LABEL_PAIRS[@]}"; do
        if [[ "$pair" == *"="* ]]; then
            local key="${pair%%=*}"
            local value="${pair#*=}"
            echo "      $key: \"$value\""
        fi
    done
}

# Create cluster deployment
create_cluster_deployment() {
    print_header "Creating Child Cluster Deployment"
    
    # Get cloud-specific configuration
    local cloud_config
    cloud_config=$(get_cloud_config)
    
    # Format cluster labels
    local formatted_labels
    formatted_labels=$(format_cluster_labels)
    
    print_info "Cluster Configuration:"
    print_info "  Name: $CLUSTER_NAME"
    print_info "  Cloud: $CLOUD"
    print_info "  Location: $LOCATION"
    print_info "  Template: $TEMPLATE"
    print_info "  Credential: $CREDENTIAL"
    print_info "  Namespace: $NAMESPACE"
    print_info "  Control Plane Size: $CP_INSTANCE_SIZE"
    print_info "  Worker Node Size: $WORKER_INSTANCE_SIZE"
    print_info "  Root Volume Size: ${ROOT_VOLUME_SIZE}GB"
    print_info "  Dry Run: $DRY_RUN"
    [[ -n "$CLUSTER_LABELS" ]] && print_info "  Labels: $CLUSTER_LABELS"
    
    case "$CLOUD" in
        azure)
            print_info "  Subscription ID: $cloud_config"
            ;;
    esac
    
    # Create ClusterDeployment YAML
    print_info "Creating ClusterDeployment..."
    
    case "$CLOUD" in
        azure)
            cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: $CLUSTER_NAME
  namespace: $NAMESPACE
spec:
  template: $TEMPLATE
  credential: $CREDENTIAL
  dryRun: $DRY_RUN
  config:
    clusterLabels: $formatted_labels
    location: "$LOCATION"
    subscriptionID: "$cloud_config"
    controlPlane:
      vmSize: $CP_INSTANCE_SIZE
      rootVolumeSize: $ROOT_VOLUME_SIZE
    worker:
      vmSize: $WORKER_INSTANCE_SIZE
      rootVolumeSize: $ROOT_VOLUME_SIZE
EOF
            ;;
    esac
    
    # Update cluster state
    init_cluster_state "$CLUSTER_NAME"
    update_cluster_state "$CLUSTER_NAME" "cluster_status" "deploying"
    update_cluster_state "$CLUSTER_NAME" "cloud_provider" "$CLOUD"
    update_cluster_state "$CLUSTER_NAME" "location" "$LOCATION"
    update_cluster_state "$CLUSTER_NAME" "template" "$TEMPLATE"
    update_cluster_state "$CLUSTER_NAME" "credential" "$CREDENTIAL"
    update_cluster_state "$CLUSTER_NAME" "dry_run" "$DRY_RUN"
    add_cluster_event "$CLUSTER_NAME" "cluster_deployment_created" "ClusterDeployment created for $CLOUD cluster"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_success "ClusterDeployment '$CLUSTER_NAME' created in dry-run mode (simulation)"
        print_info "Check status with: kubectl get clusterdeployment $CLUSTER_NAME -n $NAMESPACE"
    else
        print_success "ClusterDeployment '$CLUSTER_NAME' created successfully!"
        print_info "Monitor deployment progress with:"
        print_info "  kubectl get clusterdeployment $CLUSTER_NAME -n $NAMESPACE -w"
        print_info "  kubectl describe clusterdeployment $CLUSTER_NAME -n $NAMESPACE"
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    validate_arguments
    
    if ! check_prerequisites; then
        exit 1
    fi
    
    create_cluster_deployment
}

# Run main function with all arguments
main "$@"