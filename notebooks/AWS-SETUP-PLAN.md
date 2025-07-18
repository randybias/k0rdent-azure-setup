# AWS Setup Script Implementation Plan

## Overview
Create an AWS equivalent of `bin/setup-azure-cluster-deployment.sh` that configures k0rdent management cluster with AWS credentials for child cluster deployment.

**Key Assumptions**: 
- NO master or root AWS credentials will be used
- IAM roles are manually created in the AWS console beforehand
- All AWS access is through IAM role assumption
- AWS CLI will be configured using `aws configure set` commands for role assumption

## Script Name
`bin/setup-aws-cluster-deployment.sh`

## Key Differences from Azure Setup

### 1. Authentication
- **Azure**: Uses Service Principal with client ID/secret created programmatically
- **AWS**: Uses IAM role assumption with pre-created roles (NO programmatic user/role creation)

### 2. AWS CLI Configuration Method
- Configure AWS CLI to assume IAM role using `aws configure set` commands:
  ```bash
  aws configure set role_arn arn:aws:iam::123456789012:role/k0rdent-capa-role
  aws configure set source_profile default
  aws configure set role_session_name k0rdent-session
  aws configure set region us-west-2
  aws configure set output json
  ```

### 3. Credential Objects
- **Azure**: Creates `AzureClusterIdentity` 
- **AWS**: Creates `AWSClusterStaticIdentity` using assumed role credentials

### 4. Required IAM Policies
- IAM role must be manually created with these CAPA policies attached:
  - `control-plane.cluster-api-provider-aws.sigs.k8s.io`
  - `controllers.cluster-api-provider-aws.sigs.k8s.io`
  - `nodes.cluster-api-provider-aws.sigs.k8s.io`
  - `controllers-eks.cluster-api-provider-aws.sigs.k8s.io`
- Script will verify these permissions exist but NOT create them

### 5. Resource Template
- **Azure**: Creates cloud-config for Azure cloud provider
- **AWS**: Creates cloud-provider-aws configuration

## Implementation Steps

### 1. Script Structure
```bash
#!/usr/bin/env bash
# Script: setup-aws-cluster-deployment.sh
# Purpose: Configure k0rdent management cluster with AWS credentials for child cluster deployment
# Usage: bash setup-aws-cluster-deployment.sh [setup|cleanup|status|help] --role-arn <ARN> [options]
# Prerequisites: 
#   - k0rdent installed
#   - IAM role manually created in AWS console with required CAPA policies
#   - AWS CLI installed (but NOT necessarily configured)
#   - kubectl access to management cluster
```

### 2. Required Command-Line Arguments
```bash
# REQUIRED arguments
--role-arn         # ARN of the pre-created IAM role (e.g., arn:aws:iam::123456789012:role/k0rdent-capa-role)

# OPTIONAL arguments with defaults
--profile-name     # AWS CLI profile name (default: "k0rdent-capa")
--source-profile   # Source profile for role assumption (default: "default")
--region          # AWS region (default: "us-east-1")
--secret-name     # K8s secret name (default: "aws-cluster-identity-secret")
--identity-name   # AWS identity name (default: "aws-cluster-identity")
--credential-name # KCM credential name (default: "aws-cluster-credential")
--namespace       # Namespace (default: "kcm-system")
```

### 3. Main Functions

#### `check_prerequisites()`
- Check k0rdent installation
- Check AWS CLI installation (but NOT authentication)
- Check kubectl connectivity
- Check for CAPA (Cluster API AWS provider) readiness
- Verify required IAM role ARN format

#### `configure_aws_cli_profile()`
- Configure AWS CLI profile for role assumption using provided arguments:
  ```bash
  aws configure set role_arn "$ROLE_ARN" --profile "$PROFILE_NAME"
  aws configure set source_profile "$SOURCE_PROFILE" --profile "$PROFILE_NAME"
  aws configure set role_session_name "k0rdent-$(date +%s)" --profile "$PROFILE_NAME"
  aws configure set region "$REGION" --profile "$PROFILE_NAME"
  aws configure set output json --profile "$PROFILE_NAME"
  ```
- Test role assumption with `aws sts get-caller-identity`
- Handle errors if source profile doesn't have AssumeRole permissions

#### `verify_iam_permissions()`
- Check if the assumed role has required CAPA policies attached
- Use `aws iam list-attached-role-policies` to verify
- Provide clear error messages with console instructions if policies are missing
- List exactly which policies are missing and how to attach them

#### `wait_for_capa_ready()`
- Wait for Cluster API AWS provider pods
- Check for AWS CRDs availability (awsclusterstaticidentities.infrastructure.cluster.x-k8s.io)
- Similar to `wait_for_capz_ready()` but for AWS

#### `setup_aws_credentials()`
1. Configure AWS CLI profile for role assumption
2. Verify IAM permissions
3. Get AWS account info using assumed role credentials
4. Extract temporary credentials from assumed role session
5. Save credentials to `config/aws-credentials.yaml`
6. Create Kubernetes secret with credentials
7. Create `AWSClusterStaticIdentity` object
8. Create KCM Credential object
9. Create AWS Resource Template ConfigMap
10. Update state management

#### `cleanup_aws_credentials()`
1. Remove KCM Credential
2. Remove AWSClusterStaticIdentity
3. Remove Kubernetes secret
4. Remove Resource Template ConfigMap
5. Remove AWS CLI profile configuration
6. Remove local credentials file
7. Update state management

