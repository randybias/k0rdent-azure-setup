## ADDED Requirements

### Requirement: Terraform Azure Infrastructure
Terraform MUST provide modules to provision the resource group, virtual network, network security group, and controller/worker virtual machines equivalent to the current Azure CLI flow.

#### Scenario: Provision default cluster
- **GIVEN** the default `config/k0rdent.yaml`
- **WHEN** an operator runs `terraform apply` in the new Terraform root module
- **THEN** Azure resources for one controller and one worker are created with the existing cloud-init applied, and no Azure CLI scripts need to run.

### Requirement: Terraform Output Integration
The deployment orchestrator MUST support consuming Terraform outputs instead of invoking Azure CLI provisioning.

#### Scenario: Bootstrap from Terraform state
- **WHEN** `deploy-k0rdent.sh` (or its successor command) is invoked with the flag to reuse Terraform infrastructure
- **THEN** it reads VM connection details (public/private IPs, WireGuard port) from `terraform output -json`, skips Azure CLI provisioning steps, and proceeds with WireGuard/k0s/k0rdent installation successfully.

### Requirement: Terraform Usage Documentation
Documentation MUST describe the Terraform workflow and how it interacts with the existing scripts.

#### Scenario: Follow Terraform workflow docs
- **WHEN** an operator follows the new Terraform instructions
- **THEN** they can `terraform init/plan/apply`, generate or provide tfvars, and run the bootstrap command without ambiguity about prerequisites or remote state configuration.
