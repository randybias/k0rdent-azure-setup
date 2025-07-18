#!/usr/bin/env bash

# Script: setup-aws-cluster-deployment.sh
# Purpose: Configure k0rdent management cluster with AWS credentials for child cluster deployment
# Usage: bash setup-aws-cluster-deployment.sh [setup|cleanup|status|help] --role-arn <ARN> [options]
# Prerequisites: 
#   - k0rdent installed
#   - IAM role manually created in AWS console with required CAPA policies
#   - AWS CLI installed (but NOT necessarily configured)
#   - kubectl access to management cluster

set -euo pipefail

# Load ALL existing k0rdent infrastructure
source ./etc/k0rdent-config.sh      # Loads CONFIG_YAML automatically
source ./etc/common-functions.sh     # All common functionality
source ./etc/state-management.sh     # State tracking

# Output directory and file (reuse from k0rdent)
K0SCTL_DIR="./k0sctl-config"
KUBECONFIG_FILE="$K0SCTL_DIR/${K0RDENT_PREFIX}-kubeconfig"

# Default values
AWS_PROFILE_NAME="${K0RDENT_PREFIX}-capa"
AWS_SOURCE_PROFILE="default"
AWS_REGION="us-east-1"
AWS_SECRET_NAME="aws-cluster-identity-secret"
AWS_IDENTITY_NAME="aws-cluster-identity"
KCM_CREDENTIAL_NAME="aws-cluster-credential"
KCM_NAMESPACE="kcm-system"

# Required argument
AWS_ROLE_ARN=""

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  setup      Configure k0rdent with AWS credentials
  cleanup    Remove AWS credential configuration
  status     Show AWS credential status
  help       Show this help message" \
        "  --role-arn ARN        REQUIRED: ARN of the pre-created IAM role
  --profile-name NAME   AWS CLI profile name (default: ${AWS_PROFILE_NAME})
  --source-profile NAME Source profile for role assumption (default: ${AWS_SOURCE_PROFILE})
  --region REGION       AWS region (default: ${AWS_REGION})
  --secret-name NAME    K8s secret name (default: ${AWS_SECRET_NAME})
  --identity-name NAME  AWS identity name (default: ${AWS_IDENTITY_NAME})
  --credential-name NAME KCM credential name (default: ${KCM_CREDENTIAL_NAME})
  --namespace NS        Namespace (default: ${KCM_NAMESPACE})
  -y, --yes             Skip confirmation prompts" \
        "  $0 setup --role-arn arn:aws:iam::123456789012:role/k0rdent-capa-role
  $0 status
  $0 cleanup"
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if k0rdent is installed
    if [[ "$(get_state "k0rdent_installed")" != "true" ]]; then
        print_error "k0rdent must be installed first"
        return 1
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install AWS CLI."
        echo "Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        return 1
    fi
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        print_error "jq not found. Please install jq for JSON parsing."
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
    
    # Verify role ARN format
    if [[ -n "$AWS_ROLE_ARN" ]] && ! [[ "$AWS_ROLE_ARN" =~ ^arn:aws:iam::[0-9]+:(role|user)/.+ ]]; then
        print_error "Invalid AWS role/user ARN format: $AWS_ROLE_ARN"
        return 1
    fi
    
    print_success "Prerequisites satisfied"
    return 0
}

configure_aws_cli_profile() {
    print_info "Configuring AWS CLI profile: $AWS_PROFILE_NAME"
    
    # Check if this is a user ARN (not a role)
    if [[ "$AWS_ROLE_ARN" =~ ^arn:aws:iam::[0-9]+:user/.+ ]]; then
        print_info "Detected IAM user ARN, will use direct credentials instead of role assumption"
        return 0
    fi
    
    # Configure profile for role assumption
    aws configure set role_arn "$AWS_ROLE_ARN" --profile "$AWS_PROFILE_NAME"
    aws configure set source_profile "$AWS_SOURCE_PROFILE" --profile "$AWS_PROFILE_NAME"
    aws configure set role_session_name "k0rdent-$(date +%s)" --profile "$AWS_PROFILE_NAME"
    aws configure set region "$AWS_REGION" --profile "$AWS_PROFILE_NAME"
    aws configure set output json --profile "$AWS_PROFILE_NAME"
    
    print_info "Testing role assumption..."
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE_NAME" &>/dev/null; then
        print_error "Failed to assume role. Please check:"
        echo "  1. The source profile '$AWS_SOURCE_PROFILE' has valid credentials"
        echo "  2. The source profile has permission to assume role: $AWS_ROLE_ARN"
        echo "  3. The role exists and has a trust policy allowing assumption"
        return 1
    fi
    
    print_success "AWS CLI profile configured successfully"
    return 0
}

