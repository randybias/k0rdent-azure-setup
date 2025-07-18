#!/bin/bash

# Build script for WireGuard setuid wrapper
# This creates a setuid root binary that can run WireGuard commands without sudo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/code/wg-wrapper.c"
BINARY_NAME="wg-wrapper"
BINARY_PATH="$SCRIPT_DIR/$BINARY_NAME"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# Check if source file exists
if [ ! -f "$SOURCE_FILE" ]; then
    print_error "Source file not found: $SOURCE_FILE"
    exit 1
fi

# Check if we have a C compiler
if ! command -v cc &> /dev/null; then
    print_error "C compiler (cc) not found. Please install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

# Clean up any existing binary
if [ -f "$BINARY_PATH" ]; then
    print_warning "Removing existing binary: $BINARY_PATH"
    rm -f "$BINARY_PATH"
fi

# Compile the wrapper
echo "Compiling WireGuard wrapper..."
if cc -o "$BINARY_PATH" "$SOURCE_FILE" -Wall -Wextra -O2; then
    print_success "Compilation successful"
else
    print_error "Compilation failed"
    exit 1
fi

# Set ownership and permissions (requires sudo)
echo ""
echo "Setting setuid permissions (requires sudo)..."
if sudo chown root:wheel "$BINARY_PATH" && sudo chmod 4755 "$BINARY_PATH"; then
    print_success "Setuid permissions applied"
else
    print_error "Failed to set permissions"
    exit 1
fi

# Verify the binary
echo ""
echo "Verifying binary..."
if [ -f "$BINARY_PATH" ]; then
    ls -la "$BINARY_PATH"
    print_success "WireGuard wrapper built successfully at: $BINARY_PATH"
    echo ""
    echo "Usage:"
    echo "  $BINARY_PATH wg-show [interface]"
    echo "  $BINARY_PATH wg-quick-up <interface>"
    echo "  $BINARY_PATH wg-quick-down <interface>"
else
    print_error "Binary not found after build"
    exit 1
fi