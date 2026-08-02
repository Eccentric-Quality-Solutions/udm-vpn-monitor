## Context

The repo already has a working Bash control plane under `manage/` (deploy, status, remote control, config pull/push, log centralize) with OpenSpec coverage for those capabilities. The on-UDM agent already supports `observe-only` (detection/logging with `NO_ESCALATE=1`, no recovery). Fresh installs still initialize `state/operating_mode` to `running` via `ensure_operating_mode_initialized`, so the first cron tick after deploy can recover.

This change makes safe-by-default behavior match the near-term goal: prove the controller can manage the fleet while agents only observe. A long-lived management server remains future work (`docs/research/SERVER_APP_RECOMMENDATIONS.md`).

Constraints: UDM OS 4.3+, Bash only, no new dependencies, minimize churn, preserve existing mode on upgrade.

## Goals / Non-Goals

**Goals:**
- New installs default to `observe-only` so recovery cannot run until explicit `start`
- Missing `operating_mode` file resolves to `observe-only` (same safe default)
- Document (and optionally script) a controller acceptance checklist using existing manage tools
- Keep keepalive independent of observe-only

**Non-Goals:**
- Python/Go management server, DB inventory, web UI, REST API, alerting
- Scheduled automated log collection on the controller
- Changing observe-only’s effect on recovery (already correct)
- Stopping or disabling keepalive when entering observe-only
- Forcing existing deployments to observe-only on upgrade

## Decisions

### 1. Default mode becomes `observe-only`

**Choice:** Change `get_default_operating_mode` and `ensure_operating_mode_initialized` to use `observe-only` instead of `running`.

**Rationale:** Install and “missing state file” share one safe default. Operators enable recovery only with `vpn-monitor-control.sh start` or `control-remote-udm.sh … start`.

**Alternatives considered:**
- Keep default `running`, require post-deploy flip — easy to forget; first cron may recover
- Deploy scripts force observe-only after every deploy — would downgrade sites already in `running` during prove phase / upgrades; rejected

### 2. Upgrade preserves existing mode

**Choice:** Only write the default when the state file is absent. If `operating_mode` already exists, install/upgrade leaves it alone.

**Rationale:** Sites already intentionally running recovery must not be silently flipped.

### 3. Keepalive stays independent

**Choice:** Observe-only continues to suppress recovery only; it does not stop or disable `vpn-keepalive`.

**Rationale:** Operator decision for this milestone; tunnel keepalive traffic may still be useful while validating detection/logging. Stage-1 configs can disable keepalive separately if needed.

### 4. Validation artifact = docs + thin optional helper

**Choice:** Primary deliverable is a documented acceptance checklist under `docs/` (e.g. `docs/scripts/CONTROL_PLANE_ACCEPTANCE.md`) with exact script invocations. Optionally add `manage/prove-control-plane.sh` that prints/runs steps with `--dry-run` support later; prefer doc-first in implementation unless a wrapper is cheap.

**Rationale:** The manage scripts already exist; the gap is a single operator definition of “done,” not more fleet primitives.

**Alternatives considered:**
- Full automated integration harness against live UDMs — valuable but environment-dependent; keep as manual acceptance for now
- Management server Phase A — explicitly deferred

### 5. No new SSH or fleet config format

**Choice:** Reuse `deploy-udms.conf` / `control-udms.conf` and existing ControlMaster patterns.

**Rationale:** Already proven in fleet-status, remote-control, and config push/pull.

## Risks / Trade-offs

- **[Risk]** Operators expect new installs to recover immediately → **Mitigation:** Document that `start` is required; mention in CHANGELOG and install success message if one exists
- **[Risk]** Missing state file used to imply `running` (effective auto-recovery after state wipe) → **Mitigation:** Treat as intentional BREAKING safe default; document in CHANGELOG
- **[Risk]** Keepalive still injects traffic during “observe” → **Mitigation:** Document; optional config note in acceptance checklist
- **[Risk]** Acceptance checklist never run on real hardware → **Mitigation:** Checklist is the exit criterion for the milestone; BATS covers default-mode behavior only

## Migration Plan

1. Ship code change: default → `observe-only`; tests updated
2. Ship acceptance doc (and optional helper)
3. On first deploy of the new package: confirm `status` shows `observe-only`; run checklist
4. When ready for recovery on a canary: `control-remote-udm.sh --host <canary> start`
5. Rollback of the default: revert the two functions and reinstall, or `start` on affected hosts (no package rollback required for mode alone)

## Open Questions

- None blocking; keepalive and default-mode decisions are settled for this change.
- Whether to implement `prove-control-plane.sh` vs doc-only can be decided during apply (prefer doc-only unless wrapper is trivial).
