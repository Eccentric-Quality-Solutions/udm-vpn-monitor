# UDM VPN Monitor

A best-effort watchdog for UniFi Dream Machines that detects Site-to-Site VPN failures using IPsec xfrm state byte counters and ping connectivity checks, implementing tiered recovery. Designed for UniFi OS 4.3+ with realistic persistence expectations.

## Overview

This tool monitors Site-to-Site VPN connections on UniFi Dream Machines (UDM/UDM-Pro/UDM-SE) and automatically attempts recovery when VPN tunnels appear active but are non-functional. It uses IPsec xfrm state byte counters combined with optional ping connectivity checks to detect actual traffic flow and verify end-to-end connectivity, which is more reliable than checking IKE status alone.

## Features

- **Robust Detection**: Uses `ip xfrm state` byte counters to detect actual VPN traffic flow
- **Connectivity Verification**: Optional ping checks verify end-to-end tunnel connectivity
- **Tiered Recovery**: Escalates from logging → surgical SA cleanup → full restart
- **Safety Controls**: Lockfiles with timeout detection, cooldown timers, and rate limiting prevent restart loops
- **Persistent Logging**: Logs stored in `/mnt/data/` survive reboots
- **Cron-Based**: More resilient than long-running processes on UDM
- **Per-Peer Tracking**: Monitors multiple VPN peers independently

## What This Is

- ✅ A useful watchdog tool
- ✅ A diagnostic amplifier
- ✅ A temporary self-healing mechanism

## What This Is NOT

- ❌ A fully reliable daemon (best-effort)
- ❌ Upgrade-proof (may require re-installation after UniFi OS upgrades)
- ❌ Per-tunnel precise recovery (affects all IPsec tunnels on restart)
- ❌ Guaranteed persistence (cron may be wiped on upgrades)

## Requirements

- UniFi Dream Machine (UDM/UDM-Pro/UDM-SE)
- UniFi OS 4.3 or later
- SSH access enabled
- Root/sudo access

## Installation

1. **Transfer files to your UDM**:
   ```bash
   # From your local machine, copy files to UDM
   scp vpn-monitor.sh vpn-monitor.conf install.sh root@<UDM_IP>:/tmp/
   ```

2. **SSH into your UDM**:
   ```bash
   ssh root@<UDM_IP>
   ```

3. **Run the installer**:
   ```bash
   cd /tmp
   chmod +x install.sh
   ./install.sh
   ```

4. **Configure the monitor**:
   ```bash
   nano /mnt/data/vpn-monitor/vpn-monitor.conf
   ```
   
   Set `PEER_IPS` to your remote VPN endpoint IP address(es):
   ```bash
   PEER_IPS="192.168.1.1 192.168.2.1"
   ```

5. **Test manually**:
   ```bash
   /mnt/data/vpn-monitor/vpn-monitor.sh
   ```

6. **Monitor logs**:
   ```bash
   tail -f /mnt/data/vpn-monitor/vpn-monitor.log
   ```

## Configuration

Edit `/mnt/data/vpn-monitor/vpn-monitor.conf` to customize behavior:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `PEER_IPS` | Space-separated list of remote VPN endpoint IPs | (required) |
| `VPN_NAME` | VPN identifier for logging | "Site-to-Site VPN" |
| `TIER1_THRESHOLD` | Failures before logging starts | 1 |
| `TIER2_THRESHOLD` | Failures before surgical cleanup | 3 |
| `TIER3_THRESHOLD` | Failures before full restart | 5 |
| `COOLDOWN_MINUTES` | Minutes to wait after restart | 15 |
| `MAX_RESTARTS_PER_HOUR` | Maximum restarts per hour | 3 |
| `CRON_SCHEDULE` | Cron schedule for check frequency (cron format) | "*/5 * * * *" |
| `LOCKFILE_TIMEOUT` | Lockfile timeout in seconds (detects hung processes) | 300 |
| `ENABLE_PING_CHECK` | Enable ping connectivity verification (0 or 1) | 1 |
| `PING_TARGET_IP` | IP to ping through tunnel (empty = use peer IP) | "" |
| `PING_COUNT` | Number of ping packets to send | 3 |
| `PING_TIMEOUT` | Ping timeout per packet (seconds) | 2 |
| `DEBUG` | Enable verbose logging (0 or 1) | 0 |

