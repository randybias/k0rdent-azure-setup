---
id: task-021
title: Azure CLI Output Format Standardization
status: To Do
assignee: []
created_date: '2025-07-20'
labels:
  - enhancement
  - azure
  - standardization
dependencies: []
priority: medium
---

## Description

Switch all Azure CLI commands to use native JSON output format instead of TSV for improved performance and consistency. Mixed output formats across Azure CLI commands with some using --output tsv for parsing and others using --output table for display.

## Acceptance Criteria

- [ ] All Azure CLI commands use --output json format
- [ ] Consistent jq/yq parsing throughout codebase
- [ ] TSV-based commands converted to JSON equivalent
- [ ] Performance improvements verified
- [ ] Error handling improved with structured JSON
