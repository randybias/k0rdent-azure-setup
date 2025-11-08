# Deployment Orchestration Specification

## MODIFIED Requirements

### Requirement: Infrastructure-First Deployment Workflow
The system SHALL provision infrastructure via Terraform before executing bash orchestration scripts for WireGuard, k0s, and k0rdent.

#### Scenario: Full deployment with Terraform infrastructure
- **WHEN** deploy-k0rdent.sh deploy is executed without --legacy flag
- **THEN** terraform-wrapper.sh apply is invoked first
- **AND** Terraform outputs are synced to deployment-state.yaml
- **AND** bash orchestration scripts (prepare-deployment, manage-vpn, install-k0s, install-k0rdent) execute using Terraform outputs
- **AND** deployment completes with all phases tracked in state

#### Scenario: Infrastructure-only provisioning
- **WHEN** deploy-k0rdent.sh deploy --terraform-only is executed
- **THEN** Terraform provisions infrastructure and syncs outputs
- **AND** orchestration stops after infrastructure phase
- **AND** user can manually proceed with bash scripts later

#### Scenario: Software-only deployment on existing infrastructure
- **WHEN** deploy-k0rdent.sh deploy --skip-terraform is executed
- **THEN** infrastructure provisioning is skipped
- **AND** bash scripts use existing Terraform outputs or state data
- **AND** orchestration proceeds with WireGuard/k0s/k0rdent phases

### Requirement: Deployment Phase Detection
The system SHALL detect whether infrastructure was created by Terraform or legacy bash and adjust workflow accordingly.

#### Scenario: Terraform-managed infrastructure detection
- **WHEN** deployment state contains terraform_state_path key
- **THEN** scripts use Terraform outputs for infrastructure facts
- **AND** Azure/AWS CLI queries are skipped for VM/instance data
- **AND** phase validation checks Terraform state consistency

#### Scenario: Legacy bash infrastructure detection
- **WHEN** deployment state lacks terraform_state_path key
- **THEN** scripts use Azure/AWS CLI queries for infrastructure facts
- **AND** deployment-state.yaml contains directly stored VM data
- **AND** phase validation uses traditional state checks

#### Scenario: Conflicting infrastructure sources
- **WHEN** both Terraform state and legacy bash state exist
- **THEN** Terraform state takes precedence with warning logged
- **AND** user is prompted to migrate or remove legacy state
- **AND** deployment halts until conflict is resolved

## ADDED Requirements

### Requirement: Terraform Output Consumption in Bash
The system SHALL provide bash functions to read Terraform outputs transparently with fallback to legacy methods.

#### Scenario: Reading VM IPs from Terraform outputs
- **WHEN** get_vm_info("vm-name", "public_ip") is called
- **THEN** function first checks Terraform outputs for vm-name IP
- **AND** if Terraform output unavailable, reads from deployment-state.yaml
- **AND** if state missing, falls back to Azure/AWS CLI query
- **AND** result is cached in deployment-state.yaml for future calls

#### Scenario: Terraform output refresh after infrastructure change
- **WHEN** Terraform apply modifies infrastructure
- **THEN** sync_terraform_to_state() is automatically invoked
- **AND** deployment-state.yaml terraform_outputs section is updated
- **AND** timestamp is recorded for staleness detection

#### Scenario: Stale Terraform output detection
- **WHEN** terraform_outputs timestamp is older than 1 hour and infrastructure operations pending
- **THEN** warning is displayed suggesting terraform refresh
- **AND** scripts prompt user to run terraform-wrapper.sh refresh
- **AND** operations proceed with cached outputs unless --strict-freshness flag set

### Requirement: Multi-Stage Deployment Control
The system SHALL allow fine-grained control over deployment stages via command-line flags.

#### Scenario: Phased deployment execution
- **WHEN** deploy-k0rdent.sh deploy --stop-after terraform is executed
- **THEN** deployment stops after Terraform infrastructure phase
- **AND** state reflects terraform_complete phase
- **AND** user can resume with deploy-k0rdent.sh deploy --start-from wireguard

#### Scenario: Selective phase execution
- **WHEN** deploy-k0rdent.sh deploy --only k0s is executed
- **THEN** only k0s installation phase runs
- **AND** prerequisite phases (infrastructure, wireguard) must be already complete
- **AND** error is raised if prerequisites not met

### Requirement: Cloud Provider Workflow Consistency
The system SHALL maintain identical orchestration workflow for Azure and AWS deployments.

#### Scenario: Azure deployment with Terraform
- **WHEN** cloud_provider is azure in configuration
- **THEN** terraform-wrapper.sh loads Azure modules
- **AND** bash scripts consume Azure-specific Terraform outputs (resource_group, vm_details)
- **AND** orchestration flow matches legacy Azure bash deployment

#### Scenario: AWS deployment with Terraform
- **WHEN** cloud_provider is aws in configuration
- **THEN** terraform-wrapper.sh loads AWS modules
- **AND** bash scripts consume AWS-specific Terraform outputs (vpc_id, instance_details)
- **AND** orchestration flow matches Azure workflow with provider-specific adaptations

#### Scenario: Provider output normalization
- **WHEN** scripts access infrastructure data via abstraction functions
- **THEN** provider-specific output keys are normalized (resource_group ↔ vpc_id)
- **AND** scripts remain provider-agnostic in logic
- **AND** provider-specific details are isolated in state-management.sh
