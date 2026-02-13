# UDM VPN Monitor - Deployment Checklist

Quick reference checklist for deploying the VPN monitor on UniFi Dream Machine systems.

## Pre-Deployment Checks

### System Requirements
- [ ] UniFi Dream Machine (UDM/UDM-Pro/UDM-SE)
- [ ] UniFi OS 4.3 or later
- [ ] SSH access enabled
- [ ] Root/sudo access available
- [ ] `/data` directory exists (verified automatically by installer)

### Required Commands Availability
Verify these commands are available on your UDM:
- [ ] `ip` - Required for VPN detection (xfrm state checks)
- [ ] `ipsec` - Required for recovery actions (Tier 2/3)
- [ ] `ping` - Optional but recommended for connectivity checks
- [ ] `systemctl` - Available for keepalive daemon management
- [ ] `crontab` - Required for scheduled execution
- [ ] `bash` - Required shell interpreter

**Quick Check:**
```bash
command -v ip ipsec ping systemctl crontab bash
```

All commands should return paths (e.g., `/usr/bin/ip`). If any are missing, the monitor will gracefully degrade but functionality may be limited.

### Network Information
Before installation, gather:
- [ ] External/public IP address(es) of remote VPN gateway(s) - **REQUIRED**
- [ ] Internal/private IP address(es) of remote VPN gateway(s) - Optional (for ping checks)
- [ ] VPN connection name/identifier - Optional (for logging)

## Installation Steps

### 1. Prepare Installation Package
- [ ] Run `./prepare_install_package.sh` on development machine (creates zip file)
- [ ] Or create tar.gz: `./prepare_install_package.sh --tar`
- [ ] Verify package created: `udm-vpn-monitor.zip` (or `udm-vpn-monitor.tar.gz`)
- [ ] Transfer package to UDM: `scp udm-vpn-monitor.zip root@<UDM_IP>:/tmp/` (or `.tar.gz`)

### 2. Extract and Install
- [ ] SSH into UDM: `ssh root@<UDM_IP>`
- [ ] Extract package: `cd /tmp && unzip udm-vpn-monitor.zip` (or `tar -xzf udm-vpn-monitor.tar.gz` for tar.gz)
- [ ] Make installer executable: `chmod +x install.sh`
- [ ] Run installer:
  - **Interactive mode** (recommended for first-time): `./install.sh --interactive`
  - **Silent mode** (preserves existing config): `./install.sh --silent`
  - **Silent with overwrite**: `./install.sh --silent --overwrite-conf`
  - **Install without cron** (for manual execution): `./install.sh --no-cron`
  - **Keepalive-only mode** (requires existing installation): `./install.sh --keepalive-only`

### 3. Configure VPN Monitor
- [ ] Edit configuration file: `nano /data/vpn-monitor/vpn-monitor.conf`
- [ ] Configure locations using location-based format (see below)
- [ ] Optionally set `INTERNAL` IPs for ping checks
- [ ] Review other settings (thresholds, cooldown, resource monitoring, etc.)
- [ ] Configure resource monitoring thresholds if needed (CPU, RAM, disk space)
- [ ] Set `STATUS_LOG_INTERVAL_SECONDS` for periodic status logging (default: 300 seconds)
- [ ] Configure `RECOVERY_VERIFY_TIMEOUT` if needed (default: 30 seconds)
- [ ] Review system-wide failure detection settings if monitoring multiple locations

**Critical Configuration:**
```bash
# Location-based configuration format
LOCATION_NYC_EXTERNAL="203.0.113.1"  # REQUIRED - External/public IP
LOCATION_NYC_INTERNAL="192.168.100.1"  # Optional - Internal/private IP(s)

LOCATION_DC_EXTERNAL="198.51.100.1"  # REQUIRED - External/public IP
LOCATION_DC_INTERNAL="192.168.200.1"  # Optional - Internal/private IP(s)
```

