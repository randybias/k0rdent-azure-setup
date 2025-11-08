# Design: Configuration File Persistence and Tracking

## Architecture Overview

The solution enhances the existing deployment state tracking system to persist and retrieve the configuration file path across all deployment operations. This ensures consistent configuration usage throughout the deployment lifecycle.

## Current State Analysis

### Existing Configuration Loading

The current configuration loading mechanism in `etc/k0rdent-config.sh`:
1. Uses environment variable `K0RDENT_CONFIG_FILE` if set
2. Falls back to `./config/k0rdent.yaml`
3. Further falls back to `./config/k0rdent-default.yaml`

### Problem Scenario

```bash
# Deployment with custom config
./deploy-k0rdent.sh deploy --config config/k0rdent-baseline-westeu.yaml
# Deployment succeeds, config path is NOT persisted

# Later reset operation
./deploy-k0rdent.sh reset
# Uses ./config/k0rdent.yaml instead of the original file
# Results in configuration mismatch or file not found error
```

## Implementation Strategy

### 1. Configuration File Path Persistence

**State File Enhancement:**
```yaml
# In deployment-state.yaml
deployment:
  config_file: "config/k0rdent-baseline-westeu.yaml"
  config_last_modified: "2025-11-07T21:30:00Z"
  config_checksum: "abc123def456"
```

**Integration Points:**
- During deployment initialization: Capture and persist config file path
- During reset operations: Retrieve and use stored config file path
- During status/operations: Use tracked config for consistency

### 2. Configuration File Resolution Logic

**Enhanced Resolution Algorithm:**
```bash
resolve_config_file() {
    # Priority 1: Environment override (K0RDENT_CONFIG_FILE)
    # Priority 2: Tracked config file from state
    # Priority 3: Default config file search
    # Priority 4: Fallback to default template
}
```

**Resolution Flow:**
1. **Explicit Override**: If `K0RDENT_CONFIG_FILE` is set, use it (for manual overrides)
2. **State-Based**: If deployment config exists in state, validate and use it
3. **Default Search**: Standard config file search mechanism
4. **User Guidance**: Provide helpful messages for missing files

### 3. Configuration Validation and Migration

**Validation Checks:**
- File existence verification
- File modification time comparison
- Content checksum comparison
- YAML structure validation

**Migration Scenarios:**
```bash
# Scenario 1: Config file moved
deployment-state.yaml: config_file: "config/k0rdent-baseline-westeu.yaml"
# But file now at: "configs/production/config-k0rdent-baseline-westeu.yaml"
# Result: Warn and ask user for new path

# Scenario 2: Config file modified
# Original modified: 2025-11-07T21:30:00Z, checksum: abc123
# Current file modified: 2025-11-07T22:15:00Z, checksum: def456
# Result: Warn about configuration changes
```

## Technical Implementation Details

### 1. State Management Integration

**Configuration Persistence Function:**
```bash
persist_config_file_info() {
    local config_file="${1:-$CONFIG_YAML}"
    
    # Only persist if using custom config (not default)
    if [[ "$config_file" != "./config/k0rdent.yaml" ]]; then
        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local checksum=$(sha256sum "$config_file" | cut -d' ' -f1)
        local mtime=$(stat -f %m "$config_file" 2>/dev/null || stat -c %Y "$config_file" 2>/dev/null)
        
        yq eval ".deployment.config_file = \"$config_file\"" -i "$DEPLOYMENT_STATE_FILE"
        yq eval ".deployment.config_last_modified = \"$mtime\"" -i "$DEPLOYMENT_STATE_FILE"
        yq eval ".deployment.config_checksum = \"$checksum\"" -i "$DEPLOYMENT_STATE_FILE"
    fi
}
```

**Configuration Retrieval Function:**
```bash
get_tracked_config_file() {
    # Check for explicit override first
    if [[ -n "${K0RDENT_CONFIG_FILE:-}" ]]; then
        echo "$K0RDENT_CONFIG_FILE"
        return 0
    fi
    
    # Check state for tracked config
    local tracked_config=$(yq eval '.deployment.config_file' "$DEPLOYMENT_STATE_FILE" 2>/dev/null || echo "")
    if [[ -n "$tracked_config" && -f "$tracked_config" ]]; then
        # Validate file integrity
        validate_config_file_integrity "$tracked_config"
        echo "$tracked_config"
        return 0
    fi
    
    return 1  # No tracked valid config found
}
```

### 2. Enhanced k0rdent-config.sh Integration

**Modified Configuration Loading:**
```bash
# In etc/k0rdent-config.sh
# Allow caller to override the configuration file
CONFIG_FILE=$(get_tracked_config_file)
if [[ -n "$CONFIG_FILE" ]]; then
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "WARNING: Tracked config file not found: $CONFIG_FILE"
        echo "Falling back to default configuration search"
        unset CONFIG_FILE
    else
        CONFIG_YAML="$CONFIG_FILE"
    fi
fi

# Override with environment if explicitly set
if [[ -n "${K0RDENT_CONFIG_FILE:-}" ]]; then
    CONFIG_YAML="$K0RDENT_CONFIG_FILE"
fi
```

