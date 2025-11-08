---
id: task-020
title: Azure API Optimization with Local Caching
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - performance
  - azure
dependencies: []
priority: medium
---

## Description

Cache Azure zone/region state data locally to reduce API calls and speed up deployment process. Multiple Azure API calls during deployment for data that rarely changes like VM size availability validation region capability checks and zone availability verification.

## Acceptance Criteria

- [ ] Local caching system implemented with timestamped data
- [ ] Cache includes VM size availability per region/zone
- [ ] Automatic cache refresh based on time expiration
- [ ] Cache validation and force refresh options available
- [ ] Fallback to live API calls if cache is stale/missing

## Current Issue

Multiple Azure API calls during deployment for data that rarely changes:
- VM size availability validation in specific zones/regions
- Region capability checks
- Zone availability verification
- Repeated calls for the same data across multiple deployments

## Proposed Solution

Implement local caching system with timestamped data:
- **Cache VM size availability**: Store validated VM sizes per region/zone with timestamp
- **Cache region capabilities**: Store region features and limits
- **Cache zone availability**: Store availability zone support per region
- **Automatic cache refresh**: Implement time-based cache expiration (e.g., 24 hours)
- **Cache validation**: Option to force cache refresh or validate cached data
- **Cache location**: Store in `~/.k0rdent/cache/` or similar location
- **Cache format**: JSON or YAML files with timestamp metadata

## Implementation Details

- Add caching functions to `etc/common-functions.sh`
- Integrate with existing validation scripts
- Add cache management commands (clear, refresh, status)
- Implement cache expiration logic
- Add fallback to live API calls if cache is stale/missing

## Benefits

- Faster deployment times (reduced API latency)
- Reduced Azure API throttling risk
- Better offline capability for validation
- Improved user experience with faster feedback

## Cache Structure Example

```yaml
metadata:
  last_updated: "2025-06-18T10:30:00Z"
  cache_version: "1.0"
regions:
  westus2:
    vm_sizes:
      Standard_B2s: 
        zones: [1, 2, 3]
        validated: "2025-06-18T10:30:00Z"
      Standard_D4s_v5:
        zones: [1, 2]
        validated: "2025-06-18T10:30:00Z"
```
