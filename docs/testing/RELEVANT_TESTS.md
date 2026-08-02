# Running Relevant Tests

**Purpose**: When you change code, run the **relevant** tests for that change—not the full test suite. The full suite (~1460 tests with default `run_tests.sh`, ~1795 with `--slow`) is for CI and pre-release; during development and code reviews, run only the tests that cover what you changed.

**Last updated**: 2026-04-26

**Integration tests on developer/CI hosts:** If `check_system_resources` sees critically low disk space, `vpn-monitor.sh` can exit before VPN logic. Multi-run tests that drive the real monitor entrypoint should set `ENABLE_RESOURCE_MONITORING=0` in fixture config when the goal is to exercise detection/recovery (see `tests/test_cron_cycle_e2e.sh`).

---

## How to Run Relevant Tests

Run specific test files with BATS. Use a timeout and ensure output streams to the terminal (no buffering).

```bash
# One or more test files (use TEST_TIMEOUT so tests don't hang)
TEST_TIMEOUT=120 bats tests/test_detection.sh tests/test_detection_failure_type.sh
```

To use the project test runner with only certain files, run BATS directly as above; `run_tests.sh` does not accept a list of test files and always runs the full (filtered) set.

**Streaming**: Tests should stream to the screen. If running via a wrapper, avoid buffering (e.g. use `stdbuf` or unbuffered mode if needed).

**Slow tests**: If the relevant test file is tagged as slow, either run it explicitly with the same `bats tests/test_foo.sh` command (no special flag needed) or include `--slow` only if you use `run_tests.sh` for a broader run.

---

## Code-to-Test Mapping

Use this table to choose which test files to run for a given path or area. When you touch a file, run the tests listed for that row (and optionally related rows if the change affects callers/callees).

