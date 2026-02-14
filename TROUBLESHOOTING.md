# Troubleshooting Guide

Common issues and solutions for the UDM VPN Monitor.

## Table of Contents

- [Script Not Running](#script-not-running)
- [False Positives](#false-positives)
- [Recovery Not Working](#recovery-not-working)
- [Ping Checks Failing](#ping-checks-failing)
- [Keepalive Daemon Issues](#keepalive-daemon-issues)
- [Lockfile Issues](#lockfile-issues)
- [Configuration Issues](#configuration-issues)
- [Performance Issues](#performance-issues)
- [Log Analysis](#log-analysis)

---

## Script Not Running

### Symptoms
- No log entries appearing
- Cron job exists but nothing happens
- Manual execution works but cron doesn't

### Diagnosis Steps

1. **Check cron job exists**:
   ```bash
   crontab -l | grep vpn-monitor
   ```
   Should show: `*/1 * * * * /data/vpn-monitor/vpn-monitor.sh >> /data/vpn-monitor/logs/cron.log 2>&1`

2. **Check cron.log for errors**:
   ```bash
   tail -f /data/vpn-monitor/logs/cron.log
   ```
   Look for error messages or permission issues.

3. **Check lockfile**:
   ```bash
   ls -l /data/vpn-monitor/vpn-monitor.lock
   cat /data/vpn-monitor/vpn-monitor.lock
   ```
   Lockfile format: `timestamp:pid` (e.g., `1705320000:12345`)

4. **Check if lockfile is stale**:
   ```bash
   # Get lockfile age in seconds
   echo $(($(date +%s) - $(stat -c %Y /data/vpn-monitor/vpn-monitor.lock)))
   ```
   If older than 300 seconds (5 minutes), it's stale.

5. **Check if PID is running**:
   ```bash
   # Extract PID from lockfile
   PID=$(cat /data/vpn-monitor/vpn-monitor.lock | cut -d: -f2)
   ps -p $PID
   ```
   If PID doesn't exist, lockfile is stale.

6. **Run manually**:
   ```bash
   /data/vpn-monitor/vpn-monitor.sh
   ```
   Check for error messages.

### Solutions

**If cron job missing**:
```bash
# Re-run installer
/tmp/install.sh --silent
```

**If lockfile is stale**:
```bash
# Remove stale lockfile (only if PID is not running)
PID=$(cat /data/vpn-monitor/vpn-monitor.lock | cut -d: -f2)
if ! ps -p $PID > /dev/null 2>&1; then
    rm -f /data/vpn-monitor/vpn-monitor.lock
fi
```

**If permissions issue**:
```bash
# Check script is executable
ls -l /data/vpn-monitor/vpn-monitor.sh

# Fix permissions if needed
chmod +x /data/vpn-monitor/vpn-monitor.sh
```

**If cron service not running**:
```bash
# Check cron service status (varies by system)
systemctl status cron
# or
service cron status
```

---

## False Positives

### Symptoms
- VPN is working but monitor reports failures
- Logs show failures but VPN is actually healthy
- Byte counters not increasing but VPN is active

### Diagnosis Steps

1. **Check VPN status directly**:
   ```bash
   ip xfrm state | grep <PEER_IP>
   ```
   Should show Security Association (SA) with byte counters.

2. **Check byte counters**:
   ```bash
   ip xfrm state | grep -A 10 <PEER_IP> | grep "lifetime current"
   ```
   Look for `bytes` value - should be increasing if traffic is flowing.

3. **Check ping connectivity**:
   ```bash
   ping -c 3 <INTERNAL_PEER_IP>
   ```
   If ping fails, that's why ping check is failing.

4. **Enable debug logging**:
   ```bash
   # Edit config
   nano /data/vpn-monitor/vpn-monitor.conf
   # Set DEBUG=1
   
   # Run manually
   /data/vpn-monitor/vpn-monitor.sh
   ```
   Check debug output for detailed information.

5. **Check for false positive detection patterns**:
   Look for these log patterns that indicate false positives:
   ```
   [WARNING] VPN suspect: SA exists for <IP> but byte counter info unavailable
   [WARNING] VPN suspect: No connection found via ipsec status for <IP>
   [INFO] Ping check OK: <internal_IP> from <local_IP> (0% packet loss)
   [WARNING] VPN tunnel is down (no SA found), but connectivity exists via alternative route
   [WARNING] VPN failure type: Unknown (unable to determine specific failure type)
   ```
   If you see this pattern with successful ping checks, the VPN may actually be healthy but detection is failing due to byte counter extraction issues. The system should automatically fall back to ping checks when byte counters are unavailable (if `ENABLE_PING_CHECK=1` and internal IPs are configured).

### Solutions

**If VPN is idle (no traffic)**:
- Byte counters may be 0 or not increasing
- This is normal for idle VPNs
- Consider disabling byte counter check or increasing thresholds
- Or ensure some traffic flows through VPN

**If ping checks are failing**:
- Ping may be blocked by firewall
- Disable ping checks: `ENABLE_PING_CHECK=0`
- Or configure `LOCATION_*_INTERNAL` to a reachable IP

**If thresholds are too low**:
- Increase thresholds in config:
  ```bash
  TIER1_THRESHOLD=2
  TIER2_THRESHOLD=5
  TIER3_THRESHOLD=10
  ```
  Requires more failures before action.

**If VPN uses different detection method**:
- Script uses `ip xfrm state` (primary), `ipsec` (fallback)
- If your VPN doesn't show up in these, detection may not work
- Check which method your VPN uses:
  ```bash
  ip xfrm state
  ipsec status
  ```

---

## Recovery Not Working

### Symptoms
- Failures detected but VPN doesn't recover
- Tier 2/Tier 3 actions logged but no recovery
- VPN remains down after recovery attempts

### Diagnosis Steps

1. **Check recovery logs**:
   ```bash
   grep "Tier" /data/vpn-monitor/logs/vpn-monitor.log
   ```
   Look for Tier 2 and Tier 3 action messages.

2. **Check if ipsec command is available**:
   ```bash
   which ipsec
   ipsec --version
   ```
   Tier 2 and Tier 3 recovery require ipsec command.

4. **Check if recovery actually ran**:
   ```bash
   # Run monitor manually (not --fake)
   /data/vpn-monitor/vpn-monitor.sh
   ```
   Watch for recovery action messages.

5. **Check rate limiting**:
   ```bash
   cat /data/vpn-monitor/state/restart_count
   ```
   This file contains Unix timestamps (one per line) of Tier 3 recovery actions (full IPsec restarts and successful xfrm-based per-connection recovery). If too many restarts occurred in the last hour (default: max 3), rate limiting may block further Tier 3 recovery actions.
   
   **Important Note**: Log messages showing "Tier 3: Attempting..." are logged BEFORE the rate limit check. If you see many "Tier 3: Attempting..." messages but no actual restart commands executing, this indicates rate limiting is working correctly. The restart command only executes if rate limiting allows it. If you see "Rate limit exceeded: 3 restarts in last hour (max: 3)", this confirms rate limiting is blocking the restart.
   
   **Why 0 restarts when limit is 3?** If you see many restart attempts but 0 completed restarts, possible explanations:
   - Restart count file already contained 3 entries from before the current monitoring period (within the last hour)
   - All restart attempts occurred after the first 3 restarts had already been recorded
   - Check the restart count file timestamps to verify when the last 3 restarts occurred

6. **Check cooldown period**:
   ```bash
   cat /data/vpn-monitor/cooldown_until
   ```
   If cooldown is active, checks are skipped.

### Solutions

**If ipsec command not available**:
- Tier 2 and Tier 3 recovery require ipsec command
- Check if ipsec is installed: `which ipsec`
- Check system logs: `dmesg | tail -50`

**If rate limited**:
- Too many Tier 3 restarts in configured window (default: max 20 per 60 minutes)
- Wait for rate limit to expire (window duration from oldest restart)
- Or adjust rate limiting configuration:
  - `MAX_RESTARTS_PER_WINDOW` (default: 20, range: 1-20)
  - `RATE_LIMIT_WINDOW_MINUTES` (default: 60, range: 5-1440)
  - `MIN_RESTART_INTERVAL_SECONDS` (default: 40, range: 0-300)
- **Note**: If you see "Tier 3: Attempting..." messages but no actual restart, rate limiting is working as designed. The log message appears before the rate limit check, but the restart only executes if allowed.

**If minimum restart interval not met**:
- Restart attempted too soon after previous restart (default: minimum 40 seconds)
- Wait for minimum interval to elapse
- Or adjust `MIN_RESTART_INTERVAL_SECONDS` in config (set to 0 to disable)

**If recovery actions fail**:
- Check if `ipsec` command works manually:
  ```bash
  ipsec restart
  ipsec reload
  ```
- Check for permission issues
- Check system logs: `dmesg | tail -50`

---

## Ping Checks Failing

### "Ping timeouts but VPN never restarts"

If pings time out repeatedly but the monitor never triggers recovery:

1. **Ping check not used for this location**  
   The monitor only uses ping when **ENABLE_PING_CHECK=1** and the location has **internal IP(s)** configured (e.g. `INTERNAL_PEER_IP` or per-location internal IPs). If either is missing, the VPN is considered OK whenever xfrm byte counters show traffic; ping is not run in that path, so timeouts (e.g. from manual pings) do not affect the result.  
   **Fix:** Set `ENABLE_PING_CHECK=1` and configure internal IPs for the location so ping runs and failures are counted.

2. **Recovery needs consecutive failures**  
   Recovery runs only after **3** (Tier 2) or **5** (Tier 3) **consecutive** runs where the VPN check fails. Any single run where the check passes (e.g. one successful ping) resets the failure count to 0. So if ping is intermittent (timeout, timeout, pass, timeout…), the counter never reaches 3 or 5.  
   **Check logs:** Look for "VPN suspect" with "ping check failed" and "VPN restored" or "VPN check OK" in between; that indicates resets.  
   **Options:** Ensure the ping target and network are stable enough for consecutive failures, or consider lowering tier thresholds (see `vpn-monitor.conf`).

3. **Ipsec fallback no longer overrides ping failure**  
   If the xfrm check finds an SA but fails (e.g. ping times out), the monitor no longer uses the ipsec-status fallback to mark the VPN OK. Previously, `ipsec status` could still show the connection as established while the tunnel was broken, so the failure count was reset every run and recovery never triggered. Now, when xfrm fails with "SA exists" (e.g. bytes increasing but ping failed), the result is treated as a real failure and recovery can run after consecutive failures.

### Symptoms
- Ping checks always fail
- Logs show "Ping check failed" warnings
- VPN is working but ping fails
- "Route not found on br0" or "Failed to add route" messages in logs

### How Routes Work

Routes (IP addresses on the `br0` interface) are automatically managed by the VPN monitor in three scenarios:

1. **During Installation** (`install.sh`):
   - Function: `check_and_setup_routes()`
   - When: Runs during installation if `ENABLE_PING_CHECK=1` and internal IPs are configured
   - What it does:
     - Checks if `LOCAL_UDM_IP` is configured (auto-detects from br0 if not)
     - Adds route: `ip addr add <LOCAL_UDM_IP>/32 dev br0`
     - Tests ping connectivity to all internal IPs from all locations

2. **During Config Validation** (`lib/config.sh`):
   - Function: `setup_routes_if_needed()`
   - When: Called automatically during `validate_config()` when config is loaded
   - What it does:
     - Checks if ping checks are enabled and internal IPs are configured
     - Retrieves `LOCAL_UDM_IP` using `get_local_ip_for_ping()`
     - Checks if route exists via `check_route_exists()`
     - If route doesn't exist, calls `add_route_if_needed()` to add it
     - Fails validation if route setup fails when routes are actually needed
   - **Key Benefit:** Routes are set up proactively before any checks run, ensuring they're available even if VPN checks are skipped

3. **During Normal Operation** (`lib/detection.sh`):
   - Function: `check_ping_connectivity()`
   - When: Called during VPN monitoring when ping checks are enabled
   - What it does:
     - Checks if route exists via `check_route_exists()`
     - If route doesn't exist, calls `add_route_if_needed()` to add it
     - Then performs ping check with `-I <local_ip>` flag
   - **Note:** This now serves as a fallback/re-check mechanism, since routes should already be set up during config validation

**Key Functions:**
- `check_route_exists()`: Checks if IP exists on br0 interface
- `add_route_if_needed()`: Adds IP to br0 if it doesn't exist
- `get_local_ip_for_ping()`: Retrieves `LOCAL_UDM_IP` from config

### Diagnosis Steps

1. **Test ping manually**:
   ```bash
   ping -c 3 <INTERNAL_PEER_IP>
   ```
   If this fails, ping is blocked or target is unreachable.

2. **Check ping target configuration**:
   ```bash
   grep LOCATION.*INTERNAL /data/vpn-monitor/vpn-monitor.conf
   ```
   If empty, uses external IP (may not be pingable).

3. **Check LOCAL_UDM_IP configuration** (if using INTERNAL IPs):
   ```bash
   grep LOCAL_UDM_IP /data/vpn-monitor/vpn-monitor.conf
   ```
   Should be set to your local UDM's internal IP address (e.g., "192.168.1.1").

4. **Check if route exists on br0**:
   ```bash
   ip addr show br0 | grep <LOCAL_UDM_IP>
   ```
   Should show the IP address configured on br0 interface.

5. **Test ping with source IP** (if LOCAL_UDM_IP is configured):
   ```bash
   ping -I <LOCAL_UDM_IP> <INTERNAL_PEER_IP> -c 3
   ```
   This tests the same ping command the script uses.

6. **Check firewall rules**:
   - Ping may be blocked by firewall
   - ICMP may be disabled
   - Check firewall logs

7. **Check ping command availability**:
   ```bash
   which ping
   ping -V
   ```

### Solutions

**If ping is intentionally blocked**:
- Disable ping checks: `ENABLE_PING_CHECK=0`
- Monitor relies only on byte counters

**If ping target is wrong**:
- Configure `LOCATION_*_INTERNAL` to internal/private IPs on remote network
- Example: `LOCATION_NYC_INTERNAL="192.168.100.1"`
- See [README.md Configuration section](README.md#configuration) for location-based configuration details

**If LOCAL_UDM_IP is not configured**:
- Set `LOCAL_UDM_IP` to your local UDM's internal IP address
- Example: `LOCAL_UDM_IP="192.168.1.1"`
- The installer will attempt to auto-detect this from br0 if not set
- You can manually detect it: `ip addr show br0 | grep "inet " | awk '{print $2}' | cut -d/ -f1`

**If route addition fails**:
- Check if you have root privileges (required for `ip addr add`)
- Manually add route: `ip addr add <LOCAL_UDM_IP>/32 dev br0`
- Verify route exists: `ip addr show br0 | grep <LOCAL_UDM_IP>`
- The script will automatically re-add the route when needed (route is temporary and lost on reboot)
- **Verify route setup during config validation:**
  ```bash
  # Routes should be added automatically when config is validated
  /data/vpn-monitor/vpn-monitor.sh --check-config
  ip addr show br0 | grep <LOCAL_UDM_IP>
  ```
- **Check logs for route setup messages:**
  ```bash
  grep -i "route" /data/vpn-monitor/logs/vpn-monitor.log
  ```
- If route setup fails during validation, you'll see clear ERROR messages with manual fix instructions

**If ping command not available**:
- Install ping: `apt-get install iputils-ping`
- Or disable ping checks: `ENABLE_PING_CHECK=0`

**If IPv6 ping issues**:
- Script auto-detects IPv4 vs IPv6
- For IPv6, ensure `ping6` or `ping -6` works
- Or disable ping checks if IPv6 ping is problematic

---

## Keepalive Daemon Issues

### Symptoms
- Keepalive daemon not starting
- Keepalive daemon stops unexpectedly
- Systemd service fails to start
- Keepalive pings not being sent

### Diagnosis Steps

1. **Check if keepalive is enabled**:
   ```bash
   grep ENABLE_KEEPALIVE /data/vpn-monitor/vpn-monitor.conf
   ```
   Should show: `ENABLE_KEEPALIVE=1`

2. **Check systemd service status**:
   ```bash
   systemctl status vpn-keepalive
   ```
   Look for active/running status or error messages.

3. **Check if daemon is running manually**:
   ```bash
   /data/vpn-monitor/vpn-keepalive.sh status
   ```
   Should show: `VPN keepalive daemon is running (PID: <pid>)`

4. **Check keepalive logs**:
   ```bash
   # Systemd journal
   journalctl -u vpn-keepalive -f
   
   # Or log file
   tail -f /data/vpn-monitor/logs/vpn-keepalive.log
   ```

5. **Check PID file**:
   ```bash
   cat /data/vpn-monitor/vpn-keepalive.pid
   ps -p $(cat /data/vpn-monitor/vpn-keepalive.pid)
   ```

6. **Verify configuration**:
   ```bash
   grep -E "KEEPALIVE|LOCATION.*EXTERNAL|LOCATION.*INTERNAL" /data/vpn-monitor/vpn-monitor.conf
   ```

### Solutions

1. **Service won't start**:
   - Verify `ENABLE_KEEPALIVE=1` in config file
   - Check systemd service file exists: `ls -l /etc/systemd/system/vpn-keepalive.service`
   - Reload systemd: `systemctl daemon-reload`
   - Check service file syntax: `systemctl cat vpn-keepalive`

2. **Daemon stops unexpectedly**:
   - Check logs for error messages
   - Verify VPN peers are configured correctly
   - Check if ping commands are available: `which ping ping6`
   - Restart service: `systemctl restart vpn-keepalive`

3. **Manual start works but systemd doesn't**:
   - Check systemd service file paths are correct
   - Verify systemd has permissions to execute script
   - Check systemd logs: `journalctl -u vpn-keepalive -n 50`

4. **Keepalive pings failing**:
   - Verify location-based configuration is set (e.g., `LOCATION_*_EXTERNAL` and `LOCATION_*_INTERNAL`)
   - Check if VPN tunnel is actually up
   - Test ping manually: `ping -c 1 <peer_ip>`
   - Check firewall rules that might block ping

5. **Service enabled but not starting on boot**:
   - Enable service: `systemctl enable vpn-keepalive`
   - Check service dependencies: `systemctl list-dependencies vpn-keepalive`
   - Verify network-online.target is available

6. **Reinstall systemd service**:
   ```bash
   # Stop and remove old service
   systemctl stop vpn-keepalive
   systemctl disable vpn-keepalive
   rm /etc/systemd/system/vpn-keepalive.service
   systemctl daemon-reload
   
   # Reinstall
   /data/vpn-monitor/install.sh --silent
   systemctl enable --now vpn-keepalive
   ```

---

## Lockfile Issues

### Symptoms
- "Another instance is already running" messages
- Script won't run
- Lockfile exists but no process running

### Diagnosis Steps

1. **Check lockfile exists**:
   ```bash
   ls -l /data/vpn-monitor/vpn-monitor.lock
   ```

2. **Check lockfile format**:
   ```bash
   cat /data/vpn-monitor/vpn-monitor.lock
   ```
   Should be: `timestamp:pid` (e.g., `1705320000:12345`)

3. **Check if PID is running**:
   ```bash
   PID=$(cat /data/vpn-monitor/vpn-monitor.lock | cut -d: -f2)
   ps -p $PID
   ```

4. **Check lockfile age**:
   ```bash
   echo $(($(date +%s) - $(stat -c %Y /data/vpn-monitor/vpn-monitor.lock)))
   ```
   If older than `LOCKFILE_TIMEOUT` (default: 300 seconds), it's stale.

### Solutions

**If lockfile is stale**:
```bash
# Remove stale lockfile (only if PID is not running)
PID=$(cat /data/vpn-monitor/vpn-monitor.lock | cut -d: -f2)
if ! ps -p $PID > /dev/null 2>&1; then
    rm -f /data/vpn-monitor/vpn-monitor.lock
    echo "Removed stale lockfile"
else
    echo "PID $PID is still running, lockfile is valid"
fi
```

**If lockfile format is invalid**:
```bash
# Remove invalid lockfile
rm -f /data/vpn-monitor/vpn-monitor.lock
```

**If lockfile permissions issue**:
```bash
# Check permissions
ls -l /data/vpn-monitor/vpn-monitor.lock

# Fix if needed
chmod 644 /data/vpn-monitor/vpn-monitor.lock
```

**If multiple instances running**:
- This shouldn't happen with lockfile protection
- Check for hung processes: `ps aux | grep vpn-monitor`
- Kill hung processes: `kill <PID>`
- Remove lockfile: `rm -f /data/vpn-monitor/vpn-monitor.lock`

---

## Configuration Issues

For complete configuration documentation, including all parameters and their descriptions, see the [Configuration section in README.md](README.md#configuration).

### Symptoms
- Script exits with configuration errors
- Unexpected behavior
- Values not being used

### Diagnosis Steps

1. **Check config file exists**:
   ```bash
   ls -l /data/vpn-monitor/vpn-monitor.conf
   ```

2. **Check config file syntax**:
   ```bash
   # Source config to check for syntax errors
   source /data/vpn-monitor/vpn-monitor.conf
   ```

3. **Check required values**:
   ```bash
   grep LOCATION.*EXTERNAL /data/vpn-monitor/vpn-monitor.conf
   ```
   Should show at least one location configured (e.g., `LOCATION_NYC_EXTERNAL="203.0.113.1"`).

4. **Check config file permissions**:
   ```bash
   ls -l /data/vpn-monitor/vpn-monitor.conf
   ```
   Should be readable.

### Solutions

**If no locations are configured**:
```bash
# Edit config
nano /data/vpn-monitor/vpn-monitor.conf
# Configure VPN locations using location-based format:
# LOCATION_<NAME>_EXTERNAL="external_ip"
# LOCATION_<NAME>_INTERNAL="internal_ip1 internal_ip2 ..."
# Example:
LOCATION_NYC_EXTERNAL="203.0.113.1"
LOCATION_NYC_INTERNAL="192.168.100.1"
```
See [README.md Configuration section](README.md#configuration) for details on location-based configuration.

**If migrating from old format**:
If you have an existing configuration using `EXTERNAL_PEER_IPS`/`INTERNAL_PEER_IPS`, use the migration script:
```bash
/data/vpn-monitor/scripts/migrate-config-to-locations.sh
```
The migration script runs in interactive mode by default (prompts for location names). Use `--auto` for automatic generation or `--csv FILE` for bulk import. See [MIGRATION.md](docs/MIGRATION.md) for detailed migration instructions.

**If config syntax error**:
- Check for unclosed quotes
- Check for invalid variable names
- Check for special characters in values
- Verify config file format matches examples in [README.md Configuration section](README.md#configuration)

**If config not being loaded**:
- Check config file path in script
- Check config file permissions
- Run script with debug: `DEBUG=1 /data/vpn-monitor/vpn-monitor.sh`

**If thresholds invalid**:
- Ensure `TIER2_THRESHOLD > TIER1_THRESHOLD`
- Ensure `TIER3_THRESHOLD > TIER2_THRESHOLD`
- All thresholds should be positive integers
- See [README.md Configuration section](README.md#configuration) for threshold descriptions and defaults

---

## Performance Issues

### Symptoms
- Script takes too long to run
- High CPU usage
- System slowdown

### Diagnosis Steps

1. **Check script execution time**:
   ```bash
   time /data/vpn-monitor/vpn-monitor.sh
   ```
   Should complete in < 30 seconds.

2. **Check for multiple locations**:
   ```bash
   grep LOCATION.*EXTERNAL /data/vpn-monitor/vpn-monitor.conf
   ```
   More locations = longer execution time.

3. **Check ping timeout**:
   ```bash
   grep PING_TIMEOUT /data/vpn-monitor/vpn-monitor.conf
   ```
   Long timeout = longer execution if ping fails.

4. **Check system resources**:
   ```bash
   top
   free -h
   ```

### Solutions

**If too many locations**:
- Reduce number of locations monitored
- Or increase cron interval (check less frequently)

**If ping timeout too long**:
- Reduce `PING_TIMEOUT` (default: 2 seconds)
- Or disable ping checks: `ENABLE_PING_CHECK=0`

**If cron interval too frequent**:
- Increase `CRON_SCHEDULE` interval:
  ```bash
  # Every 5 minutes instead of 1 minute
  CRON_SCHEDULE="*/5 * * * *"
  ```
- Update cron job: Re-run installer
- See [README.md Configuration section](README.md#configuration) for CRON_SCHEDULE examples and format

**If system under load**:
- Increase `LOCKFILE_TIMEOUT` to handle slower execution
- Or reduce monitoring frequency

---

## Log Analysis

### View Recent Logs

```bash
# Last 100 lines
tail -n 100 /data/vpn-monitor/logs/vpn-monitor.log

# Follow logs in real-time
tail -f /data/vpn-monitor/logs/vpn-monitor.log

# Search for errors
grep ERROR /data/vpn-monitor/logs/vpn-monitor.log

# Search for specific peer
grep "203.0.113.1" /data/vpn-monitor/logs/vpn-monitor.log
```

### Generate Reports

```bash
# Analyze logs and generate reports
/data/vpn-monitor/analyze-logs.sh

# View reports
cat /data/vpn-monitor/reports/vpn-monitor-report.txt
cat /data/vpn-monitor/reports/vpn-monitor-analysis.csv
```

### Common Log Patterns

**VPN Healthy**:
```
[INFO] VPN OK: SA exists, bytes=1234567 (was 1234500)
```

**VPN Failure**:
```
[WARNING] VPN check failed for 203.0.113.1 (failure count: 1)
```

**Recovery Action**:
```
[INFO] Tier 2: Attempting surgical SA cleanup for 203.0.113.1
[INFO] xfrm-based surgical cleanup completed successfully for 203.0.113.1
```

**Recovery Success**:
```
[INFO] VPN recovered for 203.0.113.1 after 3 failures
```

**Rate Limited**:
```
[WARNING] Rate limit exceeded: 3 restarts in last hour (max: 3)
```

**Cooldown Active**:
```
[INFO] In cooldown period, 300 seconds remaining
```

---

## Getting More Help

If you're still experiencing issues:

1. **Check the logs**: `/data/vpn-monitor/logs/vpn-monitor.log`
2. **Enable debug mode**: `DEBUG=1` in config
3. **Run manually**: `/data/vpn-monitor/vpn-monitor.sh` (not --fake)
4. **Review documentation**: [README.md](README.md)
5. **Check architecture documentation**: [ARCHITECTURE.md](docs/ARCHITECTURE.md) for technical implementation details and design decisions

## Reporting Issues

When reporting issues, please include:

1. **UDM Model**: UDM/UDM-Pro/UDM-SE
2. **UniFi OS Version**: `cat /etc/version`
3. **Script Version**: `/data/vpn-monitor/vpn-monitor.sh --version`
4. **Configuration**: Relevant config values (sanitize IPs)
5. **Logs**: Relevant log entries
6. **Steps to Reproduce**: What you did and what happened

