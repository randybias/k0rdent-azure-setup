#!/usr/bin/env bash

# Script: install-k0s.sh
# Purpose: Generate k0sctl configuration and deploy k0s cluster on Azure VMs
# Usage: bash install-k0s.sh [deploy|reset|uninstall]
# Prerequisites: WireGuard VPN connected, SSH keys, and Azure VMs deployed

set -euo pipefail

# Load central configuration and common functions
source ./k0rdent-config.sh
source ./common-functions.sh

# Output directory and file
K0SCTL_DIR="./k0sctl-config"
K0SCTL_FILE="$K0SCTL_DIR/${K0RDENT_PREFIX}-k0sctl.yaml"
KUBECONFIG_FILE="$K0SCTL_DIR/${K0RDENT_PREFIX}-kubeconfig"

# Handle command line arguments
COMMAND="${1:-}"

if [[ "$COMMAND" == "uninstall" ]]; then
    print_info "Resetting k0s cluster..."
    
    if [[ -f "$K0SCTL_FILE" ]]; then
        print_info "Running k0sctl reset to destroy cluster..."
        k0sctl reset --config "$K0SCTL_FILE" --force || true
        print_success "k0s cluster reset completed"
    else
        print_warning "No k0sctl config found, skipping cluster reset"
    fi
    
    print_success "k0s cluster uninstall completed"
    exit
fi

if [[ "$COMMAND" == "reset" ]]; then
    print_info "Removing k0sctl configuration and kubeconfig..."
    rm -rf "$K0SCTL_DIR"
    print_success "k0sctl configuration and kubeconfig removed"
    exit
fi

print_header "k0s Cluster Installation"

# Validate prerequisites
print_info "Validating prerequisites..."

# Check for k0sctl
if ! command -v k0sctl &> /dev/null; then
    print_error "k0sctl is not installed. Please install it first."
    echo "Visit: https://docs.k0sproject.io/stable/k0sctl-install/"
    exit 1
fi

if ! check_file_exists "$WG_MANIFEST" "WireGuard key manifest"; then
    print_error "WireGuard keys not found. Run: ./generate-wg-keys.sh"
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

# Create output directory
ensure_directory "$K0SCTL_DIR"

# Check if k0sctl file already exists
if [[ -f "$K0SCTL_FILE" ]]; then
    print_info "k0sctl configuration already exists: $K0SCTL_FILE"
else
    # Generate k0sctl YAML
    print_info "Generating ${K0RDENT_PREFIX}-k0sctl.yaml configuration file..."

cat > "$K0SCTL_FILE" << EOF
apiVersion: k0sctl.k0sproject.io/v1beta1
kind: Cluster
metadata:
  name: $K0RDENT_PREFIX
spec:
  hosts:
EOF

# Add controller nodes
print_info "Adding controller nodes to configuration..."
for host in k0rdcp1 k0rdcp2 k0rdcp3; do
    wg_ip="${WG_IPS[$host]}"
    cat >> "$K0SCTL_FILE" << EOF
    - ssh:
        address: $wg_ip
        user: $ADMIN_USER
        keyPath: $SSH_KEY_PATH
      role: controller+worker
EOF
done

# Add worker nodes
print_info "Adding worker nodes to configuration..."
for host in k0rdwood1 k0rdwood2; do
    wg_ip="${WG_IPS[$host]}"
    cat >> "$K0SCTL_FILE" << EOF
    - ssh:
        address: $wg_ip
        user: $ADMIN_USER
        keyPath: $SSH_KEY_PATH
      role: worker
EOF
done

# Add k0s configuration
cat >> "$K0SCTL_FILE" << EOF
  k0s:
    version: v1.33.1+k0s.0
    dynamicConfig: false
    config:
      spec:
        network:
          provider: calico
EOF

    print_success "k0sctl configuration generated: $K0SCTL_FILE"
fi

# Display summary
print_header "Configuration Summary"
echo "Cluster Name: $K0RDENT_PREFIX"
echo "SSH User: $ADMIN_USER"
echo "SSH Key: $SSH_KEY_PATH"
echo ""
echo "Controller Nodes:"
for host in k0rdcp1 k0rdcp2 k0rdcp3; do
    echo "  - $host: ${WG_IPS[$host]}"
done
echo ""
echo "Worker Nodes:"
for host in k0rdwood1 k0rdwood2; do
    echo "  - $host: ${WG_IPS[$host]}"
done