wait_for_capa_ready() {
    print_info "Waiting for Cluster API AWS provider to be ready..."
    
    local max_attempts=60  # 5 minutes (60 * 5 seconds)
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        # Check if there are any pods with capa or aws in their name that are running
        local capa_pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep -E "(capa|aws)" | grep "Running" | wc -l | tr -d ' ')
        
        if [[ "$capa_pods" -gt 0 ]]; then
            # Check if the necessary CRDs exist
            if kubectl get crd awsclusterstaticidentities.infrastructure.cluster.x-k8s.io &>/dev/null; then
                print_success "Cluster API AWS provider is ready"
                return 0
            fi
        fi
        
        attempt=$((attempt + 1))
        if [[ $((attempt % 12)) -eq 0 ]]; then
            print_info "Still waiting for CAPA to be ready... ($((attempt * 5)) seconds elapsed)"
        fi
        sleep 5
    done
    
    print_error "Timeout waiting for Cluster API AWS provider to be ready"
    print_info "Current state:"
    kubectl get pods -A | grep -E "(capa|aws)" || echo "No CAPA/AWS pods found"
    kubectl get crd | grep aws || echo "No AWS CRDs found"
    return 1
}

get_aws_credentials() {
    print_info "Getting AWS credentials..."
    
    local access_key=""
    local secret_key=""
    local session_token=""
    local account_id=""
    
    # Check if this is a user ARN (direct credentials)
    if [[ "$AWS_ROLE_ARN" =~ ^arn:aws:iam::[0-9]+:user/.+ ]]; then
        print_info "Using direct IAM user credentials"
        
        # Check if credentials file was provided
        if [[ -f "./k0rdent-iris-provisioner_accessKeys.csv" ]]; then
            print_info "Reading credentials from k0rdent-iris-provisioner_accessKeys.csv"
            access_key=$(grep -v "Access key ID" ./k0rdent-iris-provisioner_accessKeys.csv | cut -d',' -f1)
            secret_key=$(grep -v "Access key ID" ./k0rdent-iris-provisioner_accessKeys.csv | cut -d',' -f2)
        else
            print_error "IAM user detected but no credentials file found"
            echo "Please provide credentials via:"
            echo "  1. Create ./k0rdent-iris-provisioner_accessKeys.csv with access keys, or"
            echo "  2. Configure AWS CLI with: aws configure"
            return 1
        fi
        
        # Get account ID from ARN
        account_id=$(echo "$AWS_ROLE_ARN" | cut -d':' -f5)
    else
        # Use assumed role credentials
        print_info "Getting temporary credentials from assumed role..."
        
        local assume_role_output
        assume_role_output=$(aws sts assume-role \
            --role-arn "$AWS_ROLE_ARN" \
            --role-session-name "k0rdent-setup-$(date +%s)" \
            --profile "$AWS_SOURCE_PROFILE" \
            --output json)
        
        access_key=$(echo "$assume_role_output" | jq -r '.Credentials.AccessKeyId')
        secret_key=$(echo "$assume_role_output" | jq -r '.Credentials.SecretAccessKey')
        session_token=$(echo "$assume_role_output" | jq -r '.Credentials.SessionToken')
        
        # Get account ID
        account_id=$(aws sts get-caller-identity --profile "$AWS_PROFILE_NAME" --output json | jq -r '.Account')
    fi
    
    # Save credentials to local file
    print_info "Saving AWS credentials to config/aws-credentials.yaml..."
    mkdir -p config
    cat > config/aws-credentials.yaml << EOF
# AWS credentials for k0rdent cluster deployment
# Generated on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# WARNING: This file contains sensitive credentials. Do not commit to version control.

aws:
  account_id: "$account_id"
  role_arn: "$AWS_ROLE_ARN"
  region: "$AWS_REGION"
  access_key_id: "$access_key"
  secret_access_key: "$secret_key"
  session_token: "$session_token"
EOF
    chmod 600 config/aws-credentials.yaml
    
    # Export for use in other functions
    export AWS_ACCESS_KEY_ID="$access_key"
    export AWS_SECRET_ACCESS_KEY="$secret_key"
    export AWS_SESSION_TOKEN="$session_token"
    export AWS_ACCOUNT_ID="$account_id"
    
    print_success "AWS credentials obtained and saved"
    return 0
}

