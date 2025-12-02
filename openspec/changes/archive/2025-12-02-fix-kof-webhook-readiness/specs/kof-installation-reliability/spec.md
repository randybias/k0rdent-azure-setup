# Spec: KOF Installation Reliability

## ADDED Requirements

### Requirement: Victoria Metrics Webhook Readiness Validation

The KOF installation process MUST validate that the Victoria Metrics operator webhook is fully functional before proceeding with resources that depend on webhook validation.

#### Scenario: Installing KOF mothership after operators

**Given** kof-operators chart has been installed with `helm --wait`
**And** the Victoria Metrics operator pods are running
**When** the installation process checks webhook readiness
**Then** it must wait until the ValidatingWebhookConfiguration exists
**And** the webhook service has active endpoints
**And** the webhook is accepting validation requests
**And** only then proceed to install kof-mothership

#### Scenario: Webhook becomes ready within normal timeframe

**Given** kof-operators has just been installed
**And** the Victoria Metrics operator is starting up normally
**When** the webhook readiness check runs
**Then** the webhook should become ready within 60 seconds
**And** the check should return success
**And** installation should proceed to mothership deployment

#### Scenario: Webhook fails to become ready within timeout

**Given** kof-operators installation completed
**And** the Victoria Metrics webhook is not starting correctly
**When** the webhook readiness check waits for 180 seconds
**And** the webhook does not become ready
**Then** the check must timeout with a clear error message
**And** include diagnostic information about webhook status
**And** halt the installation process
**And** prevent kof-mothership installation attempts

#### Scenario: Webhook check provides progress feedback

**Given** the webhook readiness check is running
**And** the webhook is not yet ready
**When** 30 seconds have elapsed
**Then** the system must display a progress message
**And** continue checking every 10 seconds
**And** report progress every 30 seconds
**And** maintain clear user visibility into wait state

### Requirement: Webhook Readiness Detection

The system MUST reliably detect when the Victoria Metrics webhook is fully operational using multiple validation layers.

#### Scenario: Checking ValidatingWebhookConfiguration existence

**Given** kof-operators is installed
**When** checking webhook readiness
**Then** the system must verify ValidatingWebhookConfiguration resource exists
**And** the webhook configuration includes Victoria Metrics webhooks
**And** this check must succeed before considering webhook ready

#### Scenario: Verifying webhook service endpoints

**Given** ValidatingWebhookConfiguration exists
**When** checking webhook readiness
**Then** the system must verify the webhook service has active endpoints
**And** endpoints correspond to running webhook pods
**And** network connectivity to webhook service is established
**And** this check must pass before proceeding

#### Scenario: Confirming webhook pod readiness

**Given** webhook service endpoints exist
**When** checking webhook readiness
**Then** the system must verify Victoria Metrics operator pods are ready
**And** pods are not in CrashLoopBackOff or Error state
**And** this provides redundant validation of webhook availability

### Requirement: Configurable Webhook Timeout

Users MUST be able to configure the webhook readiness timeout to accommodate different system performance characteristics.

#### Scenario: Using default timeout value

**Given** no custom webhook timeout is configured
**When** the webhook readiness check runs
**Then** it must use a default timeout of 180 seconds
**And** this provides sufficient time for normal webhook startup
**And** prevents unnecessarily long waits on failures

#### Scenario: Using custom timeout from configuration

**Given** the configuration specifies `kof.operators.webhook_timeout_seconds: 300`
**When** the webhook readiness check runs
**Then** it must use the configured 300 second timeout
**And** respect user's custom timeout preference
**And** allow for slower systems or network conditions

#### Scenario: Timeout must be reasonable

**Given** any configured webhook timeout value
**When** validating the configuration
**Then** the timeout must be at least 30 seconds
**And** provide enough time for webhook startup
**And** prevent configuration errors from breaking installation

## MODIFIED Requirements

None - this is a new capability addition.

## REMOVED Requirements

None - no existing requirements are being removed.

## Related Capabilities

This spec stands alone but relates conceptually to:
- **configuration-consistency**: Uses same configuration loading mechanisms
- **kof-deployment** (future): Overall KOF deployment reliability

## Notes

### Implementation Location

- **Primary function**: `etc/kof-functions.sh::wait_for_victoria_metrics_webhook()`
- **Integration point**: `bin/install-kof-mothership.sh::deploy_kof_mothership()` between Step 3 and Step 4

### Error Codes

- **Exit 0**: Webhook ready, continue installation
- **Exit 1**: Webhook timeout or validation failure, halt installation

### Future Enhancements

Potential future improvements not in scope for this change:
- Active webhook testing with sample validation request
- Automatic retry of operator installation if webhook fails
- Webhook health metrics collection for monitoring
- Support for custom webhook service names
