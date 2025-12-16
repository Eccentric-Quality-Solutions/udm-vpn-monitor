# Quick Start Guide

## 5-Minute Setup

1. Copy files to UDM:
   ```bash
   scp *.sh *.conf root@<UDM_IP>:/tmp/
   ```

2. Install:
   ```bash
   ssh root@<UDM_IP>
   cd /tmp
   chmod +x install.sh
   ./install.sh --interactive
   ```

3. Configure peer IPs:
   ```bash
   nano /data/vpn-monitor/vpn-monitor.conf
   # Set PEER_IPS="203.0.113.1"
   ```

4. Test:
   ```bash
   /data/vpn-monitor/vpn-monitor.sh --fake
   ```

5. Monitor logs:
   ```bash
   tail -f /data/vpn-monitor/logs/vpn-monitor.log
   ```

That's it! The monitor runs automatically via cron.

---

## Detailed Instructions

For complete installation instructions, including all installation options and flag descriptions, see the [Installation section in README.md](README.md#installation).

### Prerequisites

- UniFi Dream Machine (UDM/UDM-Pro/UDM-SE)
- UniFi OS 4.3 or later
- SSH access enabled
- Root/sudo access

For complete requirements details, see the [Requirements section in README.md](README.md#requirements).

### Quick Installation Summary

1. **Transfer files**: `scp *.sh *.conf root@<UDM_IP>:/tmp/`
2. **SSH into UDM**: `ssh root@<UDM_IP>`
3. **Run installer**: `cd /tmp && chmod +x install.sh && ./install.sh --interactive`
4. **Configure PEER_IPS**: Edit `/data/vpn-monitor/vpn-monitor.conf` and set `PEER_IPS` to your remote VPN gateway's **external/public IP address(es)**
5. **Test**: `/data/vpn-monitor/vpn-monitor.sh --fake`
6. **Monitor**: `tail -f /data/vpn-monitor/logs/vpn-monitor.log`

**Note**: Use external/public IP addresses (not internal/private IPs) for `PEER_IPS`. See [README.md Configuration section](README.md#configuration) for details.

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

For complete uninstallation instructions, see the [Uninstallation section in README.md](README.md#uninstallation).

**Quick uninstall:**

```bash
/tmp/uninstall.sh
```

Or manually remove the cron entry and `/data/vpn-monitor` directory.

## What Happens Next?

Once installed, the monitor will:

1. **Check VPN status** every minute (or your configured interval)
2. **Log failures** when VPN check fails
3. **Escalate recovery** based on failure count:
   - **Tier 1** (after 1 failure): Logging only
   - **Tier 2** (after 3 failures): Surgical cleanup (reload connection)
   - **Tier 3** (after 5 failures): Full IPsec restart

4. **Track failures per peer** independently (multiple VPNs supported)
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

**Key settings:**
- `PEER_IPS` - **Required**: External IPs of remote VPN gateways
- `TIER1_THRESHOLD` - Failures before logging (default: 1)
- `TIER2_THRESHOLD` - Failures before surgical cleanup (default: 3)
- `TIER3_THRESHOLD` - Failures before full restart (default: 5)
- `COOLDOWN_MINUTES` - Minutes to wait after restart (default: 15)
- `ENABLE_PING_CHECK` - Enable ping connectivity check (default: 1)

