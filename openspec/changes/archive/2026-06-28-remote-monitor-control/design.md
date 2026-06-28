## Context

VPN Monitor runs on each UDM via cron (direct `vpn-monitor.sh` or `vpn-monitor-wrapper.sh` per ADR-0001 and ADR-0032). An optional keepalive daemon runs under systemd (ADR-0009). There is no first-class way to stop monitoring during maintenance, schedule a maintenance window, or run in log-only mode without SSHing to each device and manually editing cron or config.

Existing management tooling (`scripts/manage/deploy-to-udm.sh`, `deploy-to-udms.sh`) already establishes SSH ControlMaster sessions to UDMs using patterns documented in `docs/reference/CODE_PATTERNS.md`. This change adds symmetric **control** tooling using the same transport.

Constraints: UDM OS 4.3+ only; bash + standard utilities; no python3/jq/node; atomic state writes; existing error-handling and logging conventions.

## Goals / Non-Goals

**Goals:**

- Four operating modes on each UDM: **running** (default), **stopped**, **paused-until** (time-bound, no execution), **observe-only** (detect + log, no recovery).
- Local CLI on UDM: `vpn-monitor-control.sh start|stop|pause|observe-only|status`.
- Remote CLI from controller: `scripts/manage/control-remote-udm.sh` targeting one host or a batch config file.
- Auto-resume from pause when end time passes.
- Immediate rollback via `start` (restores normal operation).
- Log all mode transitions at INFO in `vpn-monitor.log`.

**Non-Goals:**

- Web UI or REST API (future management server may wrap the remote CLI).
- Per-location pause (all-or-nothing at the UDM level for v1).
- Authentication beyond existing SSH (no new credential store in this change).
- Remote install/uninstall (deployment scripts remain separate).
- Changing detection algorithms or recovery tier thresholds.

## Decisions

### 1. Operating-mode state file (not config edits)

**Decision:** Persist mode in `state/operating_mode` as a simple key=value file:

```
mode=running|stopped|paused|observe-only
paused_until=<epoch_seconds>   # only when mode=paused
set_at=<epoch_seconds>
set_by=<username or "remote">
reason=<optional free text>
```

**Rationale:** Config file edits require validation/reload and are user-managed. A dedicated state file matches existing per-run state patterns (`docs/reference/STATE_SYSTEM.md`), supports atomic writes, and is easy to inspect on-UDM.

**Alternatives considered:**
- *Cron-only stop/start*: Works for stop but cannot express observe-only or timed pause without re-creating cron entries differently each time.
- *New config vars (`OPERATING_MODE=...`)*: Mixes operational overrides with static config; harder to set remotely without touching user config.

### 2. Stop and pause behavior

**Decision:**

| Mode | Cron/wrapper | Keepalive | Monitor execution | Recovery |
|------|--------------|-----------|-------------------|----------|
| **running** | enabled | per config | full | full |
| **stopped** | disabled (cron entry removed) | stopped | none | none |
| **paused** | enabled (cron fires) | per config | exits early if `now < paused_until` | none |
| **observe-only** | enabled | per config | full detection + logging | suppressed |

**Rationale:** **Stop** must halt all work including wrapper sub-minute loops — removing cron is the reliable kill switch (matches `install.sh`/`uninstall.sh` cron helpers). **Pause** keeps cron alive so auto-resume needs no external scheduler; each run checks expiry and transitions to **running** when time passes. **Observe-only** reuses `--fake`-like recovery suppression but persists across runs and still logs failures.

**Alternatives considered:**
- *Pause also removes cron*: Requires a separate timer/cron to call `start` at end time — more moving parts.
- *Observe-only as `--fake` flag in cron*: Not reachable remotely without editing crontab.

### 3. Enforcement point in monitor pipeline