**Note**: If migrating from old format (`EXTERNAL_PEER_IPS`/`INTERNAL_PEER_IPS`), use the migration script:
```bash
/data/vpn-monitor/scripts/migrate-config-to-locations.sh
```
See [MIGRATION.md](docs/MIGRATION.md) for detailed migration instructions.

**Additional Configuration Options:**
- **Resource Monitoring**: Enabled by default (`ENABLE_RESOURCE_MONITORING=1`). Monitors CPU, RAM, and disk space usage and throttles execution when resources are constrained. Adjust thresholds if needed:
  - `RESOURCE_CPU_THRESHOLD` (default: 90%) - CPU usage threshold
  - `RESOURCE_RAM_THRESHOLD` (default: 90%) - RAM usage threshold
  - `RESOURCE_DISK_WARNING_THRESHOLD` (default: 20% free) - Disk space warning
  - `RESOURCE_DISK_CRITICAL_THRESHOLD` (default: 10% free) - Disk space critical
- **Status Logging**: `STATUS_LOG_INTERVAL_SECONDS` (default: 300 seconds / 5 minutes) - How often to log periodic status updates for healthy VPNs. Set to 0 to disable.
- **Recovery Verification**: `RECOVERY_VERIFY_TIMEOUT` (default: 30 seconds) - Maximum time to wait for recovery verification after xfrm-based recovery actions.
- **System-Wide Failure Detection**: Enabled by default (`ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1`). Detects when all or majority of VPNs fail simultaneously and coordinates recovery to prevent cascades.

### 4. Test Installation
- [ ] Run monitor manually: `/data/vpn-monitor/vpn-monitor.sh --fake` (fake mode tests without triggering recovery)
- [ ] Verify no errors in output
- [ ] Check log file: `tail -f /data/vpn-monitor/logs/vpn-monitor.log`
- [ ] Verify cron job exists: `crontab -l | grep vpn-monitor`
- [ ] Validate configuration: `/data/vpn-monitor/check-config.sh`

### 5. Verify Keepalive Daemon (if enabled)
- [ ] Check keepalive status: `systemctl status vpn-keepalive`
- [ ] Or manually: `/data/vpn-monitor/vpn-keepalive.sh status`
- [ ] Verify keepalive is sending pings (check logs if needed)
- [ ] **Note**: Keepalive daemon automatically reloads configuration every 10 iterations (or every 5 minutes, whichever is longer) - no service restart needed for config changes

## Post-Installation Verification

### Verify Installation
- [ ] Script exists and is executable: `ls -l /data/vpn-monitor/vpn-monitor.sh`
- [ ] Library files present: `ls -l /data/vpn-monitor/lib/`
- [ ] Config file exists: `ls -l /data/vpn-monitor/vpn-monitor.conf`
- [ ] Log directory exists: `ls -l /data/vpn-monitor/logs/`
- [ ] Cron job installed: `crontab -l | grep vpn-monitor`
- [ ] Utility scripts present: `ls -l /data/vpn-monitor/*.sh` (check-config.sh, compare-config.sh, analyze-logs.sh, etc.)

### Verify Functionality
- [ ] Monitor runs via cron (wait 1-2 minutes, check logs/cron.log)
- [ ] Log entries appear: `tail -f /data/vpn-monitor/logs/vpn-monitor.log`
- [ ] VPN status detected correctly (check log for "VPN OK" or "VPN suspect" messages)
- [ ] No false positives (VPN working but monitor reports failures)

### Common Issues to Check
- [ ] **Script not running**: Check logs/cron.log for errors
- [ ] **Lockfile issues**: Check if lockfile exists and PID is valid
- [ ] **False positives**: Verify VPN is actually working, check ping checks
- [ ] **Recovery not working**: Verify `ipsec` command available, check rate limiting
- [ ] **Resource throttling**: Check if script is exiting early due to high CPU/RAM usage (check logs for "system resources constrained")
- [ ] **Detection reliability**: If both `ip` and `ipsec` commands are unavailable, recovery escalation (Tier 2/3) is automatically blocked to prevent false recovery actions

## After UniFi OS Upgrades

