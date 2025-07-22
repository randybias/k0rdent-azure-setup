---
id: task-049
title: Local MacOS Desktop Notifier Plan
status: Done
assignee:
  - '@claude'
created_date: '2025-07-22'
updated_date: '2025-07-22'
labels:
  - enhancement
  - macos
  - notifications
  - monitoring
dependencies: []
priority: low
---

## Description

Create a plan to create an asynchronous script that runs during deployments, monitors deployment events and sends a desktop notification for new events.  It should start at the beginning of deployments after the events file is created.  It should require a new command line argument: --with-desktop-notifications.

Two different options to send notifications include:

- hammerspoon
- osascript

But other options should be investigated.

## Implementation Plan

1. Research macOS notification methods (osascript, hammerspoon, terminal-notifier)
2. Design event monitoring approach (file watching vs polling)
3. Define notification format and content structure
4. Plan integration with deploy-k0rdent.sh script
5. Design background process management
6. Create notification filtering/configuration options
7. Plan testing approach for async notifications
8. Document usage and requirements


## Implementation Notes

Created comprehensive implementation plan in backlog/docs/doc-005. Plan covers:
- Research of 3 notification methods (osascript, terminal-notifier, hammerspoon)
- Hybrid approach using terminal-notifier with osascript fallback
- Event monitoring using fswatch with polling fallback
- Full integration design with deploy-k0rdent.sh
- Background process lifecycle management
- Configuration options via environment variables
- Complete testing and documentation plan

The plan is ready for implementation as a new task.
## Acceptance Criteria

- [ ] Comprehensive implementation plan created
- [ ] All notification methods researched and documented
- [ ] Event monitoring approach designed
- [ ] Integration points with deploy-k0rdent.sh identified
- [ ] Background process management planned
- [ ] Testing and documentation approach defined
