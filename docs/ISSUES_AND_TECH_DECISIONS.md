# Issues Encountered and Technical Decisions

**Purpose:** Capture the problems we hit while building UDM VPN Monitor, what we learned about UniFi Dream Machine constraints, and which issues drove major architectural choices. Synthesized from git history, [Architecture Decision Records](adr/README.md), [CHANGELOG.md](../CHANGELOG.md), [CODE_REVIEW_LESSONS_LEARNED.md](reference/CODE_REVIEW_LESSONS_LEARNED.md), and research docs.

**Audience:** New contributors, walkthrough sessions, and future us when wondering *why* something is the way it is.

---

## Executive Summary

Most big decisions trace back to one theme: **the UDM is not a general-purpose Linux box**. Cron runs with a stripped PATH, common utilities are missing, firmware upgrades wipe non-`/data` state, and IPsec tooling behaves differently than on a normal server. We chose **bash + cron + file-based state in `/data`** because that survives the environment better than daemons, interpreted languages, or databases.

Detection and recovery logic grew complex mainly to fight **false positives** (idle tunnels, SA rekeys, local network outages, timing bugs) and **false recoveries** (restarting VPNs when we couldn't actually see tunnel state).

---

## UDM Platform Constraints (What Doesn't Work or Isn't There)

These constraints appear repeatedly in commits and ADRs. They are not optional polish—they shaped the stack.

| Constraint | Impact | How we adapted |
|------------|--------|----------------|
| **No Python, Node, jq, Perl, Ruby** | Can't use modern tooling or JSON parsers | Pure bash; awk/sed/grep for text processing ([ADR-0017](adr/0017-bash-scripting-language.md)) |
| **`bc` not packaged** | Floating-point math in shell scripts fails | Use `awk` instead ([CHANGELOG v0.4.x](../CHANGELOG.md); [UDM-Linux-Tools.md](../UDM-Linux-Tools.md)) |
| **`swanctl` unavailable** | Can't use StrongSwan control utility | Use `ipsec` + `ip xfrm`; removed install attempts (git `288aaca`) |
| **`zip` not on UDM** | Can't unpack zip archives on device | Ship **tar.gz**; `prepare_install_package.sh` supports both ([commit 0a69d0e](../CHANGELOG.md)) |
| **`logread` unavailable** | OpenWrt-style log reading doesn't exist | Use `journalctl` / `dmesg` |
| **Restricted PATH in cron/systemd** | `ip`, `ipsec`, `ping` in `/usr/sbin` appear "missing" | `check_command_available()` + `get_command_path()` with directory fallbacks ([ADR-0027](adr/0027-enhanced-command-availability-checking.md)) |
| **`/tmp` cleared on reboot** | State/logs lost if stored there | Everything persistent under **`/data/vpn-monitor/`** ([ADR-0016](adr/0016-state-file-location-data-vpn-monitor.md)) |
| **Cron jobs wiped on UniFi OS upgrades** | Monitoring silently stops after upgrade | Document re-install; `check_cron_persistence()` warns; not "upgrade-proof" ([README](../README.md)) |
| **`apt-get` packages don't survive firmware updates** | sshpass, expect, nano, etc. vanish on upgrade | Prefer SSH keys; on-boot-script pattern documented ([UDM_PACKAGE_INSTALLATION.md](scripts/UDM_PACKAGE_INSTALLATION.md)) |
| **UDM-specific `ip -s xfrm state` format** | Byte counters on separate line after `lifetime current:` | Custom parsing in `xfrm_detection.sh` ([ADR-0019](adr/0019-byte-counter-detection-method.md)) |
| **Ping to remote internal IPs needs local source on `br0`** | Ping fails without `LOCAL_UDM_IP` on LAN bridge | `ip addr add` on default LAN interface—not a route ([CODE_REVIEW_LESSONS_LEARNED.md](reference/CODE_REVIEW_LESSONS_LEARNED.md)) |
| **xfrm SA delete needs all selectors** | Deleting by src/dst/spi alone fails with "No such process" when `mark` is set | Parse and include `mark` in delete commands (Lesson 27 in CODE_REVIEW_LESSONS_LEARNED) |
| **No `swanctl` → no Phase 1 IKE query** | Can't distinguish Phase 1 down vs Phase 2 negotiation failure when ESP SA missing | Defer Phase 1 detection; uniform `tunnel_down` + recovery fallback ([ADR-0022](adr/0022-phase-1-detection-deferred.md)) |
| **`ip xfrm state` can hang (netlink/XFRM lock)** | Detection looks like xfrm is "unavailable"; script blocks indefinitely | Wrap with `timeout` (5s); fall back to `ipsec status` ([CHANGELOG v0.7.0](../CHANGELOG.md)) |
| **Resource limits on appliance** | Heavy monitoring could load the UDM | Resource monitoring + throttling; optional early exit ([ADR-0023](adr/0023-resource-monitoring-and-throttling.md)) |

See also [UDM-Linux-Tools.md](../UDM-Linux-Tools.md) for the canonical available/unavailable tool list.

---

## Major Architectural Decisions and What Triggered Them

### Cron-based execution instead of a long-running monitor daemon

**Trigger:** UDM OS kills or disrupts long-running processes during upgrades/restarts; cron is simpler to restore after failure.

**Decision:** [ADR-0001](adr/0001-cron-based-execution.md) — script runs, exits, cron respawns it.

**Trade-off:** Minimum 1-minute granularity unless we add a wrapper (see below).

---

### Bash-only, modular libraries

**Trigger:** No guaranteed interpreters beyond bash; need tight integration with `ip` / `ipsec` / `ping`.

**Decision:** [ADR-0017](adr/0017-bash-scripting-language.md), [ADR-0005](adr/0005-modular-library-architecture.md).

**Trade-off:** Testing via BATS; string parsing instead of structured data.

---

### Byte counters (`ip xfrm state`) as primary detection

**Trigger:** IKE/SA "up" does not mean traffic flows; idle tunnels look dead if you only check existence.

**Decision:** [ADR-0019](adr/0019-byte-counter-detection-method.md) — compare byte counters run-over-run.

**Issues discovered later:**
- First run has no baseline
- SA **rekey** resets counters → false failure ([ADR-0020](adr/0020-sa-rekey-detection-and-handling.md))
- Idle tunnels with static bytes → need ping supplement ([ADR-0014](adr/0014-ping-check-as-supplementary-diagnostic.md))
- UDM multi-line xfrm output required format-specific parsing

---

### Optional keepalive systemd service

**Trigger:** Idle tunnels produced false positives; byte counters don't increment without traffic.

**Decision:** [ADR-0009](adr/0009-vpn-keepalive-daemon.md) — separate optional daemon sends periodic pings.

**Note:** Monitor stays cron-based; keepalive is additive, not a replacement for ADR-0001.

---

### Tiered recovery (log → surgical xfrm → full restart)

**Trigger:** Always restarting IPsec disrupts all tunnels; transient blips shouldn't trigger nuclear options.

**Decision:** [ADR-0003](adr/0003-tiered-recovery-system.md) with per-tunnel xfrm preferred over global `ipsec reload`/`restart`.

**Later refinement:** Tier 2 **`ipsec reload` disabled by default** (`ENABLE_TIER2_IPSEC_RELOAD=0`) because it affects all connections—too disruptive when xfrm per-tunnel recovery works.

**Rate limiting evolution:** Early cooldown blocked *all* monitoring for 15 minutes after Tier 3 restart—delayed failure detection during outages. Refactored to sliding window + minimum interval; monitoring continues ([ADR-0008](adr/0008-rate-limiting-and-cooldown-periods.md)).

---

### Location-based configuration (multi-site)

**Trigger:** Flat `EXTERNAL_PEER_IPS` / `INTERNAL_PEER_IPS` arrays didn't scale; logs and state files were IP-only and hard to correlate with sites.

**Decision:** [ADR-0024](adr/0024-location-based-configuration.md) — `LOCATION_<NAME>_EXTERNAL` / `_INTERNAL`; location names in state files and log prefixes.

**Trade-off:** Breaking config change; old state files not auto-migrated.

---

### Phase 1 (IKE) detection deferred

**Trigger:** When Phase 2 ESP SA is missing, we can't tell Phase 1 IKE down from Phase 2 negotiation failure. **`swanctl`** (the normal Phase 1 query tool) isn't on UDM; `ipsec status` Phase 1 parsing untested across OS versions.

**Decision:** [ADR-0022](adr/0022-phase-1-detection-deferred.md) — treat all tunnel-down as `tunnel_down`; try xfrm recovery first, fall back to `ipsec restart` at Tier 3 if xfrm times out (~30s).

**Trade-off:** Up to 30s delay when Phase 1 is actually down; acceptable because recovery still works via fallback.

---

### Simplified byte counter detection (v0.2.0)

**Trigger:** Historical traffic-pattern analysis (samples, rate calc, pruning) added complexity without clear benefit for a single deployment.

**Decision:** Simple heuristics only: bytes increasing = healthy; static + ping fail = broken ([ADR-0019](adr/0019-byte-counter-detection-method.md) change history).

**Trade-off:** Less nuance for edge-case traffic patterns; much easier to reason about and test.

---

### Multi-method detection with fallback

**Trigger:** Single-method detection fails when tools unavailable or output ambiguous; need idle vs broken distinction.

**Decision:** [ADR-0006](adr/0006-multi-method-detection-with-fallback.md) — primary `ip xfrm state`, fallback `ipsec status`, optional ping.

**Critical lesson (v0.8.0):** When xfrm says SA exists but bytes/ping indicate failure, **skip ipsec fallback** — `ipsec status` can still show "established" for a broken tunnel and was resetting failure counts, blocking recovery.

---

### File-based state in `/data/vpn-monitor/state/`

**Trigger:** Need persistence across reboots; JSON/SQLite libraries unavailable; simplicity on single deployment.

**Decision:** [ADR-0015](adr/0015-file-based-state-storage.md), [ADR-0016](adr/0016-state-file-location-data-vpn-monitor.md), per-peer files ([ADR-0004](adr/0004-per-peer-state-tracking.md)).

**Removed:** Checksum validation ([ADR-0013](adr/0013-state-file-checksum-validation.md)) — deprecated; complexity didn't pay off.

---

### Sub-minute checks via wrapper script

**Trigger:** Cron minimum is 1 minute; we wanted ~20–30s detection without abandoning cron resilience entirely.

**Decision:** [ADR-0032](adr/0032-sub-minute-execution-via-wrapper.md) — **`vpn-monitor-wrapper.sh`** (implemented 2026-02). Cron still resurrects the wrapper each minute; wrapper loops with `MONITOR_INTERVAL`.

**Rejected for main monitor:** Full daemon mode (conflicts with ADR-0001).

---

### Network partition detection

**Trigger:** Local ISP/router outages can cause VPN checks and recovery attempts that could never succeed.

**Decision:** [ADR-0025](adr/0025-network-partition-detection.md) — check default route, DNS, interfaces; skip VPN work when partitioned.

---

### System-wide failure coordination

**Trigger:** All locations failing at once (infrastructure outage) can cause recovery stampedes and rate-limit hits.

**Decision:** [ADR-0031](adr/0031-system-wide-failure-detection-and-coordination.md) — detect simultaneous failures; one coordinator attempts recovery.

---

### Detection reliability safeguard

**Trigger:** When both `ip` and `ipsec` are unavailable (often PATH in cron), "unknown" failures triggered recovery anyway.

**Decision:** [ADR-0026](adr/0026-detection-reliability-safeguard.md) — skip Tier 2/3 escalation if detection tools missing.

---

### Enhanced command path resolution

**Trigger:** A monitor can work interactively but fail under cron due to PATH differences.

**Decision:** [ADR-0027](adr/0027-enhanced-command-availability-checking.md) — search `/usr/sbin`, `/sbin`, etc., not just PATH.

---

### Centralized fallback functions (removed)

**Trigger:** Attempt to DRY detection fallbacks.

**Outcome:** [ADR-0030](adr/0030-centralized-fallback-functions.md) **deprecated and removed 2026-01-18** — indirection hurt clarity; explicit fallbacks per call site won.

---

## Bugs and Incidents (Git History + Docs)

Grouped by theme. Each item includes the symptom, root cause, and fix pattern where known.

### False positives — detection

| Issue | Symptom | Root cause | Fix / doc |
|-------|---------|------------|-----------|
| **False "routing issue"** | Every healthy tunnel flagged as routing failure | `last_bytes` written in `check_byte_counters` before `check_routing_issue_for_failure_type` read it; same-run `current == last` looked like regression | Defer `last_bytes` persistence until after failure-type logic ([commit 0c1487f](../CHANGELOG.md)) |
| **Idle tunnel marked failed** | SA up, bytes static, ping OK, still failed | Routing-issue override ignored primary pass; `idle_detected` cleared too aggressively | Respect primary pass for `routing_issue`; only clear idle flag when bytes **increasing** ([CHANGELOG 0.8.x](../CHANGELOG.md)) |
| **Startup false failures** | Tunnels flagged immediately on script start | Checked tunnel status before xfrm/IPsec fully settled | Startup grace period (default 5s) ([commit c0a6f6a](../CHANGELOG.md)) |
| **SA rekey false failure** | Healthy tunnel flagged after rekey | Byte counters reset to 0 on new SPI | SPI tracking + baseline reset ([ADR-0020](adr/0020-sa-rekey-detection-and-handling.md)) |
| **Idle VPN false failure** | Zero/static bytes with working tunnel | Byte-only detection can't distinguish idle vs broken | Ping supplement + keepalive suggestion ([ADR-0014](adr/0014-ping-check-as-supplementary-diagnostic.md), [ADR-0009](adr/0009-vpn-keepalive-daemon.md)) |
| **xfrm error false positive** | xfrm command errors treated as tunnel down | Over-aggressive error classification | Improved diagnostics + grace ([commit c0a6f6a, 8d93fd9](../CHANGELOG.md)) |
| **xfrm command hang** | Detection reports xfrm unavailable; cron run stalls | `ip xfrm state` blocks on netlink/XFRM lock (12–13s+ documented) | `timeout` wrapper (`XFRM_STATE_TIMEOUT=5`); graceful fallback to `ipsec status` |
| **ipsec fallback false negative** | Tunnel broken but failure count resets; recovery never triggers | `ipsec status` shows "established" while bytes/ping fail | Skip ipsec fallback when xfrm reports SA exists but validation failed ([CHANGELOG 0.8.0](../CHANGELOG.md)) |
| **Alternative route false alarm** | SA down but ping succeeds | Traffic using non-VPN path | Log warning + `ip route get` diagnostics ([ADR-0014](adr/0014-ping-check-as-supplementary-diagnostic.md)) |

### False positives — environment

| Issue | Symptom | Root cause | Fix / doc |
|-------|---------|------------|-----------|
| **Network partition** | VPN recovery during ISP outage | Can't reach peers when local network is down | Network partition checks ([ADR-0025](adr/0025-network-partition-detection.md)) |
| **Missing detection tools** | Recovery with no reliable signal | Cron PATH; both `ip` and `ipsec` missing | Detection reliability safeguard ([ADR-0026](adr/0026-detection-reliability-safeguard.md)) |
| **All locations fail at once** | Recovery storm during infra outage | Independent per-location recovery | System-wide failure coordination ([ADR-0031](adr/0031-system-wide-failure-detection-and-coordination.md)) |

### Recovery failures

| Issue | Symptom | Root cause | Fix / doc |
|-------|---------|------------|-----------|
| **xfrm delete "No such process"** | Per-tunnel recovery fails though SA exists | Kernel requires **mark** selector when SA has mark attribute | Parse all selectors including mark (CODE_REVIEW Lesson 27) |
| **SA dedup partial keys** | Recovery targets wrong SA or misses one | Multiple SAs share src/dst but differ by SPI (rekey overlap) | Deduplicate on src+dst+**SPI**, not src+dst alone (CODE_REVIEW Lesson 30) |
| **xfrm recovery timeout on Phase 1 down** | ~30s before global restart | Can't detect Phase 1 failure without swanctl | Accepted; Tier 3 `ipsec restart` fallback ([ADR-0022](adr/0022-phase-1-detection-deferred.md)) |
| **Ping-based recovery gap** | Ping fails but tier never advances | Ping was warning-only; ipsec fallback reset failure count | Ping failure counts toward tiers; skip ipsec fallback when xfrm says SA exists ([CHANGELOG 0.8.0](../CHANGELOG.md)) |
| **Tier 2 too disruptive** | `ipsec reload` bounced all tunnels | Global reload at Tier 2 | xfrm default; `ENABLE_TIER2_IPSEC_RELOAD=0` by default ([commit 2bdc956](../CHANGELOG.md)) |

### State, locking, and persistence

| Issue | Symptom | Root cause | Fix / doc |
|-------|---------|------------|-----------|
| **State corruption** | Inconsistent failure counts / peer state | Race or ordering in state writes | Fixes in fix-routing-issue PR series ([commit a6db56f](../CHANGELOG.md)) |
| **Restart count file corruption** | State validation fails; odd rate-limit behavior | Compacting expired timestamps wrote **empty file** | Remove file instead of writing empty content ([CHANGELOG 0.8.x](../CHANGELOG.md)) |
| **Lockfile far-future mtime** | Monitor never runs; stale lock not cleared | Corrupt or wrong clock on lockfile timestamp | Treat mtime >1 hour skew as stale ([CHANGELOG 0.8.x](../CHANGELOG.md)) |
| **Hang on unreadable state** | Script blocks during state validation | `find`/read on 000-permission state files | Readability check before processing ([CHANGELOG v0.5.x](../CHANGELOG.md)) |
| **Config `#` in values** | Values truncated or misparsed | Naive `#` comment stripping broke quoted strings | Quote-aware config parsing ([commit c96dafb](../CHANGELOG.md)) |
| **Lockfile races** | Duplicate instances, stale locks | Non-blocking flock + stale removal windows | Documented as acceptable risks where impact is low ([ACCEPTABLE_RISKS.md](reference/ACCEPTABLE_RISKS.md)) |
| **Lock after init window** | "Another instance running" log noise | Lock acquired after config load | Accepted risk — moving earlier conflicts with configurable paths ([ACCEPTABLE_RISKS.md](reference/ACCEPTABLE_RISKS.md)) |
| **Checksum validation overhead** | Complexity without clear win | Over-engineering for single deployment | Removed ([ADR-0013](adr/0013-state-file-checksum-validation.md)) |

### UDM-specific operational issues

| Issue | Symptom | Root cause | Fix / doc |
|-------|---------|------------|-----------|
| **PATH in cron** | `ip xfrm` works in SSH, fails in cron | Restricted PATH excludes `/usr/sbin` | `get_command_path()`, enhanced availability checks |
| **Ping to remote LAN fails** | Internal peer unreachable from UDM | Missing source IP on bridge | Auto `ip addr add` for `LOCAL_UDM_IP` on `br0` ([commit b824bb7](../CHANGELOG.md)) |
| **Install path confusion** | State lost | Used non-persistent paths | Standardize on `/data/vpn-monitor` ([commit 6f112a7](../CHANGELOG.md)) |
| **Cron wiped on upgrade** | Monitoring stops silently | UniFi OS upgrade behavior | Document + persistence check; re-run installer |
| **Wrapper swallowed errors** | Child crashes invisible in logs | `|| true` on wrapper loop | Log non-zero child exit codes ([CHANGELOG 0.8.x](../CHANGELOG.md)) |
| **Wrapper duplicate instances** | Overlapping monitor runs | PID-file check TOCTOU race | Atomic `flock` in `acquire_wrapper_lock()` ([CHANGELOG 0.8.x](../CHANGELOG.md)) |
| **Early script hang** | Cron overlap / stuck after run | Lock or subprocess cleanup edge cases | Lockfile and pipestatus fixes (early commits e.g. `b366dea`) |

### Deployment and dev tooling (off-UDM but UDM-driven)

| Issue | Symptom | Root cause | Fix / doc |
|-------|---------|------------|-----------|
| **zip on UDM** | Can't unpack deploy package on device | `zip` not installed | tar.gz for on-device use; zip optional for dev ([commit 0a69d0e](../CHANGELOG.md)) |
| **Multiple SSH password prompts** | Deploy UX painful | Separate scp/ssh sessions | SSH ControlMaster + ControlPersist ([CHANGELOG 0.8.3](../CHANGELOG.md)) |
| **`sshpass` + `ssh -f` hang** | Deploy script hangs forever | sshpass waits on pty EOF | Use `ssh ... true` synchronously, not `-f` ([CODE_PATTERNS.md](reference/CODE_PATTERNS.md)) |
| **expect security/reliability** | Fragile password automation | Tcl expect edge cases | Harden expect; cascade sshpass → expect → manual `/dev/tty` |
| **set -e in install/keepalive** | Install fails mid-way | Unhandled return in pipeline | Explicit fixes ([commits f6f9a18, c4950a4, ae60da4](../CHANGELOG.md)) |

---

## Timeline (High Level)

Rough evolution visible in git log:

1. **Initial (3c79487)** — cron monitor, basic detection, `/data` install path
2. **Modularization (81b8296, 04d5212)** — lib split, BATS, CI
3. **UDM hardening (288aaca, 4518eb0)** — drop swanctl/bc, check-utilities, PATH awareness
4. **Detection depth (96aa76a, fe42a9f)** — rekey, network partition, reliability safeguard; simplified byte counters (v0.2.0)
5. **Location config + deploy (eb19875, ea10c77)** — multi-site, multi-UDM scripts; location-based config ([ADR-0024](adr/0024-location-based-configuration.md))
6. **False routing issue fix (0c1487f, PR #7–#12)** — last_bytes ordering, state corruption
7. **xfrm timeout + sub-minute (5d449b5)** — hang protection, monitor wrapper
8. **Deploy + ping behavior (224eabc, 0.8.0)** — ControlMaster, tar, Tier 2 defaults; ping counts toward recovery; ipsec fallback skip

---

## Patterns We Keep Relearning

From [CODE_REVIEW_LESSONS_LEARNED.md](reference/CODE_REVIEW_LESSONS_LEARNED.md) and [CODE_PATTERNS.md](reference/CODE_PATTERNS.md):

1. **Defer state writes** when later logic in the same run must read the *previous* value (`last_bytes` / routing issue).
2. **Test in cron-like PATH**, not just interactive SSH — detection bugs often only appear in production scheduling.
3. **Parse all kernel selectors** — partial xfrm keys cause misleading "No such process" errors.
4. **Don't restart VPNs when you can't see** — if detection tools are gone, log and skip recovery.
5. **Distinguish local outage vs VPN outage** — network partition before recovery.
6. **Use `/data`, atomic writes, lockfiles** — UDM storage and concurrency are unforgiving.
7. **Avoid UDM-unsupported tools** — if it's not in `UDM-Linux-Tools.md`, don't depend on it.
8. **Don't trust `ipsec status` alone** — it can show established when traffic isn't flowing; byte counters + ping matter.
9. **Wrap blocking kernel/netlink calls** — `ip xfrm state` can hang under stress; always timeout and fall back.
10. **Composite keys for kernel objects** — SA dedup and delete need full selector sets (SPI, mark, etc.).

---

## Open / Accepted Limitations

Documented explicitly so we don't re-litigate:

- **Not upgrade-proof** — cron and sometimes `/data` content may need re-install ([README](../README.md))
- **Lockfile timing window** after script init ([ACCEPTABLE_RISKS.md](reference/ACCEPTABLE_RISKS.md))
- **Sub-minute via wrapper** trades pure cron simplicity for a long-running loop ([ADR-0032](adr/0032-sub-minute-execution-via-wrapper.md))
- **Phase 1 vs Phase 2 ambiguity** — without swanctl, up to ~30s xfrm timeout before Tier 3 restart ([ADR-0022](adr/0022-phase-1-detection-deferred.md))
- **Global `ipsec restart` fallback** still affects all tunnels when xfrm recovery fails
- **Future ideas** not implemented — see [FUTURE.md](../FUTURE.md) (server app, credential encryption options, etc.)

---

## Where to Go Deeper

| Topic | Document |
|-------|----------|
| All formal decisions | [docs/adr/](adr/README.md) |
| Code patterns & UDM constraints | [CODE_PATTERNS.md](reference/CODE_PATTERNS.md) § UDM-Specific Constraints |
| Review-driven bug stories | [CODE_REVIEW_LESSONS_LEARNED.md](reference/CODE_REVIEW_LESSONS_LEARNED.md) |
| Walkthrough agenda | [CODE_WALKTHROUGH_CHECKLIST.md](CODE_WALKTHROUGH_CHECKLIST.md) |
| Release-level changes | [CHANGELOG.md](../CHANGELOG.md) |
| User-facing troubleshooting | [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) |
| Tool availability on UDM | [UDM-Linux-Tools.md](../UDM-Linux-Tools.md) |
| Deploy / package constraints | [UDM_PACKAGE_INSTALLATION.md](scripts/UDM_PACKAGE_INSTALLATION.md) |

---

## Related Note

[walkthrough.md](walkthrough.md) opens with: *"Writing for UDMs is difficult."* This document is the expanded answer to *why*—the missing utilities, PATH surprises, persistence fragility, and detection false positives that forced most of the architecture.
