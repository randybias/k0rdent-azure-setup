---
id: task-045
title: Migrate from WireGuard to Nebula Mesh VPN
status: To Do
assignee:
  - rbias
created_date: '2025-07-20'
updated_date: '2025-07-20'
labels:
  - enhancement
  - networking
  - nebula
dependencies: []
priority: medium
---

## Description

Plan migration from WireGuard to Nebula to avoid potential conflicts with other mesh VPN solutions, particularly WireGuard support in Calico CNI.

## Acceptance Criteria

- [ ] Research and prototype Nebula implementation
- [ ] Design certificate management approach
- [ ] Update network configuration for Nebula
- [ ] Modify cloud-init templates for Nebula installation
- [ ] Update bin/manage-vpn.sh for Nebula client configuration
- [ ] Test with various CNI configurations
- [ ] Create migration documentation

## Current Issues with WireGuard

- **CNI Conflicts**: Calico and other CNIs now include WireGuard support, creating potential conflicts
- **Port Conflicts**: WireGuard's fixed UDP port can conflict with CNI implementations
- **Interface Naming**: Potential wg0 interface naming conflicts between deployment VPN and CNI
- **Encryption Overhead**: Double encryption when both deployment VPN and CNI use WireGuard

## Benefits of Nebula

- **Certificate-based**: Uses certificate-based authentication instead of pre-shared keys
- **Built-in CA**: Integrated certificate authority for easier node management
- **Lighthouse Architecture**: Built-in NAT traversal and peer discovery
- **No Port Conflicts**: Different default ports and protocols from WireGuard
- **Better Scaling**: Designed for large-scale deployments
- **Firewall Rules**: Built-in host-based firewall rules in configuration

## Migration Plan Requirements

1. **Configuration Changes**:
   - Replace WireGuard network configuration with Nebula settings
   - Update cloud-init templates for Nebula installation
   - Modify network security group rules for Nebula ports

2. **Certificate Management**:
   - Implement Nebula CA certificate generation
   - Create host certificates for each VM
   - Secure certificate distribution during VM provisioning

3. **Script Updates**:
   - Update `bin/manage-vpn.sh` for Nebula client configuration
   - Modify VM provisioning scripts for Nebula setup
   - Update connectivity checks for Nebula

4. **Backward Compatibility**:
   - Support both WireGuard and Nebula during transition
   - Configuration option to choose VPN backend
   - Migration path for existing deployments

## Technical Considerations

- Nebula uses UDP port 4242 by default (configurable)
- Requires certificate generation and distribution
- Different configuration file format (YAML-based)
- Performance characteristics may differ from WireGuard

## Implementation Phases

1. **Phase 1**: Research and prototype Nebula implementation
2. **Phase 2**: Add Nebula as optional VPN backend
3. **Phase 3**: Test with various CNI configurations
4. **Phase 4**: Make Nebula the default VPN backend
5. **Phase 5**: Deprecate WireGuard support

## Dependencies

- Nebula binary availability in package repositories
- Certificate management implementation
- Update to all network-related scripts
- Documentation updates

## Testing Requirements

- Verify no conflicts with Calico WireGuard mode
- Test with other CNIs (Cilium, Weave)
- Performance comparison with WireGuard
- Multi-node connectivity testing
- Firewall rule validation
