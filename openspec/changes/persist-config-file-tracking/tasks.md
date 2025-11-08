# Tasks for Configuration File Persistence and Tracking

## Implementation Tasks

### Task 001: Design Configuration File Tracking in State Management
- [ ] Analyze current deployment-state.yaml structure and identify best placement for config tracking
- [ ] Design configuration file metadata structure (path, checksum, modification time)
- [ ] Define backward compatibility strategy for existing deployments without config tracking
- [ ] Create configuration validation and change detection strategy
- [ ] Document configuration file resolution priority hierarchy

**Dependencies**: None  
**Estimated effort**: 2 hours

### Task 002: Create Configuration File Persistence Functions
- [ ] Implement `persist_config_file_info()` function in state-management.sh
- [ ] Create `get_tracked_config_file()` function for configuration retrieval
- [ ] Add configuration file validation utilities (checksum, modification time, existence)
- [ ] Implement `validate_config_file_integrity()` function for change detection
- [ ] Add configuration file path normalization and security validation
- [ ] Test persistence and retrieval functions with various configuration scenarios

**Dependencies**: Task 001  
**Estimated effort**: 3 hours

### Task 003: Enhance Configuration Loading Logic
- [ ] Modify `etc/k0rdent-config.sh` to use tracked configuration before default search
- [ ] Implement environment variable override logic (K0RDENT_CONFIG_FILE takes precedence)
- [ ] Add configuration file validation and change detection warnings
- [ ] Update configuration loading error handling for missing/invalid tracked configs
- [ ] Ensure backward compatibility for deployments without tracked config
- [ ] Test enhanced configuration loading with various scenarios

**Dependencies**: Task 002  
**Estimated effort**: 3 hours

### Task 004: Modify Deployment Initialization to Track Configuration
- [ ] Integrate `persist_config_file_info()` call into deployment initialization
- [ ] Add configuration tracking to new deployments only (skip for default config)
- [ ] Update deployment state file structure to include configuration metadata
- [ ] Test configuration tracking with both default and custom config files
- [ ] Validate configuration persistence survives deployment restarts and interruptions

**Dependencies**: Task 003  
**Estimated effort**: 2 hours

### Task 005: Update Reset Operations to Use Tracked Configuration
- [ ] Modify deploy-k0rdent.sh reset to use tracked configuration when available
- [ ] Add configuration validation at start of reset operations
- [ ] Implement user choice options for missing or changed configuration files
- [ ] Update reset error handling to handle configuration-related issues gracefully
- [ ] Test both full reset and fast reset with tracked configurations

**Dependencies**: Task 004  
**Estimated effort**: 3 hours

### Task 006: Update Status and Other Deployment Operations
- [ ] Modify status commands to use tracked configuration consistently
- [ ] Update all deployment operations (cleanup, validation, etc.) to respect tracked config
- [ ] Add configuration source display to status output
- [ ] Update help and usage documentation to reflect configuration tracking behavior
- [ ] Test all deployment operations with both tracked and untracked configurations

**Dependencies**: Task 005  
**Estimated effort**: 2 hours

### Task 007: Implement Configuration File Validation and Change Detection
- [ ] Add checksum calculation and comparison for configuration file change detection
- [ ] Implement modification time tracking for additional validation
- [ ] Create user-facing warnings and choices for configuration file changes
- [ ] Add configuration file existence and permission validation
- [ ] Test change detection with various file modification scenarios

**Dependencies**: Task 006  
**Estimated effort**: 3 hours

### Task 008: Add Error Handling and Fallback Mechanisms
- [ ] Implement missing configuration file error handling with user choice options
- [ ] Add configuration file corruption/format error recovery
- [ ] Create clear error messages and resolution guidance for configuration issues
- [ ] Implement graceful fallback to default configuration when appropriate
- [ ] Test error scenarios including missing files, permission issues, and corruption

**Dependencies**: Task 007  
**Estimated effort**: 2 hours

### Task 009: Create Configuration File Path Normalization and Security
- [ ] Implement path normalization (relative to absolute) for consistent tracking
- [ ] Add security validation to prevent directory traversal attacks
- [ ] Validate configuration file locations are within project directory bounds
- [ ] Handle edge cases for symbolic links and file system variations
- [ ] Test path normalization across different working directories and systems

**Dependencies**: Task 008  
**Estimated effort**: 2 hours

