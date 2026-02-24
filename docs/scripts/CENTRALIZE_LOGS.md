# Centralize VPN Monitor Logs

The `centralize-logs.sh` script collects `vpn-monitor.log` from multiple UDMs listed in a conf file, using a specific source IP (BindAddress) for SCP, then zips the logs and removes the temporary files.

## Requirements

- `scp` and `zip` on the machine where the script runs (typically a jump host or admin workstation with multiple IPs).
- SSH access as `root` to each target UDM (password or key; script prompts interactively).

## Usage

```bash
./scripts/manage/centralize-logs.sh
```

The script reads **centralize-logs-ips.conf** from the same directory as the script. Create it from the example:

```bash
cp scripts/manage/centralize-logs-ips.conf.example scripts/manage/centralize-logs-ips.conf
# Edit scripts/manage/centralize-logs-ips.conf: first line = your BindAddress IP, following lines = UDM IPs to fetch from
./scripts/manage/centralize-logs.sh
```

## Conf file format

- Conf file: **centralize-logs-ips.conf** in the script directory (no path argument).
- One IP per line; lines starting with `#` and blank lines are ignored.
- **First** non-comment IP = **BindAddress** (source IP used for SCP).
- **Remaining** IPs = UDMs to fetch `/data/vpn-monitor/logs/vpn-monitor.log` from.
- If only one IP is given, it is used as BindAddress only; no logs are fetched (script exits 0 with a message).

See `scripts/manage/centralize-logs-ips.conf.example` for a template.

## Behavior

- If SCP fails for one target, the script logs a warning and continues with the others. The zip is still created from any successfully fetched logs. Exit code 2 is used if any SCP failed or no logs were collected.

## Authentication

SCP will prompt for a password or SSH key passphrase when needed. To avoid repeated prompts for key passphrases, run `ssh-agent` and `ssh-add` before running the script.

## Output

- Fetched logs: `/tmp/centralize-logs/vpn-monitor-<ip>.log` (temporary; removed after zipping).
- Final artifact: `/tmp/centralize-logs/all-vpn-logs-YYYY-MM-DD-HHMMSS.zip`.
- **still-running**: `/tmp/centralize-logs/still-running` — one line per target IP: `IP cron_ok` or `IP reinstall_needed`. The script SCP-pulls each UDM’s root crontab file (`/var/spool/cron/crontabs/root`), checks it locally for a `vpn-monitor` line (wrapper or main), writes the result here, then deletes the temporary crontab files. No remote command execution (SSH) is used; only file copy (SCP). Use this to see which UDMs need `install.sh` run again.

## Exit codes

- **0**: Success (all targets fetched, or no targets in conf).
- **1**: Missing conf file (script directory) or no IPs in conf.
- **2**: One or more SCP failures, or no logs collected.

## Plan

See [CENTRALIZE_LOGS_PLAN.md](CENTRALIZE_LOGS_PLAN.md) for design and decisions.
