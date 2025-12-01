# Change: Upgrade KOF for k0rdent 1.5.0 Compatibility

## Why
k0rdent 1.5.0 moved Istio management from KOF to the k0rdent management cluster, fundamentally changing how KOF integrates with the service mesh. The current KOF implementation (v1.1.0-1.4.0) installs and manages its own Istio instance, which conflicts with k0rdent 1.5.0's approach where Istio is installed as part of the management cluster deployment.

This change is necessary to:
- Ensure KOF works correctly with k0rdent 1.5.0's centralized Istio management
- Remove duplicate Istio installation code from KOF scripts
- Align KOF with k0rdent's architectural direction
- Enable testing and validation of KOF with k0rdent 1.5.0

## What Changes
- **BREAKING**: Remove Istio installation from KOF mothership deployment
- **BREAKING**: Remove Istio installation from KOF functions library
- Add Istio discovery and validation to KOF installation workflow
- Update KOF configuration to remove Istio version/namespace configuration
- Add pre-flight checks to verify k0rdent's Istio is ready before KOF installation
- Update KOF uninstallation to skip Istio cleanup (managed by k0rdent)
- Upgrade default KOF version from 1.1.0/1.4.0 to latest compatible version
- Update configuration examples to reflect new KOF/Istio relationship
- Add comprehensive testing for KOF with k0rdent 1.5.0

## Impact
- **Affected specs**:
  - `kof-istio-integration` (NEW) - How KOF discovers and uses k0rdent's Istio
  - `kof-testing` (NEW) - Comprehensive testing approach for KOF

- **Affected code**:
  - `etc/kof-functions.sh` - Remove `install_istio_for_kof()`, modify `check_istio_installed()`
  - `bin/install-kof-mothership.sh` - Remove Istio installation step, add Istio validation
  - `bin/install-kof-regional.sh` - Update Istio references if any
  - `config/*.yaml` - Update KOF version, remove/update Istio config
  - `tests/test-kof-with-default.sh` - Update for new Istio approach

- **Breaking changes**:
  - KOF can no longer be installed without k0rdent 1.5.0's Istio
  - KOF configuration no longer controls Istio version or namespace
  - Installation order is enforced: k0rdent 1.5.0+ must be fully deployed before KOF

## Migration Path
Since backward compatibility is not required:
1. Update all KOF scripts to use k0rdent's Istio
2. Update all configuration files with new KOF version
3. Remove Istio-related configuration from KOF section
4. Add clear error messages if k0rdent 1.5.0 Istio not found

## Dependencies
- k0rdent 1.5.0+ must be deployed with Istio before KOF installation
- Existing Istio namespace discovery mechanism must work with k0rdent's Istio

## Risks
- KOF may have undocumented Istio version requirements not met by k0rdent 1.5.0's Istio
- k0rdent's Istio configuration may not meet KOF's needs (gateways, policies, etc.)
- Testing complexity increases - need k0rdent 1.5.0 environment for all KOF tests
