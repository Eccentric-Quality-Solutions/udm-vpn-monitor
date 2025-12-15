# UDM VPN Monitor

A best-effort watchdog for UniFi Dream Machines that detects Site-to-Site VPN failures using IPsec xfrm state byte counters and ping connectivity checks, implementing tiered recovery. Designed for UniFi OS 4.3+ with realistic persistence expectations.

## Overview

This tool monitors Site-to-Site VPN connections on UniFi Dream Machines (UDM/UDM-Pro/UDM-SE) and automatically attempts recovery when VPN tunnels appear active but are non-functional. It uses IPsec xfrm state byte counters combined with optional ping connectivity checks to detect actual traffic flow and verify end-to-end connectivity, which is more reliable than checking IKE status alone.

## Features

- **Robust Detection**: Uses `ip xfrm state` byte counters to detect actual VPN traffic flow
- **Connectivity Verification**: Optional ping checks verify end-to-end tunnel connectivity
- **Tiered Recovery**: Escalates from logging → surgical SA cleanup → full restart
- **Safety Controls**: Lockfiles with timeout detection, cooldown timers, and rate limiting prevent restart loops
- **Persistent Logging**: Logs stored in `/data/` survive reboots
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
   scp vpn-monitor.sh vpn-monitor.conf install.sh uninstall.sh root@<UDM_IP>:/tmp/
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
   
   If a configuration file already exists, you'll be prompted whether to overwrite it.
   
   **Installation options:**
   
   - **Install without cron scheduling** (for manual execution):
     ```bash
     ./install.sh --no-cron
     ```
   
   - **Silent installation** (no prompts, preserves existing config):
     ```bash
     ./install.sh --silent
     ```
   
   - **Silent installation with config overwrite**:
     ```bash
     ./install.sh --silent --overwrite-conf
     ```
   
   - **Combine options**:
     ```bash
     ./install.sh --silent --no-cron --overwrite-conf
     ```
   
   **Flag descriptions:**
   - `--no-cron`: Install without setting up cron job (useful for manual execution or custom scheduling)
   - `--silent`: Perform installation silently without prompts (by default preserves existing config)
   - `--overwrite-conf`: Overwrite existing config file (only effective with `--silent`)

4. **Configure the monitor**:
   ```bash
   nano /data/vpn-monitor/vpn-monitor.conf
   ```
   
   Set `PEER_IPS` to the **external/public IP address(es)** of your remote VPN gateway(s):
   ```bash
   PEER_IPS="203.0.113.1 198.51.100.1"
   ```
   
   **Important**: Use the external/public IP address that the VPN tunnel is established with, not the internal/private IP address. The script checks IPsec Security Associations (SAs) which are identified by external IP addresses.

