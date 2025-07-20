---
id: task-016
title: Add Deployment Timing Metrics
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - high-priority
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

## Technical Details

### Current Behavior
- No clear indication of when deployment started
- No summary of total deployment time
- Difficult to track deployment performance or identify slow operations

### Expected Behavior
- Display deployment start timestamp at beginning of `deploy-k0rdent.sh`
- Display deployment end timestamp upon completion
- Calculate and display total deployment duration
- Format: "Deployment started at: 2025-07-14 10:30:00"
- Format: "Deployment completed at: 2025-07-14 10:55:30"
- Format: "Total deployment time: 25 minutes 30 seconds"

### Implementation Requirements
1. **Start Time Tracking**:
   - Record start timestamp when deployment begins
   - Display in human-readable format
   - Store in deployment state for resume scenarios

2. **End Time Tracking**:
   - Record completion timestamp
   - Display upon successful completion
   - Also display on failure with "failed after X minutes"

3. **Duration Calculation**:
   - Calculate elapsed time in seconds
   - Convert to human-readable format (hours, minutes, seconds)
   - Handle interrupted/resumed deployments appropriately

4. **State Integration**:
   - Store start_time in deployment-state.yaml
   - Update end_time on completion
   - Track individual phase durations for performance analysis

### Additional Features
- Display phase-level timing (infrastructure setup, VM creation, k0s install, etc.)
- Option to output timing metrics in machine-readable format
- Historical timing tracking in deployment events

### Benefits
- Better visibility into deployment performance
- Easier to identify slow operations
- Helpful for capacity planning and optimization
- Provides deployment duration expectations for users
- Useful for troubleshooting timeout issues

### Example Output
```
=== k0rdent Deployment Started ===
Deployment ID: k0rdent-abc123
Start Time: 2025-07-14 10:30:00 PST

[... deployment progress ...]

=== k0rdent Deployment Completed ===
End Time: 2025-07-14 10:55:30 PST
Total Duration: 25 minutes 30 seconds

Phase Timing Summary:
- Infrastructure Setup: 2 minutes 15 seconds
- VM Creation: 12 minutes 45 seconds
- k0s Installation: 8 minutes 20 seconds
- k0rdent Installation: 2 minutes 10 seconds
```
