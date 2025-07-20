---
id: task-039
title: Refactor reasonable defaults from configurations
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

Extract reasonable defaults from all configuration examples into a centralized defaults file, allowing for smaller, cleaner configurations with sane defaults.

## Acceptance Criteria

- [ ] Analyze all example configurations for common values
- [ ] Create comprehensive defaults structure
- [ ] Update configuration loading to merge defaults with user config
- [ ] Simplify example configurations to show only overrides
- [ ] Document default values and override behavior

## Current Issues

- Configuration files contain many repeated values across examples
- Users must specify common values that could have sensible defaults
- Configuration files are larger than necessary
- Defaults are scattered or hardcoded in scripts

## Proposed Solution

- Create or enhance existing defaults file with common configuration values
- Extract repeated values from example configurations
- Implement hierarchical configuration loading (defaults → user config)
- Allow user configurations to override only what's needed

## Default Categories

- **VM Configurations**: Standard sizes, OS images, disk types
- **Network Settings**: Default CIDR ranges, subnet configurations
- **k0s Settings**: Version, common configurations
- **k0rdent Settings**: Standard deployment parameters
- **KOF Settings**: Default versions and namespaces
- **Azure Settings**: Common region defaults, resource naming patterns

## Implementation Approach

1. Analyze all example configurations for common values
2. Create comprehensive defaults structure
3. Update configuration loading to merge defaults with user config
4. Simplify example configurations to show only overrides
5. Document default values and override behavior

## Example Simplified Configuration

```yaml
# Before: Full configuration with all values
name: "minimal"
k0s:
  controller:
    count: 1
    size: "Standard_A4_v2"
  worker:
    count: 2
    size: "Standard_A4_v2"

# After: Only specify what differs from defaults
name: "minimal"
k0s:
  controller:
    count: 1
  worker:
    count: 2
```

## Benefits

- Cleaner, more maintainable configurations
- Easier to understand what's different from standard setup
- Reduced configuration errors
- Better upgrade path (update defaults centrally)
- Improved user experience with sensible defaults
