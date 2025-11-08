---
id: task-044
title: Refactor create-child scripts to extract common components
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - refactoring
dependencies: []
priority: medium
---

## Description

Refactor the create-child scripts to extract common components into a single support script, leaving only cloud-specific pieces in the per-cloud scripts.

## Acceptance Criteria

- [ ] Identify all common code between existing scripts
- [ ] Create etc/child-cluster-common.sh with common functions
- [ ] Update create-azure-child.sh to use common functions
- [ ] Update create-aws-child.sh to use common functions
- [ ] Ensure backward compatibility
- [ ] Create template for new cloud providers

## Current State

- Separate scripts for Azure (`create-azure-child.sh`) and AWS (`create-aws-child.sh`)
- Significant code duplication between scripts
- Common logic mixed with cloud-specific implementation
- Maintenance burden when updating common functionality

## Proposed Architecture

1. **Common Support Script** (`etc/child-cluster-common.sh`):
   - Cluster name validation and generation
   - k0rdent API interactions
   - ClusterDeployment resource creation
   - State tracking and management
   - Kubeconfig retrieval logic
   - Error handling and logging
   - Common validation functions

2. **Cloud-Specific Scripts** (minimal):
   - Cloud credential validation
   - Provider-specific template selection
   - Cloud-specific parameter validation
   - Call common functions with provider context

## Implementation Plan

1. **Analysis Phase**:
   - Identify all common code between existing scripts
   - Document cloud-specific requirements
   - Design common function interfaces

2. **Extraction Phase**:
   - Create `etc/child-cluster-common.sh`
   - Move common functions with parameters for cloud-specific values
   - Create standardized interfaces for cloud providers

3. **Refactor Phase**:
   - Update `create-azure-child.sh` to use common functions
   - Update `create-aws-child.sh` to use common functions
   - Ensure backward compatibility

4. **Extension Phase**:
   - Template for new cloud providers (GCP, etc.)
   - Documentation for adding new providers
   - Testing framework for all providers

## Benefits

- Reduced code duplication
- Easier maintenance and updates
- Consistent behavior across cloud providers
- Simpler addition of new cloud providers
- Single source of truth for child cluster logic
- Better testing coverage

## Technical Considerations

- Maintain existing script interfaces
- Preserve all current functionality
- Clear separation of concerns
- Extensible design for future providers
