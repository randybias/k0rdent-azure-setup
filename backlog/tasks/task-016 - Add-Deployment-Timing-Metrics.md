---
id: task-016
title: Add Deployment Timing Metrics
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - enhancement
  - metrics
  - monitoring
dependencies: []
priority: high
---

## Description

Report deployment start timestamp, end timestamp, and total deployment time to provide better visibility into deployment duration and performance metrics. Currently no clear indication of when deployment started or total deployment time.

## Acceptance Criteria

- [ ] Deployment start timestamp displayed at beginning of deploy-k0rdent.sh
- [ ] Deployment end timestamp displayed upon completion
- [ ] Total deployment duration calculated and displayed in human-readable format
- [ ] Phase-level timing tracked (infrastructure setup VM creation k0s install etc)
- [ ] Timing information stored in deployment state for resume scenarios
