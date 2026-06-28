# Code Walkthrough Checklist

Use this as a session guide when walking someone through the UDM VPN Monitor codebase. Check items as you go; skip sections if time is short. Estimated full pass: **90–120 minutes**; a **45-minute** core path is marked below.

**Companion docs:** [README.md](../README.md) · [docs/reference/ARCHITECTURE.md](reference/ARCHITECTURE.md) · [DEVELOPER.md](../DEVELOPER.md) · [DEPLOYMENT_CHECKLIST.md](../DEPLOYMENT_CHECKLIST.md)

---

## Before the session

- [ ] Agree on audience (operator vs developer) and depth (runtime behavior vs implementation)
- [ ] Confirm target platform: **UniFi OS 4.3+ on UDM only** — no python/jq/node; shell + UDM utilities
- [ ] Have a sample `vpn-monitor.conf` (or template) and optionally a UDM with SSH for live `ip xfrm state` / logs
- [ ] Note install path on device: `/data/vpn-monitor/` (persists across reboots)
- [ ] Optional: run `./check-config.sh` and `./check-utilities.sh` locally to show validation tooling

---

## 1. Problem and constraints (~10 min) — **core path**

- [ ] **What it solves:** Site-to-site VPNs that look “up” (IKE) but carry no traffic
- [ ] **What it is not:** Upgrade-proof daemon; cron can disappear on UniFi OS upgrades ([README](../README.md) “What This Is NOT”)
- [ ] **Execution model:** Cron every minute (default), optional sub-minute wrapper, optional keepalive systemd service
- [ ] **Detection stack:** `ip xfrm state` (byte counters) → `ipsec status` fallback → optional ping ([ARCHITECTURE](reference/ARCHITECTURE.md))
- [ ] **Recovery tiers:** Tier 1 log → Tier 2 surgical (xfrm per-tunnel, else `ipsec reload`) → Tier 3 full (xfrm per-tunnel, else `ipsec restart`)
- [ ] **Safety themes:** lockfile, cooldown, rate limits, detection-reliability safeguard, network-partition skip, resource throttling
- [ ] **Discuss:** acceptable false-positive vs false-recovery tradeoffs ([ACCEPTABLE_RISKS.md](reference/ACCEPTABLE_RISKS.md))

---

## 2. Repository map (~5 min) — **core path**

- [ ] **Root entry scripts:** `vpn-monitor.sh`, `vpn-monitor-wrapper.sh`, `vpn-keepalive.sh`
- [ ] **Install / ops:** `install.sh`, `uninstall.sh`, `check-config.sh`, `compare-config.sh`, `analyze-logs.sh`
- [ ] **`lib/`:** modular libraries (aggregate `*.sh` files source subdirs)
- [ ] **`scripts/`:** packaging, deploy, anonymize, lint helpers
- [ ] **`tests/`:** BATS (~90 files), helpers, fixtures, `tests/data/`
- [ ] **`docs/adr/`:** why decisions were made (cron, tiers, state files, etc.)
- [ ] **`.cursor/rules/`:** project conventions agents follow (error handling, testing, no new deps)

---

## 3. Main runtime path: `vpn-monitor.sh` (~15 min) — **core path**

Open `vpn-monitor.sh` and trace one cron execution top to bottom.

- [ ] **Bootstrap:** `set -euo pipefail`, `SCRIPT_DIR`, default paths (`state/`, `logs/`, lockfile)
- [ ] **Module load order:** `logging` → `config` → `state` → `detection` → `recovery` → `lockfile` → `resources`
- [ ] **Early flags:** `--help`, `--version`, `--fake` (`NO_ESCALATE` for test/dry observation)
- [ ] **Directories:** `ensure_directory_exists` for state/logs before config
- [ ] **Config:** `load_config` → `validate_config`; where `LOG_FILE` and paths get reconciled
- [ ] **Cron persistence check:** `check_cron_persistence()` — warns if crontab entry missing
- [ ] **Lock:** acquire lock (overlap protection); stale lock / timeout behavior
- [ ] **Resource gate:** skip or throttle when CPU/RAM/disk constrained (`lib/resources.sh`)
- [ ] **Network partition:** system-wide skip when local connectivity is down
- [ ] **Per-location loop:** how locations are discovered and `monitor_location` (or equivalent) is invoked
- [ ] **Shutdown / lock release:** normal exit paths and exit codes (`lib/constants.sh`)

