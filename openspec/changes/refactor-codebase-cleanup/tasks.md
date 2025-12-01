# Tasks: Codebase Cleanup and Optimization

## 1. Critical Fixes (Phase 1)

### 1.1 Fix Duplicate Function Definitions
- [ ] 1.1.1 Remove first `check_k0sctl()` definition (lines 79-91 in common-functions.sh) - keep second definition with `return 1`
- [ ] 1.1.2 Remove first `check_netcat()` definition (lines 94-106 in common-functions.sh) - keep second definition with `return 1`
- [ ] 1.1.3 Verify no callers depend on `exit 1` behavior

### 1.2 Fix Exit Patterns in Utility Functions
- [ ] 1.2.1 Replace `exit 1` with `return 1` in `handle_error()` (line 47)
- [ ] 1.2.2 Replace `exit 1` with `return 1` in `check_azure_cli()` (lines 55, 60)
- [ ] 1.2.3 Replace `exit 1` with `return 1` in `check_wireguard_tools()` (line 73)
- [ ] 1.2.4 Replace `exit 1` with `return 1` in `check_aws_cli()` (line 113)
- [ ] 1.2.5 Replace `exit 1` with `return 1` in `check_yq()` (line 129)
- [ ] 1.2.6 Update callers to handle return codes properly

### 1.3 Remove Deprecated Functions
- [ ] 1.3.1 Remove `init_cluster_state()` from state-management.sh (line 970)
- [ ] 1.3.2 Remove `update_cluster_state()` from state-management.sh (line 977)
- [ ] 1.3.3 Remove `get_cluster_state()` from state-management.sh (line 990)
- [ ] 1.3.4 Verify no scripts call deprecated functions

## 2. Remove Unused Functions (Phase 2)

### 2.1 common-functions.sh (24 unused functions)
- [ ] 2.1.1 Remove `add_to_manifest()` (line 547)
- [ ] 2.1.2 Remove `check_all_prerequisites()` (line 1382)
- [ ] 2.1.3 Remove `check_aws_cli()` (line 109)
- [ ] 2.1.4 Remove `check_azure_cli_quiet()` (line 1604)
- [ ] 2.1.5 Remove `check_command_support()` (line 825)
- [ ] 2.1.6 Remove `check_wg_wrapper()` (line 483)
- [ ] 2.1.7 Remove `cleanup_macos_wireguard_interface()` (line 192)
- [ ] 2.1.8 Remove `display_resource_status()` (line 1326)
- [ ] 2.1.9 Remove `execute_azure_command()` (line 1180)
- [ ] 2.1.10 Remove `execute_remote_command_with_output()` (line 1089)
- [ ] 2.1.11 Remove `force_cleanup_macos_wireguard()` (line 241)
- [ ] 2.1.12 Remove `format_command_list()` (line 724)
- [ ] 2.1.13 Remove `format_example_list()` (line 736)
- [ ] 2.1.14 Remove `format_option_list()` (line 730)
- [ ] 2.1.15 Remove `get_wg_path()` (line 474)
- [ ] 2.1.16 Remove `init_manifest()` (line 559)
- [ ] 2.1.17 Remove `list_macos_wireguard_interfaces()` (line 169)
- [ ] 2.1.18 Remove `log_command()` (line 907)
- [ ] 2.1.19 Remove `parse_common_args()` (line 763)
- [ ] 2.1.20 Remove `print_bold()` (line 16)
- [ ] 2.1.21 Remove `run_detailed_wireguard_connectivity_test()` (line 1422)
- [ ] 2.1.22 Remove `verify_resources()` (line 1268)
- [ ] 2.1.23 Remove `wait_for_azure_operation()` (line 1213)
- [ ] 2.1.24 Remove `wait_for_cloud_init()` (line 673)

### 2.2 config-resolution-functions.sh (10 unused functions)
- [ ] 2.2.1 Remove `_extract_state_value()` (line 935)
- [ ] 2.2.2 Remove `check_configuration_consistency()` (line 1620)
- [ ] 2.2.3 Remove `compare_config_values()` (line 1240)
- [ ] 2.2.4 Remove `detect_configuration_drift()` (line 1348)
- [ ] 2.2.5 Remove `export_state_config_to_env()` (line 883)
- [ ] 2.2.6 Remove `load_config_from_deployment_state()` (line 955)
- [ ] 2.2.7 Remove `validate_config_for_operation()` (line 1811)
- [ ] 2.2.8 Remove `validate_deployment_state_file()` (line 1000)
- [ ] 2.2.9 Remove `validate_state_config_completeness()` (line 1449)
- [ ] 2.2.10 Remove `validate_state_config_requirements()` (line 1018)

