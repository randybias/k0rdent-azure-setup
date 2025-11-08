---
id: task-056
title: Develop plan for handling ServiceTemplates in k0rdent
status: To Do
assignee: []
created_date: '2025-08-06 12:23'
updated_date: '2025-08-06 12:23'
labels:
  - planning
  - k0rdent
  - services
dependencies: []
priority: medium
---

## Description

Create a comprehensive plan for implementing and managing ServiceTemplates in k0rdent, which enable deploying applications to child clusters using Helm charts, Kustomization, or raw Kubernetes resources. ServiceTemplates are a core component of k0rdent's application deployment strategy and need proper integration with our Azure setup.

## Acceptance Criteria

- [ ] Plan defines approach for creating ServiceTemplates for common applications
- [ ] Plan includes support for all source types (Helm/Kustomization/Raw K8s)
- [ ] Plan specifies how to manage ServiceTemplateChains for deployment constraints
- [ ] Plan includes integration with existing k0rdent cluster deployment process
- [ ] Plan addresses versioning and upgrade strategies for ServiceTemplates
- [ ] Plan includes examples for at least 3 common applications (nginx/monitoring/logging)
- [ ] Plan defines storage and organization of ServiceTemplate definitions
- [ ] Plan includes testing strategy for ServiceTemplate deployments
