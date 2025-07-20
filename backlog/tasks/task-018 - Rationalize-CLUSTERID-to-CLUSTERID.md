---
id: task-018
title: Rationalize CLUSTERID to CLUSTERID
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - enhancement
  - refactoring
  - naming
dependencies: []
priority: medium
---

## Description

The codebase currently uses both CLUSTERID concepts for cluster identification which creates confusion and inconsistency. These should be unified into a single CLUSTERID concept throughout the codebase. K0RDENT_CLUSTERID contains the full cluster identifier but suffix is extracted from prefix in various places.

## Acceptance Criteria

- [ ] All references to K0RDENT_CLUSTERID replaced with K0RDENT_CLUSTERID
- [ ] Suffix extraction logic removed throughout codebase
- [ ] Consistent naming pattern established
- [ ] All scripts configs and state files updated
- [ ] Documentation reflects new naming convention
