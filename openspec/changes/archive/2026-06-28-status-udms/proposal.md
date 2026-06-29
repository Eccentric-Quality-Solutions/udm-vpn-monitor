## Why

Operators cannot safely deploy, push config, or debug drift without knowing what is actually installed on each UDM. The deploy registry (`logs/deploy-registry`) is controller bookkeeping, not live truth — manual installs, uninstalls, and failed records can drift. A fleet status script that SSH-queries each host pays off immediately and surfaces registry lies before trusting it for anything else.

## What Changes

- Add `scripts/manage/status-udms.sh` to read a fleet config (`deploy-udms.conf` or `control-udms.conf`; do not block on unified fleet config) and for each host report:
  - Live `SCRIPT_VERSION` from `/data/vpn-monitor/vpn-monitor.sh` (SSH)
  - Operating mode (via remote `vpn-monitor-control.sh status` or direct read)
  - Cron present (`grep vpn-monitor` on root crontab)
  - Deploy registry entry (version + timestamp from `logs/deploy-registry`, if any)
- Reuse existing management SSH patterns from `control-remote-udm.sh` and `deploy-to-udms.sh` (ControlMaster, BindAddress, credential handling, `host [bind_ip]` config format).
- Print a tabular or structured per-host report plus a fleet summary (installed / not installed / unreachable / registry mismatch).
- Document usage in script `--help` and update `docs/scripts/CENTRAL_MANAGEMENT_GAPS.md` §3 when implemented.

## Capabilities

### New Capabilities

- `fleet-status`: SSH-based fleet inventory reporting live installed version, operating mode, cron presence, and optional deploy-registry row per UDM from a controller/jump host.

### Modified Capabilities

- _(none — no existing OpenSpec spec requirements change; this is a new read-only management capability alongside `remote-control` and `remote-uninstall`)_

## Impact

- **Management scripts**: New `scripts/manage/status-udms.sh`; may add small helpers in `scripts/manage/lib/` for remote version/cron queries if reuse is warranted.
- **On-UDM behavior**: Read-only — no changes to monitor detection, recovery, or operating mode.
- **Live VPN impact**: None — status queries do not start, stop, or restart VPN tunnels or IPsec.
- **Registry**: Read-only lookup via existing `get_deployed_info()` in `deploy-registry.sh`; no registry writes.
- **Performance**: Accepts N SSH round trips (one or a small number per host); appropriate for a small fleet run from a jump host.
- **Tests**: New BATS file with mocked SSH (mirroring `tests/test_remote_control.sh` patterns).
- **Docs**: Update `CENTRAL_MANAGEMENT_GAPS.md` §3; add code-to-test mapping in `docs/testing/RELEVANT_TESTS.md`.
