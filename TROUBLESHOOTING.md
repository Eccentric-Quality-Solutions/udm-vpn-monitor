# Troubleshooting Guide

Common issues and solutions for the UDM VPN Monitor.

## Common Issues

### Script Not Running
**Symptoms**: No log entries, cron job exists but nothing happens

**Solutions**:
1. Check lockfile: `ls -l /data/vpn-monitor/vpn-monitor.lock`
2. Check cron: `crontab -l | grep vpn-monitor`
3. Run manually: `/data/vpn-monitor/vpn-monitor.sh`
4. Check permissions: `ls -l /data/vpn-monitor/vpn-monitor.sh`

### False Positives
**Symptoms**: VPN is working but monitor reports failures

**Solutions**:
1. Check byte counters: `ip xfrm state | grep <PEER_IP>`
2. Disable ping checks: `ENABLE_PING_CHECK=0`
3. Increase thresholds in config
4. Enable debug: `DEBUG=1` and check logs

### Recovery Not Working
**Symptoms**: Failures detected but VPN doesn't recover

**Solutions**:
1. Check recovery logs: `grep "Tier" /data/vpn-monitor/logs/vpn-monitor.log`
2. Verify swanctl available: `which swanctl`
3. Check connection names: `swanctl --list-conns`
4. Test recovery manually: `/data/vpn-monitor/vpn-monitor.sh` (not --fake)

---

## Table of Contents