verify_iam_permissions() {
    print_info "Verifying IAM permissions..."
    
    # Required CAPA policies
    local required_policies=(
        "control-plane.cluster-api-provider-aws.sigs.k8s.io"
        "controllers.cluster-api-provider-aws.sigs.k8s.io"
        "nodes.cluster-api-provider-aws.sigs.k8s.io"
        "controllers-eks.cluster-api-provider-aws.sigs.k8s.io"
    )
    
    # For IAM user, check attached user policies
    if [[ "$AWS_ROLE_ARN" =~ ^arn:aws:iam::[0-9]+:user/.+ ]]; then
        local user_name=$(echo "$AWS_ROLE_ARN" | cut -d'/' -f2)
        print_info "Checking policies for IAM user: $user_name"
        
        # Note: Verification might fail due to permissions, but we'll continue
        if ! aws iam list-attached-user-policies --user-name "$user_name" &>/dev/null; then
            print_warning "Cannot verify IAM policies (permission denied). Continuing anyway..."
            return 0
        fi
    else
        # For role, check attached role policies
        local role_name=$(echo "$AWS_ROLE_ARN" | cut -d'/' -f2)
        print_info "Checking policies for IAM role: $role_name"
        
        if ! aws iam list-attached-role-policies --role-name "$role_name" --profile "$AWS_PROFILE_NAME" &>/dev/null; then
            print_warning "Cannot verify IAM policies (permission denied). Continuing anyway..."
            return 0
        fi
    fi
    
    print_info "IAM permission verification skipped (requires additional permissions)"
    return 0
}

