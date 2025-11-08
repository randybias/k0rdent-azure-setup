---
id: task-023
title: Bicep-Based Multi-VM Deployment
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - azure
  - performance
dependencies: []
priority: low
---

## Description

Investigate using Azure Bicep templates to deploy multiple VMs simultaneously with individual cloud-init configurations in a single API call.

## Acceptance Criteria

- [ ] Research Bicep template structure for multiple VMs
- [ ] Design template for different VM configurations
- [ ] Test cloud-init parameter passing in Bicep
- [ ] Compare performance with current approach
- [ ] Implement deployment monitoring for Bicep
- [ ] Integrate with existing state management
- [ ] Document benefits and trade-offs

## Current Approach

Sequential VM creation with individual `az vm create` calls:
- Each VM created separately with its own API call
- Background processes track individual VM creation PIDs
- Multiple API calls increase deployment time and complexity

## Proposed Investigation

Bicep template for parallel VM deployment:
- **Single deployment call**: Use `az deployment group create` with Bicep template
- **Parallel VM creation**: Azure Resource Manager handles parallel provisioning
- **Individual cloud-init**: Each VM gets unique cloud-init configuration
- **Atomic deployment**: All-or-nothing deployment with rollback capability
- **Resource dependencies**: Proper dependency management within template

## Research Areas

- Bicep template structure for multiple VMs with different configurations
- Cloud-init parameter passing to individual VMs in template
- Deployment monitoring and status checking
- Error handling and rollback scenarios
- Integration with existing state management
- Performance comparison with current approach

## Potential Benefits

- Faster deployment through true parallelization
- Atomic deployments with built-in rollback
- Reduced API calls and complexity
- Better resource dependency management
- Native Azure tooling integration

## Technical Challenges

- Template complexity for different VM configurations
- Cloud-init file management and parameter passing
- State tracking integration with existing scripts
- Error handling and recovery logic adaptation
- Learning curve for Bicep template development

## Success Criteria

- Deployment time reduction compared to current approach
- Maintains all current functionality (zones, sizes, cloud-init)
- Integrates with existing state management
- Provides equivalent or better error handling