- [Script Not Running](#script-not-running)
- [False Positives](#false-positives)
- [Recovery Not Working](#recovery-not-working)
- [Ping Checks Failing](#ping-checks-failing)
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
   Should show: `*/1 * * * * /data/vpn-monitor/vpn-monitor.sh >> /data/vpn-monitor/cron.log 2>&1`

2. **Check cron.log for errors**:
   ```bash
   tail -f /data/vpn-monitor/cron.log
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
   ping -c 3 <PING_TARGET_IP>
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

### Solutions

**If VPN is idle (no traffic)**:
- Byte counters may be 0 or not increasing
- This is normal for idle VPNs
- Consider disabling byte counter check or increasing thresholds
- Or ensure some traffic flows through VPN

**If ping checks are failing**:
- Ping may be blocked by firewall
- Disable ping checks: `ENABLE_PING_CHECK=0`
- Or configure `PING_TARGET_IP` to a reachable IP

**If thresholds are too low**:
- Increase thresholds in config:
  ```bash
  TIER1_THRESHOLD=2
  TIER2_THRESHOLD=5
  TIER3_THRESHOLD=10
  ```
  Requires more failures before action.

**If VPN uses different detection method**:
- Script uses `ip xfrm state` (primary), `swanctl` (fallback), `ipsec` (fallback)
- If your VPN doesn't show up in these, detection may not work
- Check which method your VPN uses:
  ```bash
  swanctl --list-sas
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

2. **Check if swanctl is available**:
   ```bash
   which swanctl
   swanctl --version
   ```
   Tier 2 recovery requires swanctl.

3. **Check connection names**:
   ```bash
   swanctl --list-conns
   swanctl --list-sas
   ```
   Verify connection names match config (if configured).

4. **Check if recovery actually ran**:
   ```bash
   # Run monitor manually (not --fake)
   /data/vpn-monitor/vpn-monitor.sh
   ```
   Watch for recovery action messages.

5. **Check rate limiting**:
   ```bash
   cat /data/vpn-monitor/logs/restart_count
   ```
   If too many restarts in last hour, rate limiting may block recovery.

6. **Check cooldown period**:
   ```bash
   cat /data/vpn-monitor/cooldown_until
   ```
   If cooldown is active, checks are skipped.

### Solutions

**If swanctl not available**:
- Tier 2 recovery requires swanctl
- Install swanctl or use Tier 3 recovery only
- Or configure connection names manually

**If connection names don't match**:
- Auto-discovery may have failed
- Manually configure connection names (see [README.md Configuration section](README.md#configuration) for details):
  ```bash
  # Find connection name
  swanctl --list-sas | grep <PEER_IP>
  
  # Configure in config file using sanitized peer IP format
  CONNECTION_NAME_203_0_113_1="site-to-site-1"
  ```

**If rate limited**:
- Too many restarts in last hour (default: max 3)
- Wait for rate limit to expire (1 hour)
- Or increase `MAX_RESTARTS_PER_HOUR` in config

**If in cooldown**:
- Cooldown period after restart (default: 15 minutes)
- Wait for cooldown to expire
- Or reduce `COOLDOWN_MINUTES` in config

**If recovery actions fail**:
- Check if `ipsec` or `swanctl` commands work manually:
  ```bash
  ipsec restart
  swanctl --reload
  ```
- Check for permission issues
- Check system logs: `dmesg | tail -50`

---

## Ping Checks Failing

### Symptoms
- Ping checks always fail
- Logs show "Ping check failed" warnings
- VPN is working but ping fails

### Diagnosis Steps

1. **Test ping manually**:
   ```bash
   ping -c 3 <PING_TARGET_IP>
   ```
   If this fails, ping is blocked or target is unreachable.

2. **Check ping target configuration**:
   ```bash
   grep PING_TARGET_IP /data/vpn-monitor/vpn-monitor.conf
   ```
   If empty, uses peer IP (external IP, may not be pingable).

3. **Check firewall rules**:
   - Ping may be blocked by firewall
   - ICMP may be disabled
   - Check firewall logs

4. **Check ping command availability**:
   ```bash
   which ping
   ping -V
   ```

### Solutions

**If ping is intentionally blocked**:
- Disable ping checks: `ENABLE_PING_CHECK=0`
- Monitor relies only on byte counters

**If ping target is wrong**:
- Configure `PING_TARGET_IP` to an internal/private IP on remote network
- Example: `PING_TARGET_IP="192.168.100.1"`
- This verifies end-to-end connectivity through tunnel
- See [README.md Configuration section](README.md#configuration) for PING_TARGET_IP details

**If ping command not available**:
- Install ping: `apt-get install iputils-ping`
- Or disable ping checks: `ENABLE_PING_CHECK=0`

**If IPv6 ping issues**:
- Script auto-detects IPv4 vs IPv6
- For IPv6, ensure `ping6` or `ping -6` works
- Or disable ping checks if IPv6 ping is problematic

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
   grep PEER_IPS /data/vpn-monitor/vpn-monitor.conf
   ```
   Should not be empty.

4. **Check config file permissions**:
   ```bash
   ls -l /data/vpn-monitor/vpn-monitor.conf
   ```
   Should be readable.

### Solutions

**If PEER_IPS is empty**:
```bash
# Edit config
nano /data/vpn-monitor/vpn-monitor.conf
# Set PEER_IPS to your remote VPN gateway's external/public IP address(es)
# Example: PEER_IPS="203.0.113.1"
```
See [README.md Configuration section](README.md#configuration) for details on configuring PEER_IPS.

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

2. **Check for multiple peers**:
   ```bash
   grep PEER_IPS /data/vpn-monitor/vpn-monitor.conf
   ```
   More peers = longer execution time.

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

**If too many peers**:
- Reduce number of peers monitored
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
[WARNING] Tier 2: Attempting surgical SA cleanup for 203.0.113.1
[INFO] Surgical cleanup completed for 203.0.113.1
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
5. **Check code review**: [CODE_REVIEW.md](CODE_REVIEW.md) for known issues

## Reporting Issues

When reporting issues, please include:

1. **UDM Model**: UDM/UDM-Pro/UDM-SE
2. **UniFi OS Version**: `cat /etc/version`
3. **Script Version**: `/data/vpn-monitor/vpn-monitor.sh --version`
4. **Configuration**: Relevant config values (sanitize IPs)
5. **Logs**: Relevant log entries
6. **Steps to Reproduce**: What you did and what happened

