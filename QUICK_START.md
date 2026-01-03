# Quick Start Guide

> **Note**: This is a condensed quick start guide. For complete installation instructions, including all installation options and flag descriptions, see the [Installation section in README.md](README.md#installation).

## 5-Minute Setup

**Prerequisites**: UniFi Dream Machine (UDM/UDM-Pro/UDM-SE), UniFi OS 4.3+, SSH access, root/sudo access. For complete requirements, see [Requirements section in README.md](README.md#requirements).

1. **Create install package and transfer to UDM**:
   ```bash
   ./prepare_install_package.sh
   scp udm-vpn-monitor-installer.zip root@<UDM_IP>:/tmp/
   ```

2. **SSH into UDM and install**:
   ```bash
   ssh root@<UDM_IP>
   cd /tmp && unzip udm-vpn-monitor-installer.zip
   chmod +x install.sh
   ./install.sh --interactive
   ```
   
   **Other installation options:**
   - `./install.sh` - Standard installation (prompts if config exists)
   - `./install.sh --silent` - Silent installation (preserves existing config)
   - `./install.sh --silent --overwrite-conf` - Silent installation with config overwrite
   - `./install.sh --no-cron` - Install without cron (for manual execution)
   - `./install.sh --keepalive-only` - Only install/enable keepalive daemon (requires existing installation)
   
   For complete installation options, see the [Installation section in README.md](README.md#installation).

3. **Configure VPN locations**:
   ```bash
   nano /data/vpn-monitor/vpn-monitor.conf
   # Location-based configuration format:
   # LOCATION_<NAME>_EXTERNAL="external_ip"
   # LOCATION_<NAME>_INTERNAL="internal_ip1 internal_ip2 ..."
   # Example:
   LOCATION_NYC_EXTERNAL="203.0.113.1"
   LOCATION_NYC_INTERNAL="192.168.100.1"
   # If using INTERNAL IPs, also set LOCAL_UDM_IP="192.168.1.1" (installer will auto-detect if not set)
   ```
   For complete configuration options, see the [Configuration section in README.md](README.md#configuration).

4. **Test**:
   ```bash
   /data/vpn-monitor/vpn-monitor.sh --fake
   ```

5. **Monitor logs**:
   ```bash
   tail -f /data/vpn-monitor/logs/vpn-monitor.log
   ```

That's it! The monitor runs automatically via cron.

## Next Steps

- **Monitor logs**: `tail -f /data/vpn-monitor/logs/vpn-monitor.log`
- **Check status**: `/data/vpn-monitor/vpn-monitor.sh --fake`
- **View reports**: `/data/vpn-monitor/analyze-logs.sh`
- **Customize settings**: Edit `/data/vpn-monitor/vpn-monitor.conf`

## Common Configuration Options

For complete configuration options and detailed explanations, see the [Configuration section in README.md](README.md#configuration).

**Quick examples:**

- **Change check frequency**: Edit `CRON_SCHEDULE` (see [README.md Configuration section](README.md#configuration) for cron schedule examples)
- **Disable ping checks**: Set `ENABLE_PING_CHECK=0` (if ping is blocked by firewall)
- **Enable debug logging**: Set `DEBUG=1` for verbose output

After changing configuration, you may need to update the cron job. See [README.md Installation section](README.md#installation) for details.

## Troubleshooting

For comprehensive troubleshooting guides, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

**Quick checks:**

- **Script not running**: Check cron (`crontab -l | grep vpn-monitor`) and lockfile (`ls -l /data/vpn-monitor/vpn-monitor.lock`)
- **False positives**: Check VPN status (`ip xfrm state | grep <PEER_IP>`) or disable ping checks (`ENABLE_PING_CHECK=0`)
- **Need more help**: See [README.md](README.md) for detailed documentation or check logs (`tail -f /data/vpn-monitor/logs/vpn-monitor.log`)

## Uninstallation

For complete uninstallation instructions, see [Uninstallation section in README.md](README.md#uninstallation).

**Quick uninstall:**

```bash
# Transfer uninstall script if not already present
scp uninstall.sh root@<UDM_IP>:/tmp/

# SSH into UDM and run uninstaller
ssh root@<UDM_IP>
cd /tmp
chmod +x uninstall.sh
./uninstall.sh
```

**Non-interactive mode:**
```bash
./uninstall.sh --yes
```

Or manually remove the cron entry (`crontab -e`) and `/data/vpn-monitor` directory.

## What Happens Next?

Once installed, the monitor will:

1. **Check VPN status** every minute (or your configured interval)
2. **Log failures** when VPN check fails
3. **Escalate recovery** based on failure count:
   - **Tier 1** (after 1 failure): Logging only
   - **Tier 2** (after 3 failures): Surgical cleanup
   - **Tier 3** (after 5 failures): Full IPsec restart
   
   See the [Recovery Behavior section in README.md](README.md#-important-recovery-behavior) for complete details on recovery behavior, including which actions affect all tunnels vs per-connection recovery options. For technical implementation details, see [ARCHITECTURE.md](docs/ARCHITECTURE.md).

4. **Track failures per location** independently (multiple VPNs supported)
5. **Rate limit restarts** to prevent loops (max 3 per hour)
6. **Cooldown period** after restart (15 minutes default)

All actions are logged to `/data/vpn-monitor/logs/vpn-monitor.log`.

## Example Log Output

```
[2025-01-15 10:00:00] [INFO] VPN monitor script started (PID: 12345)
[2025-01-15 10:00:01] [DEBUG] VPN OK: SA exists, bytes=1234567 (was 1234500)
[2025-01-15 10:01:00] [WARNING] VPN check failed for 203.0.113.1 (failure count: 1)
[2025-01-15 10:01:00] [INFO] Tier 1: Logging VPN failure for 203.0.113.1
[2025-01-15 10:02:00] [WARNING] VPN check failed for 203.0.113.1 (failure count: 2)
[2025-01-15 10:03:00] [WARNING] VPN check failed for 203.0.113.1 (failure count: 3)
[2025-01-15 10:03:00] [WARNING] Tier 2: Attempting surgical SA cleanup for 203.0.113.1
[2025-01-15 10:03:01] [INFO] Surgical cleanup completed for 203.0.113.1
[2025-01-15 10:04:00] [INFO] VPN recovered for 203.0.113.1 after 3 failures
```

## Configuration Reference

For complete configuration options, descriptions, and examples, see the [Configuration section in README.md](README.md#configuration).

**Essential settings:**
- `LOCATION_<NAME>_EXTERNAL` - **Required**: External/public IP of remote VPN gateway for location `<NAME>`
- `LOCATION_<NAME>_INTERNAL` - **Optional**: Internal/private IP(s) for ping checks (space-separated, uses EXTERNAL IP if not set)

**Note**: If you have an existing configuration using `EXTERNAL_PEER_IPS`/`INTERNAL_PEER_IPS`, use the migration script:
```bash
/data/vpn-monitor/scripts/migrate-config-to-locations.sh
```
The migration script runs in interactive mode by default (prompts for location names). Use `--auto` for automatic generation or `--csv FILE` for bulk import. See [MIGRATION.md](docs/MIGRATION.md) for detailed migration instructions.

