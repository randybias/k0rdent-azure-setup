#!/usr/bin/env bash

# Script: check-prerequisites.sh
# Purpose: Centralized prerequisite checking for k0rdent deployment
# Usage: ./bin/check-prerequisites.sh

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source common functions for print utilities
source "$PROJECT_ROOT/etc/common-functions.sh"

# Track if all checks pass
ALL_CHECKS_PASSED=true

# Function to check bash version
check_bash_version() {
    local required_major=5
    local required_minor=0
    
    print_info "Checking Bash version..."
    
    # Get bash version
    local bash_version="${BASH_VERSION}"
    local major_version="${bash_version%%.*}"
    local minor_version="${bash_version#*.}"
    minor_version="${minor_version%%.*}"
    
    if [[ "$major_version" -lt "$required_major" ]]; then
        print_error "Bash version $required_major.$required_minor or higher is required (found: $bash_version)"
        print_info "To upgrade Bash:"
        print_info "  macOS: brew install bash"
        print_info "  Ubuntu/Debian: sudo apt update && sudo apt install bash"
        print_info "  CentOS/RHEL: sudo yum install bash"
        ALL_CHECKS_PASSED=false
    else
        print_success "Bash version: $bash_version ✓"
    fi
}

# Function to check for yq
check_yq() {
    print_info "Checking for yq..."
    
    if ! command -v yq &> /dev/null; then
        print_error "yq is not installed (required for YAML processing)"
        print_info "To install yq:"
        print_info "  macOS: brew install yq"
        print_info "  Linux: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq"
        print_info "  Snap: sudo snap install yq"
        ALL_CHECKS_PASSED=false
    else
        local yq_version=$(yq --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        print_success "yq version: $yq_version ✓"
    fi
}

# Function to check for jq
check_jq() {
    print_info "Checking for jq..."
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed (required for JSON processing)"
        print_info "To install jq:"
        print_info "  macOS: brew install jq"
        print_info "  Ubuntu/Debian: sudo apt install jq"
        print_info "  CentOS/RHEL: sudo yum install jq"
        ALL_CHECKS_PASSED=false
    else
        local jq_version=$(jq --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        print_success "jq version: $jq_version ✓"
    fi
}

# Function to check for Azure CLI
check_azure_cli() {
    print_info "Checking for Azure CLI..."
    
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed"
        print_info "To install Azure CLI:"
        print_info "  macOS: brew install azure-cli"
        print_info "  Linux: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
        print_info "  See: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        ALL_CHECKS_PASSED=false
    else
        local az_version=$(az --version 2>&1 | grep -oE 'azure-cli[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}')
        print_success "Azure CLI version: $az_version ✓"
        
        # Check if logged in
        if ! az account show &>/dev/null; then
            print_error "Azure CLI is installed but not logged in"
            print_info "Run: az login"
            ALL_CHECKS_PASSED=false
        else
            local account_name=$(az account show --query name -o tsv 2>/dev/null || echo "Unknown")
            print_success "Azure account: $account_name ✓"
        fi
    fi
}

# Function to check for WireGuard tools
check_wireguard_tools() {
    print_info "Checking for WireGuard tools..."
    
    local missing_tools=()
    
    if ! command -v wg &> /dev/null; then
        missing_tools+=("wg")
    fi
    
    if ! command -v wg-quick &> /dev/null; then
        missing_tools+=("wg-quick")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "WireGuard tools missing: ${missing_tools[*]}"
        print_info "To install WireGuard:"
        print_info "  macOS: brew install wireguard-tools"
        print_info "  Ubuntu/Debian: sudo apt install wireguard"
        print_info "  CentOS/RHEL: sudo yum install wireguard-tools"
        ALL_CHECKS_PASSED=false
    else
        print_success "WireGuard tools: wg, wg-quick ✓"
    fi
}

# Function to check for k0sctl
check_k0sctl() {
    print_info "Checking for k0sctl..."
    
    if ! command -v k0sctl &> /dev/null; then
        print_error "k0sctl is not installed"
        print_info "To install k0sctl:"
        print_info "  Download latest release:"
        print_info "  curl -sSLf https://github.com/k0sproject/k0sctl/releases/latest/download/k0sctl-\$(uname -s)-\$(uname -m) -o k0sctl"
        print_info "  chmod +x k0sctl"
        print_info "  sudo mv k0sctl /usr/local/bin/"
        ALL_CHECKS_PASSED=false
    else
        local k0sctl_version=$(k0sctl version 2>&1 | grep -oE 'version: v[0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}')
        print_success "k0sctl version: $k0sctl_version ✓"
    fi
}

# Function to check for netcat
check_netcat() {
    print_info "Checking for netcat (nc)..."
    
    if ! command -v nc &> /dev/null; then
        print_error "netcat (nc) is not installed"
        print_info "To install netcat:"
        print_info "  macOS: brew install netcat"
        print_info "  Ubuntu/Debian: sudo apt install netcat"
        print_info "  CentOS/RHEL: sudo yum install nc"
        ALL_CHECKS_PASSED=false
    else
        print_success "netcat (nc) ✓"
    fi
}

# Function to check for SSH client
check_ssh() {
    print_info "Checking for SSH client..."
    
    if ! command -v ssh &> /dev/null; then
        print_error "SSH client is not installed"
        print_info "SSH is typically pre-installed on most systems"
        print_info "  macOS: Pre-installed"
        print_info "  Ubuntu/Debian: sudo apt install openssh-client"
        print_info "  CentOS/RHEL: sudo yum install openssh-clients"
        ALL_CHECKS_PASSED=false
    else
        print_success "SSH client ✓"
    fi
    
    # Also check ssh-keygen
    if ! command -v ssh-keygen &> /dev/null; then
        print_error "ssh-keygen is not installed"
        print_info "Install openssh-client package for ssh-keygen"
        ALL_CHECKS_PASSED=false
    else
        print_success "ssh-keygen ✓"
    fi
}

# Function to check for curl
check_curl() {
    print_info "Checking for curl..."
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed"
        print_info "To install curl:"
        print_info "  macOS: brew install curl"
        print_info "  Ubuntu/Debian: sudo apt install curl"
        print_info "  CentOS/RHEL: sudo yum install curl"
        ALL_CHECKS_PASSED=false
    else
        local curl_version=$(curl --version 2>&1 | head -1 | awk '{print $2}')
        print_success "curl version: $curl_version ✓"
    fi
}

# Function to check for base64
check_base64() {
    print_info "Checking for base64..."
    
    if ! command -v base64 &> /dev/null; then
        print_error "base64 is not installed"
        print_info "base64 is typically part of coreutils"
        print_info "  macOS: Pre-installed"
        print_info "  Ubuntu/Debian: sudo apt install coreutils"
        print_info "  CentOS/RHEL: sudo yum install coreutils"
        ALL_CHECKS_PASSED=false
    else
        print_success "base64 ✓"
    fi
}

# Function to check for kubectl (required for k0rdent)
check_kubectl() {
    print_info "Checking for kubectl..."
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed (required for k0rdent deployment)"
        print_info "To install kubectl:"
        print_info "  macOS: brew install kubectl"
        print_info "  Linux: See https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
        ALL_CHECKS_PASSED=false
    else
        local kubectl_version=$(kubectl version --client --short 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        print_success "kubectl version: $kubectl_version ✓"
    fi
}

# Function to check for helm (required for k0rdent)
check_helm() {
    print_info "Checking for helm..."
    
    if ! command -v helm &> /dev/null; then
        print_error "helm is not installed (required for k0rdent deployment)"
        print_info "To install helm:"
        print_info "  macOS: brew install helm"
        print_info "  Linux: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
        ALL_CHECKS_PASSED=false
    else
        local helm_version=$(helm version --short 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        print_success "helm version: $helm_version ✓"
    fi
}

# Function to check for git
check_git() {
    print_info "Checking for git..."
    
    if ! command -v git &> /dev/null; then
        print_error "git is not installed"
        print_info "To install git:"
        print_info "  macOS: brew install git"
        print_info "  Ubuntu/Debian: sudo apt install git"
        print_info "  CentOS/RHEL: sudo yum install git"
        ALL_CHECKS_PASSED=false
    else
        local git_version=$(git --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        print_success "git version: $git_version ✓"
    fi
}

# Function to check for common utilities
check_common_utils() {
    print_info "Checking for common utilities..."
    
    local missing_utils=()
    
    # Check timeout (part of coreutils)
    if ! command -v timeout &> /dev/null; then
        missing_utils+=("timeout")
    fi
    
    # Check mktemp
    if ! command -v mktemp &> /dev/null; then
        missing_utils+=("mktemp")
    fi
    
    # Check stat
    if ! command -v stat &> /dev/null; then
        missing_utils+=("stat")
    fi
    
    # Check ping
    if ! command -v ping &> /dev/null; then
        missing_utils+=("ping")
    fi
    
    # Check platform-specific network tools
    if [[ "$(uname)" == "Darwin" ]]; then
        if ! command -v ifconfig &> /dev/null; then
            missing_utils+=("ifconfig")
        fi
    else
        if ! command -v ip &> /dev/null; then
            missing_utils+=("ip")
        fi
    fi
    
    if [[ ${#missing_utils[@]} -gt 0 ]]; then
        print_error "Missing common utilities: ${missing_utils[*]}"
        print_info "To install missing utilities:"
        print_info "  macOS: brew install coreutils"
        print_info "  Ubuntu/Debian: sudo apt install coreutils iproute2 iputils-ping"
        print_info "  CentOS/RHEL: sudo yum install coreutils iproute iputils"
        ALL_CHECKS_PASSED=false
    else
        print_success "Common utilities ✓ (timeout, mktemp, stat, ping, network tools)"
    fi
}

# Function to check system requirements
check_system_requirements() {
    print_info "Checking system requirements..."
    
    # Check OS
    local os_type="$(uname -s)"
    case "$os_type" in
        Darwin)
            print_success "Operating System: macOS ✓"
            ;;
        Linux)
            print_success "Operating System: Linux ✓"
            ;;
        *)
            print_error "Unsupported operating system: $os_type"
            print_info "Supported systems: macOS, Linux"
            ALL_CHECKS_PASSED=false
            ;;
    esac
    
    # Check available disk space (at least 5GB recommended)
    local available_space_gb
    if [[ "$os_type" == "Darwin" ]]; then
        available_space_gb=$(df -g . | awk 'NR==2 {print $4}')
    else
        available_space_gb=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    fi
    
    if [[ "$available_space_gb" -lt 5 ]]; then
        print_warning "Low disk space: ${available_space_gb}GB available (5GB recommended)"
    else
        print_success "Disk space: ${available_space_gb}GB available ✓"
    fi
}

# Main function
main() {
    print_header "k0rdent Azure Setup - Prerequisites Check"
    echo
    
    # Run all checks
    check_bash_version
    echo
    
    check_system_requirements
    echo
    
    print_header "Required Tools"
    check_ssh
    check_curl
    check_base64
    check_yq
    check_jq
    check_git
    check_azure_cli
    check_wireguard_tools
    check_k0sctl
    check_kubectl
    check_helm
    check_netcat
    check_common_utils
    echo
    
    # Summary
    print_header "Summary"
    if [[ "$ALL_CHECKS_PASSED" == "true" ]]; then
        print_success "All required prerequisites are satisfied! ✓"
        print_info "You can proceed with deployment using:"
        print_info "  ./deploy-k0rdent.sh deploy"
        return 0
    else
        print_error "Some prerequisites are missing. Please install the required tools and try again."
        print_info "After installing missing tools, run this check again:"
        print_info "  ./bin/check-prerequisites.sh"
        return 1
    fi
}

# Run main function
main "$@"