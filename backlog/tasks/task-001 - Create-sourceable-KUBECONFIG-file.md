---
id: task-001
title: Create sourceable KUBECONFIG file
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - medium-priority
  - developer-experience
dependencies: []
priority: medium
---

## Description

Create a sourceable shell script in the k0sctl-config directory that properly sets the KUBECONFIG environment variable for easy cluster access.

## Acceptance Criteria

- [ ] Sourceable script exists at ./k0sctl-config/kubeconfig-env.sh
- [ ] Script correctly sets KUBECONFIG environment variable
- [ ] Script works with both absolute and relative paths
- [ ] Helpful kubectl aliases are included
- [ ] Current context is displayed on sourcing


## Implementation Plan

1. Analyze existing k0s deployment script to find where kubeconfig is generated
2. Create the kubeconfig-env.sh generation function in common-functions.sh
3. Integrate the generation into install-k0s.sh after successful deployment
4. Add kubectl aliases and context display functionality
5. Test with both absolute and relative paths
6. Update deployment success messages to mention the new script
7. Update README documentation with usage instructions
## Current Situation

- Kubeconfig file is generated at `./k0sctl-config/${K0RDENT_CLUSTERID}-kubeconfig`
- Users must manually set KUBECONFIG or use --kubeconfig flag
- No convenient way to quickly set up shell environment for cluster access

## Proposed Solution

Create a file `./k0sctl-config/kubeconfig-env.sh` (or similar) that contains:
```bash
export KUBECONFIG="$(pwd)/k0sctl-config/${K0RDENT_CLUSTERID}-kubeconfig"
```

## Enhanced Version Could Include

```bash
# Set kubeconfig
export KUBECONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/${K0RDENT_CLUSTERID}-kubeconfig"

# Helpful aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'

# Show current context
echo "KUBECONFIG set to: $KUBECONFIG"
kubectl config current-context
```

## Benefits

- Quick environment setup: `source ./k0sctl-config/kubeconfig-env.sh`
- Consistent KUBECONFIG handling across team members
- Reduces command-line friction for cluster access
- Self-documenting cluster access method

## Integration Points

- Generate during `install-k0s.sh deploy`
- Update during any operation that changes kubeconfig
- Include instructions in deployment success messages
- Add to documentation and README
