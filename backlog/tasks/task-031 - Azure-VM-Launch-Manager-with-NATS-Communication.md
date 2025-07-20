---
id: task-031
title: Azure VM Launch Manager with NATS Communication
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - architecture
  - future
dependencies: []
priority: low
---

## Description

Create a plan for an Azure VM launch manager script that uses NATS messaging to communicate state and issues back to the main loop for event-driven architecture.

## Acceptance Criteria

- [ ] Architecture plan documented
- [ ] Benefits and tradeoffs analyzed
- [ ] Implementation approach defined
- [ ] Message schema designed

## Current Architecture

- Background processes track individual VM creation PIDs
- Monitoring loop polls Azure API for VM states
- File-based state tracking via deployment-state.yaml

## Proposed Architecture

- **NATS Message Broker**: Central communication hub for VM creation events
- **VM Launch Workers**: Separate processes that handle VM creation and report via NATS
- **Main Orchestrator**: Subscribes to NATS topics for real-time state updates
- **Event-Driven Updates**: Replace polling with push-based status updates

## Benefits

- **Real-time Status**: Immediate notification of VM state changes
- **Reduced API Calls**: Workers push updates instead of constant polling
- **Better Scalability**: Can spawn multiple workers for parallel VM creation
- **Cleaner Architecture**: Decoupled components communicate via messages
- **Enhanced Debugging**: Message history provides audit trail

## Implementation Components

1. **NATS Server Setup**:
   - Local NATS server or container
   - Topic structure for VM events
   - Message schemas for state updates

2. **VM Launch Worker Script**:
   - Subscribes to VM creation requests
   - Executes `az vm create` commands
   - Publishes status updates to NATS
   - Handles retry logic independently

3. **Main Orchestrator Updates**:
   - Publishes VM creation requests to NATS
   - Subscribes to status update topics
   - Updates deployment-state.yaml based on messages
   - Coordinates overall deployment flow

## Technical Considerations

- NATS as additional dependency
- Message persistence requirements
- Error handling and dead letter queues
- Integration with existing state management
- Backward compatibility with current approach

## Message Topics Structure

- `vm.create.request` - VM creation requests
- `vm.create.status` - Status updates from workers
- `vm.create.complete` - Successful VM creation
- `vm.create.failed` - VM creation failures
- `vm.ssh.verified` - SSH connectivity confirmed
- `vm.cloudinit.complete` - Cloud-init finished

## Future Extensions

- Use NATS for other async operations
- Implement distributed tracing
- Add metrics collection via NATS
- Enable remote monitoring capabilities
