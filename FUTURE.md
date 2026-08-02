Considerations for the future—avoid overarchitecting (YAGNI). Remove a bullet when the behavior exists in-tree.

**Context:** Deploy scripts: `manage/`. Anonymization: `scripts/anonymize/`. State: `lib/state/` (per-peer state with location as parameter; no `location_state.sh`). Tests: 90 `tests/test_*.sh`; mapping in `docs/testing/RELEVANT_TESTS.md`. For `ip` / `ip -s xfrm state` mocks, use `tests/test_helper.bash` and `tests/helpers/mocks.bash`—see `docs/testing/TEST_MAINTENANCE.md`.

- **Observe-only log wording / defense-in-depth** — Recovery suppression logs say “skipped in fake mode” even when mode is observe-only (shared `NO_ESCALATE` gate). Optional: clarify log text (“fake/observe-only”). Optional belt-and-suspenders: refuse `surgical_cleanup` / `full_restart` when `NO_ESCALATE=1` so a future mistaken caller cannot escalate. Priority: LOW (current single gate is correct for production path).

- **`DEFAULT_LAN_INTERFACE` in config (optional)** — Today `lib/constants.sh` sets `DEFAULT_LAN_INTERFACE=br0` (readonly). Nice-to-have: `vpn-monitor.conf` key or auto-detect interface for `LOCAL_UDM_IP` (`ip -o addr show`). Priority: LOW.

- **analyze-logs: richer recovery analytics** — Trends, location-level stats, app-managed vs self-healed breakdown (basic recovery-type distinction already in root `analyze-logs.sh`, 2026-01-06).

- **Module unit tests (`lib/recovery`, `lib/config`)** — Decomposed modules (since 2026-01-11) could use tighter unit coverage alongside integration tests (`docs/reference/CODE_PATTERNS.md`, Fake Mode).
  - **`lib/recovery/`** (`recovery_verification.sh`, `recovery_state.sh`, `recovery_orchestration.sh`, `ipsec_recovery.sh`, `xfrm_recovery.sh`): no or partial dedicated units; exercised via `test_recovery.sh`, `test_helper_functions.sh`.
  - **`lib/config/`** (`config_loading.sh`, `config_validation.sh`, `config_defaults.sh`, `location_parsing.sh`): partial—`test_config.sh`, `test_config_validation.sh`, `test_helper_functions.sh`.

- **Testing cleanup (low churn until touched)** — Refactor `test_recovery_multi_location_partial.sh` (and similar) to use `tests/fixtures/vpn_multi_location.bash`. Add regression test for vpn-monitor-wrapper single-instance lock (second instance exits; install tests only assert cron wiring). Improve `tests/test_lockfile.sh` case that relies on read-only dirs (timing/FS-dependent).

- **Shell API consistency (style / breaking-change candidates)** — (1) Output params: namerefs for scalars (`delete_stale_sas()` precedent) vs `eval`; MEDIUM effort. (2) `handle_error_or_exit_fake_mode`: always branch on its return (`lib/config/` has mixed patterns). (3) `handle_error`: fixed 4-arg shape so numeric messages aren’t mistaken for exit code—breaking; duplication among overloads addressed 2026-01-27; see `CODE_REVIEW_LESSONS_LEARNED.md`. (4) Widespread `source … 2>/dev/null`; stderr visibility—`lib/state.sh` and `lib/config.sh` already fail fast on missing `constants.sh`; rest in `docs/CODEBASE_REVIEW.md`. All LOW unless touched.

- **Location getter exit codes** — `get_location_external_ip` / `get_location_internal_ips`: callers could log EXIT_MALFORMED_DATA (`7`). Optional negative test after parse mutate `LOCATIONS`.

- **DNS resolution** — Cache TTL; partial resolve for multi-IP names; retries (core DNS landed 2026-01-27).

- **System-wide failure & rate limits** — Coordinator policy (ordered vs first-wins); SWF metrics/alerting/infra-tier recovery (e.g. daemon-level); loosen rate caps during SWF. Separately: per-location limits, hit counters, adaptive limits—window/min-interval refactor 2026-01-12.

- **deploy-to-udm.sh: SSH_ASKPASS vs expect** — Replace Tcl `expect` fallback with OpenSSH askpass helpers when `sshpass` absent (LOW; expect path fixed 2026-02-24).

- **centralize-logs.sh** — Alternate crontab paths on UDM variants; doc or tests (LOW).

- **Periodic summary config** — Network partition + resource hourly summaries use `SECONDS_PER_HOUR`; optional `NETWORK_PARTITION_SUMMARY_INTERVAL_MINUTES` (and resource twin) like `PING_SUMMARY_INTERVAL_MINUTES` (LOW).

- **Anonymization** — (1) `set +u`/`set -u` array-empty boilerplate (~55×) → helper (`is_array_empty` style). (2) CIDR-aware `/8` `/16` network normalization in anon pipeline (≠ last-octet-only `/24`; see `CODE_REVIEW_LESSONS_LEARNED.md`).
