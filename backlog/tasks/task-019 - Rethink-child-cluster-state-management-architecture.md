---
id: task-019
title: Rethink child cluster state management architecture
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - architecture
  - state-management
dependencies: []
priority: medium
---

## Description

Current local cluster state tracking duplicates information that k0rdent already manages, creating potential inconsistencies and maintenance overhead. The architecture should be redesigned with k0rdent as the single source of truth for cluster state while local files only track operational events and history.

## Acceptance Criteria

- [ ] k0rdent is the single source of truth for cluster state
- [ ] Local files only track operational events and history
- [ ] Scripts query kubectl for live cluster status
- [ ] State synchronization complexity eliminated
- [ ] Event-driven local tracking implemented

## Current Issues

- Local state files duplicate cluster configuration and status from k0rdent
- State synchronization required to maintain consistency  
- Risk of local state becoming stale or conflicting with k0rdent reality
- Overhead of maintaining parallel state tracking

## Proposed Architecture

- **k0rdent as Source of Truth**: All cluster state (status, configuration, readiness) comes from k0rdent ClusterDeployments
- **Local Event Tracking Only**: Local files track operational events and history:
  - When clusters were created/deleted
  - Who initiated operations
  - Deployment parameters used
  - Operational notes and troubleshooting history
  - Local development context
- **Query k0rdent for Current State**: Scripts query kubectl for live cluster status rather than local files
- **Event-Driven Updates**: Local events appended when operations occur, but no state duplication

## Benefits

- Eliminates state synchronization complexity
- Reduces inconsistency risks  
- Aligns with "cattle not pets" philosophy
- Simpler mental model: k0rdent owns state, local owns history
- Better separation of concerns

## Implementation Strategy

1. **Phase 1**: Modify existing scripts to query k0rdent directly for current state
2. **Phase 2**: Convert local state files to pure event logs
3. **Phase 3**: Remove state synchronization logic
4. **Phase 4**: Add rich event tracking for operational history

## Event Log Structure Example

```yaml
cluster_name: "my-cluster"
events:
  - timestamp: "2025-07-11T14:30:00Z"
    action: "cluster_created"
    user: "rbias"
    parameters:
      location: "eastus"
      instance_sizes: "Standard_A4_v2"
    command: "create-child.sh --cluster-name my-cluster ..."
  - timestamp: "2025-07-11T15:45:00Z"
    action: "cluster_deleted"
    user: "rbias"
    reason: "testing completed"
```

**Backward Compatibility**: Transition can be gradual with existing state files continuing to work during migration.