### 2.3 state-management.sh (14 unused functions)
- [ ] 2.3.1 Remove `add_kof_event()` (line 790)
- [ ] 2.3.2 Remove `backup_completed_deployment()` (line 532)
- [ ] 2.3.3 Remove `check_yq_available()` (line 523)
- [ ] 2.3.4 Remove `clear_artifact()` (line 359)
- [ ] 2.3.5 Remove `ensure_phases_block_initialized()` (line 78)
- [ ] 2.3.6 Remove `get_kof_state()` (line 778)
- [ ] 2.3.7 Remove `init_azure_state()` (line 824)
- [ ] 2.3.8 Remove `init_kof_state()` (line 716)
- [ ] 2.3.9 Remove `migrate_state_file_structure()` (line 105)
- [ ] 2.3.10 Remove `normalize_phase_name()` (line 211)
- [ ] 2.3.11 Remove `phase_index()` (line 218)
- [ ] 2.3.12 Remove `phase_mark_status()` (line 258)
- [ ] 2.3.13 Remove `remove_kof_state_key()` (line 811)
- [ ] 2.3.14 Remove `update_kof_state()` (line 757)

### 2.4 azure-cluster-functions.sh (4 unused functions)
- [ ] 2.4.1 Remove `cleanup_failed_cluster_deployment()` (line 123)
- [ ] 2.4.2 Remove `detect_capi_azure_sync_issue()` (line 49)
- [ ] 2.4.3 Remove `is_deployment_stuck()` (line 93)
- [ ] 2.4.4 Remove `is_transient_cluster_failure()` (line 7)

### 2.5 kof-functions.sh (2 unused functions)
- [ ] 2.5.1 Remove `check_kof_mothership_installed()` (line 125)
- [ ] 2.5.2 Remove `check_kof_operators_installed()` (line 131)

## 3. Code Consolidation (Phase 3)

### 3.1 Extract Common Patterns
- [ ] 3.1.1 Create `find_ssh_key()` function in common-functions.sh
- [ ] 3.1.2 Update bin/install-k0s.sh to use `find_ssh_key()`
- [ ] 3.1.3 Update bin/install-k0rdent.sh to use `find_ssh_key()` (3 occurrences)
- [ ] 3.1.4 Create `kubectl_delete_resources()` helper for batch deletes
- [ ] 3.1.5 Update bin/setup-azure-cluster-deployment.sh to use batch delete helper
- [ ] 3.1.6 Update bin/install-k0s-azure-csi.sh to use batch delete helper

### 3.2 Create Controller/Worker Helpers
- [ ] 3.2.1 Create `get_controller_nodes()` function in common-functions.sh
- [ ] 3.2.2 Create `get_worker_nodes()` function in common-functions.sh
- [ ] 3.2.3 Update bin/install-k0s.sh to use new helpers
- [ ] 3.2.4 Update bin/install-k0rdent.sh to use new helpers
- [ ] 3.2.5 Update deploy-k0rdent.sh to use new helpers

### 3.3 Consolidate Phase Completion Pattern
- [ ] 3.3.1 Create `check_phase_completion()` function in state-management.sh
- [ ] 3.3.2 Update bin/setup-azure-cluster-deployment.sh to use helper
- [ ] 3.3.3 Update bin/manage-vpn.sh to use helper
- [ ] 3.3.4 Update bin/install-k0s.sh to use helper
- [ ] 3.3.5 Update bin/install-k0rdent.sh to use helper
- [ ] 3.3.6 Update remaining scripts with phase validation pattern

## 4. Validation

### 4.1 Testing
- [ ] 4.1.1 Run tests/state-phase-smoke.sh
- [ ] 4.1.2 Run tests/test-kof-mothership-script.sh
- [ ] 4.1.3 Run tests/test-kof-with-default.sh
- [ ] 4.1.4 Verify bin/check-prerequisites.sh works
- [ ] 4.1.5 Test full deployment cycle (manual)

### 4.2 Code Quality Verification
- [ ] 4.2.1 Verify no duplicate function definitions remain
- [ ] 4.2.2 Verify no `exit 1` in utility functions
- [ ] 4.2.3 Run shellcheck on modified files
- [ ] 4.2.4 Verify no broken function calls