**Cron Schedule Examples:**
- `"*/5 * * * *"` - Every 5 minutes (default)
- `"*/10 * * * *"` - Every 10 minutes
- `"*/15 * * * *"` - Every 15 minutes
- `"*/2 * * * *"` - Every 2 minutes (more frequent)
- `"0 * * * *"` - Every hour (on the hour)

## How It Works

### Detection Method

The monitor uses a multi-layered approach to verify VPN tunnel health:

1. **Primary Check - xfrm State**: Uses `ip xfrm state` to check IPsec Security Associations (SAs) and validates that:
   - SA exists for the peer IP
   - Byte counters are non-zero and increasing
   - Packets are actually flowing through the tunnel

2. **Connectivity Verification - Ping Check** (if enabled): After confirming SA exists, performs ping tests to verify:
   - End-to-end connectivity through the tunnel
   - Actual routing is working (not just tunnel state)
   - Remote system is responding

This dual approach is more reliable than checking IKE status alone, as it confirms both tunnel state and actual traffic flow. The ping check helps detect cases where the tunnel exists but isn't routing traffic correctly.

### Tiered Recovery

1. **Tier 1 (Logging)**: After first failure, logs the issue
2. **Tier 2 (Surgical Cleanup)**: After 3 failures, attempts to delete specific SA states and reload configuration
3. **Tier 3 (Full Restart)**: After 5 failures, performs full `ipsec restart` (affects all tunnels)

### Safety Features

- **Lockfiles with Timeout**: Prevents overlapping script executions and detects hung processes
- **Cooldown Period**: 15-minute wait after restart before next check
- **Rate Limiting**: Maximum 3 restarts per hour (configurable)
- **Failure Thresholds**: Requires consecutive failures before action
- **Input Validation**: Validates peer IPs and prevents injection attacks

## Persistence & Upgrades

### What Survives Reboots

- ✅ Scripts in `/mnt/data/vpn-monitor/`
- ✅ Configuration files
- ✅ Log files
- ✅ Cron jobs (usually)

### What May Be Lost

- ⚠️ Cron jobs may be wiped during UniFi OS upgrades
- ⚠️ Scripts may need re-installation after major upgrades

### After UniFi OS Upgrades

If monitoring stops after an upgrade:

1. Check if cron job exists:
   ```bash
   crontab -l | grep vpn-monitor
   ```

2. If missing, re-run installer:
   ```bash
   /tmp/install.sh
   ```

3. Or manually restore cron (check config for CRON_SCHEDULE first):
   ```bash
   # Check configured schedule
   grep CRON_SCHEDULE /mnt/data/vpn-monitor/vpn-monitor.conf
   
   # Restore with default schedule (every 5 minutes)
   (crontab -l 2>/dev/null; echo "*/5 * * * * /mnt/data/vpn-monitor/vpn-monitor.sh >> /mnt/data/vpn-monitor/cron.log 2>&1") | crontab -
   ```

## Monitoring & Troubleshooting

### View Logs

```bash
# Real-time log monitoring
tail -f /mnt/data/vpn-monitor/vpn-monitor.log

# View recent entries
tail -n 100 /mnt/data/vpn-monitor/vpn-monitor.log

# Check for errors
grep ERROR /mnt/data/vpn-monitor/vpn-monitor.log
```

### Manual Testing

```bash
# Run monitor manually
/mnt/data/vpn-monitor/vpn-monitor.sh

# Check VPN status directly
ip xfrm state | grep -A 10 <PEER_IP>

# Check IPsec status
ipsec status

# Check swanctl (if available)
swanctl --list-sas

# Test ping connectivity (if ping checks enabled)
ping -c 3 <PING_TARGET_IP>
```

