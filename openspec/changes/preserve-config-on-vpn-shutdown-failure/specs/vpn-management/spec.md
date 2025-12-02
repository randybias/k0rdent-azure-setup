# VPN Management Spec Delta

## ADDED Requirements

### Requirement: VPN reset preserves config on shutdown failure

The VPN reset operation MUST verify the WireGuard interface is fully down before deleting the configuration file. If the interface cannot be shut down, the config file MUST be preserved and the operation MUST return an error.

#### Scenario: Successful VPN shutdown during reset

- Given a WireGuard VPN is connected with config file at `./wireguard/wgk0xxx.conf`
- When the operator runs `./bin/manage-vpn.sh reset`
- And the `wg-quick down` command succeeds
- And the interface is verified as down
- Then the config file is deleted
- And the command returns success (exit 0)

#### Scenario: Failed VPN shutdown during reset

- Given a WireGuard VPN is connected with config file at `./wireguard/wgk0xxx.conf`
- When the operator runs `./bin/manage-vpn.sh reset`
- And the `wg-quick down` command fails or interface remains active
- Then the config file is preserved
- And an error message indicates manual intervention is required
- And the command returns failure (exit 1)
