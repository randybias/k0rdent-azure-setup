#!/usr/bin/env bash

# Script: install-k0rdent.sh
# Purpose: Install k0rdent on an existing k0s cluster
# Usage: bash install-k0rdent.sh [deploy|uninstall]
# Prerequisites: k0s cluster deployed with kubeconfig available

set -euo pipefail

# Load central configuration and common functions
source ./k0rdent-config.sh
source ./common-functions.sh

# Output directory and file
K0SCTL_DIR="./k0sctl-config"
KUBECONFIG_FILE="$K0SCTL_DIR/${K0RDENT_PREFIX}-kubeconfig"

# Handle command line arguments
COMMAND="${1:-}"

if [[ "$COMMAND" == "uninstall" ]]; then
    print_info "Uninstalling k0rdent from cluster..."
    
    # Find SSH private key
    SSH_KEY_PATH=$(find ./azure-resources -name "${K0RDENT_PREFIX}-ssh-key" -type f 2>/dev/null | head -1)
    
    if [[ -n "$SSH_KEY_PATH" ]]; then
        # Get the first controller IP
        CONTROLLER_IP="${WG_IPS[k0rdcp1]}"
        
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
    exit
fi

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
    CONTROLLER_IP="${WG_IPS[k0rdcp1]}"
    
    print_info "Testing SSH connectivity to controller node..."
    if ! ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$CONTROLLER_IP" "echo 'SSH OK'" &>/dev/null; then
        print_error "Cannot connect to controller node. Ensure WireGuard VPN is connected."
        exit 1
    fi
    
    print_info "Installing Helm on controller node k0rdcp1..."
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
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$CONTROLLER_IP" "helm install kcm oci://ghcr.io/k0rdent/kcm/charts/kcm --version 1.0.0 -n kcm-system --create-namespace" &>/dev/null; then
        print_success "k0rdent installed successfully!"
        
        print_info "Waiting for k0rdent components to be ready..."
        sleep 30
        
        print_info "Checking k0rdent pod status..."
        ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$CONTROLLER_IP" "sudo k0s kubectl get pods -n kcm-system"
        
        print_success "k0rdent installation completed!"
        
        print_header "Next Steps"
        echo "Export kubeconfig to access your cluster:"
        echo "  export KUBECONFIG=\$PWD/$KUBECONFIG_FILE"
        echo ""
        echo "Check k0rdent status:"
        echo "  kubectl get pods -n kcm-system"
        echo ""
        echo "Access k0rdent UI:"
        echo "  kubectl port-forward -n kcm-system svc/kcm-server 9443:443"
        echo "  Then open: https://localhost:9443"
    else
        print_error "Failed to install k0rdent"
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

# Parse arguments
parse_common_args "$@" || parse_result=$?

if [[ $parse_result -eq 1 ]]; then
    # Help was requested
    show_usage
    exit 0
elif [[ $parse_result -eq 2 ]]; then
    # Invalid argument
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