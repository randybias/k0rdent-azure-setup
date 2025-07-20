---
id: task-021
title: Azure CLI Output Format Standardization
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
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

## Current Issue

Mixed output formats across Azure CLI commands:
- Some commands use `--output tsv` for parsing
- Others use `--output table` for display
- Inconsistent parsing methods (cut, awk vs jq/yq) 
- TSV parsing can be slower and more error-prone than JSON

## Proposed Solution

Standardize on JSON output format:
- **Convert all `--output tsv` to `--output json`**: Update existing Azure CLI commands
- **Standardize JSON parsing**: Use consistent jq/yq parsing throughout codebase
- **Performance improvement**: JSON parsing is typically faster than TSV
- **Better error handling**: JSON provides structured error information
- **Consistent data structures**: Eliminates parsing inconsistencies

## Implementation Tasks

- Audit all Azure CLI commands in codebase for `--output` usage
- Convert TSV-based commands to JSON with equivalent jq/yq parsing
- Update any table output commands used for data extraction
- Test performance improvements
- Update any dependent parsing logic

## Benefits

- Faster command execution and parsing
- More reliable data extraction
- Consistent error handling
- Better maintainability
- Future-proof for complex data structures