# Deploy k0s if requested
if [[ "$COMMAND" == "deploy" ]]; then
    print_header "Testing SSH Connectivity"
    
    # Test SSH connectivity to all nodes
    ALL_SSH_OK=true
    for host in k0rdcp1 k0rdcp2 k0rdcp3 k0rdwood1 k0rdwood2; do
        wg_ip="${WG_IPS[$host]}"
        print_info "Testing SSH to $host ($wg_ip)..."
        
        if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USER@$wg_ip" "echo 'SSH OK'" &>/dev/null; then
            print_success "SSH connectivity to $host: OK"
        else
            print_error "SSH connectivity to $host: FAILED"
            ALL_SSH_OK=false
        fi
    done
    
    if [[ "$ALL_SSH_OK" != "true" ]]; then
        print_error "SSH connectivity test failed. Ensure WireGuard VPN is connected and all VMs are running."
        exit 1
    fi
    
    print_header "Preparing SSH Known Hosts"
    
    # Remove SSH host keys from known_hosts to avoid conflicts
    print_info "Cleaning SSH known_hosts entries for cluster nodes..."
    for host in k0rdcp1 k0rdcp2 k0rdcp3 k0rdwood1 k0rdwood2; do
        wg_ip="${WG_IPS[$host]}"
        ssh-keygen -R "$wg_ip" 2>/dev/null || true
        print_info "Removed known_hosts entry for $wg_ip"
    done
    
    print_header "Deploying k0s Cluster"
    
    print_info "Running k0sctl apply to deploy k0s cluster..."
    if k0sctl apply --config "$K0SCTL_FILE"; then
        print_success "k0s cluster deployed successfully!"
        
        print_header "Retrieving Kubeconfig"
        
        print_info "Waiting for API server to be fully ready..."
        sleep 60
        
        print_info "Getting kubeconfig from cluster..."
        KUBECONFIG_SUCCESS=false
        for i in {1..3}; do
            print_info "Attempting to retrieve kubeconfig (attempt $i/3)..."
            if k0sctl kubeconfig --config "$K0SCTL_FILE" > kubeconfig.tmp; then
                if grep -q "contexts:" kubeconfig.tmp && ! grep -q "contexts: \[\]" kubeconfig.tmp; then
                    mv kubeconfig.tmp "$KUBECONFIG_FILE"
                    print_success "Kubeconfig saved to: $KUBECONFIG_FILE"
                    KUBECONFIG_SUCCESS=true
                    break
                else
                    print_warning "Kubeconfig incomplete (missing contexts), retrying in 30 seconds..."
                    rm -f kubeconfig.tmp
                    sleep 30
                fi
            else
                print_warning "Failed to retrieve kubeconfig, retrying in 30 seconds..."
                rm -f kubeconfig.tmp
                sleep 30
            fi
        done
        
        if [[ "$KUBECONFIG_SUCCESS" == "true" ]]; then
            print_header "Cluster Access"
            echo "Export kubeconfig to access your cluster:"
            echo "  export KUBECONFIG=\$PWD/$KUBECONFIG_FILE"
            echo ""
            echo "Test cluster access:"
            echo "  kubectl get nodes"
            echo "  kubectl get pods -A"
        else
            print_error "Failed to retrieve valid kubeconfig after 3 attempts"
            print_info "You can manually retrieve it later with:"
            print_info "  k0sctl kubeconfig --config $K0SCTL_FILE > $KUBECONFIG_FILE"
            exit 1
        fi
    else
        print_error "k0s cluster deployment failed"
        exit 1
    fi
else
    print_header "Next Steps"
    echo "1. Ensure WireGuard VPN is connected to access the cluster nodes"
    echo "2. Deploy k0s cluster:"
    echo "   ./install-k0s.sh deploy"
    echo ""
    echo "Or manually:"
    echo "3. Verify SSH connectivity to all nodes:"
    echo "   ssh -i $SSH_KEY_PATH $ADMIN_USER@172.24.24.11  # k0rdcp1"
    echo ""
    echo "4. Deploy k0s using k0sctl:"
    echo "   k0sctl apply --config $K0SCTL_FILE"
    echo ""
    echo "5. Get kubeconfig after deployment:"
    echo "   k0sctl kubeconfig --config $K0SCTL_FILE > $KUBECONFIG_FILE"
    echo "   export KUBECONFIG=\$PWD/$KUBECONFIG_FILE"
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
        deploy_k0s
        ;;
    "uninstall")
        uninstall_k0s
        ;;
    "reset")
        reset_k0s
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