---

## 4. Configuration (~10 min) — **core path**

- [ ] **Template:** `vpn-monitor.conf` — location variables, thresholds, rate limits, paths
- [ ] **Location format:** `LOCATION_<NAME>_EXTERNAL` / `_INTERNAL` (multi-IP, 30% ping threshold for health)
- [ ] **Schema & defaults:** `lib/config_schema.sh`, `lib/config/config_defaults.sh`
- [ ] **Loading & parsing:** `lib/config/config_loading.sh`, `lib/config/location_parsing.sh`
- [ ] **Validation:** `lib/config/config_validation.sh` — fatal vs test-recoverable errors
- [ ] **CLI tools:** `check-config.sh`, `compare-config.sh`
- [ ] **ADR:** [0024-location-based-configuration](adr/0024-location-based-configuration.md), [0010-configuration-schema-validation](adr/0010-configuration-schema-validation.md)

---

## 5. Detection layer (~15 min) — **core path**

- [ ] **Aggregate entry:** `lib/detection.sh` → sources under `lib/detection/`
- [ ] **Primary:** `lib/detection/xfrm_detection.sh` — byte counter delta, SA/rekey, idle
- [ ] **Fallback:** `ipsec status` path (see `failure_analysis.sh`, guides below)
- [ ] **Supplementary:** `lib/detection/ping_detection.sh` — not primary truth
- [ ] **Failure typing:** `tunnel_down` / `no_traffic` / `idle` / `unknown` state files
- [ ] **System-wide:** `lib/detection/system_wide_failure.sh` — coordinated behavior when many peers fail
- [ ] **Reliability safeguard:** block Tier 2/3 when detection tools unavailable and type is `unknown`
- [ ] **Deep dives (optional):** [IP_XFRM_GUIDE.md](reference/IP_XFRM_GUIDE.md) (UDM ops), [IP_XFRM_IPROUTE2_REFERENCE.md](reference/IP_XFRM_IPROUTE2_REFERENCE.md) (generic syntax), [IPSEC_GUIDE.md](reference/IPSEC_GUIDE.md)
- [ ] **ADRs:** [0019](adr/0019-byte-counter-detection-method.md), [0006](adr/0006-multi-method-detection-with-fallback.md), [0026](adr/0026-detection-reliability-safeguard.md), [0031](adr/0031-system-wide-failure-detection-and-coordination.md)

---

## 6. Recovery layer (~15 min) — **core path**

- [ ] **Aggregate entry:** `lib/recovery.sh` → `lib/recovery/*`
- [ ] **Orchestration:** `lib/recovery/recovery_orchestration.sh` — strategy selection, tier escalation
- [ ] **Per-tunnel xfrm:** `lib/recovery/xfrm_recovery.sh` — preferred Tier 2/3 path
- [ ] **IPsec fallback:** `lib/recovery/ipsec_recovery.sh` — reload/restart (wider blast radius)
- [ ] **Verification:** `lib/recovery/recovery_verification.sh` — post-recovery checks
- [ ] **Recovery state:** `lib/recovery/recovery_state.sh`, cooldown / method tracking
- [ ] **Rate limits & intervals:** global Tier 3 window vs per-location failure counters
- [ ] **ADR:** [0003-tiered-recovery-system](adr/0003-tiered-recovery-system.md), [0029](adr/0029-recovery-type-distinction.md), [0008](adr/0008-rate-limiting-and-cooldown-periods.md)

---

## 7. State and logging (~10 min)

