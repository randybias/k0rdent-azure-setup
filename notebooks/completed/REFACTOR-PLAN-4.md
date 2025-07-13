# Enhancement Plan: SSH Lockdown and WireGuard Connection Management

**Date**: December 5, 2024  
**Status**: Planning Phase  
**Priority**: Medium  

## Overview

This plan outlines two key enhancements to improve security and user experience:
1. Optional SSH lockdown after deployment completion
2. Separation of WireGuard setup and connection operations

---

## Part 1: Optional SSH Lockdown Step

### Objective
After deployment is complete and WireGuard VPN is working, optionally disable SSH access from the internet by removing/modifying Azure NSG rules.

### Implementation Strategy

#### New Standalone Script
```bash
./bin/lockdown-ssh.sh           # Remove SSH port 22 from Azure NSG
./bin/lockdown-ssh.sh unlock    # Restore SSH port 22 to Azure NSG
```

#### Core Features

1. **Simple NSG Management**:
   - Remove SSH (port 22) access from 0.0.0.0/0 in Azure NSG
   - Keep all other ports unchanged (including WireGuard port)
   - Store original NSG rule for restoration

2. **Minimal Validation**:
   - Verify Azure CLI authentication
   - Check that resource group and NSG exist
   - Require confirmation unless using `-y` flag

#### Implementation Files

- **bin/lockdown-ssh.sh**: New standalone script for SSH port management

#### Workflow
```bash
# After successful deployment (optional, advanced users only)
./bin/lockdown-ssh.sh           # Remove internet SSH access

# To restore access if needed
./bin/lockdown-ssh.sh unlock    # Restore internet SSH access
```

---

## Part 2: Separate WireGuard Setup and Connect Operations

### Current Issue
The `connect` command does both setup (config generation/import) and connection in one step, making it difficult for users to quickly connect/disconnect the VPN.

### Script Renaming

**Current**: `bin/connect-laptop-wireguard.sh`  
**New**: `bin/connect-vpn.sh`

**Rationale**: Shorter, more intuitive name that focuses on the action (connecting to VPN) rather than the implementation details (laptop + WireGuard).

### New Command Structure

```bash
# Setup phase (one-time)
./bin/connect-vpn.sh setup     # Generate and setup config
./bin/connect-vpn.sh setup -y  # Non-interactive setup

# Connection management (repeatable)
./bin/connect-vpn.sh connect   # Connect to VPN
./bin/connect-vpn.sh disconnect # Disconnect from VPN

# Utilities (existing)
./bin/connect-vpn.sh status    # Show status
./bin/connect-vpn.sh test      # Test connectivity
./bin/connect-vpn.sh cleanup   # Clean up orphaned interfaces
```

### Implementation Details

#### Setup Command
- **Purpose**: One-time configuration and preparation
- **Actions**:
  - Validates prerequisites (config file exists)
  - Handles GUI import OR CLI setup (wg-quick configuration)
  - Creates persistent connection capability
  - Does NOT automatically connect
  - Stores setup completion marker
- **Output**: Ready-to-connect configuration

#### Connect Command
- **Purpose**: Fast VPN activation
- **Actions**:
  - Validates setup is complete
  - Simply activates existing WireGuard configuration
  - Uses `sudo wg-quick up <config>` or activates GUI tunnel
- **Performance**: Fast operation (no lengthy setup)

#### Disconnect Command
- **Purpose**: VPN deactivation while preserving config
- **Actions**:
  - Uses improved shutdown logic from recent macOS enhancements
  - Preserves configuration for reconnection
  - Uses `sudo wg-quick down <config>` or deactivates GUI tunnel

### State Management

#### Setup Tracking
```bash
# Setup completion marker
./laptop-wg-config/.setup-complete

# Contents track setup method
echo "gui" > ./laptop-wg-config/.setup-complete     # GUI setup
echo "cli" > ./laptop-wg-config/.setup-complete     # CLI setup
```

#### Connection State
- Use existing `/var/run/wireguard/` detection on macOS
- Use `wg show` command on Linux
- No persistent state files needed

### Integration with deploy-k0rdent.sh

#### Current Flow
```bash
Step 5: Generate laptop WireGuard configuration
Step 6: Connect to WireGuard VPN  # Does setup + connect
Step 7: Install k0s cluster
Step 8: Install k0rdent
```

#### New Flow
```bash
Step 5: Generate laptop WireGuard configuration
Step 6: Setup WireGuard VPN       # One-time setup only
Step 7: Connect to WireGuard VPN   # Simple connection
Step 8: Install k0s cluster
Step 9: Install k0rdent
```

**Note**: All references to `bin/connect-laptop-wireguard.sh` in `deploy-k0rdent.sh` will be updated to use `bin/connect-vpn.sh`.

### Backwards Compatibility

#### Deployment Integration
The deploy script will run both commands in sequence:
```bash
# In deploy-k0rdent.sh
Step 6: bash bin/connect-vpn.sh setup $DEPLOY_FLAGS
Step 7: bash bin/connect-vpn.sh connect $DEPLOY_FLAGS
```

#### End User Usage
After deployment, users can manage VPN independently:
```bash
./bin/connect-vpn.sh connect     # Turn VPN on
./bin/connect-vpn.sh disconnect  # Turn VPN off
./bin/connect-vpn.sh status      # Check status
```

### User Experience Benefits

#### For Daily VPN Users
- **Fast Connect**: No setup overhead for repeat connections
- **Quick Disconnect**: Clean shutdown without losing configuration
- **Reliable**: Improved macOS interface handling

#### For Deployment
- **Clear Separation**: Setup vs operational phases
- **Better Debugging**: Isolate setup issues from connection issues
- **Flexibility**: Users can skip auto-connect during deployment

### Implementation Files

#### Primary Changes
- **bin/connect-laptop-wireguard.sh**: Rename to `bin/connect-vpn.sh` and refactor with new command structure
- **deploy-k0rdent.sh**: Update Steps 6-7 to use `setup` then `connect`

#### New Functions
```bash
# In connect-vpn.sh
setup_wireguard()           # One-time setup
connect_wireguard()         # Simple connection (refactored)
disconnect_wireguard()      # Enhanced with state preservation
check_setup_complete()      # Validate setup state
```

---

## Part 3: Enhanced Configuration Reporting

### Current Issue
The `./deploy-k0rdent.sh config` command shows inaccurate information:
- Reports single "VM Size" but system uses different sizes for controllers vs workers
- Doesn't show zone distribution or cluster topology details
- Missing network configuration and resource naming details

### Current Output (Inaccurate)
```
=== Deployment Configuration ===
Prefix: k0rdent-bj8s89a1
Region: southeastasia
Resource Group: k0rdent-bj8s89a1-resgrp
VM Size: Standard_D8pls_v6
VM Count: 5
VMs: k0s-controller k0s-controller-2 k0s-controller-3 k0s-worker-1 k0s-worker-2
```

### Proposed Enhanced Configuration Report

#### Comprehensive Configuration Display
```
=== k0rdent Deployment Configuration ===

Project Settings:
  Prefix: k0rdent-bj8s89a1
  Region: southeastasia
  Resource Group: k0rdent-bj8s89a1-resgrp

Cluster Topology:
  Controllers: 3 nodes (Standard_D2pls_v6)
  Workers: 2 nodes (Standard_D8pls_v6)
  Total VMs: 5 nodes

VM Configuration:
  k0s-controller     → Standard_D2pls_v6 (Zone 2)
  k0s-controller-2   → Standard_D2pls_v6 (Zone 3)
  k0s-controller-3   → Standard_D2pls_v6 (Zone 2)
  k0s-worker-1       → Standard_D8pls_v6 (Zone 3)
  k0s-worker-2       → Standard_D8pls_v6 (Zone 2)

Network Configuration:
  VNet: 10.240.0.0/16
  Subnet: 10.240.1.0/24
  WireGuard Network: 172.24.24.0/24
  SSH User: k0rdent

Software Versions:
  k0s: v1.33.1+k0s.0
  k0rdent: 1.0.0
  Registry: oci://ghcr.io/k0rdent/kcm/charts/kcm

Azure Settings:
  VM Priority: Regular
  Image: Debian:debian-12:12-arm64:latest

Kubeconfig:
  Location: ./k0sctl-config/k0rdent-bj8s89a1-kubeconfig
```

### Implementation Plan

#### Enhanced show_config() Function
```bash
show_config() {
    print_header "k0rdent Deployment Configuration"
    
    echo
    echo "Project Settings:"
    echo "  Prefix: $K0RDENT_PREFIX"
    echo "  Region: $AZURE_LOCATION"
    echo "  Resource Group: $RG"
    
    echo
    echo "Cluster Topology:"
    echo "  Controllers: $K0S_CONTROLLER_COUNT nodes ($AZURE_CONTROLLER_VM_SIZE)"
    echo "  Workers: $K0S_WORKER_COUNT nodes ($AZURE_WORKER_VM_SIZE)"
    echo "  Total VMs: ${#VM_HOSTS[@]} nodes"
    
    echo
    echo "VM Configuration:"
    # Show each VM with its size and zone
    
    echo
    echo "Network Configuration:"
    echo "  VNet: $VNET_PREFIX"
    echo "  Subnet: $SUBNET_PREFIX"
    echo "  WireGuard Network: $WG_NETWORK"
    echo "  SSH User: $SSH_USERNAME"
    
    echo
    echo "Software Versions:"
    echo "  k0s: $K0S_VERSION"
    echo "  k0rdent: $K0RDENT_VERSION"
    echo "  Registry: $K0RDENT_OCI_REGISTRY"
    
    echo
    echo "Azure Settings:"
    echo "  VM Priority: $AZURE_VM_PRIORITY"
    echo "  Image: $AZURE_VM_IMAGE"
    
    echo
    echo "Kubeconfig:"
    echo "  Location: ./k0sctl-config/${K0RDENT_PREFIX}-kubeconfig"
}
```

#### VM Details Helper Function
```bash
show_vm_details() {
    local controller_index=0
    local worker_index=0
    
    for HOST in "${VM_HOSTS[@]}"; do
        local vm_size zone
        
        if [[ "$HOST" =~ controller ]]; then
            vm_size="$AZURE_CONTROLLER_VM_SIZE"
            zone="${CONTROLLER_ZONES[$controller_index]:-${CONTROLLER_ZONES[0]}}"
            ((controller_index++))
        else
            vm_size="$AZURE_WORKER_VM_SIZE"
            zone="${WORKER_ZONES[$worker_index]:-${WORKER_ZONES[0]}}"
            ((worker_index++))
        fi
        
        printf "  %-18s → %s (Zone %s)\n" "$HOST" "$vm_size" "$zone"
    done
}
```

### Benefits

#### Accuracy
- Shows actual VM sizes for each node type
- Displays zone distribution strategy
- Reflects true cluster topology

#### Completeness
- Network configuration details
- Software versions being deployed
- Azure-specific settings

#### Usability
- Clear categorization of information
- Easy to verify configuration before deployment
- Helpful for troubleshooting and documentation

#### Cost Awareness
- Shows different VM sizes so users understand cost implications
- Zone distribution visible for availability planning

### Implementation Files
- **deploy-k0rdent.sh**: Enhance `show_config()` function
- **etc/common-functions.sh**: Add helper functions if needed

---

## Part 4: Enhanced Prerequisites Checking

### Current Issues
The prerequisites checking is incomplete and fragmented:
- `k0sctl` is only checked when `install-k0s.sh` runs, not upfront
- `netcat` is only checked in `connect-vpn.sh`, not in main deploy script
- Prerequisites scattered across multiple scripts instead of centralized validation
- Missing documentation in README

### Current Prerequisites Coverage

#### Main Deploy Script (`deploy-k0rdent.sh`):
- ✅ Azure CLI (`az`) - installed and authenticated
- ✅ WireGuard tools (`wg`) - installed

#### Individual Scripts:
- `install-k0s.sh`: Checks `k0sctl` (should be upfront)
- `connect-vpn.sh`: Checks `netcat` (should be upfront)

### Enhanced Prerequisites Plan

#### Comprehensive Prerequisites Check
```bash
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Azure CLI (existing)
    check_azure_cli
    
    # WireGuard tools (existing)
    check_wireguard_tools
    
    # k0sctl (new - critical for k0s deployment)
    check_k0sctl
    
    # netcat (new - needed for connectivity testing)
    check_netcat

    print_success "All prerequisites satisfied"
}
```

#### New Prerequisite Functions
```bash
# Check k0sctl installation
check_k0sctl() {
    if ! command -v k0sctl &> /dev/null; then
        print_error "k0sctl is not installed. Please install it first."
        echo "Visit: https://docs.k0sproject.io/stable/k0sctl-install/"
        echo "Or install via:"
        echo "  # macOS:"
        echo "  brew install k0sproject/tap/k0sctl"
        echo "  # Linux:"
        echo "  curl -sSLf https://get.k0s.sh | sudo sh"
        exit 1
    fi
    print_success "k0sctl is installed"
}

# Check netcat installation
check_netcat() {
    if ! command -v nc &> /dev/null; then
        print_error "netcat (nc) not found. Please install netcat first:"
        echo "  # macOS:"
        echo "  brew install netcat"
        echo "  # Ubuntu/Debian:"
        echo "  sudo apt install netcat-openbsd"
        echo "  # CentOS/RHEL:"
        echo "  sudo yum install nmap-ncat"
        exit 1
    fi
    print_success "netcat is installed"
}
```

#### Remove Duplicate Checks
- Remove `k0sctl` check from `install-k0s.sh`
- Remove `netcat` check from `connect-vpn.sh`
- Rely on centralized prerequisites validation

### README Documentation Enhancement

#### Add Prerequisites Section
```markdown
## Prerequisites

Before running the k0rdent deployment, ensure you have the following tools installed:

### Required Tools

1. **Azure CLI** - For managing Azure resources
   ```bash
   # macOS
   brew install azure-cli
   
   # Ubuntu/Debian
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   
   # Windows
   # Download from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
   ```

2. **WireGuard Tools** - For VPN connectivity
   ```bash
   # macOS
   brew install wireguard-tools
   
   # Ubuntu/Debian
   sudo apt install wireguard
   
   # CentOS/RHEL
   sudo yum install wireguard-tools
   ```

3. **k0sctl** - For Kubernetes cluster management
   ```bash
   # macOS
   brew install k0sproject/tap/k0sctl
   
   # Linux
   curl -sSLf https://get.k0s.sh | sudo sh
   ```

4. **netcat** - For network connectivity testing
   ```bash
   # macOS
   brew install netcat
   
   # Ubuntu/Debian
   sudo apt install netcat-openbsd
   
   # CentOS/RHEL
   sudo yum install nmap-ncat
   ```

### Authentication Setup

1. **Azure Authentication**:
   ```bash
   az login
   ```

2. **Verify Prerequisites**:
   ```bash
   ./deploy-k0rdent.sh check
   ```
```

### Benefits

#### Early Validation
- Catch missing dependencies before deployment starts
- Clear error messages with installation instructions
- Prevents partial deployments due to missing tools

#### Centralized Management
- Single location for all prerequisite checks
- Consistent error handling and messaging
- Easier maintenance and updates

#### Better Documentation
- Clear installation instructions for all platforms
- Prerequisites visible in README before users start
- Reduces support burden from missing dependencies

### Implementation Files
- **deploy-k0rdent.sh**: Enhanced `check_prerequisites()` function
- **etc/common-functions.sh**: New `check_k0sctl()` and `check_netcat()` functions
- **README.md**: New Prerequisites section
- **bin/install-k0s.sh**: Remove duplicate `k0sctl` check
- **bin/connect-vpn.sh**: Remove duplicate `netcat` check

---

## Implementation Priority

### Phase 1: WireGuard Connection Management
- Higher user impact
- Improves daily workflow
- Builds on recent macOS improvements
- Estimated effort: 1-2 days

### Phase 2: SSH Lockdown
- Security enhancement
- Lower frequency of use
- Requires Azure NSG management
- Estimated effort: 1 day

## Testing Strategy

### WireGuard Changes
- Test setup once, connect/disconnect multiple times
- Verify backwards compatibility with existing scripts
- Test both GUI and CLI setup paths on macOS
- Validate state management across reboots