**Configuration Validation:**
```bash
validate_config_file_integrity() {
    local config_file="$1"
    local stored_checksum=$(yq eval '.deployment.config_checksum' "$DEPLOYMENT_STATE_FILE" 2>/dev/null || echo "")
    local stored_mtime=$(yq eval '.deployment.config_last_modified' "$DEPLOYMENT_STATE_FILE" 2>/dev/null || echo "")
    
    # Only validate if we have stored checksum/time
    if [[ -n "$stored_checksum" ]]; then
        local current_checksum=$(sha256sum "$config_file" | cut -d' ' -f1)
        local current_mtime=$(stat -f %m "$config_file" 2>/dev/null || stat -c %Y "$config_file" 2>/dev/null)
        
        if [[ "$current_checksum" != "$stored_checksum" ]]; then
            print_warning "Configuration file has been modified since deployment:"
            print_info "  Original: $stored_checksum (modified: $stored_mtime)"
            print_info "  Current:  $current_checksum (modified: $current_mtime)"
            print_info "  This may affect reset/operation behavior"
        fi
    fi
}
```

### 3. Deployment Operation Integration

**Operation Enhancement Points:**

**1. Deployment Initialization:**
```bash
# In deploy-k0rdent.sh, after config loading
if should_run_phase "prepare_deployment" ""; then
    persist_config_file_info "${CONFIG_FILE:-$CONFIG_YAML}"
fi
```

**2. Reset Operations:**
```bash
# In deploy-k0rdent.sh reset, at the beginning
print_header "Checking Deployment Configuration"
TRUSTED_CONFIG=$(get_tracked_config_file)
if [[ -n "$TRUSTED_CONFIG" ]]; then
    print_info "Using original deployment configuration: $TRUSTED_CONFIG"
    export K0RDENT_CONFIG_FILE="$TRUSTED_CONFIG"
else
    print_info "No tracked configuration found, using default search"
fi
```

**3. Status Operations:**
```bash
# In status display functions
local config_source="unknown"
if [[ -n "${K0RDENT_CONFIG_FILE:-}" ]]; then
    config_source="$K0RDENT_CONFIG_FILE (custom)"
else
    config_source="${CONFIG_YAML} (default)"
fi
print_info "Configuration source: $config_source"
```

## Error Handling and Fallback Scenarios

### Missing Configuration File
```bash
if [[ ! -f "$tracked_config" ]]; then
    print_warning "Original configuration file not found:"
    print_info "  Expected: $tracked_config"
    print_info ""
    print_info "Options:"
    print_info "  1. Create the missing file"
    print_info "  2. Run with --config to specify new location"
    print_info "  3. Continue with default configuration: --config ./config/k0rdent.yaml"
    echo ""
    read -p "How would you like to proceed? (default/new-skip): " -r choice
    
    case "$choice" in
        "new")
            read -p "Enter path to config file: " new_config
            if [[ -f "$new_config" ]]; then
                export K0RDENT_CONFIG_FILE="$new_config"
            else
                print_error "File not found: $new_config"
                exit 1
            fi
            ;;
        "skip")
            print_warning "Continuing with default configuration"
            unset K0RDENT_CONFIG_FILE
            ;;
        "default"|"")
            print_info "Using default configuration"
            export K0RDENT_CONFIG_FILE="./config/k0rdent.yaml"
            ;;
        *)
            print_info "Operation cancelled"
            exit 1
            ;;
    esac
fi
```

### Configuration File Changed
```bash
if [[ "$current_checksum" != "$stored_checksum" ]]; then
    print_warning "Configuration file content has changed since deployment"
    print_info "This may affect reset consistency and operation behavior"
    echo ""
    print_info "Options:"
    print_info "  1. Proceed with current configuration"
    print_info "  2. Cancel and review the changes"
    print_info "  3. Restore original configuration"
    echo ""
    read -p "Proceed with current configuration? (y/n): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        exit 1
    fi
fi
```

## Testing Strategy

### Unit Tests
- Configuration file path persistence and retrieval
- Fallback logic for missing or invalid files
- Checksum validation and change detection
- Environment variable override behavior

### Integration Tests
- Full deployment lifecycle with custom config
- Reset operations using tracked config
- Status and other operations with config consistency
- Error handling for missing/changed configuration files

### Edge Case Tests
- Configuration file moved to different location
- Configuration file content changes between operations
- Multiple configuration files with overlapping names
- Environment variable override scenarios

## Backward Compatibility

### Existing Deployments
- Deployments without tracked config will use standard config search
- No breaking changes to existing functionality
- Transparent upgrade path for existing state files

### Migration Strategy
- First run with upgraded code will start tracking custom configs
- Existing deployments continue working as before
- Gradual adoption of persistent config tracking

## Security Considerations

### Configuration File Access
- Validate file permissions before use
- Check for symlink redirection attacks
- Ensure configuration files are within expected paths

### Path Validation
- Normalize file paths to prevent directory traversal
- Validate that config files are within project directory
- Check for suspicious file names or locations

## Performance Impact

**Overhead:** Minimal
- Additional state file I/O operations
- Configuration file checksum calculation (once per operation)
- No performance impact on core deployment operations

**Optimizations:**
- Checksum calculation only if file exists and is not the default
- Lazy validation only when needed
- Config path caching within single operation session
