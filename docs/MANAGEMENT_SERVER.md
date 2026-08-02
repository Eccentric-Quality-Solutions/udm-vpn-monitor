# Management Server User Guide

The **management server** is the Bash fleet control plane under `manage/`. It runs on any Linux host with `bash`, `ssh`, and `scp` (optional `sshpass`) — including a workstation, jump host, or a UDM acting as controller — and manages VPN Monitor agents on remote UDMs over SSH.

There is no long-lived daemon, database, or web UI. You run tools from a checkout of this repo (or an extracted install package that includes `manage/`).

**Related:** [CONTROL_PLANE_ACCEPTANCE.md](scripts/CONTROL_PLANE_ACCEPTANCE.md) (prove deploy/mode/config before enabling recovery), [CENTRALIZE_LOGS.md](scripts/CENTRALIZE_LOGS.md) (log collection details), [README.md](../README.md) (on-box install and config).

## What it does

| Task | Script |
|------|--------|
| Build install package | `./scripts/prepare_install_package.sh` |
| Deploy one UDM | `./manage/deploy-to-udm.sh` |
| Deploy fleet of UDMs | `./manage/deploy-to-udms.sh` |
| UDM Fleet health / inventory | `./manage/status-udms.sh` |
| Remote start / stop / pause / observe-only / status | `./manage/control-remote-udm.sh` |
| Pull configs to Management Server | `./manage/pull-config-from-udms.sh` |
| Push configs to UDMs | `./manage/push-config-to-udms.sh` |
| Pull logs archive | `./manage/centralize-logs.sh` |
| Uninstall one / fleet | `./manage/uninstall-from-udm.sh`, `./manage/uninstall-from-udms.sh` |

Deploy registry helpers live in `manage/deploy-registry.sh` (sourced by deploy/status tools). Shared SSH and fleet-config helpers live in `manage/lib/`.

## Prerequisites

- OpenSSH client (`ssh`, `scp`); ControlMaster is used so you authenticate once per host per run
- Network path from the controller to each UDM (SSH, typically port 22 as `root`)
- For deploy: an install package (`udm-vpn-monitor.zip` or `.tar.gz`) from `./scripts/prepare_install_package.sh`, CI artifacts, or a GitHub Release
- SSH keys via `ssh-agent` recommended; otherwise the scripts prompt (or use `sshpass` where supported)

Run all examples from the **repo root** (or the root of an extracted package that contains `manage/` and `lib/`).

## Fleet config

Most tools take `--host HOST` for a single UDM or `--config FILE` for a batch list.

**Deploy / status / config / uninstall** default to `deploy-udms.conf` in the repo root:

```bash
cp manage/deploy-udms.conf.example deploy-udms.conf
```

**Remote control** defaults to `control-udms.conf`:

```bash
cp manage/control-udms.conf.example control-udms.conf
```

Format (same for both):

```text
# host_or_ip [bind_ip]
192.168.1.100
192.168.1.101 192.168.50.1
```

- `host_or_ip` — target UDM
- `bind_ip` — optional source IP for SSH/SCP `BindAddress` (multi-homed controllers)
- Lines starting with `#` and blank lines are ignored

