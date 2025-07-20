---
id: doc-003
title: k0rdent CLI Specification
type: design
created_date: '2025-07-20'
updated_date: '2025-07-20'
---
# k0rdent CLI Specification

## Overview

This specification defines a unified command-line interface for k0rdent that focuses exclusively on k0rdent cluster management operations. The design follows ZFS's hierarchical command principles and incorporates k0s's approach of embedding kubectl functionality.

## Design Philosophy

1. **Single Binary**: All k0rdent functionality in one executable
2. **Hierarchical Commands**: Clear command hierarchy with subcommands
3. **Smart Abbreviations**: Unambiguous partial commands are automatically resolved
4. **Embedded Tools**: Common tools (like kubectl) embedded within k0rdent command
5. **Context-Aware**: Commands operate on current cluster context by default

## Command Structure

### Base Command
```
k0rdent <subcommand> [options] [arguments]
```

### Primary Subcommands

#### cluster - Cluster Management
```
k0rdent cluster <operation> [options]

Operations:
  create    Create a new k0rdent cluster
  delete    Delete a k0rdent cluster  
  list      List all clusters
  status    Show cluster status
  upgrade   Upgrade cluster version
  
Abbreviations:
  cl → cluster
  c  → cluster (if unambiguous)
  cr → create
  del → delete
  ls → list
  st → status
  up → upgrade

Examples:
  k0rdent cluster create production --provider azure --region westus2
  k0rdent cl cr production --provider azure --region westus2
  k0rdent c ls
```

#### deployment - ClusterDeployment Management
```
k0rdent deployment <operation> [options]

Operations:
  create    Create cluster deployment
  apply     Apply deployment configuration
  delete    Delete deployment
  list      List deployments
  describe  Show deployment details
  
Abbreviations:
  deploy → deployment
  dep → deployment
  d → deployment (if unambiguous)

Examples:
  k0rdent deployment create child-west --template small
  k0rdent dep apply -f deployment.yaml
  k0rdent d ls --namespace production
```

#### template - ClusterTemplate Management
```
k0rdent template <operation> [options]

Operations:
  list      List available templates
  show      Show template details
  create    Create custom template
  validate  Validate template
  
Abbreviations:
  tmpl → template
  t → template (if unambiguous)

Examples:
  k0rdent template list
  k0rdent tmpl show azure-small
  k0rdent t create custom-large --from azure-medium
```

#### credential - Credential Management
```
k0rdent credential <operation> [options]

Operations:
  add       Add cloud credentials
  list      List credentials
  validate  Validate credentials
  rotate    Rotate credentials
  
Abbreviations:
  cred → credential
  cr → credential (if ambiguous with create)

Examples:
  k0rdent credential add azure-prod --provider azure
  k0rdent cred list
  k0rdent cred validate azure-prod
```

#### addon - Addon Management
```
k0rdent addon <operation> [options]

Operations:
  list      List available addons
  enable    Enable addon on cluster
  disable   Disable addon
  status    Show addon status
  
Abbreviations:
  add → addon
  a → addon (if unambiguous)

Examples:
  k0rdent addon enable kof --cluster production
  k0rdent add list --enabled
  k0rdent a status kof
```

#### kubeconfig - Kubeconfig Management
```
k0rdent kubeconfig <operation> [options]

Operations:
  get       Get kubeconfig for cluster
  merge     Merge into local kubeconfig
  switch    Switch current context
  
Abbreviations:
  kc → kubeconfig
  config → kubeconfig

Examples:
  k0rdent kubeconfig get production
  k0rdent kc merge production --path ~/.kube/config
  k0rdent config switch production
```

#### kubectl - Embedded kubectl
```
k0rdent kubectl [kubectl-args...]

Direct pass-through to kubectl for current k0rdent context

Abbreviations:
  k → kubectl

Examples:
  k0rdent kubectl get pods -A
  k0rdent k get nodes
  k0rdent k apply -f manifest.yaml
```

#### troubleshoot - Troubleshooting Operations
```
k0rdent troubleshoot <target> [options]

Targets:
  cluster      Diagnose cluster issues
  deployment   Diagnose deployment issues
  network      Network diagnostics
  addon        Addon diagnostics
  
Abbreviations:
  ts → troubleshoot
  diag → troubleshoot

Examples:
  k0rdent troubleshoot cluster production
  k0rdent ts deployment child-west
  k0rdent diag network --test connectivity
```

#### backup - Backup and Restore
```
k0rdent backup <operation> [options]

Operations:
  create    Create backup
  restore   Restore from backup
  list      List backups
  delete    Delete backup
  
Abbreviations:
  bk → backup
  b → backup (if unambiguous)

Examples:
  k0rdent backup create production --full
  k0rdent bk restore production --from backup-2024-01-18
  k0rdent b ls
```

