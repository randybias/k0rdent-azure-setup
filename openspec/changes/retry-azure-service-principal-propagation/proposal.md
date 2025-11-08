# Change Proposal: Implement Service Principal Propagation Retry Logic

**Created**: 2025-11-07  
**Author**: Droid (droid@factory.ai)  
**Status:** Draft  

## Summary

The Azure credential setup script creates Service Principals but often fails to authenticate them immediately due to Azure propagation delays. The current implementation waits only 5 seconds and tries authentication once, leading to frequent failures when the Service Principal hasn't fully propagated through Azure's systems. This change implements robust retry logic with exponential backoff to handle Service Principal propagation delays within a reasonable time limit.

## Problem Statement

When running `./bin/setup-azure-cluster-deployment.sh setup`, the script frequently fails with:

```
✓ Service Principal created: 62754e91-a6bc-4759-a4b1-59a175d30799
✗ Failed to authenticate with the new Service Principal
✗ The Service Principal may need more time to propagate, or there may be a permissions issue
```

**Current Implementation Issues:**
1. **Fixed Wait Time**: Only waits 5 seconds before attempting authentication
2. **Single Attempt**: Tries authentication exactly once and fails immediately
3. **No Adaptive Logic**: All scenarios use the same fixed timeout regardless of environment conditions
4. **Poor User Experience**: Users must manually retry the entire setup process

## Proposed Solution

Implement intelligent retry logic with exponential backoff to handle Service Principal propagation delays:

1. **Exponential Backoff Retry**: Start with short intervals and increase retry duration
2. **Configurable Time Limit**: Default 5-minute maximum wait time with configurable overrides
3. **Progressive Feedback**: Show retry progress to users during extended wait periods
4. **Error Classification**: Distinguish between propagation delays vs actual permission issues
5. **Fallback Handling**: Provide clear guidance when retries are exhausted

## Scope

**In Scope:**
- Service Principal authentication retry logic in setup-azure-cluster-deployment.sh
- Exponential backoff implementation with configurable time limits
- User progress reporting during retry attempts
- Error classification and appropriate messaging
- Configuration options for retry behavior via environment variables

**Out of Scope:**
- Azure API optimization or propagation speed improvements
- Multi-cloud Service Principal handling (currently Azure-only)
- Long-term Service Principal health monitoring
- Automated Service Principal recreation on failures

## Success Criteria

1. Service Principal authentication succeeds >95% of the time when using retry logic
2. Maximum retry time is configurable and defaults to under 5 minutes
3. Users see clear progress indication during retry attempts
4. Actual permission errors are distinguished from propagation delays
5. Retry logic gracefully handles network interruptions and Azure API throttling

## Impact Analysis

- **Reliability**: Dramatically reduces Azure credential setup failures
- **User Experience**: Eliminates need for manual retries and uncertainty
- **Deployment Time**: Slightly increased initial setup time (for retries) but eliminates setup failures
- **Complexity**: Moderate increase in script complexity with manageable retry logic

## Dependencies

- Existing Service Principal creation logic in setup-azure-cluster-deployment.sh
- Azure CLI authentication methods and error handling
- Current k0rdent configuration and state management systems

## Considerations

- **Azure API Throttling**: Retry logic must respect Azure rate limits and handle throttling gracefully
- **Network Connectivity**: Retry attempts should be resilient to temporary network issues
- **Environment Variability**: Different Azure regions/tenants may have different propagation characteristics
- **User Control**: Allow users to override retry behavior via environment variables

## Technical Requirements

- **Retry Strategy**: Exponential backoff starting at 10秒, doubling each attempt up to 60秒 max
- **Total Timeout**: 300秒 (5 minutes) default, configurable via `AZURE_SP_PROPAGATION_TIMEOUT`
- **Retry Count**: Up to 12 attempts within timeout window
- **Progress Reporting**: Show attempt number and remaining time to users
- **Error Classification**: Distinguishes between various Azure authentication error types

## Implementation Priority

**High Priority:**
1. Core retry logic with exponential backoff
2. Progress reporting for user feedback
3. Error classification and appropriate messaging

**Medium Priority:**
1. Environment variable configuration options
2. Network resilience improvements
3. Enhanced error handling and logging

## Testing Strategy

- Simulated Azure authentication delays to validate retry behavior
- Testing with various Azure regions and account types
- Error injection scenarios (network, throttling, permission issues)
- Performance testing with different retry configurations
- User experience testing with progress reporting