### Post-Upgrade Checklist
- [ ] Check if cron job still exists: `crontab -l | grep vpn-monitor`
- [ ] If missing, re-run installer: `./install.sh --silent`
- [ ] Verify monitoring resumes: `tail -f /data/vpn-monitor/logs/vpn-monitor.log`
- [ ] Check keepalive daemon: `systemctl status vpn-keepalive`

**Note:** Cron jobs may be wiped during UniFi OS upgrades. The installer includes a persistence check that warns if cron is missing.

## Troubleshooting Quick Reference

### Script Not Running
```bash
# Check cron job
crontab -l | grep vpn-monitor

# Check cron.log for errors
tail -f /data/vpn-monitor/logs/cron.log

# Check lockfile
ls -l /data/vpn-monitor/vpn-monitor.lock
cat /data/vpn-monitor/vpn-monitor.lock
```

### Configuration Issues
```bash
# Verify config file syntax
bash -n /data/vpn-monitor/vpn-monitor.conf

# Check location-based configuration is set
grep LOCATION_.*_EXTERNAL /data/vpn-monitor/vpn-monitor.conf

# Validate configuration against schema
/data/vpn-monitor/check-config.sh
```

### VPN Detection Issues
```bash
# Check xfrm state (primary detection method)
ip xfrm state | grep <PEER_IP>

# Check ipsec status (fallback method)
ipsec status | grep <PEER_IP>

# Test ping connectivity
ping -c 3 <PEER_IP>
```

### Recovery Not Working
```bash
# Check if ipsec command available
command -v ipsec

# Check rate limiting
cat /data/vpn-monitor/state/restart_count

# Check cooldown
cat /data/vpn-monitor/cooldown_until

# Check if detection is reliable (both ip and ipsec should be available)
command -v ip ipsec

# Check resource monitoring state (if script is throttling)
cat /data/vpn-monitor/state/resource_cpu_constrained
cat /data/vpn-monitor/state/resource_ram_constrained
```

## Uninstallation

If you need to remove the VPN monitor:
- [ ] Run uninstaller: `./uninstall.sh`
- [ ] **Non-interactive mode** (for automation): `./uninstall.sh --yes`
- [ ] Or manually:
  - Remove cron entry: `crontab -e` (delete vpn-monitor line)
  - Remove directory: `rm -rf /data/vpn-monitor`
  - Remove systemd service: `systemctl disable vpn-keepalive` (if installed)
  - Remove logrotate config: `rm /etc/logrotate.d/vpn-monitor` (if present)

## Additional Resources

- **Quick Start**: See [QUICK_START.md](QUICK_START.md) for 5-minute setup guide
- **Troubleshooting**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed solutions
- **Architecture**: See [ARCHITECTURE.md](ARCHITECTURE.md) for technical details
- **Configuration**: See [README.md](README.md#configuration) for all configuration options

## Notes

- Scripts and config files persist across reboots (stored in `/data/`)
- Cron jobs may be wiped during UniFi OS upgrades (re-run installer if needed)
- Keepalive daemon requires systemd (available on UDM OS 4.3+) and automatically reloads configuration every 10 iterations (or every 5 minutes, whichever is longer)
- Log rotation is automatically configured via logrotate (daily rotation, 7 days retention)
- All recovery actions are logged to `/data/vpn-monitor/logs/vpn-monitor.log`
- Utility scripts (check-config.sh, compare-config.sh, analyze-logs.sh) are installed for configuration validation and log analysis
- **Resource Monitoring**: Enabled by default. Script throttles execution when CPU/RAM usage is high or disk space is low to prevent system overload
- **Detection Reliability Safeguard**: Recovery escalation (Tier 2/3) is automatically blocked when detection tools (`ip` and `ipsec` commands) are unavailable to prevent false recovery actions
- **Status Logging**: Periodic status updates for healthy VPNs are logged every 5 minutes by default (configurable via `STATUS_LOG_INTERVAL_SECONDS`)
- **System-Wide Failure Detection**: When monitoring multiple locations, system-wide failure detection coordinates recovery to prevent cascades and rate limiting