**Log centralization** uses a different conf (see [Pulling logs](#pulling-logs)).

## Typical workflow

Fresh fleet deploy leaves agents in **observe-only** (detect and log; no recovery). Enable recovery with `start` only when you intend to.

```bash
# 1. Build package
./scripts/prepare_install_package.sh

# 2. Deploy fleet (non-interactive; records deploy registry)
./manage/deploy-to-udms.sh --config deploy-udms.conf

# 3. Check inventory
./manage/status-udms.sh --config deploy-udms.conf

# 4. Confirm modes (expect observe-only after fleet deploy)
./manage/control-remote-udm.sh --config control-udms.conf status

# 5. Edit configs on the controller, then push
./manage/pull-config-from-udms.sh --config deploy-udms.conf
# edit configs/<host>/vpn-monitor.conf
./manage/push-config-to-udms.sh --config deploy-udms.conf

# 6. Collect logs when needed
./manage/centralize-logs.sh

# 7. Enable recovery on a canary, then expand
./manage/control-remote-udm.sh --host <canary> start
```

To prove the loop before any `start`, use [CONTROL_PLANE_ACCEPTANCE.md](scripts/CONTROL_PLANE_ACCEPTANCE.md).

## Deploy

### Build the package

```bash
./scripts/prepare_install_package.sh        # zip (default)
./scripts/prepare_install_package.sh --tar # tar.gz
```

Default package path for fleet deploy: `${REPO_ROOT}/udm-vpn-monitor.zip`.

### One host

```bash
./manage/deploy-to-udm.sh --target-ip 192.168.1.100
./manage/deploy-to-udm.sh --target-ip 192.168.1.100 --bind-ip 192.168.50.1
./manage/deploy-to-udm.sh --dry-run --target-ip 192.168.1.100
```

Behavior highlights:

- Uninstall then install over SSH/SCP (defaults: keep config; remove state and logs)
- After fleet-style uninstall with `--remove-state`, operating mode resets to **observe-only**
- Optional `--tail-follow` for interactive `tail -f` after deploy
- Writes deploy log under `logs/deploy-to-udm.log` (credentials are not logged)
- Records the host in `logs/deploy-registry` unless `--no-record` / interactive confirm path

### Fleet

```bash
./manage/deploy-to-udms.sh --config deploy-udms.conf
./manage/deploy-to-udms.sh --config deploy-udms.conf --force
./manage/deploy-to-udms.sh --config deploy-udms.conf --dry-run
./manage/deploy-to-udms.sh --config deploy-udms.conf --tail-follow  # interactive per host
```

- **Default:** skip interactive `tail -f`; auto-record the registry (`--skip-tail` is the default behavior)
- Skips hosts already at the package version in the registry unless `--force`
- Continues across per-host failures and summarizes at the end

### Deploy registry

Path: `logs/deploy-registry` (tab-separated `host`, `version`, `timestamp`).

Used to skip re-deploys and to flag version drift in `status-udms.sh`.

## Status (fleet inventory)

```bash
./manage/status-udms.sh --config deploy-udms.conf
./manage/status-udms.sh --host 192.168.1.100
./manage/status-udms.sh --dry-run --config deploy-udms.conf
```

Tab-separated columns:

```text
HOST  VERSION  MODE  CRON  REGISTRY_VERSION  REGISTRY_TIME  REGISTRY_MATCH
```

Use this after deploy and when checking for registry drift vs the live installed version.

## Remote control (operating mode)

Remotely runs `/data/vpn-monitor/vpn-monitor-control.sh` on each target.

```bash
./manage/control-remote-udm.sh --host 192.168.1.100 status
./manage/control-remote-udm.sh --host 192.168.1.100 observe-only
./manage/control-remote-udm.sh --host 192.168.1.100 pause --until +30m --reason "maintenance"
./manage/control-remote-udm.sh --host 192.168.1.100 pause --reason "hold"   # until explicit mode change
./manage/control-remote-udm.sh --config control-udms.conf stop
./manage/control-remote-udm.sh --host 192.168.1.100 start   # enables recovery
```

| Command | Effect |
|---------|--------|
| `status` | Show mode on target |
| `observe-only` | Detect and log; suppress recovery |
| `pause` | Skip monitor runs; timed (`--until`) or indefinite |
| `stop` | Remove cron / halt monitoring |
| `start` | Normal monitoring with **recovery enabled** |

**Mode defaults:** Fresh install or missing `state/operating_mode` → `observe-only`. Fleet deploy with default `--remove-state` also resets to `observe-only`. On-box reinstall without removing state keeps an existing mode file.

**Caution:** Expired timed pause auto-resumes to `running` (recovery on). Prefer indefinite `pause` then `observe-only` when you must not enable recovery yet.

Observe-only does **not** disable `vpn-keepalive`. Turn keepalive off in each host’s `vpn-monitor.conf` if needed (pull → edit → push).

## Config pull and push

Working tree on the controller (default `--config-dir configs/`):

```text
configs/<host>/vpn-monitor.conf
configs/backups/<host>/vpn-monitor.conf.<timestamp>   # created on push
```

```bash
./manage/pull-config-from-udms.sh --config deploy-udms.conf
# edit configs/<host>/vpn-monitor.conf
./manage/push-config-to-udms.sh --config deploy-udms.conf

# Single host / dry-run
./manage/pull-config-from-udms.sh --host 192.168.1.100
./manage/push-config-to-udms.sh --host 192.168.1.100 --dry-run
```

Push behavior:

- Stages the file and runs remote `check-config.sh` before replacing live config
- Writes a timestamped backup on the UDM under `/data/vpn-monitor/backups/`
- Writes a controller backup under `configs/backups/<host>/`
- Applies on the next cron cycle (does not restart IPsec)
- Batch mode uses per-host files only; `--file` requires `--host` so one file cannot overwrite every site

Rollback: restore a backup locally, then push again.

## Pulling logs

See [CENTRALIZE_LOGS.md](scripts/CENTRALIZE_LOGS.md) for full detail.

```bash
cp manage/centralize.conf.example manage/centralize.conf
# Edit: BIND=IP (required), then NAME=IP per UDM
./manage/centralize-logs.sh
```

Output: `/tmp/centralize-logs/all-vpn-logs-YYYY-MM-DD-HHMMSS.tar.gz` and a `still-running` cron check summary in the same directory.

## Uninstall

```bash
./manage/uninstall-from-udm.sh --host 192.168.1.100 --yes
./manage/uninstall-from-udm.sh --host 192.168.1.100 --keep-config --update-registry --yes
./manage/uninstall-from-udms.sh --config deploy-udms.conf --yes
```

Defaults match deploy’s uninstall step (keep config; remove state and logs). Use `--update-registry` to drop the host from `logs/deploy-registry` after success. Logs go under `logs/uninstall-from-udm.log` / `uninstall-from-udms.log`.

## Common options

Shared by most SSH fleet tools:

| Option | Purpose |
|--------|---------|
| `--host HOST` | Single target |
| `--config FILE` | Fleet host list |
| `--bind-ip IP` | SSH/SCP source address |
| `--username USER` | SSH user (default `root`) |
| `--port` / `--ssh-port` | SSH port (default 22) |
| `--timeout SEC` | Connect timeout |
| `--dry-run` | Print planned actions; do not change remotes |
| `--help` | Script-specific usage |

Batch tools generally continue after a per-host failure and print a summary.

## Controller artifacts

| Path | Purpose |
|------|---------|
| `deploy-udms.conf` / `control-udms.conf` | Fleet host lists (repo root; not committed if gitignored locally) |
| `manage/centralize.conf` | Log centralization targets |
| `configs/<host>/` | Pulled/editable `vpn-monitor.conf` copies |
| `configs/backups/` | Controller-side config snapshots from push |
| `logs/deploy-registry` | Last deployed version per host |
| `logs/deploy-to-udm*.log`, `logs/uninstall-from-udm*.log` | Operator action logs |
| `/tmp/centralize-logs/` | Log pull staging and tar.gz archives |

## Safety notes

- Prefer proving deploy + observe-only before `start` ([acceptance checklist](scripts/CONTROL_PLANE_ACCEPTANCE.md))
- Canary `start` first; expand only after log review
- Invalid configs are rejected on push (`validation_failed`); live config is left unchanged
- Passwords prompted on the terminal are not written to deploy/uninstall logs
- Future persistent server / UI / scheduling ideas: [SERVER_APP_RECOMMENDATIONS.md](research/SERVER_APP_RECOMMENDATIONS.md)