**Decision:** Add `check_operating_mode()` early in `vpn-monitor.sh` `main()` (after logging init, before detection). Return early with exit 0 for **stopped**/**paused** (active pause). Set `OPERATING_MODE_OBSERVE_ONLY=1` export for **observe-only**; recovery orchestration checks this before any tier action.

**Rationale:** Single choke point; wrapper invokes `vpn-monitor.sh` unchanged. Recovery module already has tier gating — observe-only adds one guard before `determine_recovery_action` / execution.

### 4. Local control script

**Decision:** New root script `vpn-monitor-control.sh` with subcommands. Sources `lib/control/operating_mode.sh` for read/write and `install.sh` cron helpers (extracted to `lib/control/cron_control.sh` if needed to avoid sourcing all of install.sh).

Subcommands:
- `start` — set mode=running, restore cron via shared helper, start keepalive if configured
- `stop` — set mode=stopped, remove cron, stop wrapper (kill via PID file), stop keepalive
- `pause --until <epoch|+duration|ISO-local>` — set mode=paused with parsed end time; ensure cron enabled
- `observe-only [--reason TEXT]` — set mode=observe-only; ensure cron enabled
- `status` — print current mode, paused_until (human-readable), cron/keepalive state

**Rationale:** Mirrors `vpn-keepalive.sh start|stop|status` UX. Single entry point for both local and remote invocation.

### 5. Remote control script

**Decision:** New `scripts/manage/control-remote-udm.sh`:

```
control-remote-udm.sh [--config FILE] COMMAND [ARGS]
  COMMAND: start | stop | pause | observe-only | status
  --host HOST          single target (alternative to config)
  --user USER          SSH user (default: root)
  --port PORT          SSH port (default: 22)
```

Remote command: `ssh … '/data/vpn-monitor/vpn-monitor-control.sh' <command> [args]`

Reuse `setup_control_master` / `build_ssh_opts` patterns from `deploy-to-udm.sh`. Batch mode reads same host-list format as `deploy-udms.conf.example`.

**Rationale:** Controller may be Ubuntu server or another UDM; SSH is already the operational transport. Thin remote wrapper avoids installing agent software on UDM.

**Alternatives considered:**
- *UDM API*: Not available for arbitrary shell; SSH is proven in this project.
- *Push-based message queue*: Over-engineered for v1.

### 6. Pause time parsing

**Decision:** Accept three forms for `--until`:
1. Absolute epoch seconds (e.g. `1735689600`)
2. Relative duration (e.g. `+30m`, `+2h`, `+1d`) parsed with shell arithmetic from `date +%s`
3. Local datetime `YYYY-MM-DDTHH:MM:SS` converted with `date -d` (GNU date on UDM)

Reject past times with validation error.

**Rationale:** Covers maintenance-window use cases without external tools.

### 7. Install integration

**Decision:** `install.sh` copies `vpn-monitor-control.sh`, ensures `state/operating_mode` defaults to `mode=running` if missing. `uninstall.sh` removes operating_mode file. No change to default cron behavior on fresh install.

## Risks / Trade-offs

- **[Risk] Remote stop during active Tier 3 recovery** → Mitigation: `stop` logs warning if lockfile present; does not kill in-flight `vpn-monitor.sh` (waits for natural exit); cron removal prevents new runs.
- **[Risk] Clock skew affects pause expiry** → Mitigation: Use UDM local epoch consistently; document NTP expectation.
- **[Risk] Observe-only allows failure counters to accumulate** → Mitigation: Document that counters still increment; recovery resumes on `start`. Optional future: freeze counters in observe-only (non-goal v1).
- **[Risk] SSH credentials on controller** → Mitigation: Reuse existing deploy auth patterns; reference `docs/research/CREDENTIAL_STORAGE_RECOMMENDATIONS.md` for future hardening; out of scope here.
- **[Trade-off] Stop removes cron entry** → Must call `start` to restore (not just flip state file). Acceptable: explicit, matches operator intent.

## Migration Plan

1. Deploy updated package to UDMs via existing install flow.
2. New installs get `vpn-monitor-control.sh`; existing installs gain it on next deploy — no operating_mode file means **running** (implicit default).
3. Rollback: run `vpn-monitor-control.sh start` or redeploy previous version; `start` restores cron from config.
4. No VPN tunnel impact during migration unless operator invokes stop/pause/observe-only.

## Open Questions

- Should **pause** also stop keepalive, or leave it running to keep tunnels warm during maintenance? **Proposed default:** keep keepalive running during pause (only monitor/recovery halted).
- Should batch remote control continue on per-host failure or abort? **Proposed default:** continue, summarize failures at end (matches `deploy-to-udms.sh`).
