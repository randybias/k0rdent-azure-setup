---
id: task-018
title: Scoped Azure credentials management
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - security
  - azure
dependencies: []
priority: low
---

## Description

Currently Azure credentials (AzureClusterIdentity) are configured with allowedNamespaces: {} which allows all namespaces. Enhance security by implementing namespace-specific credentials.

## Acceptance Criteria

- [ ] Design namespace-specific credential strategy
- [ ] Create separate AzureClusterIdentity resources per namespace
- [ ] Implement role-based scoping with different permissions
- [ ] Document tenant/subscription scoping approach
- [ ] Maintain backward compatibility with open configuration
- [ ] Create migration guide for existing deployments
