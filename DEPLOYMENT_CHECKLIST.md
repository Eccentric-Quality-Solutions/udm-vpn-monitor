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
- [ ] Run `./prepare_install_package.sh` on development machine
- [ ] Verify package created: `udm-vpn-monitor-installer.zip` (or `.tar.gz`)
- [ ] Transfer package to UDM: `scp udm-vpn-monitor-installer.zip root@<UDM_IP>:/tmp/`

### 2. Extract and Install
- [ ] SSH into UDM: `ssh root@<UDM_IP>`
- [ ] Extract package: `cd /tmp && unzip udm-vpn-monitor-installer.zip`
- [ ] Make installer executable: `chmod +x install.sh`
- [ ] Run installer:
  - **Interactive mode** (recommended for first-time): `./install.sh --interactive`
  - **Silent mode** (preserves existing config): `./install.sh --silent`
  - **Silent with overwrite**: `./install.sh --silent --overwrite-conf`

### 3. Configure VPN Monitor
- [ ] Edit configuration file: `nano /data/vpn-monitor/vpn-monitor.conf`
- [ ] Set `EXTERNAL_PEER_IPS` to your remote VPN gateway external/public IP(s)
- [ ] Optionally set `INTERNAL_PEER_IPS` for ping checks
- [ ] Review other settings (thresholds, cooldown, etc.)

**Critical Configuration:**
```bash
EXTERNAL_PEER_IPS="203.0.113.1 198.51.100.1"  # REQUIRED - External/public IPs
INTERNAL_PEER_IPS="192.168.100.1 192.168.200.1"  # Optional - Internal/private IPs
```

### 4. Test Installation
- [ ] Run monitor manually: `/data/vpn-monitor/vpn-monitor.sh --fake`
- [ ] Verify no errors in output
- [ ] Check log file: `tail -f /data/vpn-monitor/logs/vpn-monitor.log`
- [ ] Verify cron job exists: `crontab -l | grep vpn-monitor`

### 5. Verify Keepalive Daemon (if enabled)
- [ ] Check keepalive status: `systemctl status vpn-keepalive`
- [ ] Or manually: `/data/vpn-monitor/vpn-keepalive.sh status`
- [ ] Verify keepalive is sending pings (check logs if needed)

## Post-Installation Verification

### Verify Installation
- [ ] Script exists and is executable: `ls -l /data/vpn-monitor/vpn-monitor.sh`
- [ ] Library files present: `ls -l /data/vpn-monitor/lib/`
- [ ] Config file exists: `ls -l /data/vpn-monitor/vpn-monitor.conf`
- [ ] Log directory exists: `ls -l /data/vpn-monitor/logs/`
- [ ] Cron job installed: `crontab -l | grep vpn-monitor`

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

# Check EXTERNAL_PEER_IPS is set
grep EXTERNAL_PEER_IPS /data/vpn-monitor/vpn-monitor.conf
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
cat /data/vpn-monitor/logs/restart_count

# Check cooldown
cat /data/vpn-monitor/cooldown_until
```

## Uninstallation

If you need to remove the VPN monitor:
- [ ] Run uninstaller: `./uninstall.sh`
- [ ] Or manually:
  - Remove cron entry: `crontab -e` (delete vpn-monitor line)
  - Remove directory: `rm -rf /data/vpn-monitor`
  - Remove systemd service: `systemctl disable vpn-keepalive` (if installed)

## Additional Resources

- **Quick Start**: See [QUICK_START.md](QUICK_START.md) for 5-minute setup guide
- **Troubleshooting**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed solutions
- **Architecture**: See [ARCHITECTURE.md](ARCHITECTURE.md) for technical details
- **Configuration**: See [README.md](README.md#configuration) for all configuration options

## Notes

- Scripts and config files persist across reboots (stored in `/data/`)
- Cron jobs may be wiped during UniFi OS upgrades (re-run installer if needed)
- Keepalive daemon requires systemd (available on UDM OS 4.3+)
- All recovery actions are logged to `/data/vpn-monitor/logs/vpn-monitor.log`

