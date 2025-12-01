# Design: KOF Integration with k0rdent 1.5.0 Istio

## Context
KOF (K0rdent Operations Framework) historically managed its own Istio installation as part of the mothership deployment. With k0rdent 1.5.0, Istio management moved to the k0rdent management cluster, creating an architectural shift where:

- k0rdent 1.5.0 installs and manages Istio during management cluster deployment
- KOF should discover and use this existing Istio instance
- No separate Istio installation by KOF is needed or desired
- Istio configuration is controlled by k0rdent, not KOF

Current KOF implementation:
- Installs Istio via `install_istio_for_kof()` function
- Uses `oci://ghcr.io/k0rdent/kof/charts/kof-istio` Helm chart
- Configures Istio namespace, version, and settings via KOF YAML config
- Waits for Sveltos CRDs before Istio installation

## Goals / Non-Goals

### Goals
- Remove all Istio installation code from KOF scripts
- Add robust Istio discovery and validation
- Ensure KOF works correctly with k0rdent 1.5.0's Istio
- Provide clear error messages if k0rdent Istio not ready
- Maintain KOF's existing functionality (mothership, regional clusters)
- Support comprehensive testing with k0rdent 1.5.0

### Non-Goals
- Backward compatibility with KOF's self-managed Istio
- Support for KOF without k0rdent 1.5.0
- Custom Istio configuration from KOF
- Fallback to KOF-managed Istio if k0rdent's is missing

## Decisions

### Decision 1: Istio Discovery Approach
**Choice**: Use namespace and deployment checks to validate k0rdent's Istio

**Rationale**:
- k0rdent installs Istio in `istio-system` namespace (standard)
- Can verify critical components: istiod, ingress gateway
- Provides clear feedback on what's missing
- Aligns with existing `check_istio_installed()` pattern

**Alternatives considered**:
- Query k0rdent for Istio status → More complex, requires k0rdent API knowledge
- Assume Istio present if k0rdent deployed → Risky, silent failures possible
- Wait indefinitely for Istio → Poor user experience, no timeout

### Decision 2: Pre-flight Validation
**Choice**: Add comprehensive Istio validation before KOF operator installation

**Implementation**:
- Check `istio-system` namespace exists
- Verify `istiod` deployment is ready (replicas > 0)
- Verify istio-ingressgateway service exists
- Optionally check Istio version compatibility

**Rationale**:
- Fail fast with clear error messages
- Prevent partial KOF installation failures
- Guide users to fix k0rdent Istio issues first

### Decision 3: Configuration Cleanup
**Choice**: Remove Istio configuration from KOF YAML sections

**Removed**:
```yaml
kof:
  istio:
    version: "1.1.0"        # Removed - k0rdent controls version
    namespace: "istio-system"  # Removed - standard namespace assumed
```

**Retained**:
```yaml
kof:
  enabled: false
  version: "1.4.0"  # Updated to latest compatible version
  mothership:
    namespace: "kof"
    storage_class: "default"
  regional:
    # ... regional config remains
```

**Rationale**:
- KOF no longer controls Istio
- Simplifies configuration
- Reduces confusion about who manages Istio
- Still allows discovery of non-standard Istio namespace if needed

### Decision 4: Error Handling Strategy
**Choice**: Clear, actionable error messages with specific remediation steps

**Example messages**:
```
ERROR: Istio not found in istio-system namespace
Cause: k0rdent 1.5.0 Istio not deployed or not ready
Action: Verify k0rdent deployment completed successfully
Check: kubectl get deployment -n istio-system istiod
```

**Rationale**:
- Users need clear guidance on fixing issues
- Distinguishes between k0rdent Istio issues vs KOF issues
- Reduces troubleshooting time

### Decision 5: KOF Version Strategy
**Choice**: Upgrade to latest KOF version compatible with k0rdent 1.5.0

**Rationale**:
- KOF releases are tied to k0rdent releases
- Version 1.4.0+ likely targets k0rdent 1.5.0 changes
- Default config shows 1.1.0 (very old) and 1.4.0 (newer)
- Research needed to identify correct version for k0rdent 1.5.0

**Action items**:
- Investigate KOF 1.5.0 release if available
- Check KOF release notes for k0rdent 1.5.0 compatibility
- Update default version in all config files

### Decision 6: Uninstallation Changes
**Choice**: Skip Istio cleanup during KOF uninstallation

**Current behavior**:
```bash
if check_istio_installed; then
    if helm uninstall kof-istio -n "$istio_namespace" --wait; then
        # Cleanup Istio
    fi
fi
```

**New behavior**:
```bash
# Skip Istio cleanup - managed by k0rdent
print_info "Istio managed by k0rdent - not removing"
```

**Rationale**:
- k0rdent owns Istio lifecycle
- Removing k0rdent's Istio would break management cluster
- Clear separation of responsibilities

## Architecture Changes

### Before (KOF with self-managed Istio)
```
┌─────────────────────────────────────┐
│ k0rdent Management Cluster          │
│                                     │
│  ┌────────────┐                    │
│  │ k0rdent    │                    │
│  │ (no Istio) │                    │
│  └────────────┘                    │
│                                     │
│  ┌────────────────────────────┐    │
│  │ KOF                        │    │
│  │  - Installs Istio          │    │
│  │  - Configures Istio        │    │
│  │  - Manages Istio lifecycle │    │
│  └────────────────────────────┘    │
└─────────────────────────────────────┘
```

