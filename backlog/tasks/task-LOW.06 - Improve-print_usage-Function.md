---
id: task-LOW.06
title: Improve print_usage Function
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - enhancement
  - refactoring
  - ux
dependencies: []
parent_task_id: task-LOW
---

## Description

The print_usage function in common-functions.sh needs refactoring for better readability and maintainability with cleaner multi-line output and consistent formatting.

## Acceptance Criteria

- [ ] Analyze current print_usage implementations
- [ ] Design consistent formatting approach using heredoc
- [ ] Create helper functions for formatting
- [ ] Implement color coding for different sections
- [ ] Update all scripts to use new approach
- [ ] Test across different terminal widths
