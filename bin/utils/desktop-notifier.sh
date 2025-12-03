#!/usr/bin/env bash

# Desktop notifier daemon for k0rdent deployments
# Monitors deployment events and sends desktop notifications

set -euo pipefail

# Script directory resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source required functions
source "$ROOT_DIR/etc/notifier-functions.sh"

# Configuration - defaults
DEFAULT_EVENTS_FILE="$ROOT_DIR/state/deployment-events.yaml"
EVENTS_FILE=""
DEPLOYMENT_STATE_FILE="$ROOT_DIR/state/deployment-state.yaml"

# These will be set after parsing arguments
INSTANCE_NAME=""
PID_FILE=""
LAST_PROCESSED_FILE=""
LOG_FILE=""

# Function to set instance-specific paths
set_instance_paths() {
    # Use provided events file or default
    EVENTS_FILE="${EVENTS_FILE:-$DEFAULT_EVENTS_FILE}"
    
    # Derive instance name from events file (e.g., deployment, kof, azure)
    INSTANCE_NAME=$(basename "$EVENTS_FILE" | sed 's/-events\.yaml$//')
    
    # Instance-specific files
    PID_FILE="$ROOT_DIR/state/notifier-${INSTANCE_NAME}.pid"
    LAST_PROCESSED_FILE="$ROOT_DIR/state/notifier-${INSTANCE_NAME}-last-processed"
    LOG_FILE="$ROOT_DIR/state/notifier-${INSTANCE_NAME}.log"
}

# Help message
show_help() {
    cat << EOF
k0rdent Desktop Notifier

Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -e, --events-file FILE  Path to events file (default: state/deployment-events.json)
    -t, --test              Run in test mode with sample events
    -d, --daemon            Run as daemon (detach from terminal)
    -s, --stop              Stop the notifier daemon

DESCRIPTION:
    Monitors k0rdent deployment events and sends desktop notifications
    for important milestones and status changes.

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -e|--events-file)
                EVENTS_FILE="$2"
                shift 2
                ;;
            -t|--test)
                TEST_MODE=true
                shift
                ;;
            -d|--daemon)
                DAEMON_MODE=true
                shift
                ;;
            -s|--stop)
                # Need to set paths before stopping
                set_instance_paths
                stop_notifier
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Stop the notifier daemon
stop_notifier() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping $INSTANCE_NAME notifier daemon (PID: $pid)..."
            kill "$pid"
            rm -f "$PID_FILE" "$LAST_PROCESSED_FILE"
            echo "$INSTANCE_NAME notifier stopped."
        else
            echo "$INSTANCE_NAME notifier process not found (stale PID file)"
            rm -f "$PID_FILE" "$LAST_PROCESSED_FILE"
        fi
    else
        echo "$INSTANCE_NAME notifier is not running."
    fi
}

# Check if notifier is already running
check_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "$INSTANCE_NAME notifier is already running (PID: $pid)"
            exit 1
        else
            # Stale PID file
            rm -f "$PID_FILE"
        fi
    fi
}

# Cleanup on exit
cleanup() {
    echo "Cleaning up notifier..."
    rm -f "$PID_FILE" "$LAST_PROCESSED_FILE"
    exit 0
}

# Monitor events file using tail
monitor_events() {
    echo "Starting desktop notifier..."
    echo "Monitoring: $EVENTS_FILE"
    
    # Save PID
    echo $$ > "$PID_FILE"
    
    # Set up signal handlers
    trap cleanup SIGINT SIGTERM EXIT
    
    # Initialize last processed tracking
    local last_processed_time=""
    if [[ -f "$LAST_PROCESSED_FILE" ]]; then
        last_processed_time=$(cat "$LAST_PROCESSED_FILE")
    fi
    
    # Check notification support
    check_notification_support || exit 1
    
    # If events file doesn't exist yet, wait for it
    while [[ ! -f "$EVENTS_FILE" ]]; do
        echo "Waiting for events file to be created..."
        sleep 2
    done
    
    # Send initial notification
    send_notification "k0rdent Notifier Active" "Monitoring $INSTANCE_NAME events" "" "$INSTANCE_NAME"
    
    # Monitor the YAML file for changes and process new events
    local last_event_count=0
    if [[ -f "$LAST_PROCESSED_FILE" ]]; then
        last_event_count=$(cat "$LAST_PROCESSED_FILE")
    fi
    
    while true; do
        if [[ -f "$EVENTS_FILE" ]]; then
            # Get current event count
            local current_event_count=$(yq eval '.events | length' "$EVENTS_FILE" 2>/dev/null || echo 0)
            
            # Process new events
            if [[ $current_event_count -gt $last_event_count ]]; then
                # Process each new event
                for i in $(seq $((last_event_count)) $((current_event_count - 1))); do
                    local event_yaml=$(yq eval ".events[$i]" "$EVENTS_FILE" 2>/dev/null)
                    if [[ -n "$event_yaml" ]] && [[ "$event_yaml" != "null" ]]; then
                        # Convert YAML event to JSON for processing
                        local event_json=$(echo "$event_yaml" | yq eval -o=json)
                        
                        # Extract action as event type
                        local action=$(echo "$event_json" | jq -r '.action // empty')
                        if [[ -n "$action" ]]; then
                            # Add event field for compatibility
                            event_json=$(echo "$event_json" | jq --arg event "$action" '. + {event: $event}')

                            # Get phase from event data first (authoritative for phase_completed events)
                            # Fall back to state file for older events without phase field
                            local phase
                            phase=$(echo "$event_json" | jq -r '.phase // empty')
                            if [[ -z "$phase" ]]; then
                                # Fall back to state file for backward compatibility
                                if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
                                    phase=$(yq eval '.phase // "unknown"' "$DEPLOYMENT_STATE_FILE" 2>/dev/null || echo "unknown")
                                else
                                    phase="unknown"
                                fi
                                event_json=$(echo "$event_json" | jq --arg phase "$phase" '. + {phase: $phase}')
                            fi
                            
                            # Pass instance name as notification group
                            notify_deployment_event "$event_json" "$INSTANCE_NAME"
                        fi
                    fi
                done
                
                # Update last processed count
                last_event_count=$current_event_count
                echo "$last_event_count" > "$LAST_PROCESSED_FILE"
            fi
        fi
        
        # Check every 2 seconds
        sleep 2
    done
}

