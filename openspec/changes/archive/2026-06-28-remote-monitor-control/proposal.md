## Why

Operating multiple UDMs with VPN Monitor today requires SSHing to each device individually to stop monitoring during maintenance, pause recovery during risky changes, or restart after an incident. There is no unified way to control whether the monitor runs, logs only, or takes recovery action on a remote UDM from a central server or peer UDM.

## What Changes

- Add an on-UDM control script (`vpn-monitor-control.sh`) that manages monitor lifecycle: **start**, **stop**, **pause** (until a specified time), **observe-only** (detect and log, no recovery), and **status**.
- Add a persistent operating-mode state file under `state/` that `vpn-monitor.sh` and the wrapper honor on every run.
- Add a remote control CLI (`scripts/manage/control-remote-udm.sh`) that SSHes to one or more UDMs (reusing existing deployment SSH patterns) and invokes the on-UDM control script.
- Support batch remote control via a config file (same host-list pattern as `deploy-to-udms.sh`).
- Auto-resume from **pause** when the configured end time passes (cron/wrapper continues to run; each cycle checks expiry).
- Document operating modes, remote usage, and maintenance-window workflow in README and DEVELOPER.md.

## Capabilities

### New Capabilities

- `operating-mode`: On-UDM operating modes (running, stopped, paused-until, observe-only), state persistence, and enforcement in the monitor execution path.
- `remote-control`: SSH-based remote invocation of operating-mode commands from a controller machine (server or UDM) to one or more target UDMs.

### Modified Capabilities

- _(none — no existing OpenSpec specs yet)_

## Impact

- **Root scripts**: New `vpn-monitor-control.sh`; changes to `vpn-monitor.sh`, `vpn-monitor-wrapper.sh`, and possibly `vpn-keepalive.sh` to respect operating mode.
- **lib/**: New `lib/control/` module (operating-mode read/write, pause expiry, cron enable/disable helpers); possible hooks in `lib/recovery/` to skip actions in observe-only mode.
- **install/**: `install.sh` installs control script; `uninstall.sh` cleans operating-mode state.
- **Management scripts**: New `scripts/manage/control-remote-udm.sh` and example config; optional integration point for future management server (see `docs/research/SERVER_APP_RECOMMENDATIONS.md`).
- **State**: New `state/operating_mode` (or equivalent) file; pause stores ISO-8601 or epoch end time.
- **Live VPN impact**: **Stop** and **pause** prevent recovery actions (and stop/pause skip execution entirely). **Observe-only** continues detection/logging but suppresses all recovery tiers — tunnels are not restarted or reloaded. Rollback is immediate via `start` or clearing operating mode.
- **ADRs**: Complements ADR-0001 (cron-based execution) and ADR-0032 (wrapper); does not replace them — stop removes cron; start restores it.
- **Tests**: New BATS files for operating-mode and remote-control CLI; updates to `tests/test_main.sh`, `tests/test_install.sh` as needed.
