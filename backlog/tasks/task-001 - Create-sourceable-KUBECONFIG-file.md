---
id: task-001
title: Create sourceable KUBECONFIG file
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - enhancement
  - medium-priority
  - developer-experience
dependencies: []
---

## Description

Create a sourceable shell script in the k0sctl-config directory that properly sets the KUBECONFIG environment variable for easy cluster access.

## Acceptance Criteria

- [ ] Sourceable script exists at ./k0sctl-config/kubeconfig-env.sh
- [ ] Script correctly sets KUBECONFIG environment variable
- [ ] Script works with both absolute and relative paths
- [ ] Helpful kubectl aliases are included
- [ ] Current context is displayed on sourcing