### Common Issues

**Script not running:**
- Check cron: `crontab -l`
- Check lockfile: `ls -l /mnt/data/vpn-monitor/vpn-monitor.lock`
- Check if lockfile is stale (older than LOCKFILE_TIMEOUT): `stat /mnt/data/vpn-monitor/vpn-monitor.lock`
- Check logs: `tail /mnt/data/vpn-monitor/vpn-monitor.log`

**Ping checks failing:**
- Verify `PING_TARGET_IP` is reachable: `ping <PING_TARGET_IP>`
- Check if ping is blocked by firewall rules
- Consider disabling ping checks (`ENABLE_PING_CHECK=0`) if ping is intentionally blocked
- Ensure ping target is on the remote network (not just the peer IP)

**False positives:**
- Increase thresholds in config
- Check if VPN actually has traffic (byte counters may be 0 if idle)
- If ping checks are enabled, ensure `PING_TARGET_IP` is reachable
- Disable ping checks (`ENABLE_PING_CHECK=0`) if ping is blocked by firewall
- Enable DEBUG=1 for verbose logging

**Restart loops:**
- Check rate limiting is working
- Increase `COOLDOWN_MINUTES`
- Reduce `MAX_RESTARTS_PER_HOUR`

## Uninstallation

1. Remove cron entry:
   ```bash
   crontab -e
   # Delete the vpn-monitor.sh line
   ```

2. Remove installation directory:
   ```bash
   rm -rf /mnt/data/vpn-monitor
   ```

## Limitations & Disclaimers

### Important Warnings

1. **Full Restart Impact**: Tier 3 recovery restarts all IPsec tunnels, temporarily affecting all Site-to-Site and remote user VPNs
2. **Best-Effort**: This is a watchdog tool, not a guaranteed daemon. It may miss failures or require manual intervention
3. **Upgrade Compatibility**: UniFi OS upgrades may break functionality or remove cron jobs
4. **No Official Support**: This is an unofficial tool. Use at your own risk

### When to Use

- Site-to-Site VPNs that occasionally fail silently
- Networks where automatic recovery is acceptable
- Situations where brief VPN downtime is acceptable

### When NOT to Use

- Critical production environments requiring guaranteed uptime
- Networks where VPN restart affects critical services
- Situations requiring per-tunnel recovery

## Technical Details

### Detection Logic

The monitor queries `ip xfrm state` for each configured peer IP and validates:
- SA existence
- Byte counter values (must be > 0 and increasing)
- Packet flow confirmation

If ping checks are enabled (`ENABLE_PING_CHECK=1`), it additionally:
- Pings the target IP (configured via `PING_TARGET_IP` or uses peer IP)
- Verifies packet loss is < 100%
- Confirms end-to-end connectivity through the tunnel

If validation fails, it escalates through recovery tiers. The ping check helps distinguish between "tunnel exists but broken" and "tunnel exists and working but idle".

### State Management

State is tracked via files in `/mnt/data/vpn-monitor/`:
- `failure_counter`: Consecutive failure count (shared across all peers)
- `last_restart`: Timestamp of last restart
- `restart_count`: Timestamps of all restarts (for rate limiting)
- `last_bytes_<peer_ip>`: Per-peer last known byte counter value (sanitized IP in filename)
- `cooldown_until`: Cooldown expiration timestamp
- `vpn-monitor.lock`: Lockfile for execution control (includes timestamp:pid for timeout detection)
- `.cron_checked`: Flag file to prevent repeated cron persistence checks

## License

This tool is provided as-is without warranty. Use at your own risk.

## Contributing

Issues and pull requests welcome. Please test thoroughly on UDM systems before submitting.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed architecture diagrams, component interactions, and design decisions.

## Future Enhancements

See [ENHANCEMENTS.md](ENHANCEMENTS.md) for a comprehensive list of potential improvements and future development ideas.

## Acknowledgments

Designed based on real-world UDM VPN monitoring needs and UniFi OS 4.3+ constraints.

