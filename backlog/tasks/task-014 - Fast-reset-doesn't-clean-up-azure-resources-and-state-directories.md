---
id: task-014
title: Fast reset doesn't clean up azure-resources and state directories
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - bug
  - reset
  - cleanup
dependencies: []
priority: low
---

## Description

The fast reset option deletes the Azure resource group but fails to clean up local directories that should be removed for a complete reset. The azure-resources/ directory containing SSH keys and state/ directory persist after fast reset, requiring manual cleanup.

## Acceptance Criteria

- [ ] Fast reset removes azure-resources/ directory
- [ ] Fast reset removes state/ directory
- [ ] Fast reset provides complete cleanup equivalent to full reset
- [ ] No manual cleanup required after fast reset