### Task 010: Create Comprehensive Test Suite
- [ ] Unit tests for configuration persistence and retrieval functions
- [ ] Integration tests for configuration loading with various scenarios
- [ ] End-to-end tests for deployment + reset lifecycle with custom configs
- [ ] Error handling tests for missing, changed, and corrupted configuration files
- [ ] Cross-platform compatibility tests for path handling

**Dependencies**: Task 009  
**Estimated effort**: 3 hours

### Task 011: Update Documentation and Usage Examples
- [ ] Update CLAUDE.md and AGENTS.md to reflect configuration tracking behavior
- [ ] Add usage examples for custom configuration files and tracking
- [ ] Create troubleshooting guide for configuration-related issues
- [ ] Update help text and command usage documentation
- [ ] Document backward compatibility and migration considerations

**Dependencies**: Task 010  
**Estimated effort**: 1.5 hours

## Testing Tasks

### Task 012: Manual User Testing Scenarios
- [ ] Test deployment with custom configuration file and subsequent reset
- [ ] Test configuration file moved between deployment and reset operations
- [ ] Test configuration file content changes between operations
- [ ] Test environment variable override behavior with tracked configurations
- [ ] Test deployment workflow with default configuration (no changes expected)

**Dependencies**: Task 011  
**Estimated effort**: 2 hours

### Task 013: Edge Case and Error Scenario Testing
- [ ] Test missing configuration file scenarios with user choice options
- [ ] Test corrupted/unreadable configuration file handling
- [ ] Test configuration file permission issues and resolution
- [ ] Test symbolic links and path normalization edge cases
- [ ] Test multiple configuration files with name conflicts

**Dependencies**: Task 012  
**Estimated effort**: 1.5 hours

### Task 014: Backward Compatibility Testing
- [ ] Test existing deployments without configuration tracking
- [ ] Test upgrade scenario from untracked to tracked configuration
- [ ] Verify default configuration behavior is unchanged for existing setups
- [ ] Test mixed deployment environments with some tracking and some not
- [ ] Validate rollback scenarios and state file compatibility

**Dependencies**: Task 013  
**Estimated effort**: 1.5 hours

## Total Estimated Effort: ~27.5 hours

## Implementation Sequence

**Phase 1** (Foundation): Tasks 001-003 - Design and core tracking infrastructure  
**Phase 2** (Integration): Tasks 004-006 - Integration with deployment operations  
**Phase 3** (Enhancement): Tasks 007-009 - Validation, error handling, and security  
**Phase 4** (Polish): Tasks 010-011 - Testing and documentation  
**Phase 5** (Validation): Tasks 012-014 - User testing and edge case validation

## Migration Strategy

**For Existing Deployments:**
- Continue using existing configuration loading logic
- No changes to current behavior until new deployment occurs
- Transparent upgrade path when users run new deployment with custom config

**For New Deployments:**
- Custom configuration files automatically tracked
- Consistent behavior across all deployment operations
- Enhanced error handling and validation

## Risk Mitigation

**High Risk Areas:**
- Configuration file access issues (mitigated by Task 008 security validation)
- Backward compatibility breaking changes (mitigated by Task 014 testing)
- Performance overhead of checksum calculation (minimal impact, only for custom configs)

**Medium Risk Areas:**
- User confusion over configuration choices (mitigated by clear error messages)
- Edge cases in path normalization (mitigated by comprehensive testing)
- Configuration file change detection false positives (mitigated by user choice)

## Success Criteria

1. ✅ Custom configuration files are tracked and reused across all deployment operations
2. ✅ Reset operations use the same configuration file as the original deployment
3. ✅ Clear error handling and guidance for missing or changed configuration files
4. ✅ Backward compatibility maintained for existing deployments
5. ✅ All deployment operations consistently use tracked configuration
6. ✅ Configuration file changes are detected and reported to users
7. ✅ Environment variable override behavior preserved
8. ✅ Security validation prevents configuration file attacks

## Rollback Plan

If issues arise:
- Revert to original configuration loading logic in k0rdent-config.sh
- Remove config tracking fields from state management (preserve other improvements)
- Update error handling and help text to reflect original behavior
- Ensure zero impact on deployments that never used custom configuration files

## Post-Implementation Benefits

1. Eliminates configuration file mismatch errors in reset operations
2. Provides predictable behavior across the entire deployment lifecycle
3. Improves user experience with automatic configuration consistency
4. Reduces support queries related to configuration file issues
5. Establishes foundation for future configuration management enhancements
