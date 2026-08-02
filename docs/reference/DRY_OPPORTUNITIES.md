# DRY Opportunities Review

**Date:** 2026-06-28  
**Scope:** `lib/`, root scripts, `manage/`, install/uninstall, and related tests

This document catalogs significant **Don't Repeat Yourself (DRY)** opportunities still open in the UDM VPN Monitor codebase. Trivial one-liner duplication is omitted. Items are ranked by impact and drift risk.

The core monitor path is already well-factored — `lib/common.sh`, config loading, atomic writes, and SPI parsing are shared consistently. Remaining duplication sits in **hourly summary modules**, **install file manifest**, and a minor **test helper** gap.

---

## Summary Priority Matrix

| Priority | Opportunity | Action | Est. savings | Drift risk if ignored |
|----------|-------------|--------|--------------|------------------------|
| **Medium** | Hourly summary modules | Shared summary skeleton; merge partition + resource modules | ~80–100 lines | Medium |
| **Medium** | Install file manifest | Shared manifest for package prep + install | — | Medium |
| **Low** | CLI colors, peer formatters, tier rate limits | Leave as-is | — | Low |
| **Low** | Cron test assertion helper | `assert_or_skip_cron_entry EXPECTED_LINE` | — | Low (maintenance) |

---

## Medium Impact

### 1. Hourly summary stats modules

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

### 2. Install file manifest in two places

| Location | Content |
|----------|---------|
| `scripts/prepare_install_package.sh` | `MAIN_FILES`, `LIB_FILES`, `SCRIPT_FILES`, `MODULE_DIRS` |
| `install.sh` | `install_scripts()` (829+) with per-file `if [[ -f ]]` blocks |

Adding a new script (e.g. `vpn-monitor-control.sh`) requires updating both plus test fixtures.

**Recommendation:** Single manifest array (e.g. in `scripts/install_manifest.sh`) consumed by package prep and install.

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
| `centralize-logs.sh` SSH | Uses `ssh -M -N -f` — different from ControlMaster multiplex pattern in `manage/lib/ssh_control.sh` |

---

## Highest-ROI Next Step

**Install file manifest** — single source of truth for package prep and install reduces drift when adding scripts or lib modules.
