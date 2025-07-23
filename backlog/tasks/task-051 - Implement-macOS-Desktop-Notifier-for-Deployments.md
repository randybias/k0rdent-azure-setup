---
id: task-051
title: Implement macOS Desktop Notifier for Deployments
status: To Do
assignee: []
created_date: '2025-07-22'
updated_date: '2025-07-23'
labels:
  - enhancement
  - macos
  - notifications
dependencies:
  - task-049
parent_task_id: task-high
---

## Description

Implement the desktop notification system for k0rdent deployments based on the plan in doc-005. This will provide real-time desktop notifications during deployments on macOS.

## Acceptance Criteria

- [ ] Desktop notifier script implemented
- [ ] Integration with deploy-k0rdent.sh completed
- [ ] Event monitoring working correctly
- [ ] Notifications appear for key deployment events
- [ ] Process management handles cleanup properly
- [ ] Documentation updated with usage instructions

## Implementation Notes

Implemented desktop notifier for macOS with the following features:
- Created bin/utils/desktop-notifier.sh - Main daemon that monitors deployment events
- Created etc/notifier-functions.sh - Shared notification functions
- Updated etc/state-management.sh to write JSON events alongside YAML
- Updated deploy-k0rdent.sh with --with-desktop-notifications flag
- Added proper cleanup on deployment completion/failure
- Uses terminal-notifier (preferred) with osascript fallback
- Monitors state/deployment-events.json using tail -F
- Created test script: scratch/test-notifier-integration.sh

Key design decisions:
- JSON events file for efficient tail-based monitoring
- Separate daemon process with PID tracking
- Notification grouping to avoid spam
- Graceful fallback when terminal-notifier not available
