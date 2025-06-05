#!/usr/bin/env bash

# Script: install-k0rdent.sh
# Purpose: Install k0rdent on an existing k0s cluster
# Usage: bash install-k0rdent.sh [deploy|uninstall]
# Prerequisites: k0s cluster deployed with kubeconfig available

set -euo pipefail

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh

# Output directory and file
K0SCTL_DIR="./k0sctl-config"
KUBECONFIG_FILE="$K0SCTL_DIR/${K0RDENT_PREFIX}-kubeconfig"

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  deploy     Install k0rdent on existing k0s cluster
  uninstall  Remove k0rdent from cluster
  status     Show k0rdent installation status
  help       Show this help message" \
        "  -y, --yes        Skip confirmation prompts
  --no-wait        Skip waiting for resources" \
        "  $0 deploy        # Install k0rdent
  $0 status        # Check installation status
  $0 uninstall     # Remove k0rdent"
}

uninstall_k0rdent() {
    print_info "Uninstalling k0rdent from cluster..."
    
    # Find SSH private key
    SSH_KEY_PATH=$(find ./azure-resources -name "${K0RDENT_PREFIX}-ssh-key" -type f 2>/dev/null | head -1)
    
    if [[ -n "$SSH_KEY_PATH" ]]; then
        # Get the first controller IP
        CONTROLLER_IP="${WG_IPS[k0s-controller]}"
        
        print_info "Uninstalling k0rdent using Helm..."
        if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$CONTROLLER_IP" "helm uninstall kcm -n kcm-system" &>/dev/null; then
            print_success "k0rdent uninstalled successfully"
        else
            print_warning "Failed to uninstall k0rdent (it may not be installed)"
        fi
    else
        print_warning "SSH key not found, cannot uninstall k0rdent"
    fi
    
    print_success "k0rdent uninstall completed"
}

deploy_k0rdent() {

print_header "k0rdent Installation"

# Validate prerequisites
print_info "Validating prerequisites..."

# Check for kubeconfig
if ! check_file_exists "$KUBECONFIG_FILE" "Kubeconfig file"; then
    print_error "Kubeconfig not found. Run: ./install-k0s.sh deploy"
    exit 1
fi

# Find SSH private key
SSH_KEY_PATH=$(find ./azure-resources -name "${K0RDENT_PREFIX}-ssh-key" -type f 2>/dev/null | head -1)
if [[ -z "$SSH_KEY_PATH" ]]; then
    print_error "SSH private key not found. Expected: ./azure-resources/${K0RDENT_PREFIX}-ssh-key"
    print_info "Run: ./setup-azure-network.sh"
    exit 1
fi

print_success "Prerequisites validated"

# Deploy k0rdent if requested
if [[ "$COMMAND" == "deploy" ]]; then
    print_header "Installing k0rdent on Cluster"
    
    # Get the first controller IP
    CONTROLLER_IP="${WG_IPS[k0s-controller]}"
    
    print_info "Testing SSH connectivity to controller node..."
    if ! ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$CONTROLLER_IP" "echo 'SSH OK'" &>/dev/null; then
        print_error "Cannot connect to controller node. Ensure WireGuard VPN is connected."
        exit 1
    fi
    
    print_info "Installing Helm on controller node k0s-controller..."
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$CONTROLLER_IP" "command -v helm &>/dev/null"; then
        print_success "Helm already installed"
    else
        print_info "Installing Helm..."
        ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$CONTROLLER_IP" "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash" &>/dev/null
        if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$CONTROLLER_IP" "command -v helm &>/dev/null"; then
            print_success "Helm installed successfully"
        else
            print_error "Failed to install Helm"
            exit 1
        fi
    fi
    
    print_info "Setting up kubeconfig on controller node..."
    ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$CONTROLLER_IP" "mkdir -p ~/.kube && sudo k0s kubeconfig admin > ~/.kube/config" &>/dev/null
    
    print_info "Installing k0rdent v1.0.0 using Helm..."
    
    # Capture helm install output to a log file
    local helm_log="./logs/k0rdent-helm-install-$(date +%Y%m%d_%H%M%S).log"
    ensure_directory "./logs"
    
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$CONTROLLER_IP" "helm install kcm oci://ghcr.io/k0rdent/kcm/charts/kcm --version 1.0.0 -n kcm-system --create-namespace --debug --timeout 10m" > "$helm_log" 2>&1; then
        print_success "k0rdent installed successfully!"
        print_info "Installation log saved to: $helm_log"
        
        print_info "Waiting for k0rdent components to be ready..."
        sleep 30
        
        print_info "Checking k0rdent pod status..."
        ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$CONTROLLER_IP" "sudo k0s kubectl get pods -n kcm-system"
        
        print_success "k0rdent installation completed!"
    else
        print_error "Failed to install k0rdent"
        print_info "Check the installation log for details: $helm_log"
        exit 1
    fi
else
    print_header "Next Steps"
    echo "1. Ensure k0s cluster is deployed and accessible"
    echo "2. Ensure WireGuard VPN is connected"
    echo "3. Install k0rdent:"
    echo "   ./install-k0rdent.sh deploy"
    echo ""
    echo "To uninstall k0rdent:"
    echo "   ./install-k0rdent.sh uninstall"
fi
}

show_status() {
    print_header "k0rdent Installation Status"
    
    # Find SSH private key
    SSH_KEY_PATH=$(find ./azure-resources -name "${K0RDENT_PREFIX}-ssh-key" -type f 2>/dev/null | head -1)
    
    if [[ -n "$SSH_KEY_PATH" ]]; then
        # Get the first controller IP
        CONTROLLER_IP="${WG_IPS[k0s-controller]}"
        
        print_info "Checking k0rdent installation status..."
        if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$CONTROLLER_IP" "helm list -n kcm-system | grep -q kcm" &>/dev/null; then
            print_success "k0rdent is installed"
            ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$CONTROLLER_IP" "helm list -n kcm-system"
        else
            print_info "k0rdent is not installed"
        fi
    else
        print_warning "SSH key not found, cannot check k0rdent status"
    fi
}

# Default values
SKIP_PROMPTS=false
NO_WAIT=false

# Parse standard arguments
PARSED_ARGS=$(parse_standard_args "$@")
eval "$PARSED_ARGS"

# Get command from positional arguments
COMMAND="${POSITIONAL_ARGS[0]:-}"

# Check for help flag
if [[ "$SHOW_HELP" == "true" ]]; then
    show_usage
    exit 0
fi

# Check command support
SUPPORTED_COMMANDS="deploy uninstall status help"
if [[ -z "$COMMAND" ]]; then
    show_usage
    exit 1
fi

# Execute command
case "$COMMAND" in
    "deploy")
        deploy_k0rdent
        ;;
    "uninstall")
        uninstall_k0rdent
        ;;
    "status")
        show_status
        ;;
    "help")
        show_usage
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac
