# k0rdent Azure Setup - Program Flow Diagram

## Overview
This document provides visual diagrams showing the program flow, script relationships, and state tracking mechanisms in the k0rdent Azure setup project.

## Main Deployment Flow

```mermaid
graph TD
    Start([User runs deploy-k0rdent.sh deploy]) --> LoadConfig[Load Configuration]
    
    LoadConfig --> PrepDeploy[prepare-deployment.sh]
    PrepDeploy --> |Updates State| State1[(deployment-state.yaml)]
    
    PrepDeploy --> SetupNet[setup-azure-network.sh]
    SetupNet --> |Updates State| State2[(deployment-state.yaml)]
    
    SetupNet --> CreateVMs[create-azure-vms.sh]
    CreateVMs --> |Updates State| State3[(deployment-state.yaml)]
    
    CreateVMs --> SetupVPN[manage-vpn.sh setup]
    SetupVPN --> |Updates State| State4[(deployment-state.yaml)]
    
    SetupVPN --> ConnectVPN[manage-vpn.sh connect]
    ConnectVPN --> |Updates State| State5[(deployment-state.yaml)]
    
    ConnectVPN --> Installk0s[install-k0s.sh]
    Installk0s --> |Updates State| State6[(deployment-state.yaml)]
    
    Installk0s --> ValidateNet[validate-pod-network.sh]
    ValidateNet --> |Network OK?| NetDecision{Network Valid?}
    NetDecision -->|Yes| Installk0rdent[install-k0rdent.sh]
    NetDecision -->|No| FailNet[Network Validation Failed]
    
    Installk0rdent --> |Updates State| State7[(deployment-state.yaml)]
    
    Installk0rdent --> OptionalCheck{Optional Components?}
    OptionalCheck -->|--with-azure-children| AzureSetup[setup-azure-cluster-deployment.sh]
    OptionalCheck -->|--with-kof| KOFCheck{Azure Children Enabled?}
    OptionalCheck -->|None| Complete([Deployment Complete])
    
    AzureSetup --> |Updates State| State8[(deployment-state.yaml)]
    AzureSetup --> KOFCheck2{KOF Enabled?}
    
    KOFCheck -->|Yes| InstallCSI[install-k0s-azure-csi.sh]
    KOFCheck -->|No| InstallCSI
    KOFCheck2 -->|Yes| InstallCSI
    KOFCheck2 -->|No| Complete
    
    InstallCSI --> InstallKOFMothership[install-kof-mothership.sh]
    InstallKOFMothership --> InstallKOFRegional[install-kof-regional.sh]
    InstallKOFRegional --> |Updates State| State9[(deployment-state.yaml)]
    InstallKOFRegional --> Complete
    
    Complete --> Backup[Backup to old_deployments/]
    
    style Start fill:#90EE90
    style Complete fill:#90EE90
    style State1 fill:#FFE4B5
    style State2 fill:#FFE4B5
    style State3 fill:#FFE4B5
    style State4 fill:#FFE4B5
    style State5 fill:#FFE4B5
    style State6 fill:#FFE4B5
    style State7 fill:#FFE4B5
    style State8 fill:#FFE4B5
    style State9 fill:#FFE4B5
    style FailNet fill:#FF6B6B
    style NetDecision fill:#FFEB9C
    style OptionalCheck fill:#FFEB9C
    style KOFCheck fill:#FFEB9C
    style KOFCheck2 fill:#FFEB9C
```

## Configuration Loading System

```mermaid
graph LR
    A[deploy-k0rdent.sh] --> B[etc/k0rdent-config.sh]
    B --> C{Config exists?}
    C -->|Yes| D[bin/configure.sh]
    C -->|No| E[Use k0rdent-default.yaml]
    D --> F[Load YAML config]
    E --> F
    F --> G[etc/config-internal.sh]
    G --> H[Compute dynamic values]
    H --> I[Configuration Ready]
    
    style A fill:#87CEEB
    style I fill:#90EE90
```

## Script Dependencies and Relationships

```mermaid
graph TD
    subgraph "Main Orchestrator"
        Main[deploy-k0rdent.sh]
    end
    
    subgraph "Configuration Layer"
        Config1[etc/k0rdent-config.sh]
        Config2[etc/config-internal.sh]
        Config3[bin/configure.sh]
        Config1 --> Config2
        Config1 --> Config3
    end
    
    subgraph "Common Functions"
        Common[etc/common-functions.sh]
    end
    
    subgraph "State Management"
        State[etc/state-management.sh]
    end
    
    subgraph "Deployment Scripts"
        Prep[bin/prepare-deployment.sh]
        Network[bin/setup-azure-network.sh]
        VMs[bin/create-azure-vms.sh]
        VPN[bin/manage-vpn.sh]
        K0s[bin/install-k0s.sh]
        Validate[bin/validate-pod-network.sh]
        K0rdent[bin/install-k0rdent.sh]
        SSH[bin/lockdown-ssh.sh]
    end
    
    subgraph "Optional Components"
        AzureSetup[bin/setup-azure-cluster-deployment.sh]
        CSI[bin/install-k0s-azure-csi.sh]
        KOFMother[bin/install-kof-mothership.sh]
        KOFRegional[bin/install-kof-regional.sh]
    end
    
    Main --> Config1
    Main --> Prep
    Main --> Network
    Main --> VMs
    Main --> VPN
    Main --> K0s
    Main --> K0rdent
    
    Prep --> Common
    Prep --> State
    Network --> Common
    Network --> State
    VMs --> Common
    VMs --> State
    VPN --> Common
    VPN --> State
    K0s --> Common
    K0s --> State
    K0s --> Validate
    Validate --> Common
    Validate --> State
    K0rdent --> Common
    K0rdent --> State
    SSH --> Common
    
    Main --> AzureSetup
    Main --> CSI
    Main --> KOFMother
    Main --> KOFRegional
    
    AzureSetup --> Common
    AzureSetup --> State
    CSI --> Common
    CSI --> State
    KOFMother --> Common
    KOFMother --> State
    KOFRegional --> Common
    KOFRegional --> State
    
    style Main fill:#FF6B6B
    style Common fill:#4ECDC4
    style State fill:#FFE66D
```

## State Tracking Timeline

```mermaid
sequenceDiagram
    participant U as User
    participant D as deploy-k0rdent.sh
    participant S as State Manager
    participant Y as deployment-state.yaml
    
    U->>D: deploy command
    D->>S: Initialize state
    S->>Y: Create initial state
    
    Note over D,Y: Step 1: Prepare Deployment
    D->>S: Update WireGuard keys
    S->>Y: Save keys and peer configs
    
    Note over D,Y: Step 2: Setup Azure Network
    D->>S: Update resource group status
    S->>Y: Save network resources
    D->>S: Update SSH key info
    S->>Y: Save SSH public key
    
    Note over D,Y: Step 3: Create VMs
    loop For each VM
        D->>S: Update VM state
        S->>Y: Save VM IPs and status
    end
    
    Note over D,Y: Step 4-5: Setup VPN
    D->>S: Update VPN config
    S->>Y: Save VPN status
    D->>S: Update connection state
    S->>Y: Save peer connections
    
    Note over D,Y: Step 6: Install k0s
    D->>S: Update cluster state
    S->>Y: Save cluster status
    D->>S: Save kubeconfig
    S->>Y: Update k0s readiness
    
    Note over D,Y: Step 7: Install k0rdent
    D->>S: Update k0rdent state
    S->>Y: Save k0rdent readiness
    D->>S: Mark deployment complete
    S->>Y: Final state backup
```

## State File Structure

```yaml
# deployment-state.yaml structure
deployment:
  id: "unique-deployment-id"
  started_at: "timestamp"
  completed_at: "timestamp"
  
phases:
  prepare_deployment: true/false
  setup_network: true/false
  create_vms: true/false
  setup_vpn: true/false
  connect_vpn: true/false
  install_k0s: true/false
  install_k0rdent: true/false
  
resources:
  resource_group: "name"
  vnet: "name"
  subnet: "name"
  nsg: "name"
  ssh_key: "name"
  
vms:
  vm1:
    name: "vm-name"
    public_ip: "x.x.x.x"
    private_ip: "10.x.x.x"
    wireguard_ip: "192.168.100.x"
    status: "running"
    
wireguard:
  peers:
    laptop:
      public_key: "key"
      wireguard_ip: "192.168.100.1"
    vm1:
      public_key: "key"
      wireguard_ip: "192.168.100.x"
      
cluster:
  k0s_deployed: true/false
  k0rdent_ready: true/false
  kubeconfig_retrieved: true/false
```

## Reset/Cleanup Flow

```mermaid
graph TD
    Start([User runs deploy-k0rdent.sh reset]) --> Check{Check State}
    
    Check --> |KOF regional exists| DeleteKOFRegional[Delete KOF Regional Cluster]
    Check --> |Azure children exist| DeleteAzureChildren[Delete Azure Child Clusters]
    Check --> |k0rdent installed| Uninstallk0rdent[Uninstall k0rdent]
    Check --> |k0s deployed| Uninstallk0s[Uninstall k0s]
    Check --> |VPN connected| DisconnectVPN[Disconnect VPN]
    Check --> |VMs exist| DeleteVMs[Delete VMs]
    Check --> |Network exists| DeleteNetwork[Delete Network]
    
    DeleteKOFRegional --> DeleteAzureChildren
    DeleteAzureChildren --> Uninstallk0rdent
    Uninstallk0rdent --> Uninstallk0s
    Uninstallk0s --> DisconnectVPN
    DisconnectVPN --> DeleteVMs
    DeleteVMs --> DeleteNetwork
    DeleteNetwork --> CleanState[Clean State Files]
    CleanState --> Complete([Cleanup Complete])
    
    style Start fill:#FFB6C1
    style Complete fill:#90EE90
    style DeleteKOFRegional fill:#FFD700
    style DeleteAzureChildren fill:#FFD700
```

## Error Handling and Recovery

```mermaid
graph TD
    A[Script Execution] --> B{Error Occurred?}
    B -->|No| C[Continue to Next Step]
    B -->|Yes| D[Log Error]
    D --> E{Critical Error?}
    E -->|No| F[Retry Operation]
    E -->|Yes| G[Trigger Rollback]
    F --> H{Success?}
    H -->|Yes| C
    H -->|No| G
    G --> I[Execute Reset for Current Phase]
    I --> J[Update State]
    J --> K[Exit with Error]
    
    style A fill:#87CEEB
    style K fill:#FF6347
    style C fill:#90EE90
```

## Key Features Illustrated

1. **Modular Architecture**: Each script handles a specific domain
2. **State-Driven**: All operations tracked in deployment-state.yaml
3. **Progressive Enhancement**: Each step builds on the previous
4. **Rollback Capability**: Reset reverses deployment in opposite order
5. **Configuration Flexibility**: YAML-based with dynamic computation
6. **Error Recovery**: State tracking enables resumption after failures

## Common Patterns

- **Check-then-act**: Scripts verify existing state before operations
- **State updates**: Every significant action updates deployment state
- **Shared functions**: Common operations centralized in library
- **Standard commands**: Consistent CLI interface across scripts
- **Idempotent design**: Safe to run scripts multiple times