| Code changed | Run these test files |
|--------------|----------------------|
| **Root / entry scripts** | |
| `vpn-monitor.sh` | `test_vpn_monitor.sh`, `test_main.sh`, `test_operating_mode.sh` |
| `vpn-monitor-wrapper.sh` | `test_vpn_monitor_wrapper.sh`, `test_vpn_monitor.sh`, `test_main.sh`, `test_operating_mode.sh` |
| `vpn-monitor-control.sh` | `test_operating_mode.sh`, `test_install.sh` |
| **Integration (multi-run / cron-style)** | `test_cron_cycle_e2e.sh`, `test_integration_e2e_recovery.sh` |
| `vpn-keepalive.sh` | `test_vpn_keepalive.sh` |
| `install.sh` | `test_install.sh` |
| `uninstall.sh` | `test_uninstall.sh` |
| `analyze-logs.sh` | `test_analyze_logs.sh` |
| `check-config.sh` | `test_check_config.sh` |
| `compare-config.sh` | `test_compare_config.sh` |
| `check-utilities.sh` | `test_check_utilities.sh` |
| **lib/common.sh** | `test_helper_functions.sh`, `test_common_*.sh` |
| **lib/constants.sh** | (no dedicated tests; run tests for code that uses it) |
| **lib/config_schema.sh** | `test_config.sh`, `test_config_validation.sh`, `test_helper_functions.sh` |
| **lib/config.sh** (compat layer) | Any `test_config*.sh` |
| **lib/config/** | `test_config.sh`, `test_config_loading.sh`, `test_config_validation.sh`, `test_config_location.sh`, `test_config_*.sh` as appropriate |
| **lib/detection.sh** (compat layer) | Any `test_detection*.sh` |
| **lib/detection/xfrm_detection.sh** | `test_detection.sh`, `test_detection_status.sh`, `test_detection_fallback.sh`, `test_detection_rekey.sh`, `test_detection_failure_type.sh`, `test_detection_idle.sh`, `test_detection_xfrm_edge_cases.sh`, `test_detection_network_partition.sh`, `test_xfrm_sa_management.sh` |
| **lib/detection/ping_detection.sh** | `test_detection.sh`, `test_detection_ping_optional.sh`, `test_detection_ping_multiple.sh`, `test_detection_ping_summary.sh`, `test_ping_command_building.sh` |
| **lib/detection/failure_analysis.sh** | `test_failure_diagnosis.sh`, `test_detection_failure_type.sh`, `test_detection.sh` |
| **lib/detection/network_validation.sh** | `test_detection_network_partition.sh`, `test_detection.sh`, `test_config_validation.sh`, `test_ping_command_building.sh` |
| **lib/detection/system_wide_failure.sh** | `test_detection_system_wide_failure.sh`, `test_system_wide_failure_coordination.sh` |
| **lib/recovery.sh** (compat layer) | Any `test_recovery*.sh` |
| **lib/recovery/recovery_orchestration.sh** | `test_recovery_orchestration_determine_action.sh`, `test_recovery_orchestration_execute_xfrm_fallback.sh`, `test_recovery.sh` |
| **lib/recovery/xfrm_recovery.sh** | `test_recovery.sh`, `test_retry_xfrm_recovery.sh`, `test_xfrm_sa_management.sh`, `test_recovery_tier2.sh`, `test_recovery_tier3.sh` |
| **lib/recovery/ipsec_recovery.sh** | `test_recovery.sh`, `test_recovery_tier2.sh`, `test_recovery_tier3.sh` |
| **lib/recovery/recovery_verification.sh** | `test_recovery.sh`, `test_recovery_state.sh` |
| **lib/recovery/recovery_state.sh** | `test_recovery_state.sh`, `test_recovery.sh` |
| **lib/state/global_state.sh** (`read_validated_state_file`, `write_validated_state_file`) | `test_validated_state_file.sh`, `test_state.sh`, `test_state_atomic_write_failures.sh` |
| **lib/state.sh**, **lib/state/** | `test_state.sh`, `test_state_location.sh`, `test_state_concurrent_updates.sh`, `test_state_atomic_write_failures.sh`, `test_state_network_partition_stats.sh`, `test_state_resource_monitoring_stats.sh`, `test_rapid_state_changes.sh`, `test_validated_state_file.sh` |
| **lib/lockfile.sh** | `test_lockfile.sh` |
| **lib/logging.sh** | `test_logging.sh`, `test_logging_prefix.sh` |
| **lib/resources.sh** | `test_resources.sh` |
| **lib/control.sh**, **lib/control/** | `test_operating_mode.sh`, `test_keepalive_control.sh`, `test_wrapper_control.sh`, `test_main.sh`, `test_install.sh` |
| **lib/anonymize.sh** | `test_anonymize.sh` (optional filter: `--filter-tags anonymize:ipset` / `anonymize:ip-rules` / `anonymize:firewall` / `anonymize:logs` / `anonymize:all`) |
| **manage/** (e.g. deploy-to-udm, deploy-to-udms, control-remote-udm, uninstall-from-udm, uninstall-from-udms, status-udms, pull-config-from-udms, push-config-to-udms, manage/lib/config_fleet_common.sh, manage/lib/ssh_control.sh, centralize-logs) | `test_deploy_to_udm.sh`, `test_deploy_to_udms.sh`, `test_remote_control.sh`, `test_remote_uninstall.sh`, `test_fleet_status.sh`, `test_pull_config_from_udms.sh`, `test_push_config_to_udms.sh` |
| **scripts/** (e.g. prepare_install_package, update-version, export, anonymize scripts) | `test_prepare_install_package.sh`, `test_update_version.sh`, `test_export_udm_routes_firewall.sh`, `test_anonymize.sh` for anonymize scripts |
| **docs/scripts/CONTROL_PLANE_ACCEPTANCE.md** (operator checklist; no code under test) | Manual validation on fleet; related automated coverage via `test_operating_mode.sh`, `test_install.sh`, `test_deploy_to_udms.sh`, `test_fleet_status.sh`, `test_remote_control.sh`, `test_pull_config_from_udms.sh`, `test_push_config_to_udms.sh` |
| **Tests / fixtures / helpers** | `test_test_isolation.sh`, `test_test_data_generators.sh`, `test_fixtures_vpn_at_tier.sh`, `test_fixtures_vpn_idle.sh`, `test_fixtures_vpn_multi_location.sh`; plus tests that use the changed helper/fixture |

**Deploy tests**: `test_deploy_to_udm.sh` and `test_deploy_to_udms.sh` use `DEPLOY_LOG_FILE` to redirect deploy script logs and `DEPLOY_REGISTRY_FILE` for the deployment registry to test-specific paths, so logs and registry do not pollute the repo.

---

## When to Run More

- **Broad or refactor changes** (e.g. touching `lib/common.sh` or multiple modules): run the full fast suite or the union of all affected areas.
- **Unclear impact**: run the tests for the directory you changed and one level up (e.g. recovery + main script).
- **Before commit / PR**: consider `./tests/run_tests.sh` (fast) or `./tests/run_tests.sh --slow` for full confidence; CI will run the full suite.

---

## References

- **Test file list by category**: [tests/README.md](../../tests/README.md#test-files-by-category)
- **Run options**: [CLAUDE.md](../../CLAUDE.md#build-and-test-commands), [BATS_GUIDE.md](BATS_GUIDE.md#running-tests)
- **Tags**: Use `./tests/run_tests.sh --filter-tags category:unit` (or similar) to run by tag when that matches your change.
