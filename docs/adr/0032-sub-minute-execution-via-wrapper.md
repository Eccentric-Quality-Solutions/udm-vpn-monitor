# ADR-0032: Sub-Minute Execution via Wrapper Script

## Status
Accepted

**Implemented:** 2026-02-11

## Context

The VPN monitor runs on a cron schedule (default: every 1 minute). Standard cron does not support sub-minute intervals natively. With default tier thresholds (`TIER1_THRESHOLD=1`, `TIER2_THRESHOLD=2`, `TIER3_THRESHOLD=3`):

- **Tier 2** triggers after 2 consecutive failures (~1–2 minutes with 1-minute cron)
- **Tier 3** triggers after 3 consecutive failures (~2–3 minutes with 1-minute cron)

Faster failure detection and recovery (e.g., checks every 20–30 seconds) requires an alternative to pure once-per-minute cron execution.

[ADR-0001](0001-cron-based-execution.md) chose cron-based run-and-exit execution over a long-running monitor daemon because UDM OS upgrades and restarts disrupt long-running processes, and cron provides simpler recovery (process exits, cron respawns it). That decision still applies to **`vpn-monitor.sh` itself** — each check remains an independent run-and-exit invocation.

We evaluated several approaches before implementing (see **Alternatives Considered** below). The goal was sub-minute checks **without** converting the core monitor into a daemon or revisiting the cron resilience model.

## Decision

We will use an optional **`vpn-monitor-wrapper.sh`** that runs `vpn-monitor.sh` in a loop with configurable `MONITOR_INTERVAL` seconds between checks.

- **Enabled by default** (`ENABLE_MONITOR_WRAPPER=1` in `vpn-monitor.conf`; installer sets cron accordingly)
- **Cron still runs every minute**, invoking the wrapper (backgrounded with `&`)
- **Wrapper loops** with `sleep "$MONITOR_INTERVAL"` (default: 20 seconds; range: 10–60)
- **`vpn-monitor.sh` is unchanged** in its run-and-exit model; lockfile protection still prevents overlapping monitor runs

This preserves ADR-0001 for the monitor core while adding a thin scheduling layer — similar in spirit to the optional keepalive daemon ([ADR-0009](0009-vpn-keepalive-daemon.md)), but driven by cron rather than systemd.

**Rejected for the main monitor:** Full daemon mode (Option 4 below) — would conflict with ADR-0001 and require signal handling, config reload, and process lifecycle management in the monitor itself.

## Alternatives Considered

| Option | Summary | Outcome |
|--------|---------|---------|
| **1. Multiple cron entries** | Two cron lines (`* * * * *` and `sleep 30; ...`) | Rejected — inflexible interval, two entries to manage, installer complexity |
| **2. Self-scheduling wrapper** | Cron starts wrapper; wrapper loops with `MONITOR_INTERVAL` | **Chosen** — configurable, minimal monitor changes, same cron restoration path |
| **3. Systemd timer** | `OnUnitActiveSec=30s` timer invoking oneshot service | Not chosen — different operational model; enabled/started state may not survive upgrades; cron + wrapper is simpler to restore |
| **4. Monitor daemon** | `while true` loop inside `vpn-monitor.sh` with systemd | Rejected — major architectural change; conflicts with ADR-0001 |
| **5. Hybrid internal loop** | Multiple checks per cron invocation inside `vpn-monitor.sh` | Rejected — still needs wrapper or multiple cron entries for true sub-minute timing; adds complexity to monitor |
| **Lower thresholds only** | Reduce `TIER2_THRESHOLD` / `TIER3_THRESHOLD` without sub-minute checks | Valid tuning alternative; does not achieve sub-minute detection granularity — use wrapper when faster checks are required |

### Persistence note

Both cron jobs and systemd units can be affected by UniFi OS upgrades. ADR-0001’s statement that cron is *more likely* to survive upgrades is relative, not a guarantee. The wrapper advantage is **operational simplicity**: re-run the installer to restore one cron entry that resurrects the wrapper, without managing separate timer/service enablement.

## Consequences

### Positive
- **Faster detection/recovery**: With `MONITOR_INTERVAL=20` and default thresholds, Tier 2 can trigger after ~40 seconds (2 failures × 20s)
- **Preserves monitor model**: `vpn-monitor.sh` remains run-and-exit; easier debugging per invocation
- **Configurable**: `MONITOR_INTERVAL` (10–60 seconds) without crontab edits
- **Cron resilience**: If the wrapper exits, cron restarts it on the next minute boundary
- **Lockfile safety**: Monitor lockfile prevents overlapping `vpn-monitor.sh` runs; wrapper has its own exclusive lock
- **Optional**: `ENABLE_MONITOR_WRAPPER=0` restores direct cron → `vpn-monitor.sh` (once per minute)

