## Why

The Bash fleet tools in `manage/` already cover deploy, status, remote control, config pull/push, and log centralization, but installs still default to `running` (recovery enabled). Before trusting automated recovery in the field, operators need a safe first posture—agents that only detect and log—plus a concrete way to prove the controller can change configs, pause/start agents, and pull logs on a real fleet. A long-lived Python/Go management server is out of scope; this milestone treats the controller host + fleet scripts as the central control plane.

## What Changes

- **BREAKING (safe-by-default):** Fresh installs and missing `state/operating_mode` default to `observe-only` instead of `running`, so detection and logging run without recovery until an operator explicitly runs `start` (or remote `start`).
- Upgrades that already have an `operating_mode` file **preserve** the existing mode (no forced flip to observe-only on upgrade).
- Keepalive behavior is **unchanged** by observe-only (recovery suppression only); stage-1 configs may still disable keepalive separately if desired.
- Document a controller-side **acceptance checklist** that proves the control plane end-to-end: deploy → observe-only → pause/start → push/pull config → centralize logs → status/registry consistency.
- Optionally add a thin controller helper that walks that checklist (or documents the exact script invocations) so operators do not skip steps.
- Clarify in research/docs that the Bash fleet layer is sufficient for this milestone; deferred server (scheduler, DB, UI) remains future work in `docs/research/SERVER_APP_RECOMMENDATIONS.md`.

## Capabilities

### New Capabilities

- `control-plane-validation`: Controller-side acceptance procedure (and optional helper) to verify deploy, observe-only posture, pause/start, config pull/push, log pull, and fleet status against a live or staged UDM fleet using existing `manage/` tools.

### Modified Capabilities

- `operating-mode`: Default mode on first initialization (and when the state file is missing) becomes `observe-only` instead of `running`; explicit `start` remains required to enable recovery.

## Impact

- **On-UDM:** `lib/control/operating_mode.sh` (`get_default_operating_mode`, `ensure_operating_mode_initialized`), install path that creates `state/operating_mode`, related tests (`tests/test_operating_mode.sh`, install tests).
- **Controller:** Docs and optionally a small script under `manage/`; no change to recovery detection logic itself beyond the default mode.
- **Live VPN / recovery:** New installs will not escalate recovery until `vpn-monitor-control.sh start` (or remote equivalent). Existing deployments keep their current mode across upgrade.
- **Keepalive:** Unchanged by this change; observe-only does not stop or disable `vpn-keepalive`.
- **Out of scope:** Persistent management server, SQLite inventory, web UI, REST API, scheduled background jobs, alerting, incremental log search (see research doc Phases A–E).
- **Dependencies:** None new (Bash + existing SSH manage scripts only).
