## Why

Removing VPN Monitor from a remote UDM today requires either a full deploy cycle (which always reinstalls after uninstall) or manual SSH to each device. Fleet operators need a dedicated remote-uninstall path that mirrors local `uninstall.sh` flags without transferring or installing a new package.

## What Changes

- Add `scripts/manage/uninstall-from-udm.sh` to SSH to one UDM and run `/data/vpn-monitor/uninstall.sh --yes` with forwarded uninstall flags (`--keep-config`, `--remove-state`, `--remove-logs`, etc.).
- Add `scripts/manage/uninstall-from-udms.sh` for batch uninstall across hosts listed in a config file (same `host [bind_ip]` format as `deploy-udms.conf` / `control-udms.conf`).
- Reuse existing management SSH patterns from `deploy-to-udm.sh` and `control-remote-udm.sh` (ControlMaster, BindAddress, credential handling).
- Optionally remove or annotate deploy-registry entries for uninstalled hosts (best-effort; registry is controller bookkeeping).
- Document remote uninstall usage in management script help and `docs/scripts/CENTRAL_MANAGEMENT_GAPS.md` (mark gap closed when implemented).

## Capabilities

### New Capabilities

- `remote-uninstall`: SSH-based remote invocation of on-UDM `uninstall.sh` from a controller machine to one or more target UDMs, with flag parity to local uninstall and batch config support.

### Modified Capabilities

- _(none — no existing OpenSpec spec requirements change; this is a new management script capability alongside `remote-control`)_

## Impact

- **Management scripts**: New `scripts/manage/uninstall-from-udm.sh` and `scripts/manage/uninstall-from-udms.sh`; possible small helper extraction in `scripts/manage/lib/` if uninstall command building is shared with `deploy-to-udm.sh`.
- **On-UDM behavior**: Uses existing `uninstall.sh` — removes cron, keepalive service, scripts, and optionally config/state/logs. No change to monitor detection or recovery logic.
- **Live VPN impact**: Uninstall stops monitoring and removes recovery automation. VPN tunnels themselves are not restarted or torn down by uninstall; operators lose automatic failure detection and tiered recovery until reinstalled.
- **Registry**: Optional cleanup of `logs/deploy-registry` entries; no requirement for live fleet inventory sync.
- **Tests**: New BATS file(s) for remote uninstall CLI (mocked SSH, mirroring `tests/test_remote_control.sh` patterns).
- **Docs**: Update `CENTRAL_MANAGEMENT_GAPS.md`; add example config if batch script uses a dedicated conf file or documents reuse of `deploy-udms.conf`.
