---
id: task-058
title: Validate k0rdent config for CPU architecture compatibility
status: To Do
assignee: []
created_date: '2025-08-13 10:30'
updated_date: '2025-08-13 10:50'
labels: []
dependencies: []
---

## Description

Add validation to ensure that the k0rdent configuration YAML doesn't deploy incompatible images to instances. This validation should check: 1) ARM vs x86 architecture compatibility between VM instance types and container/OS images, 2) Gen1 vs Gen2 x86 image compatibility with instance types. Prevent architecture and generation mismatches that would cause deployment failures.
## Acceptance Criteria

- [ ] Architecture validation logic implemented
- [ ] ARM images blocked from x86 instances
- [ ] x86 images blocked from ARM instances
- [ ] Gen1 x86 images blocked from Gen2-only instances
- [ ] Gen2 x86 images blocked from Gen1-only instances
- [ ] Validation runs during configure.sh init
- [ ] Clear error messages for architecture and generation mismatches
