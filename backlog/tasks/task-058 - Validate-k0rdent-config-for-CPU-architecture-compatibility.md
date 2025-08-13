---
id: task-058
title: Validate k0rdent config for CPU architecture compatibility
status: To Do
assignee: []
created_date: '2025-08-13 10:30'
labels: []
dependencies: []
---

## Description

Add validation to ensure that the k0rdent configuration YAML doesn't deploy ARM images to x86 instances or vice versa. This validation should check the VM instance types against the container/OS images to prevent architecture mismatches that would cause deployment failures.

## Acceptance Criteria

- [ ] Architecture validation logic implemented
- [ ] ARM images blocked from x86 instances
- [ ] x86 images blocked from ARM instances
- [ ] Validation runs during configure.sh init
- [ ] Clear error messages for architecture mismatches