#### `show_aws_credential_status()`
- Display current AWS credential configuration
- Show configured AWS CLI profile details
- Show Kubernetes resources status
- Display current role ARN and session info

### 4. AWS-Specific Helper Functions

#### `get_assumed_role_credentials()`
- Use `aws sts assume-role` to get temporary credentials
- Parse the JSON response to extract:
  - AccessKeyId
  - SecretAccessKey
  - SessionToken
- Handle expiration and refresh as needed

#### `create_aws_resource_template()`
- Create ConfigMap with AWS-specific cloud provider configuration
- Different from Azure template - focuses on AWS regions, VPCs, etc.

### 5. Resource Templates

#### Kubernetes Secret Structure
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-cluster-identity-secret
  namespace: kcm-system
type: Opaque
data:
  AccessKeyID: <base64-encoded-access-key>
  SecretAccessKey: <base64-encoded-secret-key>
  SessionToken: <base64-encoded-session-token>  # Required for assumed role
```

#### AWSClusterStaticIdentity Structure
```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AWSClusterStaticIdentity
metadata:
  name: aws-cluster-identity
  namespace: kcm-system
spec:
  secretRef: aws-cluster-identity-secret
  allowedNamespaces: {}  # Allow all namespaces
```

#### AWS Resource Template ConfigMap
- Similar to Azure but focused on AWS infrastructure
- Includes VPC, subnet, and security group configurations
- AWS-specific storage class definitions

### 6. State Management Integration
- Add AWS-specific state keys:
  - `aws_credentials_configured`
  - `aws_account_id`
  - `aws_role_arn`
  - `aws_profile_name`
- Track AWS events in state history

### 7. Error Handling

#### Role Assumption Errors
- **Missing AssumeRole permission**: Provide instructions to add trust policy
- **Expired credentials**: Automatically refresh using configured profile
- **Invalid role ARN**: Validate format and provide correction guidance

#### Missing IAM Policies
When required policies are missing, provide console instructions:
```
ERROR: Missing required IAM policies on role <role-name>

To fix this in AWS Console:
1. Go to IAM → Roles → <role-name>
2. Click "Attach policies"
3. Search for and attach:
   - control-plane.cluster-api-provider-aws.sigs.k8s.io
   - controllers.cluster-api-provider-aws.sigs.k8s.io
   - nodes.cluster-api-provider-aws.sigs.k8s.io
   - controllers-eks.cluster-api-provider-aws.sigs.k8s.io
```

#### AWS CLI Profile Issues
- Check if source profile exists
- Verify ~/.aws/credentials has valid entries
- Provide setup instructions if missing

## Dependencies

### Required Tools
- AWS CLI (`aws`) - for role assumption and API calls
- `jq` - for JSON parsing
- Standard k0rdent dependencies (kubectl, etc.)

### Required AWS Resources (Pre-created)
- IAM role with CAPA policies attached
- IAM user/role with permission to assume the CAPA role
- Valid AWS credentials in source profile

## Testing Plan

1. **Basic Setup Test**
   - Run setup with valid IAM role ARN
   - Verify AWS CLI profile configuration
   - Verify Kubernetes resources created successfully

2. **Status Test**
   - Run status command after setup
   - Verify all resources displayed correctly

3. **Cleanup Test**
   - Run cleanup command
   - Verify all resources removed

## Security Considerations

1. **Credential Storage**
   - Store temporary AWS credentials in `config/aws-credentials.yaml` with 600 permissions
   - Never commit credentials to version control
   - Use Kubernetes secrets for cluster storage
   - Session tokens expire automatically (no long-lived credentials)

2. **IAM Role Security**
   - No programmatic role/user creation (manual only)
   - Roles must be pre-configured with least-privilege CAPA policies
   - Trust relationships must be explicitly configured

3. **Credential Lifecycle**
   - Assumed role credentials are temporary (typically 1 hour)
   - Script should handle credential refresh transparently
   - No permanent access keys stored anywhere

## Integration Points

1. **Common Functions**
   - Reuse all existing common functions from `common-functions.sh`
   - Add minimal AWS-specific validation functions

2. **State Management**
   - Integrate with existing `state-management.sh`
   - Add AWS-specific state keys using existing functions

3. **Configuration**
   - Follow existing k0rdent configuration patterns
   - No separate AWS config file - use command-line args

## Implementation Notes

### Key Differences from Azure Script
1. **No Service Principal Creation**: Azure script creates SP programmatically; AWS requires pre-created role
2. **Credential Type**: Azure uses permanent client_id/secret; AWS uses temporary assumed role credentials
3. **Configuration Method**: Azure uses `az ad sp create-for-rbac`; AWS uses `aws configure set` commands
4. **Cleanup**: Azure deletes SP; AWS only removes local config and k8s resources

### Script Flow
1. Parse command-line arguments (role ARN is required)
2. Configure AWS CLI profile for role assumption
3. Test role assumption and verify permissions
4. Extract temporary credentials from assumed role
5. Create k0rdent/CAPA Kubernetes resources
6. Save state for tracking

### Console Instructions Template
When manual intervention is needed, provide clear AWS Console instructions:
- IAM role creation steps
- Policy attachment procedures
- Trust relationship configuration
- Troubleshooting common issues