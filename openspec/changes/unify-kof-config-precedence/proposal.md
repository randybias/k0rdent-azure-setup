# Proposal: Unify KOF Configuration Precedence

## Problem Statement

Currently, there are two independent mechanisms for enabling KOF:
1. CLI flag: `--with-kof` in `deploy-k0rdent.sh`
2. Configuration file: `kof.enabled: true` in YAML

This creates inconsistency and late-stage failures. When a user provides `--with-kof` flag, the deployment proceeds through all phases (network setup, VMs, VPN) only to fail during KOF installation with:

```
✗ KOF is not enabled in configuration
==> Set 'kof.enabled: true' in your k0rdent.yaml
```

This wastes time and resources since the failure occurs after significant infrastructure deployment.

## Current Behavior (Broken)

**Problem 1: Flag Required, YAML Ignored**
1. `deploy-k0rdent.sh` only checks `WITH_KOF` variable from `--with-kof` flag
2. Setting `kof.enabled: true` in YAML without flag = **KOF is NOT installed**
3. The YAML `kof.enabled` setting is completely ignored by the main deployment script

**Problem 2: Late-Stage Validation Failure**
1. User provides `--with-kof` flag (sets `WITH_KOF=true`)
2. Deployment proceeds through all phases (network, VMs, VPN, k0s, k0rdent)
3. KOF installation scripts check `kof.enabled` in YAML independently
4. If `kof.enabled: false`, installation fails after infrastructure is already deployed
5. No validation of KOF configuration happens early in the deployment

**Result**: Two disconnected checks mean KOF only installs when BOTH conditions are true, but they're checked at different times with no coordination.

## Proposed Solution

Implement standard CLI precedence model following industry best practices:

**Precedence Order (highest to lowest)**:
1. CLI flags (explicit user intent for this invocation)
2. Configuration file (persistent defaults)
3. Built-in defaults (fallback)

**Resolution Logic**:
- When `--with-kof` flag provided: Enable KOF regardless of YAML setting
- When no flag provided: Use `kof.enabled` value from YAML (true or false)
- Default: `kof.enabled: false` if not specified in YAML

**Early Validation**:
- When KOF is enabled (either by flag OR config), immediately validate KOF configuration
- Check required fields: `kof.version`, `kof.istio.version`, `kof.regional.domain`, etc.
- Fail fast before any infrastructure deployment begins
- Provide clear guidance on what needs to be fixed

## Key Design Decisions

### 1. CLI Flag Overrides Configuration
- `--with-kof` flag forces KOF enabled (overrides `kof.enabled: false`)
- No flag + `kof.enabled: true` = KOF enabled (respects configuration)
- No flag + `kof.enabled: false` = KOF disabled (respects configuration)
- Updates in-memory configuration to reflect resolved state
- Persists override in deployment state for consistency with downstream scripts

### 2. Early Configuration Validation
- Validate KOF configuration immediately after argument parsing
- Check before any Azure resources are created
- Provide actionable error messages with examples

### 3. Consistent State Tracking
- Store resolved configuration (with overrides applied) in deployment state
- Downstream scripts read from deployment state, not CLI flags
- Eliminates need for flag propagation through script chain

## Industry Best Practices

Based on research (POSIX standards, Git, Kubernetes, modern CLI tools):

**Standard Precedence**: Command line > Environment > User config > System config > Defaults

**Key Principles**:
- Command line arguments represent most immediate user intent
- Configuration files provide persistent, sharable defaults
- Explicit overrides trump implicit configuration
- Fail fast with clear validation messages

## Benefits

1. **Eliminates Confusion**: Single source of truth for feature enablement
2. **Saves Time**: Validates configuration before infrastructure deployment
3. **Better UX**: Clear error messages guide users to fix configuration
4. **Follows Standards**: Aligns with widely-accepted CLI precedence model
5. **Consistent State**: Deployment state reflects actual configuration used

## Risks and Mitigations

**Risk**: Users might forget to update YAML for subsequent deployments
**Mitigation**: Warn when CLI override differs from file, suggest updating YAML

**Risk**: Breaking change for existing workflows
**Mitigation**: Backwards compatible - existing behavior preserved when no flag provided

## Related Changes

This proposal affects:
- `deploy-k0rdent.sh`: Add early validation logic
- KOF installation scripts: Continue using `check_kof_enabled()` unchanged
- Deployment state: Store resolved configuration with overrides
- Documentation: Update to explain precedence model

## Success Criteria

1. **Flag overrides config**: `--with-kof` enables KOF even when `kof.enabled: false` in YAML
2. **Config works without flag**: `kof.enabled: true` in YAML installs KOF without requiring `--with-kof`
3. **Early validation**: Invalid KOF configuration detected before any Azure resources created
4. **Clear errors**: Error messages clearly indicate what configuration is missing/invalid
5. **Consistent state**: Deployment state contains resolved configuration for downstream scripts
6. **No late failures**: No configuration-related failures after infrastructure deployment
