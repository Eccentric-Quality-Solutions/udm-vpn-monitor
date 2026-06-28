# DRY Opportunities Review

**Date:** 2026-06-28  
**Scope:** `lib/`, root scripts, `scripts/manage/`, install/uninstall, and related tests

This document catalogs significant **Don't Repeat Yourself (DRY)** opportunities in the UDM VPN Monitor codebase. Trivial one-liner duplication is omitted. Items are ranked by impact and drift risk.

The core monitor path is already well-factored — `lib/common.sh`, config loading, atomic writes, and SPI parsing are shared consistently. The biggest remaining duplication sits in **install/uninstall vs shared lib** and **test boilerplate**.

---

## Summary Priority Matrix

| Priority | Opportunity | Action | Est. savings | Drift risk if ignored |
|----------|-------------|--------|--------------|------------------------|
| **Medium** | Hourly summary modules | Shared summary skeleton; merge partition + resource modules | ~80–100 lines | Medium |
| **Medium** | Test helpers | Control tree, dev install, SSH mocks, crontab scrub | ~300+ lines | Medium (maintenance) |
| **Medium** | Install file manifest | Shared manifest for package prep + install | — | Medium |
| **Low** | CLI colors, peer formatters, tier rate limits | Leave as-is | — | Low |

### Suggested implementation order

```mermaid
flowchart TD
    A["1. Test helpers: control tree + dev install"]
```

---


## Medium Impact

### 3. Hourly summary stats modules

Three parallel implementations of "track counter → log summary if interval elapsed → reset counters":

| Module | Track fn | Summary fn | Lines |
|--------|----------|------------|-------|
| `lib/detection/ping_detection.sh` | (inline increment in summary) | `log_ping_summary_if_due` | 61–111 |
| `lib/state/network_partition_stats.sh` | `track_network_partition_check` | `log_network_partition_summary_if_due` | 32–152 |
| `lib/state/resource_monitoring_stats.sh` | `track_resource_check`, `track_resource_constraint` | `log_resource_monitoring_summary_if_due` | 32–220 |

Shared pieces already used: `summary_interval_is_due`, `read_counter_file`, `atomic_write_state_file_or_warn`, `ensure_file_exists`, `increment_counter_file` (`lib/common.sh`).

**Existing abstraction:** Pattern documented in `CODE_PATTERNS.md` (lines 1112–1148); helpers exist but each domain reimplements the summary skeleton.

**Recommendation:** **Partial consolidate** — a parameterized helper (prefix, interval, counter names, message builder) could cut ~80–100 lines. **Acceptable duplication** if message formats stay domain-specific; risk is over-abstracting message strings. At minimum, unify the two 1-hour modules (`network_partition_stats` + `resource_monitoring_stats`) — they are structurally almost identical.

---

### 4. Install file manifest in two places

| Location | Content |
|----------|---------|
| `scripts/prepare_install_package.sh` | `MAIN_FILES`, `LIB_FILES`, `SCRIPT_FILES`, `MODULE_DIRS` |
| `install.sh` | `install_scripts()` (829+) with per-file `if [[ -f ]]` blocks |

Adding a new script (e.g. `vpn-monitor-control.sh`) requires updating both plus test fixtures.

**Recommendation:** Single manifest array (e.g. in `scripts/install_manifest.sh`) consumed by package prep and install.

---

## Test-Layer DRY

High volume, lower production risk, but significant maintenance pain.

| Opportunity | Where | Count | Fix |
|-------------|-------|-------|-----|
| Dev-install boilerplate | `tests/test_install.sh` | ~33 uses of `create_test_install_setup` + repeated stub config | `run_dev_install()` helper in `test_helper.bash` |
| Control-script mini-install | `tests/test_operating_mode.sh` | 4× identical ~15-line copy block | `setup_control_script_install_tree()` |
| SSH mocks | `tests/test_deploy_to_udm.sh` | ~11× mock bin setup | `setup_deploy_ssh_mocks()` in `tests/helpers/mocks.bash` |
| Operating mode fixture | `test_main.sh`, `test_vpn_monitor_wrapper.sh` | Manual heredocs vs `set_operating_mode()` | `setup_operating_mode_fixture()` in `tests/helpers/state.bash` |
| Crontab scrub | install/uninstall tests | 12+ inline `grep -v "vpn-monitor"` | `clear_vpn_monitor_crontab()` helper |
| Stats test setup | `test_state_network_partition_stats.sh`, `test_state_resource_monitoring_stats.sh` | Nearly identical setup blocks | `setup_stats_summary_test()` in `tests/helpers/state.bash` |

