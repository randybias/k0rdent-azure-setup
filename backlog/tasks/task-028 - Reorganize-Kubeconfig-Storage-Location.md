---
id: task-028
title: Reorganize Kubeconfig Storage Location
status: In Progress
assignee:
  - '@claude'
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - organization
dependencies: []
priority: low
---

## Description

Move kubeconfig files from k0sctl-config/ directory to a dedicated kubeconfig/ directory for better organization and clarity.

## Acceptance Criteria

- [ ] Create new kubeconfig/ directory structure
- [ ] Update all scripts to use new location
- [ ] Implement backward compatibility checks
- [ ] Update .gitignore for new directory
- [ ] Update all documentation references
- [ ] Create migration strategy for existing deployments

## Implementation Plan

1. Search for all references to k0sctl-config/ directory in the codebase
2. Create new kubeconfig/ directory structure  
3. Update .gitignore to include kubeconfig/ instead of k0sctl-config/
4. Update all scripts to use new kubeconfig/ location
5. Add backward compatibility logic to check both locations
6. Update documentation (README.md, CLAUDE.md, and any other docs)
7. Test the changes with a deployment
8. Create migration instructions for existing users
