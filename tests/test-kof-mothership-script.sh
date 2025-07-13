#!/usr/bin/env bash

# Test KOF mothership script functionality
set -euo pipefail

# Change to project root
cd ..

print_header() {
    echo ""
    echo "=== $1 ==="
}

print_info() {
    echo "=> $1"
}

print_success() {
    echo "✓ $1"
}

print_header "Testing KOF Mothership Script"

# Test 1: Help command
print_info "Test 1: Testing help command..."
if ./bin/install-kof-mothership.sh help | grep -q "Install KOF mothership"; then
    print_success "Help command works correctly"
else
    echo "✗ Help command failed"
fi

# Test 2: Status command (should show not enabled since we're using default config)
print_info "Test 2: Testing status command..."
if ./bin/install-kof-mothership.sh status | grep -q "KOF is not enabled"; then
    print_success "Status correctly shows KOF not enabled"
else
    echo "✗ Status command failed"
fi

# Test 3: Check prerequisites fail appropriately  
print_info "Test 3: Testing prerequisite checks..."
# This should fail because k0rdent is not installed in test environment
deploy_output=$(./bin/install-kof-mothership.sh deploy -y 2>&1 || true)
if echo "$deploy_output" | grep -q "k0rdent must be installed"; then
    print_success "Prerequisite checks work correctly"
else
    echo "✗ Prerequisite check should have failed"
    echo "Debug output: $deploy_output"
fi

print_header "All tests completed!"