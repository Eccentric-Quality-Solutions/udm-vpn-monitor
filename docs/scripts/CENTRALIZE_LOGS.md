# Centralize VPN Monitor Logs

The `centralize-logs.sh` script collects `vpn-monitor.log` from multiple UDMs listed in a conf file, using a specific source IP (BindAddress) for SCP, then archives the logs to a tar.gz and removes the temporary files.

## Requirements

- `ssh`, `scp`, and `tar` on the machine where the script runs (typically a jump host or admin workstation with multiple IPs). OpenSSH client required for ControlMaster.
- SSH access as `root` to each target UDM (password or key; script prompts interactively).

## Usage

```bash
./scripts/manage/centralize-logs.sh
```

The script reads **centralize.conf** from the same directory as the script. Create it from the example:

```bash
cp scripts/manage/centralize.conf.example scripts/manage/centralize.conf
# Edit scripts/manage/centralize.conf: BIND=IP (required), then NAME=IP per UDM (name shown before each host)
./scripts/manage/centralize-logs.sh
```

## Conf file format

- Conf file: **centralize.conf** in the script directory (no path argument).
- Lines starting with `#` and blank lines are ignored.
- **BIND=IP** — required; source IP for SCP (BindAddress).
- **NAME=IP** — target UDM (e.g. `NYC=192.168.1.1`). The **name is shown before each host** so you know which UDM you're logging into.
- If only BIND is given (no targets), no logs are fetched (script exits 0 with a message).

See `scripts/manage/centralize.conf.example` for a template.

## Behavior

- If SCP fails for one target, the script logs a warning and continues with the others. The archive is still created from any successfully fetched logs. Exit code 2 is used if any SCP failed or no logs were collected.

## Authentication

SSH/SCP will prompt for a password or SSH key passphrase when needed. The script uses **OpenSSH ControlMaster**: it opens one SSH connection per host (prompting once), then runs two SCPs over that connection (log and crontab). If the crontab fetch fails (e.g. root has no crontab yet), the log is still collected. Requires an OpenSSH client (typical on Linux and macOS). Before each host it prints which target is being used (e.g. "Connecting to NYC (192.168.1.1) - enter password/passphrase when prompted."). To avoid prompts entirely, run `ssh-agent` and `ssh-add` before running the script.

## Output

- Fetched logs: `/tmp/centralize-logs/vpn-monitor-<ip>.log` (temporary; removed after archiving).
- Final artifact: `/tmp/centralize-logs/all-vpn-logs-YYYY-MM-DD-HHMMSS.tar.gz`.

Extract with: `tar xzf all-vpn-logs-YYYY-MM-DD-HHMMSS.tar.gz` (Linux, macOS, Git Bash, WSL). On Windows 10 (1803+): `tar -xzf all-vpn-logs-YYYY-MM-DD-HHMMSS.tar.gz` in PowerShell or Command Prompt.
- **still-running**: `/tmp/centralize-logs/still-running` — one line per target: `NAME IP cron_ok` or `NAME IP reinstall_needed`. The script SCP-pulls each UDM’s root crontab file (`/var/spool/cron/crontabs/root`), checks it locally for a `vpn-monitor` line (wrapper or main), writes the result here, then deletes the temporary crontab files. No remote command execution (SSH) is used; only file copy (SCP). Use this to see which UDMs need `install.sh` run again.

## Exit codes

- **0**: Success (all targets fetched, or no targets in conf).
- **1**: Missing conf file (script directory), no entries in conf, or missing BIND=IP.
- **2**: One or more SCP failures, or no logs collected.

## Plan

See [CENTRALIZE_LOGS_PLAN.md](CENTRALIZE_LOGS_PLAN.md) for design and decisions.