setup_aws_credentials() {
    print_header "Setting up AWS Credentials for k0rdent"
    
    
    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi
    
    # Check if role ARN was provided
    if [[ -z "$AWS_ROLE_ARN" ]]; then
        print_error "AWS role/user ARN is required. Use --role-arn option."
        show_usage
        return 1
    fi
    
    # Wait for CAPA to be ready
    if ! wait_for_capa_ready; then
        print_error "Cannot proceed without Cluster API AWS provider"
        return 1
    fi
    
    # Configure AWS CLI profile (if using role)
    if ! configure_aws_cli_profile; then
        return 1
    fi
    
    # Get AWS credentials
    if ! get_aws_credentials; then
        return 1
    fi
    
    # Verify IAM permissions (optional, may fail due to permissions)
    verify_iam_permissions
    
    # Create Kubernetes secret
    print_info "Creating Kubernetes secret..."
    
    # Check if secret already exists
    if kubectl get secret "$AWS_SECRET_NAME" -n "$KCM_NAMESPACE" &>/dev/null; then
        print_info "Secret already exists, updating it"
        kubectl delete secret "$AWS_SECRET_NAME" -n "$KCM_NAMESPACE"
    fi
    
    # Create secret with appropriate data based on credential type
    if [[ -n "$AWS_SESSION_TOKEN" ]]; then
        # Assumed role with session token
        kubectl create secret generic "$AWS_SECRET_NAME" \
            --from-literal=AccessKeyID="$AWS_ACCESS_KEY_ID" \
            --from-literal=SecretAccessKey="$AWS_SECRET_ACCESS_KEY" \
            --from-literal=SessionToken="$AWS_SESSION_TOKEN" \
            -n "$KCM_NAMESPACE"
    else
        # Direct IAM user credentials
        kubectl create secret generic "$AWS_SECRET_NAME" \
            --from-literal=AccessKeyID="$AWS_ACCESS_KEY_ID" \
            --from-literal=SecretAccessKey="$AWS_SECRET_ACCESS_KEY" \
            -n "$KCM_NAMESPACE"
    fi
    
    kubectl label secret "$AWS_SECRET_NAME" \
        -n "$KCM_NAMESPACE" \
        k0rdent.mirantis.com/component=kcm
    
    # Create AWSClusterStaticIdentity
    print_info "Creating AWSClusterStaticIdentity..."
    
    # Check if AWSClusterStaticIdentity already exists
    if kubectl get awsclusterstaticidentity "$AWS_IDENTITY_NAME" -n "$KCM_NAMESPACE" &>/dev/null; then
        print_info "AWSClusterStaticIdentity already exists, updating it"
        kubectl delete awsclusterstaticidentity "$AWS_IDENTITY_NAME" -n "$KCM_NAMESPACE"
    fi
    
    cat <<EOF | kubectl apply -f -
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AWSClusterStaticIdentity
metadata:
  name: $AWS_IDENTITY_NAME
  namespace: $KCM_NAMESPACE
spec:
  secretRef: $AWS_SECRET_NAME
  allowedNamespaces: {}
EOF
    
    # Create KCM Credential
    print_info "Creating KCM Credential..."
    
    if kubectl get credential "$KCM_CREDENTIAL_NAME" -n "$KCM_NAMESPACE" &>/dev/null; then
        print_info "KCM Credential already exists, updating it"
        kubectl delete credential "$KCM_CREDENTIAL_NAME" -n "$KCM_NAMESPACE"
    fi
    
    cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  name: $KCM_CREDENTIAL_NAME
  namespace: $KCM_NAMESPACE
spec:
  description: "AWS credentials for cluster deployment"
  identityRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: AWSClusterStaticIdentity
    name: $AWS_IDENTITY_NAME
    namespace: $KCM_NAMESPACE
EOF
    
    # Create AWS Resource Template ConfigMap
    print_info "Creating AWS Resource Template ConfigMap..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-cluster-identity-resource-template
  namespace: $KCM_NAMESPACE
  labels:
    k0rdent.mirantis.com/component: "kcm"
  annotations:
    projectsveltos.io/template: "true"
data:
  storageclass.yaml: |
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: gp2
      annotations:
        storageclass.kubernetes.io/is-default-class: "true"
    provisioner: kubernetes.io/aws-ebs
    parameters:
      type: gp2
      fsType: ext4
    volumeBindingMode: WaitForFirstConsumer
    allowVolumeExpansion: true
EOF
    
    # Update state
    update_state "aws_credentials_configured" "true"
    update_state "aws_account_id" "$AWS_ACCOUNT_ID"
    update_state "aws_role_arn" "$AWS_ROLE_ARN"
    update_state "aws_profile_name" "$AWS_PROFILE_NAME"
    add_event "aws_credentials_configured" "AWS credentials configured for cluster deployment"
    
    print_success "AWS credentials configured successfully!"
    print_info ""
    print_info "Next steps:"
    print_info "  1. Create a cluster deployment using the configured credentials"
    print_info "  2. Reference credential '$KCM_CREDENTIAL_NAME' in your cluster templates"
}

cleanup_aws_credentials() {
    print_header "Cleaning up AWS Credentials"
    
    # Check if configured
    if [[ "$(get_state "aws_credentials_configured")" != "true" ]]; then
        print_info "AWS credentials not configured"
        return 0
    fi
    
    # Confirm cleanup (check if SKIP_PROMPTS is set by parse_standard_args)
    if [[ "${SKIP_PROMPTS:-false}" != "true" ]]; then
        print_warning "This will remove AWS credentials and Kubernetes resources"
        if ! confirm_action "Proceed with cleanup?"; then
            print_info "Cleanup cancelled"
            return 0
        fi
    fi
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    # Remove KCM Credential
    kubectl delete credential "$KCM_CREDENTIAL_NAME" -n "$KCM_NAMESPACE" --ignore-not-found
    
    # Remove AWSClusterStaticIdentity
    kubectl delete awsclusterstaticidentity "$AWS_IDENTITY_NAME" -n "$KCM_NAMESPACE" --ignore-not-found
    
    # Remove Kubernetes secret
    kubectl delete secret "$AWS_SECRET_NAME" -n "$KCM_NAMESPACE" --ignore-not-found
    
    # Remove AWS Resource Template ConfigMap
    kubectl delete configmap aws-cluster-identity-resource-template -n "$KCM_NAMESPACE" --ignore-not-found
    
    # Remove AWS CLI profile (if not using direct user credentials)
    local profile_name=$(get_state "aws_profile_name")
    if [[ -n "$profile_name" ]] && [[ ! "$AWS_ROLE_ARN" =~ ^arn:aws:iam::[0-9]+:user/.+ ]]; then
        print_info "Removing AWS CLI profile: $profile_name"
        aws configure set role_arn "" --profile "$profile_name"
        aws configure set source_profile "" --profile "$profile_name"
        aws configure set role_session_name "" --profile "$profile_name"
    fi
    
    # Remove local credentials file
    if [[ -f "config/aws-credentials.yaml" ]]; then
        rm -f config/aws-credentials.yaml
        print_info "Removed config/aws-credentials.yaml"
    fi
    
    # Update state
    update_state "aws_credentials_configured" "false"
    # Note: We keep the aws_account_id, aws_role_arn, aws_profile_name for history
    add_event "aws_credentials_cleanup" "AWS credentials cleanup completed"
    
    print_success "AWS credentials cleanup completed!"
}