5. **Test manually**:
   ```bash
   /data/vpn-monitor/vpn-monitor.sh
   ```
   
   **Fake mode** (runs checks but doesn't escalate tiers):
   ```bash
   /data/vpn-monitor/vpn-monitor.sh --fake
   ```

6. **Monitor logs**:
   ```bash
   tail -f /data/vpn-monitor/vpn-monitor.log
   ```

## Configuration

Edit `/data/vpn-monitor/vpn-monitor.conf` to customize behavior:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `PEER_IPS` | Space-separated list of remote VPN endpoint **external/public** IPs | (required) |
| `VPN_NAME` | VPN identifier for logging | "Site-to-Site VPN" |
| `TIER1_THRESHOLD` | Failures before logging starts | 1 |
| `TIER2_THRESHOLD` | Failures before surgical cleanup | 3 |
| `TIER3_THRESHOLD` | Failures before full restart | 5 |
| `COOLDOWN_MINUTES` | Minutes to wait after restart | 15 |
| `MAX_RESTARTS_PER_HOUR` | Maximum restarts per hour | 3 |
| `CRON_SCHEDULE` | Cron schedule for check frequency (cron format) | "*/1 * * * *" |
| `LOCKFILE_TIMEOUT` | Lockfile timeout in seconds (detects hung processes) | 300 |
| `ENABLE_PING_CHECK` | Enable ping connectivity verification (0 or 1) | 1 |
| `PING_TARGET_IP` | **Internal/private** IP to ping through tunnel (empty = use peer external IP) | "" |
| `PING_COUNT` | Number of ping packets to send | 3 |
| `PING_TIMEOUT` | Ping timeout per packet (seconds) | 2 |
| `DEBUG` | Enable verbose logging (0 or 1) | 0 |

**Cron Schedule Examples:**
- `"*/1 * * * *"` - Every 1 minute (default)
- `"*/5 * * * *"` - Every 5 minutes
- `"*/10 * * * *"` - Every 10 minutes
- `"*/15 * * * *"` - Every 15 minutes
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

- ✅ Scripts in `/data/vpn-monitor/`
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
   grep CRON_SCHEDULE /data/vpn-monitor/vpn-monitor.conf
   
   # Restore with default schedule (every 1 minute)
   (crontab -l 2>/dev/null; echo "*/1 * * * * /data/vpn-monitor/vpn-monitor.sh >> /data/vpn-monitor/cron.log 2>&1") | crontab -
   ```

## Monitoring & Troubleshooting

### View Logs

```bash
# Real-time log monitoring
tail -f /data/vpn-monitor/vpn-monitor.log

# View recent entries
tail -n 100 /data/vpn-monitor/vpn-monitor.log

# Check for errors
grep ERROR /data/vpn-monitor/vpn-monitor.log
```

### Manual Testing

```bash
# Run monitor manually
/data/vpn-monitor/vpn-monitor.sh

# Run in fake mode (checks failures but doesn't escalate tiers)
/data/vpn-monitor/vpn-monitor.sh --fake

# Check VPN status directly
ip xfrm state | grep -A 10 <PEER_IP>

# Check IPsec status
ipsec status

# Check swanctl (if available)
swanctl --list-sas

# Test ping connectivity (if ping checks enabled)
ping -c 3 <PING_TARGET_IP>
```

**Fake Mode (`--fake` flag):**
The `--fake` flag allows you to test the monitoring script without triggering recovery actions. When enabled:
- VPN status checks are performed normally
- Failures are detected and logged
- Failure counters are incremented
- **Tier 2 (surgical cleanup) and Tier 3 (full restart) actions are skipped**
- Useful for testing detection logic without affecting VPN connections

### Common Issues

**Script not running:**
- Check cron: `crontab -l`
- Check lockfile: `ls -l /data/vpn-monitor/vpn-monitor.lock`
- Check if lockfile is stale (older than LOCKFILE_TIMEOUT): `stat /data/vpn-monitor/vpn-monitor.lock`
- Check logs: `tail /data/vpn-monitor/vpn-monitor.log`

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

### Automated Uninstallation (Recommended)

Use the provided uninstall script:

1. **Transfer uninstall script to your UDM** (if not already present):
   ```bash
   scp uninstall.sh root@<UDM_IP>:/tmp/
   ```

2. **SSH into your UDM**:
   ```bash
   ssh root@<UDM_IP>
   ```

3. **Run the uninstaller**:
   ```bash
   cd /tmp
   chmod +x uninstall.sh
   ./uninstall.sh
   ```

The script will:
- Remove the cron job entry
- Remove the installation directory (`/data/vpn-monitor`)
- Remove all configuration, log, and state files
- Verify complete removal

**Non-interactive mode** (for automation):
```bash
./uninstall.sh --yes
```

### Manual Uninstallation

If you prefer to uninstall manually:

1. Remove cron entry:
   ```bash
   crontab -e
   # Delete the vpn-monitor.sh line
   ```

2. Remove installation directory:
   ```bash
   rm -rf /data/vpn-monitor
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

State is tracked via files in `/data/vpn-monitor/`:
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

