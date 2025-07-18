#!/usr/bin/env bash

# Script: create-aws-child.sh
# Purpose: Create a k0rdent AWS child cluster deployment
# Usage: bash create-aws-child.sh --cluster-name <name> --region <region> [options]
# Prerequisites: k0rdent management cluster with configured AWS credentials

set -euo pipefail

# Load ALL existing k0rdent infrastructure
source ./etc/k0rdent-config.sh      # Loads CONFIG_YAML automatically
source ./etc/common-functions.sh     # All common functionality
source ./etc/state-management.sh     # State tracking

# Output directory (reuse from k0rdent)
K0SCTL_DIR="./k0sctl-config"
KUBECONFIG_FILE="$K0SCTL_DIR/${K0RDENT_CLUSTERID}-kubeconfig"

# Initialize variables
CLUSTER_NAME=""
REGION=""
AVAILABILITY_ZONES=""  # Optional, comma-separated list
NAMESPACE=""
TEMPLATE=""
CREDENTIAL=""
CP_INSTANCE_SIZE=""
WORKER_INSTANCE_SIZE=""
ROOT_VOLUME_SIZE=""
DRY_RUN="false"
CLUSTER_LABELS=""
CLUSTER_ANNOTATIONS=""
CLUSTER_IDENTITY_NAME=""
CLUSTER_IDENTITY_NAMESPACE=""
CP_NUMBER=""
WORKER_NUMBER=""

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  --cluster-name <name>           Name of the child cluster to create (required)
         --region <region>               AWS region (e.g., us-east-1, us-west-2) (required)
         --availability-zones <zones>    Availability zones (comma-separated, e.g., \"us-east-1a,us-east-1b\")
         --cp-instance-size <size>       Control plane instance size (e.g., t3.medium) (required)
         --worker-instance-size <size>   Worker node instance size (e.g., t3.large) (required)
         --root-volume-size <gb>         Root volume size in GB (required)
         --namespace <ns>                Kubernetes namespace (required)
         --template <name>               Cluster template to use (required)
         --credential <name>             Credential name to use (required)
         --cp-number <num>               Number of control plane nodes (required)
         --worker-number <num>           Number of worker nodes (required)
         --cluster-identity-name <name>  Name of the cluster identity (required)
         --cluster-identity-namespace <ns> Namespace of the cluster identity (required)
         --dry-run                       Create deployment in dry-run mode (simulation)
         --cluster-labels <labels>       Cluster labels in key=value,key2=value2 format
         --cluster-annotations <annotations> Cluster annotations in key=value,key2=value2 format" \
        "  -h, --help                     Show this help message" \
        "  $0 --cluster-name my-cluster --region us-east-1 \\
             --cp-instance-size t3.medium --worker-instance-size t3.large \\
             --root-volume-size 50 --namespace kcm-system \\
             --template aws-standalone-cp-1-0-8 --credential aws-cluster-credential \\
             --cp-number 1 --worker-number 3 \\
             --cluster-identity-name aws-cluster-identity --cluster-identity-namespace kcm-system
             
           $0 --cluster-name ha-cluster --region us-west-2 \\
             --availability-zones \"us-west-2a,us-west-2b,us-west-2c\" \\
             --cp-instance-size m5.large --worker-instance-size m5.xlarge \\
             --root-volume-size 100 --namespace kcm-system \\
             --template aws-ha-cp-1-0-8 --credential aws-cluster-credential \\
             --cp-number 3 --worker-number 3 \\
             --cluster-identity-name aws-cluster-identity --cluster-identity-namespace kcm-system \\
             --cluster-labels environment=production,team=platform"
    }

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --availability-zones)
                AVAILABILITY_ZONES="$2"
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
            --cluster-annotations)
                CLUSTER_ANNOTATIONS="$2"
                shift 2
                ;;
            --cp-number)
                CP_NUMBER="$2"
                shift 2
                ;;
            --worker-number)
                WORKER_NUMBER="$2"
                shift 2
                ;;
            --cluster-identity-name)
                CLUSTER_IDENTITY_NAME="$2"
                shift 2
                ;;
            --cluster-identity-namespace)
                CLUSTER_IDENTITY_NAMESPACE="$2"
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
    
    if [[ -z "$REGION" ]]; then
        print_error "Region is required (--region)"
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
    
    if [[ -z "$CP_NUMBER" ]]; then
        print_error "Control plane number is required (--cp-number)"
        ((errors++))
    fi
    
    if [[ -z "$WORKER_NUMBER" ]]; then
        print_error "Worker number is required (--worker-number)"
        ((errors++))
    fi
    
    if [[ -z "$CLUSTER_IDENTITY_NAME" ]]; then
        print_error "Cluster identity name is required (--cluster-identity-name)"
        ((errors++))
    fi
    
    if [[ -z "$CLUSTER_IDENTITY_NAMESPACE" ]]; then
        print_error "Cluster identity namespace is required (--cluster-identity-namespace)"
        ((errors++))
    fi
    
    
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
    
    # Check if AWS credentials are configured
    if [[ "$(get_state "aws_credentials_configured")" != "true" ]]; then
        print_error "AWS credentials not configured. Run: bash bin/setup-aws-cluster-deployment.sh setup --role-arn <ARN>"
        return 1
    fi
    
    # Verify credential exists
    if ! kubectl get credential "$CREDENTIAL" -n "$NAMESPACE" &>/dev/null; then
        print_error "AWS credential '$CREDENTIAL' not found in namespace '$NAMESPACE'"
        return 1
    fi
    
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