# Test mode - generate sample events
run_test_mode() {
    echo "Running in test mode..."
    
    # Create test state directory
    mkdir -p "$ROOT_DIR/state"
    
    # Create test events file
    local test_events_file="$ROOT_DIR/state/test-deployment-events.yaml"
    EVENTS_FILE="$test_events_file"
    # Update paths for test instance
    set_instance_paths
    
    # Start notifier in background
    echo "Starting notifier in background..."
    "$0" --events-file "$test_events_file" &
    local notifier_pid=$!
    
    sleep 2
    
    # Initialize test YAML file
    cat > "$test_events_file" << EOF
deployment_id: "test-deployment"
created_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
last_updated: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
events:
EOF
    
    # Generate test events
    echo "Generating test events..."
    
    # Deployment started
    yq eval '.events += [{"timestamp": "2025-01-23T10:00:00Z", "action": "deployment_started", "message": "Starting k0rdent deployment"}]' -i "$test_events_file"
    sleep 2
    
    # Prerequisites phase
    yq eval '.events += [{"timestamp": "2025-01-23T10:00:05Z", "action": "phase_started", "message": "Checking system requirements"}]' -i "$test_events_file"
    sleep 2
    yq eval '.events += [{"timestamp": "2025-01-23T10:00:10Z", "action": "phase_completed", "message": "All prerequisites satisfied"}]' -i "$test_events_file"
    sleep 2
    
    # VMs phase
    yq eval '.events += [{"timestamp": "2025-01-23T10:00:15Z", "action": "phase_started", "message": "Creating Azure VMs"}]' -i "$test_events_file"
    sleep 2
    yq eval '.events += [{"timestamp": "2025-01-23T10:00:20Z", "action": "vm_created", "message": "VM created successfully: k0rdent-controller-1"}]' -i "$test_events_file"
    sleep 2
    
    # Error event
    yq eval '.events += [{"timestamp": "2025-01-23T10:00:25Z", "action": "error", "message": "VM creation failed: quota exceeded"}]' -i "$test_events_file"
    sleep 2
    
    # Deployment completed
    yq eval '.events += [{"timestamp": "2025-01-23T10:00:30Z", "action": "deployment_completed", "message": "k0rdent deployment completed successfully"}]' -i "$test_events_file"
    sleep 3
    
    # Stop notifier
    echo "Stopping test notifier..."
    kill $notifier_pid 2>/dev/null || true
    
    # Cleanup
    rm -f "$test_events_file" "$PID_FILE" "$LAST_PROCESSED_FILE"
    
    echo "Test completed!"
}

# Main execution
main() {
    parse_args "$@"
    
    # Set instance-specific paths after parsing arguments
    set_instance_paths
    
    if [[ "${TEST_MODE:-false}" == "true" ]]; then
        run_test_mode
        exit 0
    fi
    
    # Check if already running
    check_running
    
    # Run as daemon if requested
    if [[ "${DAEMON_MODE:-false}" == "true" ]]; then
        echo "Starting notifier as daemon for instance: $INSTANCE_NAME"
        nohup "$0" --events-file "$EVENTS_FILE" > "$LOG_FILE" 2>&1 &
        echo "Notifier daemon started (PID: $!) for $INSTANCE_NAME"
        exit 0
    fi
    
    # Run in foreground
    monitor_events
}

# Run main function
main "$@"