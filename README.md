# UDM VPN Monitor

A best-effort watchdog for UniFi Dream Machines that detects Site-to-Site VPN failures using IPsec xfrm state byte counters and implements tiered recovery. Designed for UniFi OS 4.3+ with realistic persistence expectations.

## Overview

This tool monitors Site-to-Site VPN connections on UniFi Dream Machines (UDM/UDM-Pro/UDM-SE) and automatically attempts recovery when VPN tunnels appear active but are non-functional. It uses IPsec xfrm state byte counters to detect actual traffic flow, which is more reliable than simple ping checks or connection status queries.

## Features

- **Robust Detection**: Uses `ip xfrm state` byte counters to detect actual VPN traffic flow
- **Tiered Recovery**: Escalates from logging → surgical SA cleanup → full restart
- **Safety Controls**: Lockfiles, cooldown timers, and rate limiting prevent restart loops
- **Persistent Logging**: Logs stored in `/mnt/data/` survive reboots
- **Cron-Based**: More resilient than long-running processes on UDM

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
| `DEBUG` | Enable verbose logging (0 or 1) | 0 |

## How It Works

### Detection Method

The monitor uses `ip xfrm state` to check IPsec Security Associations (SAs) and validates that:
1. SA exists for the peer IP
2. Byte counters are non-zero and increasing
3. Packets are actually flowing through the tunnel

This is more reliable than checking IKE status alone, as it confirms actual traffic flow.

### Tiered Recovery

1. **Tier 1 (Logging)**: After first failure, logs the issue
2. **Tier 2 (Surgical Cleanup)**: After 3 failures, attempts to delete specific SA states and reload configuration
3. **Tier 3 (Full Restart)**: After 5 failures, performs full `ipsec restart` (affects all tunnels)

### Safety Features

- **Lockfiles**: Prevents overlapping script executions
- **Cooldown Period**: 15-minute wait after restart before next check
- **Rate Limiting**: Maximum 3 restarts per hour (configurable)
- **Failure Thresholds**: Requires consecutive failures before action

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

3. Or manually restore cron:
   ```bash
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
```

### Common Issues

**Script not running:**
- Check cron: `crontab -l`
- Check lockfile: `ls -l /mnt/data/vpn-monitor/vpn-monitor.lock`
- Check logs: `tail /mnt/data/vpn-monitor/vpn-monitor.log`

**False positives:**
- Increase thresholds in config
- Check if VPN actually has traffic (byte counters may be 0 if idle)
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

If validation fails, it escalates through recovery tiers.

### State Management

State is tracked via files in `/mnt/data/vpn-monitor/`:
- `failure_counter`: Consecutive failure count
- `last_restart`: Timestamp of last restart
- `restart_count`: Timestamps of all restarts (for rate limiting)
- `last_bytes`: Last known byte counter value
- `cooldown_until`: Cooldown expiration timestamp
- `vpn-monitor.lock`: Lockfile for execution control

## License

This tool is provided as-is without warranty. Use at your own risk.

## Contributing

Issues and pull requests welcome. Please test thoroughly on UDM systems before submitting.

## Acknowledgments

Designed based on real-world UDM VPN monitoring needs and UniFi OS 4.3+ constraints.