### SSH Lockdown
- Test lockdown with active VPN connection
- Verify unlock restores original access
- Test with various NSG rule configurations
- Ensure no impact on WireGuard connectivity

## Risk Assessment

### Low Risk
- WireGuard changes are additive and backwards compatible
- SSH lockdown is optional and reversible

### Mitigation
- Maintain backwards compatibility for existing workflows
- Provide clear documentation for new commands
- Include safety checks before destructive operations

---

## Future Considerations

### Additional Enhancements
- **VPN Auto-reconnect**: Detect and restore dropped connections
- **Multiple Profiles**: Support different WireGuard configurations
- **GUI Integration**: Native macOS menu bar VPN control
- **SSH Key Rotation**: Automatic SSH key updates with lockdown

### Monitoring
- Track VPN uptime and connection quality
- Log SSH access attempts after lockdown
- Alert on failed VPN connections during critical operations

---

## Part 5: Deploy Reset VPN Verification (User Request)

### Requirement
The `deploy-k0rdent.sh reset` process needs to verify that the VPN is up when starting the reset to ensure it can run the reset processes for k0rdent and k0s. The rest of the reset process does not require SSH access - just those two initial steps.

### Implementation Plan

#### VPN Connectivity Check
Add a VPN verification step at the beginning of `run_full_reset()` function:

```bash
# Step 0: Verify VPN connectivity (required for k0rdent/k0s reset)
verify_vpn_for_reset() {
    print_header "Verifying VPN Connectivity for Reset"
    
    # Check if VPN configuration exists
    if [[ ! -d "./laptop-wg-config" ]]; then
        print_warning "No VPN configuration found. k0rdent/k0s reset will be skipped."
        return 1
    fi
    
    # Test VPN connectivity to at least one VM
    print_info "Testing VPN connectivity to cluster nodes..."
    local connected_count=0
    
    for HOST in "${VM_HOSTS[@]}"; do
        local VM_IP="${WG_IPS[$HOST]}"
        if ping -c 1 -W 2000 "$VM_IP" &>/dev/null; then
            print_success "✓ $HOST ($VM_IP) reachable via VPN"
            ((connected_count++))
            break  # Only need one working connection
        fi
    done
    
    if [[ $connected_count -gt 0 ]]; then
        print_success "VPN connectivity verified - reset can proceed"
        return 0
    else
        print_error "No VMs reachable via VPN"
        print_warning "k0rdent and k0s cluster reset will be skipped"
        print_info "The rest of the reset (Azure resources, keys, etc.) will continue"
        return 1
    fi
}
```

#### Updated Reset Flow
```bash
run_full_reset() {
    print_header "Full k0rdent Deployment Reset"
    # ... existing warning and confirmation ...
    
    # Step 0: Check VPN connectivity
    local vpn_available=false
    if verify_vpn_for_reset; then
        vpn_available=true
    fi
    
    # Step 1: Uninstall k0rdent (only if VPN available)
    if [[ "$vpn_available" == "true" ]] && [[ -d "./k0sctl-config" ]]; then
        print_header "Step 1: Uninstalling k0rdent from Cluster"
        bash bin/install-k0rdent.sh uninstall $DEPLOY_FLAGS || true
    else
        print_info "Step 1: Skipping k0rdent uninstall (VPN not available or no cluster)"
    fi
    
    # Step 2: Reset k0s cluster (only if VPN available)
    if [[ "$vpn_available" == "true" ]] && [[ -d "./k0sctl-config" ]]; then
        print_header "Step 2: Removing k0s Cluster"
        bash bin/install-k0s.sh uninstall $DEPLOY_FLAGS
        bash bin/install-k0s.sh reset $DEPLOY_FLAGS
    else
        print_info "Step 2: Skipping k0s cluster reset (VPN not available or no cluster)"
    fi
    
    # Rest of reset continues regardless of VPN status...
}
```

### Benefits
- **Graceful Degradation**: Reset continues even if VPN is down
- **Clear Messaging**: User understands what can/cannot be reset
- **Fast Check**: Quick ping test doesn't delay reset significantly
- **Selective Reset**: Only SSH-dependent operations are skipped

### Files to Modify
- `deploy-k0rdent.sh`: Add VPN verification and conditional reset logic

---