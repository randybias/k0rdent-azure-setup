---
id: task-053
title: Fix --with-desktop-notifications flag validation in deploy-k0rdent.sh
status: To Do
assignee: []
created_date: '2025-07-23'
updated_date: '2025-07-23'
labels:
  - bug
dependencies:
  - task-004
---

## Description

The --with-desktop-notifications flag is accepted by the argument parser but then causes an 'Unknown option' error when used with non-deploy commands like reset. The flag should only be valid for the deploy command.

## Acceptance Criteria

- [ ] Flag only accepted when command is 'deploy'
- [ ] Error message shown immediately if flag used with wrong command
- [ ] Argument parsing validates command context