**Not significant:** `test_remote_control.sh` is appropriately thin (dry-run CLI tests, no SSH mocks needed).

### Details

#### `tests/test_install.sh` — repeated dev-install boilerplate (~25×)

Nearly every test repeats:

```bash
cd "$TEST_DIR"
local test_install
test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
echo "# Test config" >"${TEST_DIR}/source/vpn-monitor.conf"
chmod +x "${TEST_DIR}/source/vpn-monitor.sh"
run bash "$test_install" --dev --silent --no-cron
```

**Existing helper:** `create_test_install_setup()` in `tests/test_helper.bash` (lines 487–516).

**Recommendation:** Add `prepare_dev_install_source()` / `run_dev_install()` in `test_helper.bash`.

#### `tests/test_operating_mode.sh` — control-script mini-install copied 4×

Identical block in four tests (lines 93–146): copy `vpn-monitor-control.sh`, `lib/control/*`, `control.sh`, `common.sh`, `logging.sh`, `constants.sh`, `lib/config`. Also partially duplicated in `tests/test_install.sh` (lines 1214–1218).

**Recommendation:** Add `setup_control_script_install_tree()` in `test_helper.bash` (or extend `create_test_install_setup` with a `--with-control` flag).

#### Cron test setup/teardown scattered

- `tests/test_install.sh` — 12× `crontab -l | grep -v "vpn-monitor" | crontab -`
- `tests/test_uninstall.sh` — mix of `grep -v "vpn-monitor"` and `grep -v "vpn-monitor.sh"`
- `tests/test_helper.bash` — `create_test_cron_entry()` (695–703), teardown cleanup (268–279)

**Recommendation:** Add `clear_vpn_monitor_crontab()` and `assert_or_skip_cron_entry EXPECTED_LINE` in `test_helper.bash`. Align filter pattern with production (`vpn-monitor`, not just `.sh`).

---

## Acceptable Duplication (Do Not Chase)

| Area | Why it's fine |
|------|---------------|
| Colored CLI logging in manage scripts vs `log_message` in monitor | Intentional separation: standalone CLI tools vs cron-driven monitor (`manage_log_*` override for file logging in deploy scripts) |
| `format_peer_display` vs `format_peer_ip_display` | Different display contracts (`lib/recovery/recovery_state.sh` vs `lib/common.sh`) |
| Tier 1/2/3 rate limit logic | Similar shape, different coordinator bypass and config — over-abstracting hides behavior |
| SPI handling in xfrm_detection | Already delegates to `extract_spi_from_xfrm_line` and `validate_spi_format` in `lib/common.sh` |
| Atomic writes | Well centralized in `lib/common.sh`; manual `.tmp`+`mv` only outside `lib/` |
| Install/uninstall logrotate patterns | Symmetric shape, different enough to defer |
| `centralize-logs.sh` SSH | Uses `ssh -M -N -f` — different from ControlMaster multiplex pattern in `scripts/manage/lib/ssh_control.sh` |

---

## Already DRY (Good Patterns to Extend)

- **Timestamp list compaction:** `compact_timestamp_list_file` in `lib/state/global_state.sh` — used by `compact_restart_count_file` and `compact_tier2_recovery_count_file`
- **Keepalive daemon control:** `lib/control/keepalive_control.sh` — used by `install.sh`, `uninstall.sh`, `vpn-monitor-control.sh`
- **Cron management:** `lib/control/cron_control.sh` — used by `install.sh`, `uninstall.sh`, `vpn-monitor-control.sh`
- **SSH ControlMaster:** `scripts/manage/lib/ssh_control.sh` — used by `deploy-to-udm.sh`, `control-remote-udm.sh`, `deploy-to-udms.sh`
- **Control module split:** `lib/control.sh` → `operating_mode.sh` + `cron_control.sh`; remote control delegates to UDM script instead of reimplementing mode logic
- **Config parsing:** `get_config_var_value_from_file` is the standard path for most code paths (including `vpn-monitor-wrapper.sh` `get_monitor_interval()`)
- **File I/O:** `atomic_write_file`, counter helpers, `summary_interval_is_due` reused consistently in newer code
- **Validated single-value state files:** `read_validated_state_file` / `write_validated_state_file` in `lib/state/global_state.sh` — used by network partition and system-wide failure state/timestamp wrappers
- **SPI parsing:** Refactored to `lib/common.sh` helpers used by xfrm detection
- **Documentation:** `CODE_PATTERNS.md` documents SSH and stats patterns — good foundation for consolidation without new dependencies

---

## Highest-ROI Next Step

**Test helpers: control tree + dev install** — `setup_control_script_install_tree()` and `run_dev_install()` (see Test-Layer DRY above).