### Negative
- **Long-running wrapper process**: Less resilient than pure run-and-exit cron; wrapper can be killed between cron respawns
- **Process management**: Wrapper requires PID file and exclusive lock (`flock` or mkdir fallback) to prevent duplicate instances when cron fires while a previous wrapper is still running
- **Cron overlap window**: Cron runs wrapper every minute with `&`; second instance must exit quietly if lock is held
- **Upgrade restoration**: Cron entry (and wrapper script under `/data/vpn-monitor/`) may need re-install after UniFi OS upgrades — same class of problem as ADR-0001
- **Timing imprecision**: Checks occur at `interval` offsets from wrapper start, not aligned to clock boundaries (e.g., :00/:20/:40) unless wrapper happens to start on a boundary

## Implementation Details

### Configuration

In `vpn-monitor.conf` (schema in `lib/config_schema.sh`):

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_MONITOR_WRAPPER` | `1` | When `1`, installer configures cron to run `vpn-monitor-wrapper.sh` |
| `MONITOR_INTERVAL` | `20` | Seconds between checks (range: 10–60) |

### Cron entry (when wrapper enabled)

```bash
*/1 * * * * /data/vpn-monitor/vpn-monitor-wrapper.sh >> /data/vpn-monitor/logs/cron.log 2>&1 &
```

The trailing `&` backgrounds the wrapper so cron returns immediately. Cron re-invokes every minute; if a wrapper is already running, the new instance acquires the wrapper lock, finds it held, and exits 0 (avoiding cron failure noise).

### Wrapper behavior (`vpn-monitor-wrapper.sh`)

1. Source `lib/common.sh` for shared helpers (`is_non_negative_integer`, etc.)
2. Read and clamp `MONITOR_INTERVAL` from config (10–60 seconds)
3. **`acquire_wrapper_lock()`**: atomic exclusive lock via `flock` on `state/vpn-monitor-wrapper.pid` (preferred) or `mkdir` fallback — replaces earlier TOCTOU-prone PID check (2026-02)
4. **Loop**: run `vpn-monitor.sh` (append stdout/stderr to `logs/cron.log`); log non-zero child exit codes with timestamp (2026-02 — failures no longer silent); `sleep "$interval"`; repeat
5. **`--help`**: documents config options

Monitor invocations still use the existing lockfile in `vpn-monitor.sh` / `lib/lockfile.sh` (ADR-0002).

### Expected timing impact

With `MONITOR_INTERVAL=20` and thresholds 1/2/3:

- Tier 2: ~40 seconds after sustained failure (2 × 20s)
- Tier 3: ~60 seconds after sustained failure (3 × 20s)

With direct cron (wrapper disabled) and 1-minute schedule:

- Tier 2: ~1–2 minutes
- Tier 3: ~2–3 minutes

### Installer

`install.sh` copies `vpn-monitor-wrapper.sh` to the install directory, sets `ENABLE_MONITOR_WRAPPER` and `MONITOR_INTERVAL` in config, and wires cron to the wrapper when enabled.

## Related ADRs

- [ADR-0001](0001-cron-based-execution.md): Cron-based execution — applies to `vpn-monitor.sh`; wrapper is an optional scheduling layer
- [ADR-0002](0002-lockfile-protection-mechanism.md): Lockfile prevents concurrent monitor runs
- [ADR-0003](0003-tiered-recovery-system.md): Tier thresholds define how many consecutive failures trigger recovery
- [ADR-0009](0009-vpn-keepalive-daemon.md): Other optional long-running process; independent purpose (idle traffic)

## References

- `vpn-monitor-wrapper.sh`: Wrapper implementation
- `vpn-monitor.conf`: `ENABLE_MONITOR_WRAPPER`, `MONITOR_INTERVAL`
- `lib/config_schema.sh`: Schema defaults and validation
- `install.sh`: Cron wiring and wrapper installation
- `tests/test_vpn_monitor_wrapper.sh`: Wrapper behavior tests
- `tests/test_install.sh`: Cron entry uses wrapper when enabled
- [ARCHITECTURE.md](../reference/ARCHITECTURE.md): Sub-minute execution overview
- [ISSUES_AND_TECH_DECISIONS.md](../ISSUES_AND_TECH_DECISIONS.md): Platform constraints and decision timeline
- CHANGELOG.md v0.8.x: Wrapper introduction, lock hardening, exit-code logging