# Get AWS account configuration
get_aws_config() {
    # Get account ID from AWS credentials
    local account_id=$(get_state "aws_account_id")
    if [[ -z "$account_id" || "$account_id" == "null" ]]; then
        print_error "AWS account ID not found in state"
        return 1
    fi
    echo "$account_id"
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

# Convert cluster annotations to YAML format
format_cluster_annotations() {
    if [[ -z "$CLUSTER_ANNOTATIONS" ]]; then
        echo "{}"
        return
    fi
    
    # Convert key=value,key2=value2 to YAML
    echo ""
    IFS=',' read -ra ANNOTATION_PAIRS <<< "$CLUSTER_ANNOTATIONS"
    for pair in "${ANNOTATION_PAIRS[@]}"; do
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
    
    # Get AWS account configuration
    local account_id
    account_id=$(get_aws_config)
    
    # Format cluster labels and annotations
    local formatted_labels
    formatted_labels=$(format_cluster_labels)
    
    local formatted_annotations
    formatted_annotations=$(format_cluster_annotations)
    
    print_info "Cluster Configuration:"
    print_info "  Name: $CLUSTER_NAME"
    print_info "  Cloud: AWS"
    print_info "  Region: $REGION"
    [[ -n "$AVAILABILITY_ZONES" ]] && print_info "  Availability Zones: $AVAILABILITY_ZONES"
    print_info "  Template: $TEMPLATE"
    print_info "  Credential: $CREDENTIAL"
    print_info "  Namespace: $NAMESPACE"
    print_info "  Control Plane Size: $CP_INSTANCE_SIZE"
    print_info "  Worker Node Size: $WORKER_INSTANCE_SIZE"
    print_info "  Root Volume Size: ${ROOT_VOLUME_SIZE}GB"
    print_info "  Control Plane Count: $CP_NUMBER"
    print_info "  Worker Count: $WORKER_NUMBER"
    print_info "  Cluster Identity: $CLUSTER_IDENTITY_NAME (namespace: $CLUSTER_IDENTITY_NAMESPACE)"
    print_info "  Dry Run: $DRY_RUN"
    [[ -n "$CLUSTER_LABELS" ]] && print_info "  Labels: $CLUSTER_LABELS"
    [[ -n "$CLUSTER_ANNOTATIONS" ]] && print_info "  Annotations: $CLUSTER_ANNOTATIONS"
    print_info "  Account ID: $account_id"
    
    # Create ClusterDeployment YAML
    print_info "Creating ClusterDeployment..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: $CLUSTER_NAME
  namespace: $NAMESPACE
  labels: $formatted_labels
  annotations: $formatted_annotations
spec:
  template: $TEMPLATE
  credential: $CREDENTIAL
  dryRun: $DRY_RUN
  config:
    clusterIdentity:
      name: $CLUSTER_IDENTITY_NAME
      namespace: $CLUSTER_IDENTITY_NAMESPACE
    region: "$REGION"
    controlPlaneNumber: $CP_NUMBER
    controlPlane:
      instanceType: $CP_INSTANCE_SIZE
      rootVolumeSize: $ROOT_VOLUME_SIZE
    workersNumber: $WORKER_NUMBER
    worker:
      instanceType: $WORKER_INSTANCE_SIZE
      rootVolumeSize: $ROOT_VOLUME_SIZE
EOF

    # Note: availability zones configuration would be added here if k0rdent templates support it
    # availabilityZones: ["$AVAILABILITY_ZONES"] if specified
    
    # Track cluster creation event (k0rdent is source of truth for state)
    init_cluster_events "$CLUSTER_NAME"
    add_cluster_event "$CLUSTER_NAME" "cluster_deployment_created" "ClusterDeployment '$CLUSTER_NAME' created for AWS cluster in $REGION"
    add_cluster_event "$CLUSTER_NAME" "cluster_config_recorded" "Template: $TEMPLATE, Credential: $CREDENTIAL, DryRun: $DRY_RUN"
    
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