### After (KOF with k0rdent-managed Istio)
```
┌─────────────────────────────────────┐
│ k0rdent Management Cluster          │
│                                     │
│  ┌────────────────────────┐         │
│  │ k0rdent 1.5.0          │         │
│  │  - Installs Istio      │         │
│  │  - Configures Istio    │         │
│  │  - Manages Istio       │         │
│  └────────────────────────┘         │
│           │                         │
│           ▼                         │
│  ┌────────────────────────┐         │
│  │ Istio (istio-system)   │         │
│  └────────────────────────┘         │
│           │                         │
│           ▼ (uses)                  │
│  ┌────────────────────────┐         │
│  │ KOF                    │         │
│  │  - Discovers Istio     │         │
│  │  - Validates Istio     │         │
│  │  - Uses Istio          │         │
│  └────────────────────────┘         │
└─────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Code Cleanup
- Remove `install_istio_for_kof()` from `etc/kof-functions.sh`
- Remove Istio installation step from `bin/install-kof-mothership.sh`
- Remove Istio uninstall logic from cleanup functions
- Update `check_istio_installed()` to be validation-focused

### Phase 2: Validation Logic
- Add `validate_k0rdent_istio()` function
- Check namespace, istiod deployment, ingress gateway
- Add timeout and retry logic for transient issues
- Return detailed error information

### Phase 3: Configuration Updates
- Remove Istio config from all YAML files
- Update KOF version to k0rdent 1.5.0 compatible version
- Update configuration examples
- Add migration notes to YAML comments

### Phase 4: Testing Infrastructure
- Create test scenarios for KOF with k0rdent 1.5.0
- Test Istio discovery and validation
- Test KOF mothership installation
- Test KOF regional cluster deployment
- Test error cases (Istio not ready, wrong version, etc.)

## Risks / Trade-offs

### Risk 1: KOF-Istio Version Compatibility
**Risk**: KOF may require specific Istio version not provided by k0rdent 1.5.0
**Impact**: HIGH - KOF installation could fail
**Mitigation**:
- Research KOF Istio requirements early
- Add version compatibility check
- Document version requirements clearly
- Test with actual k0rdent 1.5.0 Istio

### Risk 2: Istio Configuration Mismatch
**Risk**: k0rdent's Istio may lack features KOF needs (gateways, policies)
**Impact**: MEDIUM - Some KOF features may not work
**Mitigation**:
- Document k0rdent Istio requirements for KOF
- Add feature detection checks
- Provide clear error messages if features missing
- Consider if KOF can configure additional Istio resources

### Risk 3: Testing Complexity
**Risk**: All KOF testing now requires full k0rdent 1.5.0 deployment
**Impact**: MEDIUM - Slower test cycles, more complex CI/CD
**Mitigation**:
- Create minimal k0rdent 1.5.0 test configuration
- Document test setup clearly
- Consider mock/stub approaches for unit tests
- Maintain integration test suite

### Risk 4: Upgrade Path Confusion
**Risk**: Users with existing KOF deployments may be confused by changes
**Impact**: LOW - Backward compatibility not required per requirements
**Mitigation**:
- Clear documentation of breaking changes
- Explicit version requirements (k0rdent 1.5.0+)
- Error messages guide users to correct approach

### Trade-off 1: Simplicity vs Flexibility
**Choice**: Hard-coded Istio namespace (istio-system) vs configurable
**Decision**: Hard-coded initially, add config if needed
**Rationale**: k0rdent 1.5.0 uses standard namespace, YAGNI principle

### Trade-off 2: Fail Fast vs Resilient
**Choice**: Strict validation vs lenient checks
**Decision**: Strict validation with clear errors
**Rationale**: Better to fail early than partially deploy

## Migration Plan

### For Users
Since backward compatibility is not required:

1. **Fresh installs**: Use new KOF version, works automatically with k0rdent 1.5.0
2. **Existing KOF deployments**: Must uninstall old KOF, upgrade k0rdent to 1.5.0, reinstall KOF
3. **Configuration changes**: Remove Istio section from KOF config, update KOF version

### For Development
1. Update code in feature branch
2. Test with k0rdent 1.5.0 environment
3. Validate all test scenarios pass
4. Update documentation
5. Merge to main

## Testing Strategy

### Unit Tests
- Istio discovery function with various namespace states
- Validation logic with different deployment states
- Error message generation

### Integration Tests
- KOF mothership installation with k0rdent 1.5.0 Istio
- KOF regional cluster deployment
- Istio validation during installation
- Error cases (missing Istio, not ready, etc.)

### E2E Tests
- Full k0rdent 1.5.0 + KOF deployment
- Verify KOF functionality with k0rdent Istio
- Test KOF features requiring Istio (ingress, mesh, etc.)

## Open Questions

1. **Q**: What is the correct KOF version for k0rdent 1.5.0?
   **A**: Research needed - check KOF releases and compatibility matrix

2. **Q**: Does k0rdent 1.5.0 Istio include all features KOF needs?
   **A**: Testing required - deploy both and verify KOF functionality

3. **Q**: Are there Istio version constraints for KOF?
   **A**: Check KOF documentation and Helm chart requirements

4. **Q**: Should we validate Istio version or just presence?
   **A**: Start with presence, add version check if compatibility issues found

5. **Q**: How to handle custom Istio configurations users may need for KOF?
   **A**: Document that k0rdent Istio config must meet KOF needs, users configure via k0rdent

## Success Criteria

- [ ] All Istio installation code removed from KOF scripts
- [ ] KOF successfully installs with k0rdent 1.5.0 Istio
- [ ] KOF mothership functions correctly
- [ ] KOF regional clusters deploy correctly
- [ ] Clear error messages if k0rdent Istio not ready
- [ ] All tests pass with k0rdent 1.5.0
- [ ] Configuration files updated and validated
- [ ] Documentation reflects new architecture
