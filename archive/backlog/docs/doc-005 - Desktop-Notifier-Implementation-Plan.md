---
id: doc-005
title: Desktop Notifier Implementation Plan
type: design
created_date: '2025-07-22'
---

# Desktop Notifier Implementation Plan

## Overview

This document outlines the implementation plan for adding desktop notifications to k0rdent deployments on macOS. The feature will monitor deployment events in real-time and send desktop notifications for key deployment milestones.

## Requirements

- Monitor `state/deployment-events.yaml` for new events
- Send desktop notifications for important deployment events
- Run asynchronously without blocking deployment
- Activated via `--with-desktop-notifications` flag
- Clean process management (start/stop with deployment)
- macOS-specific implementation

## Notification Methods Research

### 1. osascript (AppleScript)
**Pros:**
- Built into macOS (no dependencies)
- Simple to implement
- Reliable

**Cons:**
- Limited customization
- No action buttons
- Basic styling only

**Example:**
```bash
osascript -e 'display notification "VM creation completed" with title "k0rdent Deployment" subtitle "Phase: Infrastructure"'
```

### 2. terminal-notifier
**Pros:**
- Rich notifications with actions
- Can include images/sounds
- Homebrew installable
- Better customization

**Cons:**
- External dependency
- Requires Homebrew

**Example:**
```bash
terminal-notifier -title "k0rdent Deployment" -subtitle "Phase: Infrastructure" -message "VM creation completed" -sound default
```

### 3. Hammerspoon
**Pros:**
- Very powerful automation
- Can create complex notifications
- Lua scripting

**Cons:**
- Requires Hammerspoon installation
- More complex setup
- Overkill for simple notifications

### Recommendation: Hybrid Approach
1. Check for `terminal-notifier` first (better experience)
2. Fall back to `osascript` (always available)
3. Allow user to force specific method via environment variable

## Event Monitoring Design

### Approach: File Watching with fswatch
```bash
# Use fswatch if available (more efficient)
if command -v fswatch &> /dev/null; then
    fswatch -o state/deployment-events.yaml | while read; do
        process_new_events
    done
else
    # Fall back to polling
    while true; do
        process_new_events
        sleep 2
    done
fi
```

### Alternative: Tail-based Monitoring
```bash
# Monitor events file growth
tail -F state/deployment-events.yaml 2>/dev/null | while read line; do
    process_event_line "$line"
done
```

## Notification Content Structure

### Event Categories and Messages

1. **Deployment Start**
   - Title: "k0rdent Deployment Started"
   - Message: "Deployment ID: {id}"
   - Sound: default

2. **Phase Transitions**
   - Title: "Deployment Phase: {phase}"
   - Message: "{description}"
   - Sound: default

3. **Critical Events**
   - Title: "⚠️ Deployment Warning"
   - Message: "{error_message}"
   - Sound: Basso

4. **Completion**
   - Title: "✅ Deployment Complete"
   - Message: "Total time: {duration}"
   - Sound: Glass

### Event Filtering
```yaml
# Important events to notify
notification_events:
  - deployment_started
  - phase_transition
  - vm_creation_started
  - vm_creation_completed
  - vpn_connected
  - k0s_installed
  - k0rdent_deployed
  - deployment_completed
  - deployment_failed
  - error_occurred
```

## Integration with deploy-k0rdent.sh

### Command Line Flag
```bash
# Add to argument parsing
--with-desktop-notifications)
    WITH_DESKTOP_NOTIFICATIONS="true"
    shift
    ;;
```

### Notifier Launch
```bash
# Start notifier after state initialization
if [[ "$WITH_DESKTOP_NOTIFICATIONS" == "true" ]]; then
    start_desktop_notifier
fi

# Function to start notifier
start_desktop_notifier() {
    if [[ "$(uname)" != "Darwin" ]]; then
        print_warning "Desktop notifications only supported on macOS"
        return
    fi
    
    # Start notifier in background
    nohup ./bin/utils/desktop-notifier.sh "$K0RDENT_CLUSTERID" > /dev/null 2>&1 &
    NOTIFIER_PID=$!
    
    # Save PID for cleanup
    echo $NOTIFIER_PID > "$STATE_DIR/.notifier.pid"
    
    print_info "Desktop notifier started (PID: $NOTIFIER_PID)"
}
```

