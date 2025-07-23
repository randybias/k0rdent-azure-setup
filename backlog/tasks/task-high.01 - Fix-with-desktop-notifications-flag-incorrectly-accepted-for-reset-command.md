---
id: task-high.01
title: 'Fix: --with-desktop-notifications flag incorrectly accepted for reset command'
status: To Do
assignee: []
created_date: '2025-07-23'
labels:
  - bug
  - cli
dependencies: []
parent_task_id: task-high
---

## Description

The --with-desktop-notifications flag is being parsed globally in deploy-k0rdent.sh, which means it's incorrectly available for all commands (reset, config, check, etc). This flag should only be valid for the 'deploy' command. Currently, using it with reset gives an 'Unknown option' error after the configuration is loaded.

## Acceptance Criteria

- [ ] Flag parsing validates command context before accepting flags
- [ ] --with-desktop-notifications only works with 'deploy' command
- [ ] Other deployment-specific flags (--with-azure-children
- [ ] --with-kof) also validated
- [ ] Clear error message when flag used with wrong command
- [ ] Help text remains accurate for each command
