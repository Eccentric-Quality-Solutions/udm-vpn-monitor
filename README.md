# UDM VPN Monitor

[![CI](https://github.com/eccentric-quality-solutions/udm-vpn-monitor/workflows/CI/badge.svg)](https://github.com/eccentric-quality-solutions/udm-vpn-monitor/actions)

A best-effort watchdog for UniFi Dream Machines that detects Site-to-Site VPN failures using IPsec xfrm state byte counters and ping connectivity checks with tiered recovery. Designed for UniFi OS 4.3+ with realistic persistence expectations.

## Overview

This tool monitors Site-to-Site VPN connections on UniFi Dream Machines (UDM/UDM-Pro/UDM-SE) and automatically attempts recovery when VPN tunnels appear active but are non-functional. It uses IPsec xfrm state byte counters combined with optional ping connectivity checks to detect actual traffic flow and verify end-to-end connectivity, which is more reliable than checking IKE status alone.

## Quick Start

- See [QUICK_START.md](QUICK_START.md) for a 5-minute setup guide.
- See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common problems and solutions.
- See [DEVELOPER.md](DEVELOPER.md) for development setup and [CODE_REVIEW.md](CODE_REVIEW.md) for code quality analysis.

## ⚠️ Important: Recovery Behavior

**Recovery behavior:**

- **Detection**: Uses `ip xfrm state` (primary) → `ipsec status` (fallback)
- **Tier 2 Recovery**: 
  - **Experimental option**: xfrm-based per-connection recovery (⚠️ EXPERIMENTAL, opt-in via `ENABLE_XFRM_RECOVERY=1`, disabled by default)
  - **Default**: `ipsec reload` (affects **all connections**)
- **Tier 3 Recovery**: Always uses `ipsec restart` (affects **all connections**)

**Important Notes:**
- **Tier 2 recovery**: By default affects all VPN tunnels (not just the failed one) - **per-connection recovery is not supported by default**
- **Tier 3 recovery**: Always affects all tunnels regardless of configuration
- **Per-peer monitoring**: Each VPN is monitored independently, but recovery actions may affect all tunnels
- ⚠️ **Experimental xfrm recovery**: Available but **disabled by default** (`ENABLE_XFRM_RECOVERY=0`) due to documented risks. Most users should not enable this.

See the [Tiered Recovery](#tiered-recovery) section for detailed behavior.

## Features

- **Robust Detection**: Uses `ip xfrm state` byte counters to detect actual VPN traffic flow
- **Connectivity Verification**: Optional ping checks verify end-to-end tunnel connectivity
- **Tiered Recovery**: Escalates from logging → surgical SA cleanup → full restart
- **VPN Keepalive Daemon**: Optional background daemon sends periodic pings to prevent idle VPN tunnels from timing out
- **Safety Controls**: Lockfiles with timeout detection, cooldown timers, and rate limiting prevent restart loops
- **Persistent Logging**: Logs stored in `/data/` survive reboots
- **Cron-Based**: More resilient than long-running processes on UDM
- **Per-Peer Tracking**: Monitors multiple VPN peers independently with independent failure counters
- **Log Analysis**: Built-in `analyze-logs.sh` script for failure pattern analysis and CSV export
- **Comprehensive Testing**: Extensive test suite with CI/CD integration
- **Security**: Robust IP address validation prevents injection attacks

## What This Is

- ✅ A useful watchdog tool
- ✅ A diagnostic amplifier
- ✅ A temporary self-healing mechanism

## What This Is NOT

- ❌ A fully reliable daemon (best-effort)
- ❌ Upgrade-proof (may require re-installation after UniFi OS upgrades)
- ❌ Per-tunnel precise recovery by default (Tier 2 affects all tunnels unless experimental xfrm recovery is enabled)
- ❌ Guaranteed persistence (cron may be wiped on upgrades)

## Requirements

- UniFi Dream Machine (UDM/UDM-Pro/UDM-SE)
- UniFi OS 4.3 or later
- SSH access enabled
- Root/sudo access

## Installation

The install package (recommended) includes all required files with proper directory structure. It can be created using `./prepare_install_package.sh` (creates zip) or `./prepare_install_package.sh --tar` (creates tar.gz).

1. **Transfer files to your UDM**:
   ```bash
   # First, create the package:
   ./prepare_install_package.sh              # Creates zip file
   # Or create tar.gz:
   ./prepare_install_package.sh --tar         # Creates tar.gz file
   # Then transfer and extract:
   scp udm-vpn-monitor-installer.zip root@<UDM_IP>:/tmp/

   ```

2. **SSH into your UDM**:
   ```bash
   ssh root@<UDM_IP>
   cd /tmp && unzip udm-vpn-monitor-installer.zip
   # Or for tar.gz:
   # cd /tmp && tar -xzf udm-vpn-monitor-installer.tar.gz
   ```

3. **Run the installer**:
   ```bash
   cd /tmp
   chmod +x install.sh
   ./install.sh
   ```
   
   If a configuration file already exists, you'll be prompted whether to overwrite it.
   
   **Installation options:**
   
   - **Interactive configuration** (prompts for each config value with defaults):
     ```bash
     ./install.sh --interactive
     ```
   
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
   
   - **Dev mode** (install to current directory instead of /data/vpn-monitor):
     ```bash
     ./install.sh --dev
     ```
   
   - **Combine options**:
     ```bash
     ./install.sh --silent --no-cron --overwrite-conf
     ./install.sh --interactive --dev
     ```
   
   **Flag descriptions:**
   - `--interactive`: Prompt for each configuration value with defaults (press Enter to accept default)
   - `--no-cron`: Install without setting up cron job (useful for manual execution or custom scheduling)
   - `--silent`: Perform installation silently without prompts (by default preserves existing config)
   - `--overwrite-conf`: Overwrite existing config file (only effective with `--silent`)
   - `--dev`: Install to current working directory instead of `/data/vpn-monitor` (useful for development/testing)
   
   **Note:** `--interactive` and `--silent` flags cannot be used together.

4. **Configure the monitor**:
   ```bash
   nano /data/vpn-monitor/vpn-monitor.conf
   ```
   
   Set `EXTERNAL_PEER_IPS` to the **external/public IP address(es)** of your remote VPN gateway(s):
   ```bash
   EXTERNAL_PEER_IPS="203.0.113.1 198.51.100.1"
   ```
   
   Optionally, set `INTERNAL_PEER_IPS` to the **internal/private IP address(es)** for ping checks:
   ```bash
   INTERNAL_PEER_IPS="192.168.100.1 192.168.200.1"
   ```
   
   **Important**: Use the external/public IP address that the VPN tunnel is established with, not the internal/private IP address. The script checks IPsec Security Associations (SAs) which are identified by external IP addresses. If `INTERNAL_PEER_IPS` is not set, ping checks will use `EXTERNAL_PEER_IPS` instead.

5. **Test manually**:
   ```bash
   /data/vpn-monitor/vpn-monitor.sh
   ```
   
   **Fake mode** (runs checks but doesn't escalate tiers):
   ```bash
   /data/vpn-monitor/vpn-monitor.sh --fake
   ```
   
   **Show version**:
   ```bash
   /data/vpn-monitor/vpn-monitor.sh --version
   ```

6. **Monitor logs**:
   ```bash
   tail -f /data/vpn-monitor/logs/vpn-monitor.log
   ```

## Configuration

Edit `/data/vpn-monitor/vpn-monitor.conf` to customize behavior:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `EXTERNAL_PEER_IPS` | Space-separated list of remote VPN endpoint **external/public** IPs | (required) |
| `INTERNAL_PEER_IPS` | Space-separated list of remote VPN endpoint **internal/private** IPs (for ping checks, optional) | "" |
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
| `ENABLE_KEEPALIVE` | Enable VPN keepalive daemon (0 or 1, see [Keepalive Daemon](#keepalive-daemon)) | 0 |
| `KEEPALIVE_INTERVAL` | Keepalive ping interval (seconds, 10-300) | 30 |
| `KEEPALIVE_PING_COUNT` | Number of ping packets per keepalive ping (1-5) | 1 |
| `DEBUG` | Enable verbose logging (0 or 1) | 0 |
| `ENABLE_XFRM_RECOVERY` | ⚠️ EXPERIMENTAL: Enable xfrm-based per-connection recovery (0 or 1, see risks below) | 0 |


**Cron Schedule Examples:**
- `"*/1 * * * *"` - Every 1 minute (default)
- `"*/5 * * * *"` - Every 5 minutes
- `"*/10 * * * *"` - Every 10 minutes
- `"*/15 * * * *"` - Every 15 minutes
- `"0 * * * *"` - Every hour (on the hour)

### Keepalive Daemon

The VPN keepalive daemon is an optional background process that sends periodic ping traffic through VPN tunnels to prevent them from being marked as idle or disconnected by network devices. This helps prevent false positives where healthy but idle VPN tunnels are incorrectly detected as failed.

**Configuration:**

1. **Enable keepalive** in `vpn-monitor.conf`:
   ```bash
   ENABLE_KEEPALIVE=1
   KEEPALIVE_INTERVAL=30
   KEEPALIVE_PING_COUNT=1
   ```

2. **Start the daemon** using systemd (recommended):
   ```bash
   systemctl enable --now vpn-keepalive
   ```
   
   Or start manually:
   ```bash
   /data/vpn-monitor/vpn-keepalive.sh start
   ```

**Management:**

- **Check status**: `systemctl status vpn-keepalive` or `/data/vpn-monitor/vpn-keepalive.sh status`
- **Stop daemon**: `systemctl stop vpn-keepalive` or `/data/vpn-monitor/vpn-keepalive.sh stop`
- **Restart daemon**: `systemctl restart vpn-keepalive` or `/data/vpn-monitor/vpn-keepalive.sh restart`
- **View logs**: `journalctl -u vpn-keepalive -f` or `tail -f /data/vpn-monitor/logs/vpn-keepalive.log`

**How It Works:**

- Runs as a separate background daemon process (independent from the monitoring script)
- Pings each configured peer at regular intervals (default: every 30 seconds)
- Uses internal IP addresses (from `INTERNAL_PEER_IPS`) when available, falls back to external IPs
- Minimal logging (only logs failures, not successful pings)
- Automatically restarts on failure (when managed via systemd)
- Respects `ENABLE_KEEPALIVE` configuration - won't start if disabled

**When to Use:**

- VPN tunnels that may be idle for extended periods
- Network devices that timeout idle connections
- VPNs that require periodic traffic to maintain state
- Reducing false positives from idle tunnel detection

**Note:** The keepalive daemon is separate from the monitoring script. The monitoring script still runs via cron and performs its own checks. Keepalive only sends periodic pings to keep tunnels alive - it does not perform failure detection or recovery.

## Common Scenarios

### Monitoring 3 Site-to-Site VPNs

When monitoring multiple VPN tunnels, configure all peer IPs in your config file:

```bash
# /data/vpn-monitor/vpn-monitor.conf
EXTERNAL_PEER_IPS="203.0.113.1 198.51.100.1 192.0.2.1"
INTERNAL_PEER_IPS="192.168.100.1 192.168.200.1 192.168.300.1"
VPN_NAME="Multi-Site VPN"
```

**Key Points:**
- Each VPN is monitored independently with its own failure counter
- Failures in one tunnel don't affect monitoring of other tunnels
- Recovery actions are per-peer (each peer has independent failure tracking)
- State files are created per peer (e.g., `failure_counter_203_0_113_1`, `last_bytes_198_51_100_1`)

**Example Log Output:**
```
[2025-01-15 10:00:00] INFO: VPN check for 203.0.113.1: OK
[2025-01-15 10:00:00] INFO: VPN check for 198.51.100.1: OK
[2025-01-15 10:00:00] WARNING: VPN check for 192.0.2.1: FAILED (tunnel down)
```

**Per-Connection Recovery:**

**Default Behavior:**
- **Tier 2 recovery** affects **all VPN tunnels** (uses `ipsec reload`)
- **Tier 3 recovery** always affects **all VPN tunnels** (uses `ipsec restart`)

⚠️ **Experimental Option**: There is an experimental xfrm-based per-connection recovery option (`ENABLE_XFRM_RECOVERY=1`), but it's **disabled by default** due to documented risks and requires extensive testing. See the [Configuration](#configuration) section for details. **Most users should not enable this** - the default behavior (affecting all tunnels) is safer and more reliable.

### Testing without Affecting Production VPNs

Use the `--fake` flag to test the monitoring script without triggering recovery actions:

```bash
# Run in fake mode (checks failures but doesn't escalate tiers)
/data/vpn-monitor/vpn-monitor.sh --fake
```

**What Fake Mode Does:**
- ✅ Performs all VPN status checks normally
- ✅ Detects and logs failures
- ✅ Increments failure counters
- ✅ Logs what recovery actions would be taken
- ❌ **Skips Tier 2 (surgical cleanup) actions**
- ❌ **Skips Tier 3 (full restart) actions**

**Use Cases:**
- Testing detection logic without affecting VPN connections
- Validating configuration before enabling automatic recovery
- Troubleshooting false positives without risk
- Verifying that peer IPs are correctly configured

**Example Output:**
```
[2025-01-15 10:00:00] INFO: Running in FAKE mode - recovery actions will be skipped
[2025-01-15 10:00:00] WARNING: VPN check for 203.0.113.1: FAILED (routing issue)
[2025-01-15 10:00:00] INFO: [FAKE] Would trigger Tier 2 recovery (surgical cleanup) after 3 failures
```

**Testing Keepalive Separately:**
You can also test the keepalive daemon independently:
```bash
# Start keepalive manually (if enabled in config)
/data/vpn-monitor/vpn-keepalive.sh start

# Check status
/data/vpn-monitor/vpn-keepalive.sh status

# View logs
tail -f /data/vpn-monitor/logs/vpn-keepalive.log
```

### Troubleshooting False Positives

False positives occur when the monitor reports VPN failures even though the tunnel is actually healthy. Common causes and solutions:

**1. Idle VPN Tunnels**

**Problem:** Healthy VPN tunnels with no traffic are detected as failed because byte counters aren't increasing.

**Solution:** Enable the VPN keepalive daemon to send periodic pings:
```bash
# In vpn-monitor.conf
ENABLE_KEEPALIVE=1
KEEPALIVE_INTERVAL=30
KEEPALIVE_PING_COUNT=1
```

Then enable and start the keepalive service:
```bash
systemctl enable --now vpn-keepalive
```

**2. Ping Checks Failing (But VPN Working)**

**Problem:** Ping checks fail even though the VPN tunnel is working correctly.

**Possible Causes:**
- Firewall rules blocking ICMP on the remote network
- Remote gateway not responding to pings
- Using external IPs for ping (should use internal IPs)

**Solution:**
- Configure `INTERNAL_PEER_IPS` for ping checks:
  ```bash
  INTERNAL_PEER_IPS="192.168.100.1 192.168.200.1"
  ```
- Or disable ping checks if not needed:
  ```bash
  ENABLE_PING_CHECK=0
  ```

**Note:** Ping failures don't cause VPN failures - they only log warnings. The primary detection method (SA state + byte counters) is authoritative.

**3. Byte Counter Detection Issues**

**Problem:** Byte counters aren't increasing even though traffic is flowing.

**Possible Causes:**
- Traffic is flowing but counters haven't updated yet
- Very low traffic volume
- Counters reset after SA rekey

**Solution:**
- Increase thresholds to allow more tolerance:
  ```bash
  TIER1_THRESHOLD=2
  TIER2_THRESHOLD=5
  TIER3_THRESHOLD=8
  ```
- Enable keepalive to ensure regular traffic flow
- Check logs to understand the failure pattern:
  ```bash
  tail -f /data/vpn-monitor/logs/vpn-monitor.log
  ```

**4. Transient Network Issues**

**Problem:** Brief network hiccups trigger false positives.

**Solution:**
- Increase thresholds to require multiple consecutive failures:
  ```bash
  TIER1_THRESHOLD=2    # Log after 2 consecutive failures
  TIER2_THRESHOLD=5    # Recover after 5 consecutive failures
  TIER3_THRESHOLD=10   # Full restart after 10 consecutive failures
  ```
- Adjust cron schedule to check less frequently:
  ```bash
  CRON_SCHEDULE="*/5 * * * *"  # Check every 5 minutes instead of every minute
  ```

**5. Verification Steps**

When troubleshooting false positives:

1. **Check VPN status manually:**
   ```bash
   ip xfrm state | grep <peer_ip>
   ipsec status
   ```

2. **Verify byte counters are increasing:**
   ```bash
   # Run monitor manually and check output
   /data/vpn-monitor/vpn-monitor.sh
   ```

3. **Review failure type in logs:**
   ```bash
   grep "FAILED" /data/vpn-monitor/logs/vpn-monitor.log | tail -20
   ```
   Look for failure types: "tunnel down", "routing issue", or "unknown"

4. **Test connectivity:**
   ```bash
   ping -c 3 <internal_peer_ip>
   ```

5. **Check keepalive status** (if enabled):
   ```bash
   systemctl status vpn-keepalive
   tail -f /data/vpn-monitor/logs/vpn-keepalive.log
   ```

For more detailed troubleshooting guidance, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## How It Works

The monitor uses a multi-layered approach to verify VPN tunnel health and automatically recover from failures.

### Detection Method

The monitor checks VPN tunnel health using multiple detection methods with automatic fallback:

1. **Primary**: `ip xfrm state` - Verifies IPsec Security Associations (SAs) and byte counters to confirm the tunnel exists and traffic is flowing
2. **Fallback**: `ipsec status` - Checks for connections via ipsec command
3. **Optional**: Ping checks to verify end-to-end connectivity through the tunnel

### Failure Type Detection

The monitor distinguishes between different types of VPN failures to provide more accurate diagnostics:

1. **Tunnel Down**: The IPsec Phase 2 SA (ESP/AH SA) doesn't exist, indicating the tunnel is not established.Detected by checking `ip xfrm state` for Phase 2 SAs.

2. **Routing Issue**: The Phase 2 SA exists (tunnel is established), but traffic is not flowing properly. This could indicate routing problems, firewall issues, or network connectivity problems beyond the VPN tunnel itself. Detected by checking byte counters (not increasing) or ping failures when the tunnel is established.

3. **Unknown**: Unable to determine the specific failure type (fallback when detection methods are unavailable).

Failure types are automatically detected and logged with each failure, helping you understand the root cause of VPN issues. The failure type is included in log messages and can help guide troubleshooting efforts.

### Tiered Recovery

The system uses a three-tier recovery approach that escalates based on consecutive failures:

1. **Tier 1 (Logging)**: Logs the failure for monitoring
2. **Tier 2 (Surgical Cleanup)**: 
   - **Experimental option (xfrm enabled)**: Uses xfrm-based per-connection recovery via `ip xfrm state delete` (⚠️ EXPERIMENTAL, requires `ENABLE_XFRM_RECOVERY=1`)
   - **Default (xfrm disabled or failed)**: Uses `ipsec reload` (affects all connections)
3. **Tier 3 (Full Restart)**: 
   - Uses `ipsec restart` to restart all IPsec tunnels

**Important**: Each peer IP has its own independent failure counter, allowing per-peer monitoring. However, recovery actions:
- **Default**: Tier 2 affects all connections (uses `ipsec reload`) - **per-connection recovery is not supported by default**
- **Experimental option**: xfrm-based per-connection recovery exists but is disabled by default (⚠️ EXPERIMENTAL, requires `ENABLE_XFRM_RECOVERY=1`)

⚠️ **Warning**: xfrm-based recovery is experimental and disabled by default. Only enable if you understand the risks and have tested on your system.

See [Configuration](#configuration) for xfrm recovery settings.

### Safety Features

- Lockfile protection prevents overlapping executions
- Cooldown period after restarts
- Rate limiting to prevent excessive restarts
- Per-peer failure tracking
- Input validation for security

For detailed architecture information including detection flow diagrams, recovery tier details, and technical implementation, see [ARCHITECTURE.md](ARCHITECTURE.md).

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

## Monitoring

### View Logs

```bash
# Real-time log monitoring
tail -f /data/vpn-monitor/logs/vpn-monitor.log

# View recent entries
tail -n 100 /data/vpn-monitor/logs/vpn-monitor.log
```

### Generate Reports

The `analyze-logs.sh` script analyzes VPN monitor logs and generates reports:

```bash
# Analyze logs and generate reports
/data/vpn-monitor/analyze-logs.sh

# Analyze logs for a specific date range
/data/vpn-monitor/analyze-logs.sh -d 2025-01-01:2025-01-31

# View generated reports
cat /data/vpn-monitor/reports/vpn-monitor-report.txt
```

Reports include summary statistics, tier action analysis, and event timelines. CSV exports are available for spreadsheet analysis.

### Manual Testing

```bash
# Run monitor manually
/data/vpn-monitor/vpn-monitor.sh

# Run in fake mode (checks failures but doesn't escalate tiers)
/data/vpn-monitor/vpn-monitor.sh --fake
```

For detailed troubleshooting, log analysis patterns, and diagnostic commands, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

**Fake Mode (`--fake` flag):**
The `--fake` flag allows you to test the monitoring script without triggering recovery actions. When enabled:
- VPN status checks are performed normally
- Failures are detected and logged
- Failure counters are incremented
- **Tier 2 (surgical cleanup) and Tier 3 (full restart) actions are skipped**
- Useful for testing detection logic without affecting VPN connections

### Troubleshooting

For comprehensive troubleshooting guides covering common issues, diagnosis steps, and solutions, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

**Common issues include:**
- Script not running (cron, lockfile, permissions)
- False positives (VPN working but monitor reports failures)
- Ping checks failing
- Keepalive daemon issues
- Recovery not working
- Configuration issues
- Performance issues
- Lockfile issues

Each issue includes detailed diagnosis steps and solutions in the troubleshooting guide.

## Keepalive Daemon

See the [Keepalive Daemon](#keepalive-daemon) section in Configuration for details on enabling and managing the VPN keepalive daemon.

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

1. **⚠️ Tier 2 Recovery Impact - READ THIS**: See the [Tiered Recovery](#tiered-recovery) section for detailed behavior. In summary: Tier 2 affects all tunnels by default (uses `ipsec reload`). Experimental xfrm-based per-connection recovery is available but disabled by default.
2. **Full Restart Impact**: Tier 3 recovery always restarts all IPsec tunnels using `ipsec restart`, temporarily affecting all Site-to-Site and remote user VPNs, regardless of configuration.
3. **Best-Effort**: This is a watchdog tool, not a guaranteed daemon. It may miss failures or require manual intervention
4. **Upgrade Compatibility**: UniFi OS upgrades may break functionality or remove cron jobs
5. **No Official Support**: This is an unofficial tool. Use at your own risk

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

**Ping Check Behavior:**

The ping check provides additional connectivity verification beyond SA state checks. However, it's important to understand how ping failures interact with SA state:

**Scenario 1: SA Exists But Ping Fails**
- **Behavior**: VPN is marked as **OK** (SA check passes), but a **WARNING** is logged
- **Reasoning**: The Security Association exists, indicating the tunnel is established at the IPsec level. The ping failure suggests the tunnel may not be routing traffic correctly, but the SA state is still valid
- **Impact**: The tunnel passes the primary check (SA exists), allowing it to remain active while warning about connectivity issues
- **Escalation**: If ping continues to fail, byte counters should also stop increasing (no traffic flowing), which will eventually trigger a failure when byte counters don't increase. This provides a natural escalation path: ping warnings → byte counter failure → recovery actions
- **Use Case**: Helps detect cases where the tunnel is established but routing is broken, without immediately failing on transient ping issues

**Scenario 2: SA Doesn't Exist But Ping Succeeds**
- **Behavior**: VPN is marked as **FAILED** (SA check fails), but a **WARNING** is logged
- **Reasoning**: No Security Association exists, so the VPN tunnel is down. However, ping succeeds, indicating connectivity exists via another route (not through the VPN tunnel)
- **Impact**: The tunnel fails the primary check (no SA), triggering normal failure handling. The ping success warning helps distinguish between "no connectivity at all" vs "connectivity exists but not through VPN"
- **Use Case**: Helps identify when connectivity exists via alternative routes (e.g., direct internet, other VPNs) even though the monitored tunnel is down

**Why This Design?**
The ping check is designed as a **supplementary diagnostic tool**, not a hard failure condition. The primary detection method (SA state + byte counters) remains the authoritative source for tunnel health. Ping checks provide early warning of connectivity issues while allowing the more reliable byte counter method to confirm actual traffic flow problems before triggering recovery actions.

If validation fails (based on SA state and byte counters), it escalates through recovery tiers. The ping check helps distinguish between "tunnel exists but broken" and "tunnel exists and working but idle".

### State Management

State is tracked via files in `/data/vpn-monitor/`:
- `logs/failure_counter_<peer_ip>`: Per-peer consecutive failure count (sanitized IP in filename, e.g., `failure_counter_192_168_1_1`)
- `last_restart`: Timestamp of last restart
- `logs/restart_count`: Timestamps of all restarts (for rate limiting)
- `logs/vpn-monitor.log`: Main log file
- `last_bytes_<peer_ip>`: Per-peer last known byte counter value (sanitized IP in filename, e.g., `last_bytes_192_168_1_1`)
- `cooldown_until`: Cooldown expiration timestamp
- `vpn-monitor.lock`: Lockfile for execution control (format: `timestamp:pid` for timeout detection)
- `.cron_checked`: Flag file to prevent repeated cron persistence checks

**Per-Peer State Tracking:**

The monitor tracks state independently for each configured peer IP, enabling independent monitoring and recovery actions for multiple VPN tunnels. This is essential when monitoring multiple Site-to-Site VPN connections, as failures in one tunnel should not affect the monitoring or recovery of other tunnels.

**File Naming Convention:**
All per-peer state files use sanitized peer IP addresses in their filenames. Dots and colons are replaced with underscores (e.g., `192.168.1.1` becomes `192_168_1_1`, `2001:db8::1` becomes `2001_db8__1`). This ensures safe filenames while maintaining uniqueness per peer.

**Per-Peer State Files:**

1. **Failure Counters** (`logs/failure_counter_<peer_ip>`)
   - **Purpose**: Tracks consecutive failure count for each peer independently
   - **Creation**: Created on-demand when a peer first fails
   - **Usage**: Used to determine which recovery tier to trigger (Tier 1, 2, or 3)
   - **Independence**: Each peer has its own counter. For example:
     - Peer A (`203.0.113.1`) failing 3 times → triggers Tier 2 recovery for Peer A
     - Peer B (`198.51.100.1`) failing 2 times → triggers Tier 1 logging for Peer B
     - These are tracked completely independently
   - **Reset**: Counter resets to 0 when VPN check succeeds for that peer
   - **Location**: Stored in `logs/` directory

2. **Byte Counters** (`last_bytes_<peer_ip>`)
   - **Purpose**: Stores the last known byte counter value from `ip xfrm state` for each peer
   - **Creation**: Created on-demand when byte counters are first read for a peer
   - **Usage**: Used to detect if byte counters are increasing (indicating active traffic flow)
   - **Independence**: Each peer has its own byte counter file, allowing independent traffic flow detection
   - **Update**: Updated each time a successful check reads increasing byte counters
   - **Location**: Stored in main state directory (`/data/vpn-monitor/`)

**Benefits of Per-Peer Tracking:**
- **Independent Recovery**: Each tunnel can be recovered independently based on its own failure count
- **Accurate Detection**: Byte counter tracking per peer ensures accurate detection of traffic flow issues for each tunnel
- **Multi-Tunnel Support**: Enables monitoring of multiple VPN peers without interference between them
- **Granular Logging**: Failure counters and recovery actions are tracked per peer, making troubleshooting easier

**Example Scenario:**
If you're monitoring three VPN peers (`203.0.113.1`, `198.51.100.1`, `192.0.2.1`), the monitor creates separate state files:
- `logs/failure_counter_203_0_113_1` - tracks failures for first peer
- `logs/failure_counter_198_51_100_1` - tracks failures for second peer  
- `logs/failure_counter_192_0_2_1` - tracks failures for third peer
- `last_bytes_203_0_113_1` - tracks byte counters for first peer
- `last_bytes_198_51_100_1` - tracks byte counters for second peer
- `last_bytes_192_0_2_1` - tracks byte counters for third peer

Each peer's monitoring and recovery actions operate completely independently.

## License

This tool is provided as-is without warranty. Use at your own risk.

## Testing

The project includes a comprehensive test suite using [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

Quick start:
```bash
# Run all tests
./tests/run_tests.sh

# Run tests with coverage reporting
./tests/run_tests.sh --coverage
```

For detailed testing documentation including prerequisites, test structure, coverage reporting, and writing new tests, see [tests/README.md](tests/README.md).

## CI/CD

This project uses GitHub Actions for continuous integration. The CI pipeline automatically runs on every push and pull request.

Check the [Actions](https://github.com/YOUR_USERNAME/udm-vpn-monitor/actions) tab to view the status of CI runs.

**Note:** Update the badge URL in the README header with your actual GitHub username/repository name to display the CI status badge correctly.

For detailed CI/CD pipeline information, local development checks, and workflow instructions, see [DEVELOPER.md](DEVELOPER.md).

## Contributing

Issues and pull requests welcome. Please test thoroughly on UDM systems before submitting.

When contributing:
1. Add tests for new functionality
2. Ensure all tests pass: `./tests/run_tests.sh`
3. Follow existing code patterns and style

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed architecture diagrams, component interactions, and design decisions.

## Documentation

- **[README.md](README.md)** - This file: User-facing documentation, installation, and usage
- **[QUICK_START.md](QUICK_START.md)** - 5-minute setup guide for new users
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System architecture, design decisions, and component interactions
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and release notes
- **[DEVELOPER.md](DEVELOPER.md)** - Developer guide with tooling setup, workflows, and code quality standards
- **[ENHANCEMENTS.md](ENHANCEMENTS.md)** - Future enhancement ideas and roadmap
- **[tests/README.md](tests/README.md)** - Comprehensive testing documentation

**In-Code Documentation**: All functions in the codebase include comprehensive documentation with:
- Function purpose and behavior
- Parameter descriptions and types
- Return values and exit codes
- Side effects and file operations
- Usage examples where helpful
- Notes about dependencies and requirements

See individual source files for detailed function documentation.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a detailed history of changes and version information.

## Future Enhancements

See [ENHANCEMENTS.md](ENHANCEMENTS.md) for a comprehensive list of potential improvements and future development ideas.

## Acknowledgments

Designed based on real-world UDM VPN monitoring needs and UniFi OS 4.3+ constraints.

