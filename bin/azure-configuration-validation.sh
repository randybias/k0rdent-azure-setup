#!/usr/bin/env bash

# azure-configuration-validation.sh
# Validates Azure VM size availability in specified zones

set -euo pipefail

# Load configuration
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh

# Cache for VM availability to avoid duplicate API calls
declare -A VM_AVAILABILITY_CACHE

# Get VM availability for a size (caches result)
get_vm_availability() {
    local location="$1"
    local vm_size="$2"
    
    # Check cache first
    local cache_key="${location}:${vm_size}"
    if [[ -n "${VM_AVAILABILITY_CACHE[$cache_key]:-}" ]]; then
        echo "${VM_AVAILABILITY_CACHE[$cache_key]}"
        return 0
    fi
    
    # Get SKU info in YAML format
    local sku_info
    sku_info=$(az vm list-skus \
        --location "$location" \
        --size "$vm_size" \
        --output yaml 2>/dev/null || echo "")
    
    if [[ -z "$sku_info" ]]; then
        VM_AVAILABILITY_CACHE[$cache_key]="none"
        echo "none"
        return 0
    fi
    
    # Extract zones using yq
    local zones_available
    zones_available=$(echo "$sku_info" | yq eval '.[0].locationInfo[0].zones[]' - 2>/dev/null | tr '\n' ' ' || echo "")
    
    if [[ -z "$zones_available" ]]; then
        VM_AVAILABILITY_CACHE[$cache_key]="regional"
        echo "regional"
    else
        VM_AVAILABILITY_CACHE[$cache_key]="$zones_available"
        echo "$zones_available"
    fi
}

validate_vm_configuration() {
    local location="$1"
    local vm_size="$2"
    local vm_type="$3"
    local -a zones=("${!4}")
    
    print_info "Checking $vm_type VM: $vm_size in $location..."
    
    # Get availability once for this VM size
    local available_zones
    available_zones=$(get_vm_availability "$location" "$vm_size")
    
    if [[ "$available_zones" == "none" ]]; then
        print_error "$vm_type: $vm_size is NOT available in $location"
        return 1
    elif [[ "$available_zones" == "regional" ]]; then
        print_warning "$vm_type: $vm_size is available in $location but NOT in availability zones"
        print_info "Consider removing zone specifications for regional deployment"
        return 1
    else
        # Check each requested zone
        local all_zones_valid=true
        for zone in "${zones[@]}"; do
            if echo " $available_zones " | grep -q " $zone "; then
                print_success "$vm_type: $vm_size is available in zone $zone"
            else
                print_error "$vm_type: $vm_size is NOT available in zone $zone"
                all_zones_valid=false
            fi
        done
        
        if [[ "$all_zones_valid" == "false" ]]; then
            print_info "Available zones for $vm_size: $available_zones"
            return 1
        fi
        
        return 0
    fi
}

main() {
    print_header "Azure VM Configuration Validation"
    echo "Location: $AZURE_LOCATION"
    echo
    
    # Check required tools
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is required but not installed"
        exit 1
    fi
    
    if ! command -v yq &> /dev/null; then
        print_error "yq is required but not installed"
        print_info "Install yq: https://github.com/mikefarah/yq"
        exit 1
    fi
    
    local validation_passed=true
    
    # Validate controller VMs
    print_info "Validating controller configuration..."
    if ! validate_vm_configuration "$AZURE_LOCATION" "$AZURE_CONTROLLER_VM_SIZE" "Controller" CONTROLLER_ZONES[@]; then
        validation_passed=false
    fi
    
    # Validate worker VMs (only if different from controller)
    if [[ "$AZURE_WORKER_VM_SIZE" != "$AZURE_CONTROLLER_VM_SIZE" ]]; then
        echo
        print_info "Validating worker configuration..."
        if ! validate_vm_configuration "$AZURE_LOCATION" "$AZURE_WORKER_VM_SIZE" "Worker" WORKER_ZONES[@]; then
            validation_passed=false
        fi
    else
        echo
        print_info "Worker VMs use same size as controllers - validation already complete"
    fi
    
    echo
    if [[ "$validation_passed" == "true" ]]; then
        print_success "All VM sizes are available in specified zones!"
    else
        print_error "Some VM sizes are not available in specified zones."
        echo
        echo "Options to fix:"
        echo "1. Change to zones where the VMs are available"
        echo "2. Remove zone specifications for regional deployment"
        echo "3. Choose different VM sizes"
        exit 1
    fi
}

# Run validation
main