- [ ] **State system doc:** [STATE_SYSTEM.md](reference/STATE_SYSTEM.md)
- [ ] **Paths:** `lib/state/state_paths.sh`, `peer_state.sh`, `global_state.sh`
- [ ] **Per-peer files:** `failure_count_*`, `last_bytes_*`, `failure_type_*`, SPI, idle flags
- [ ] **System-wide files:** `cooldown_until`, `restart_count`, network partition, system-wide failure coordinator
- [ ] **Atomic writes:** `.tmp` + `mv` pattern ([CODE_PATTERNS](reference/CODE_PATTERNS.md), [ADR 0012](adr/0012-atomic-file-operations.md))
- [ ] **State validation:** Format checks on read; checksum validation removed v0.2.0 ([ADR 0013](adr/0013-state-file-checksum-validation.md) — superseded, kept for history)
- [ ] **Logging:** `lib/logging.sh` — levels, `SYSTEM` vs location context, DEBUG gating
- [ ] **Log analysis:** `analyze-logs.sh`

---

## 8. Shared infrastructure (~10 min)

- [ ] **`lib/common.sh`:** IP validation, timestamps, regex helpers, file helpers, fake-mode helpers
- [ ] **`lib/constants.sh`:** exit codes, time constants — used with `handle_error_or_exit_fake_mode` vs `die`
- [ ] **`lib/lockfile.sh`:** flock vs atomic fallback ([ADR 0002](adr/0002-lockfile-protection-mechanism.md))
- [ ] **`lib/resources.sh`:** throttling stats in `lib/state/resource_monitoring_stats.sh`
- [ ] **Error-handling convention:** fatal test-recoverable vs truly fatal vs non-fatal `return 1`
- [ ] **Recent consolidation (if on current branch):** shared regex helpers — `tests/test_common_regex_helpers.sh`, [DUPLICATE_REGEX_PATTERNS.md](research/DUPLICATE_REGEX_PATTERNS.md)

---

## 9. Installation and deployment (~10 min)

- [ ] **`install.sh`:** paths under `/data/vpn-monitor/`, cron entry, permissions, config prompts
- [ ] **Package build:** `scripts/prepare_install_package.sh` (zip/tar)
- [ ] **Deploy from machine:** `scripts/manage/deploy-registry.sh`, `deploy-to-udm.sh`, `deploy-to-udms.sh`
- [ ] **Post-deploy:** [DEPLOYMENT_CHECKLIST.md](../DEPLOYMENT_CHECKLIST.md)
- [ ] **Sub-minute execution:** `vpn-monitor-wrapper.sh` + [ADR 0032](adr/0032-sub-minute-execution-via-wrapper.md)
- [ ] **Keepalive:** `vpn-keepalive.sh` + [ADR 0009](adr/0009-vpn-keepalive-daemon.md)
- [ ] **Version bumps:** `scripts/update-version.sh`, [VERSIONING.md](reference/VERSIONING.md)

---

## 10. Supporting scripts (~5 min, optional)

- [ ] **Anonymization / sharing logs:** `scripts/anonymize/`, `lib/anonymize.sh`
- [ ] **Quality gates:** ShellCheck + shfmt (`.shellcheckrc`, pre-commit), `scripts/check-logging-prefix.sh`
- [ ] **Git hooks:** `scripts/setup-git-hooks.sh` (run after hook changes)

---

## 11. Testing (~10 min)

- [ ] **Runner:** `tests/run_tests.sh` — fast vs `--slow`, parallel jobs, timeout
- [ ] **Framework:** BATS + `tests/helpers/*.bash` (mocks, config, detection, state, assertions)
- [ ] **Fixtures:** `tests/fixtures/` scenarios (`vpn_failing`, `vpn_at_tier`, `vpn_xfrm_recovery`, etc.)
- [ ] **Mapping changes to tests:** [RELEVANT_TESTS.md](testing/RELEVANT_TESTS.md)
- [ ] **Fake mode:** how tests use `NO_ESCALATE` / `handle_error_or_exit_fake_mode`
- [ ] **Principle:** tests exercise real code — do not “fit code to tests”
- [ ] **Try live:** `TEST_TIMEOUT=120 bats tests/test_detection.sh` (or a file relevant to your branch)