### Global Options

```
--context        k0rdent context to use
--namespace      Kubernetes namespace
--output, -o     Output format (json|yaml|table|wide)
--quiet, -q      Minimal output
--verbose, -v    Verbose output
--dry-run        Show what would be done
--force          Skip confirmations
--help, -h       Show help
```

## Smart Abbreviation Rules

1. **Unambiguous Resolution**: Any unique prefix resolves to full command
2. **Common Shortcuts**: Frequently used commands get priority shortcuts
3. **Context Preservation**: Abbreviations work at any command level

Examples:
```
k0rdent c ls                    → k0rdent cluster list
k0rdent dep cr myapp            → k0rdent deployment create myapp
k0rdent t sh azure-small        → k0rdent template show azure-small
k0rdent k get po -A             → k0rdent kubectl get pods -A
```

## Context Management

### Automatic Context
- Commands operate on current k0rdent context
- Context includes: management cluster, namespace, credentials

### Context Commands
```
k0rdent context <operation>

Operations:
  list      List contexts
  current   Show current context
  use       Switch context
  
Examples:
  k0rdent context use production
  k0rdent ctx ls
```

## Output Formats

### Default Table Format
```
$ k0rdent cluster list
NAME         PROVIDER   REGION      STATUS    AGE
production   azure      westus2     Ready     30d
staging      azure      eastus      Ready     15d
dev          aws        us-east-1   Creating  5m
```

### JSON Format
```
$ k0rdent cluster list -o json
{
  "clusters": [
    {
      "name": "production",
      "provider": "azure",
      "region": "westus2",
      "status": "Ready",
      "age": "30d"
    }
  ]
}
```

## Interactive Features

### Confirmation Prompts
```
$ k0rdent cluster delete production
Warning: This will delete cluster 'production' and all its resources.
Are you sure? [y/N]: 
```

### Progress Indication
```
$ k0rdent cluster create staging --provider azure
Creating cluster 'staging'...
✓ Validating configuration
✓ Creating management cluster
⠼ Deploying k0rdent components (3/5)
```

### Auto-completion
- Shell completion for all commands and options
- Dynamic completion for resource names
- Context-aware suggestions

## Error Handling

### Descriptive Errors
```
$ k0rdent cluster create prod --provider aws
Error: Missing required cloud credentials for AWS
Hint: Add credentials using 'k0rdent credential add aws-creds --provider aws'
```

### Exit Codes
- 0: Success
- 1: General error
- 2: Invalid usage
- 3: Resource not found
- 4: Permission denied
- 5: Network error

## Integration Points

### Environment Variables
```
K0RDENT_CONTEXT      Current context
K0RDENT_NAMESPACE    Default namespace
K0RDENT_CONFIG       Config file location
K0RDENT_LOG_LEVEL    Log verbosity
```

### Configuration File
```yaml
# ~/.k0rdent/config.yaml
current-context: production
contexts:
  - name: production
    cluster: prod-mgmt
    namespace: default
  - name: staging
    cluster: stage-mgmt
    namespace: staging
```

## Examples of Complete Workflows

### Deploy New Child Cluster
```bash
# Add cloud credentials
k0rdent cred add azure-prod --provider azure

# Create cluster deployment
k0rdent dep create west-child --template azure-small --region westus2

# Monitor deployment
k0rdent dep status west-child --watch

# Get kubeconfig when ready
k0rdent kc get west-child > west-child.kubeconfig

# Use embedded kubectl
k0rdent k get nodes --context west-child
```

### Troubleshoot Deployment
```bash
# Check deployment status
k0rdent dep status problematic-cluster

# Run diagnostics
k0rdent ts deployment problematic-cluster

# Check detailed logs
k0rdent dep describe problematic-cluster --show-events

# Test network connectivity
k0rdent ts network --cluster problematic-cluster
```

### Manage Addons
```bash
# List available addons
k0rdent addon list

# Enable KOF addon
k0rdent addon enable kof --cluster production

# Check addon status
k0rdent addon status kof

# Configure addon
k0rdent addon configure kof --set monitoring.enabled=true
```

## Design Rationale

1. **Single Tool**: Everything k0rdent-related through one command
2. **Discoverable**: Hierarchical structure aids discovery
3. **Efficient**: Smart abbreviations reduce typing
4. **Familiar**: Follows kubectl patterns where appropriate
5. **Focused**: Only k0rdent operations, no infrastructure provisioning
6. **Extensible**: Easy to add new subcommands and operations