### Cleanup
```bash
# Stop notifier on exit/error
cleanup_notifier() {
    if [[ -f "$STATE_DIR/.notifier.pid" ]]; then
        local pid=$(cat "$STATE_DIR/.notifier.pid")
        if kill -0 $pid 2>/dev/null; then
            kill $pid
            print_info "Desktop notifier stopped"
        fi
        rm -f "$STATE_DIR/.notifier.pid"
    fi
}

# Add to trap
trap 'cleanup_notifier' EXIT ERR
```

## Background Process Management

### Process Lifecycle
1. Started after deployment state initialization
2. Monitors events file for changes
3. Tracks last processed event to avoid duplicates
4. Automatically terminates when deployment completes/fails
5. Cleaned up on script exit

### State Tracking
```bash
# Track last processed event
LAST_EVENT_FILE="$STATE_DIR/.notifier-last-event"
LAST_TIMESTAMP=""

# Read last timestamp
if [[ -f "$LAST_EVENT_FILE" ]]; then
    LAST_TIMESTAMP=$(cat "$LAST_EVENT_FILE")
fi
```

## Configuration Options

### Environment Variables
```bash
# Notification method preference
export K0RDENT_NOTIFIER_METHOD="terminal-notifier"  # or "osascript"

# Notification verbosity
export K0RDENT_NOTIFIER_LEVEL="normal"  # or "verbose", "quiet"

# Custom sound preferences
export K0RDENT_NOTIFIER_SOUND="default"  # or "none", specific sound name
```

### Event Filtering Config
```bash
# Only notify for specific events
export K0RDENT_NOTIFY_EVENTS="deployment_started,deployment_completed,deployment_failed"

# Exclude specific events
export K0RDENT_NOTIFY_EXCLUDE="ping_test,state_update"
```

## Implementation Files

### 1. bin/utils/desktop-notifier.sh
Main notification daemon that:
- Monitors events file
- Processes new events
- Sends notifications
- Manages state

### 2. etc/notifier-functions.sh
Shared functions for:
- Notification method detection
- Event parsing
- Message formatting
- Sound selection

### 3. Integration Updates
- deploy-k0rdent.sh: Add flag and lifecycle management
- etc/common-functions.sh: Add notifier helper functions
- etc/state-management.sh: Add notifier-specific event markers

## Testing Plan

### Unit Tests
1. Test notification methods (osascript, terminal-notifier)
2. Test event parsing and filtering
3. Test state tracking (no duplicate notifications)

### Integration Tests
1. Test with full deployment
2. Test with deployment failures
3. Test cleanup on interrupt
4. Test with missing dependencies

### Manual Testing Checklist
- [ ] Notifications appear for all major events
- [ ] No duplicate notifications
- [ ] Proper cleanup on deployment completion
- [ ] Graceful fallback when terminal-notifier missing
- [ ] Works with both success and failure scenarios

## Usage Documentation

### Basic Usage
```bash
# Enable desktop notifications for deployment
./deploy-k0rdent.sh deploy --with-desktop-notifications

# With other options
./deploy-k0rdent.sh deploy --with-azure-children --with-desktop-notifications -y
```

### Requirements
- macOS (notifications only work on macOS)
- Optional: terminal-notifier (install via `brew install terminal-notifier`)

### Troubleshooting
1. **No notifications appearing**
   - Check System Preferences > Notifications > Terminal
   - Ensure notifications are enabled for Terminal.app

2. **terminal-notifier not found**
   - Install with: `brew install terminal-notifier`
   - Or notifications will use osascript fallback

3. **Duplicate notifications**
   - Check if multiple notifier processes running
   - Clean state with: `rm -f state/.notifier*`

## Future Enhancements

1. **Notification Actions**
   - Add buttons to view logs
   - Quick actions (cancel deployment, view status)

2. **Rich Content**
   - Progress bars in notifications
   - Deployment statistics
   - Error details with solutions

3. **Cross-Platform Support**
   - Linux: notify-send
   - Windows: PowerShell notifications

4. **Integration Options**
   - Slack notifications
   - Email notifications
   - Custom webhooks

## Summary

This plan provides a comprehensive approach to adding desktop notifications to k0rdent deployments. The implementation prioritizes:
- Zero required dependencies (osascript fallback)
- Clean process management
- Meaningful notifications without spam
- Easy integration with existing deployment flow

The feature enhances the deployment experience by providing real-time feedback without requiring constant terminal monitoring.