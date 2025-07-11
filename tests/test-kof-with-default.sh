#!/usr/bin/env bash

# Test KOF functions with default config
set -euo pipefail

# Use default config for testing
export CONFIG_YAML="../config/k0rdent-default.yaml"

# Load functions
source ../etc/common-functions.sh
source ../etc/kof-functions.sh

print_header "Testing KOF Functions with Default Config"

# Test getting values
kof_enabled=$(get_kof_config "enabled" "unknown")
kof_version=$(get_kof_config "version" "unknown")
istio_version=$(get_kof_config "istio.version" "unknown")
mothership_ns=$(get_kof_config "mothership.namespace" "unknown")

print_info "KOF Enabled: $kof_enabled"
print_info "KOF Version: $kof_version"
print_info "Istio Version: $istio_version"
print_info "Mothership Namespace: $mothership_ns"

if [[ "$kof_version" == "1.1.0" ]] && [[ "$istio_version" == "1.1.0" ]] && [[ "$mothership_ns" == "kof" ]]; then
    print_success "All KOF configuration values read correctly from default config!"
else
    print_error "Some values not read correctly"
fi

# Test completed