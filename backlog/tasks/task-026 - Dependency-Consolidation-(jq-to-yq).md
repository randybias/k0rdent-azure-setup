---
id: task-026
title: Dependency Consolidation (jq to yq)
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - refactoring
  - dependencies
dependencies: []
priority: low
---

## Description

Replace jq with yq throughout the codebase to reduce dependencies since yq can handle both YAML and JSON formats.

## Acceptance Criteria

- [ ] Audit all jq usage in the codebase
- [ ] Convert jq commands to yq equivalents
- [ ] Test all conversions for correctness
- [ ] Update dependency documentation
- [ ] Remove jq from prerequisites
- [ ] Verify performance impact