show_aws_credential_status() {
    print_header "AWS Credential Status"
    
    # Check configuration state
    local configured=$(get_state "aws_credentials_configured")
    if [[ "$configured" != "true" ]]; then
        print_info "AWS credentials not configured"
        return 0
    fi
    
    # Show configuration
    print_info "AWS Credential Information:"
    print_info "  Account ID: $(get_state "aws_account_id")"
    print_info "  Role/User ARN: $(get_state "aws_role_arn")"
    print_info "  Profile Name: $(get_state "aws_profile_name")"
    
    # Check if local credentials file exists
    if [[ -f "config/aws-credentials.yaml" ]]; then
        print_info "  Credentials file: config/aws-credentials.yaml (exists)"
    else
        print_warning "  Credentials file: config/aws-credentials.yaml (missing)"
    fi
    
    # Check Kubernetes resources if connected
    if [[ -f "$KUBECONFIG_FILE" ]]; then
        export KUBECONFIG="$KUBECONFIG_FILE"
        
        if kubectl get nodes &>/dev/null; then
            print_info ""
            print_info "Kubernetes Resources:"
            kubectl get awsclusterstaticidentity,credential,secret \
                -n "$KCM_NAMESPACE" \
                --selector=k0rdent.mirantis.com/component=kcm 2>/dev/null || true
        fi
    fi
}

# Store original arguments
ORIGINAL_ARGS=("$@")

# Parse AWS-specific options first and build filtered args for parse_standard_args
FILTERED_ARGS=()
for ((i=0; i<${#ORIGINAL_ARGS[@]}; i++)); do
    case "${ORIGINAL_ARGS[i]}" in
        --role)
            print_error "Invalid option: --role. Did you mean --role-arn?"
            show_usage
            exit 1
            ;;
        --role-arn)
            AWS_ROLE_ARN="${ORIGINAL_ARGS[i+1]:-}"
            ((i++))
            ;;
        --profile-name)
            AWS_PROFILE_NAME="${ORIGINAL_ARGS[i+1]:-}"
            ((i++))
            ;;
        --source-profile)
            AWS_SOURCE_PROFILE="${ORIGINAL_ARGS[i+1]:-}"
            ((i++))
            ;;
        --region)
            AWS_REGION="${ORIGINAL_ARGS[i+1]:-}"
            ((i++))
            ;;
        --secret-name)
            AWS_SECRET_NAME="${ORIGINAL_ARGS[i+1]:-}"
            ((i++))
            ;;
        --identity-name)
            AWS_IDENTITY_NAME="${ORIGINAL_ARGS[i+1]:-}"
            ((i++))
            ;;
        --credential-name)
            KCM_CREDENTIAL_NAME="${ORIGINAL_ARGS[i+1]:-}"
            ((i++))
            ;;
        --namespace)
            KCM_NAMESPACE="${ORIGINAL_ARGS[i+1]:-}"
            ((i++))
            ;;
        *)
            # Pass through non-AWS options to parse_standard_args
            FILTERED_ARGS+=("${ORIGINAL_ARGS[i]}")
            ;;
    esac
done

# Don't parse here - let handle_standard_commands do it
# But we need to set ORIGINAL_ARGS to FILTERED_ARGS so it doesn't see AWS options
ORIGINAL_ARGS=("${FILTERED_ARGS[@]}")


# Use consolidated command handling
handle_standard_commands "$0" "setup cleanup status help" \
    "setup" "setup_aws_credentials" \
    "cleanup" "cleanup_aws_credentials" \
    "status" "show_aws_credential_status" \
    "usage" "show_usage"