---

## 12. Documentation and decisions (~5 min, optional)

- [ ] **Architecture (long form):** [ARCHITECTURE.md](reference/ARCHITECTURE.md) diagrams
- [ ] **Patterns (review / coding):** [CODE_PATTERNS.md](reference/CODE_PATTERNS.md) — **canonical**; search during review, not linear read
- [ ] **Bash gotchas:** [BASH_CODING_GUIDE.md](reference/BASH_CODING_GUIDE.md) — strict mode, traps, review items 39–41/45/47–49
- [ ] **Review history (optional):** [CODE_REVIEW_LESSONS_LEARNED.md](reference/CODE_REVIEW_LESSONS_LEARNED.md) — *why* patterns exist; full sections 1–29 only, 30+ are summary index
- [ ] **ADR index:** [docs/adr/README.md](adr/README.md) — pick 2–3 ADRs matching audience interest
- [ ] **Research docs (future work):** `docs/research/*` — credential storage, server app ideas, etc.

---

## 13. CI and developer workflow (~5 min, optional)

- [ ] **CI badge / workflow:** GitHub Actions (see README)
- [ ] **Local lint:** `shellcheck --severity=error`, `shfmt -d`
- [ ] **DEVELOPER.md:** setup, PR checklist, troubleshooting ([DEV_TROUBLESHOOTING.md](reference/DEV_TROUBLESHOOTING.md))

---

## 14. Branch-specific / in-flight work (customize)

Use this section for whatever is on your branch today. Example items from recent work:

- [ ] Deploy registry and multi-UDM deploy scripts (`scripts/manage/`)
- [ ] Regex helper deduplication (`lib/common.sh`, anonymize, deploy scripts)
- [ ] Config/location parsing changes (`lib/config/location_parsing.sh`)
- [ ] System-wide failure / xfrm / recovery verification tweaks

---

## 45-minute core path (minimum viable walkthrough)

1. §1 Problem and constraints  
2. §2 Repository map  
3. §3 `vpn-monitor.sh` main path  
4. §4 Configuration (skim template only)  
5. §5 Detection (xfrm + safeguard only)  
6. §6 Recovery (orchestration + xfrm vs ipsec blast radius)  
7. §11 Testing (how we gain confidence)

---

## Session wrap-up

- [ ] Recap: detection → state → tier decision → recovery → verification
- [ ] Identify open risks (upgrade wipes cron, global `ipsec restart`, false recovery)
- [ ] Point maintainers to: change code → [RELEVANT_TESTS.md](testing/RELEVANT_TESTS.md) → run subset → ADR if design shifts
- [ ] Schedule follow-up: live UDM trace, failure injection in `--fake`, or deploy dry-run

---

## Quick reference: high-signal files

| Area | Files |
|------|--------|
| Entry | `vpn-monitor.sh`, `vpn-monitor-wrapper.sh`, `vpn-keepalive.sh` |
| Config | `vpn-monitor.conf`, `lib/config/*`, `lib/config_schema.sh` |
| Detect | `lib/detection/xfrm_detection.sh`, `system_wide_failure.sh`, `ping_detection.sh` |
| Recover | `lib/recovery/recovery_orchestration.sh`, `xfrm_recovery.sh`, `ipsec_recovery.sh` |
| State | `lib/state/peer_state.sh`, `global_state.sh`, [STATE_SYSTEM.md](reference/STATE_SYSTEM.md) |
| Shared | `lib/common.sh`, `lib/constants.sh`, `lib/logging.sh`, `lib/lockfile.sh` |
| Install | `install.sh`, `scripts/prepare_install_package.sh` |
| Deploy | `scripts/manage/deploy-to-udm.sh`, `deploy-to-udms.sh`, `deploy-registry.sh` |
| Tests | `tests/run_tests.sh`, `tests/helpers/`, `docs/testing/RELEVANT_TESTS.md` |
