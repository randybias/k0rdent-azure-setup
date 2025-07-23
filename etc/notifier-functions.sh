#!/usr/bin/env bash

# Notification functions for k0rdent deployments

# Send a desktop notification
# Usage: send_notification "title" "message" ["subtitle"] ["group"]
send_notification() {
    local title="$1"
    local message="$2"
    local subtitle="${3:-}"
    local group="${4:-k0rdent}"  # Default group, can be overridden
    
    # Try terminal-notifier first
    if command -v terminal-notifier >/dev/null 2>&1; then
        if [[ -n "$subtitle" ]]; then
            terminal-notifier -title "$title" -subtitle "$subtitle" -message "$message" -group "$group" -sound default
        else
            terminal-notifier -title "$title" -message "$message" -group "$group" -sound default
        fi
    else
        # Fallback to osascript
        osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
    fi
}

# Parse deployment event and send appropriate notification
# Usage: notify_deployment_event "event_json" ["notification_group"]
notify_deployment_event() {
    local event_json="$1"
    local notification_group="${2:-k0rdent}"  # Optional group name
    
    # Extract event details
    local timestamp=$(echo "$event_json" | jq -r '.timestamp // empty')
    local event_type=$(echo "$event_json" | jq -r '.event // empty')
    local phase=$(echo "$event_json" | jq -r '.phase // empty')
    local status=$(echo "$event_json" | jq -r '.status // empty')
    local message=$(echo "$event_json" | jq -r '.message // empty')
    local error=$(echo "$event_json" | jq -r '.error // empty')
    
    # Determine notification based on event type
    case "$event_type" in
        "deployment_started")
            send_notification "k0rdent Deployment Started" "Initializing deployment process" "Phase: $phase" "$notification_group"
            ;;
        "phase_started")
            case "$phase" in
                "prerequisites")
                    send_notification "Checking Prerequisites" "Validating system requirements" "$notification_group"
                    ;;
                "prepare_deployment")
                    send_notification "Preparing Deployment" "Generating keys and cloud-init" "$notification_group"
                    ;;
                "azure_network")
                    send_notification "Azure Network Setup" "Creating virtual network infrastructure" "$notification_group"
                    ;;
                "vms"|"azure_vms")
                    send_notification "Creating Virtual Machines" "Provisioning Azure VMs" "$notification_group"
                    ;;
                "vpn"|"wireguard")
                    send_notification "Setting up VPN" "Configuring WireGuard connection" "$notification_group"
                    ;;
                "k0s")
                    send_notification "Installing k0s" "Setting up Kubernetes cluster" "$notification_group"
                    ;;
                "k0rdent")
                    send_notification "Installing k0rdent" "Deploying k0rdent platform" "$notification_group"
                    ;;
                "azure_children")
                    send_notification "Azure Child Setup" "Configuring Azure child cluster support" "$notification_group"
                    ;;
                "kof")
                    send_notification "Installing KOF" "Deploying KOF components" "$notification_group"
                    ;;
                *)
                    send_notification "Phase Started" "$phase" "$message" "$notification_group"
                    ;;
            esac
            ;;
        "phase_completed")
            send_notification "✓ Phase Completed" "$phase completed successfully" "$message" "$notification_group"
            ;;
        "vm_created")
            local vm_name=$(echo "$event_json" | jq -r '.vm_name // "VM"')
            send_notification "VM Created" "$vm_name is ready" "$notification_group"
            ;;
        "vm_creation_started")
            send_notification "Creating VM" "$message" "$notification_group"
            ;;
        "preparation_started")
            send_notification "Preparing Deployment" "$message" "$notification_group"
            ;;
        "wireguard_ips_assigned")
            send_notification "WireGuard Setup" "IP addresses assigned" "$notification_group"
            ;;
        "wireguard_keys_generated")
            send_notification "WireGuard Setup" "Keys generated successfully" "$notification_group"
            ;;
        "cloud_init_generated")
            send_notification "Cloud-Init Ready" "Configuration files generated" "$notification_group"
            ;;
        "azure_rg_created")
            send_notification "Azure Setup" "$message" "$notification_group"
            ;;
        "azure_ssh_key_created")
            send_notification "Azure Setup" "SSH key imported" "$notification_group"
            ;;
        "azure_network_created")
            send_notification "Azure Network" "$message" "$notification_group"
            ;;
        "azure_setup_completed")
            send_notification "✓ Azure Setup Complete" "$message" "$notification_group"
            ;;
        "vpn_connected")
            send_notification "VPN Connected" "WireGuard tunnel established" "$notification_group"
            ;;
        "deployment_completed")
            # Extract duration from message if present
            if [[ "$message" =~ ([0-9]+)\ seconds ]]; then
                local duration="${BASH_REMATCH[1]}"
                local minutes=$((duration / 60))
                local seconds=$((duration % 60))
                send_notification "🎉 k0rdent Deployment Complete" "Completed in ${minutes}m ${seconds}s" "" "$notification_group"
            else
                send_notification "🎉 k0rdent Deployment Complete" "$message" "" "$notification_group"
            fi
            ;;
        "error")
            send_notification "❌ Deployment Error" "$error" "Phase: $phase" "$notification_group"
            ;;
        "deployment_failed")
            send_notification "❌ Deployment Failed" "Check logs for details" "Phase: $phase" "$notification_group"
            ;;
        *)
            # For other events, only notify if they seem important
            if [[ "$status" == "error" ]] || [[ "$status" == "failed" ]]; then
                send_notification "k0rdent Event" "$event_type" "$message" "$notification_group"
            fi
            ;;
    esac
}

# Check if notification commands are available
check_notification_support() {
    if command -v terminal-notifier >/dev/null 2>&1; then
        echo "Using terminal-notifier for desktop notifications"
        return 0
    elif command -v osascript >/dev/null 2>&1; then
        echo "Using osascript for desktop notifications"
        return 0
    else
        echo "ERROR: No notification method available on this system"
        return 1
    fi
}