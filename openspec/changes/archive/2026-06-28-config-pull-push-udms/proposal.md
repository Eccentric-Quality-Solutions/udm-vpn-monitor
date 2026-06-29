## Why

Each UDM’s `vpn-monitor.conf` is site-specific (`LOCAL_UDM_IP`, location names, etc.). Operators need a simple workflow: pull live configs to the controller, edit locally, push back with a backup of what was on the device — not fleet-wide diff against a shared template. Gap §1 in `docs/scripts/CENTRAL_MANAGEMENT_GAPS.md` remains partial; manual SSH edits are the only option today.

## What Changes

- Add `scripts/manage/pull-config-from-udms.sh` to SCP live `/data/vpn-monitor/vpn-monitor.conf` from one or many UDMs into a controller working tree (default `configs/<host>/vpn-monitor.conf`).
- Add `scripts/manage/push-config-to-udms.sh` to push a local config file to one or many UDMs with:
  - Timestamped backup of the remote file before overwrite (on UDM and on controller)
  - Atomic install on UDM (`*.tmp` then `mv`)
  - Remote `check-config.sh` validation before commit; restore from backup on failure
- Reuse fleet config and SSH patterns from `status-udms.sh` / `deploy-to-udms.sh` (`--config`, `--host`, `host [bind_ip]`, ControlMaster, `--dry-run`).
- Document local layout, rollback, and that config changes apply on next cron cycle (no IPsec restart).
- Update `docs/scripts/CENTRAL_MANAGEMENT_GAPS.md` §1 when implemented; drop `diff-config-udms.sh` from suggested additions (not aligned with per-site config model).
- Add `configs/` to `.gitignore` (or document example path) so pulled secrets/site data are not committed.

## Capabilities

### New Capabilities

- `remote-config-pull-push`: Pull live `vpn-monitor.conf` from fleet UDMs to a controller working tree; push edited configs back with timestamped backups and remote validation.

### Modified Capabilities

- _(none — new management capability alongside `fleet-status`, `remote-control`, and `remote-uninstall`)_

## Impact

- **Management scripts**: New `pull-config-from-udms.sh` and `push-config-to-udms.sh`; optional small helpers in `scripts/manage/lib/` for paths/backups if reuse is warranted.
- **On-UDM behavior**: Push writes config only; creates backup under `/data/vpn-monitor/backups/` (or equivalent). Runs installed `check-config.sh`.
- **Live VPN impact**: None at push time — monitor reads config on next cron run; no `ipsec restart` or tunnel manipulation.
- **Controller filesystem**: Creates `configs/` working tree and `configs/backups/` snapshots; should be gitignored.
- **Tests**: New BATS files with mocked SCP/SSH (mirroring `tests/test_fleet_status.sh` / deploy test patterns).
- **Docs**: Update `CENTRAL_MANAGEMENT_GAPS.md` §1; add code-to-test mapping in `docs/testing/RELEVANT_TESTS.md`.
