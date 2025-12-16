# UDM VPN Monitor

[![CI](https://github.com/eccentric-quality-solutions/udm-vpn-monitor/workflows/CI/badge.svg)](https://github.com/eccentric-quality-solutions/udm-vpn-monitor/actions)

A best-effort watchdog for UniFi Dream Machines that detects Site-to-Site VPN failures using IPsec xfrm state byte counters and ping connectivity checks, implementing tiered recovery. Designed for UniFi OS 4.3+ with realistic persistence expectations.

## Overview

This tool monitors Site-to-Site VPN connections on UniFi Dream Machines (UDM/UDM-Pro/UDM-SE) and automatically attempts recovery when VPN tunnels appear active but are non-functional. It uses IPsec xfrm state byte counters combined with optional ping connectivity checks to detect actual traffic flow and verify end-to-end connectivity, which is more reliable than checking IKE status alone.

## ⚠️ Important: Tier 2 Recovery Behavior

**Before using this tool, understand how Tier 2 recovery works:**

- **With connection name configured (or auto-discovered)**: Tier 2 uses `swanctl --reload-conn <connection-name>` to reload **only the specific failing connection**. This is true per-connection recovery with minimal impact.

- **Without connection name**: Tier 2 uses `swanctl --reload` which reloads **ALL IPsec connections**, temporarily affecting **all Site-to-Site and remote user VPNs**. This is less "surgical" than intended.

**To enable per-connection recovery:**
- Connection names are automatically discovered from `swanctl` if available (recommended)
- Or manually configure `CONNECTION_NAME_<sanitized_peer_ip>` in the config file
- See the [Configuration](#configuration) section for details

**Note:** Tier 3 recovery always affects all tunnels regardless of configuration.

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
- ❌ Per-tunnel precise recovery by default (Tier 2 affects all tunnels unless connection names are configured)
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
| `PEER_IPS` | Space-separated list of remote VPN endpoint **external/public** IPs | (required) |
| `VPN_NAME` | VPN identifier for logging | "Site-to-Site VPN" |
| `CONNECTION_NAME_<peer_ip>` | Per-peer connection name for targeted reloads (see below) | "" |
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

**Per-Peer Connection Name Configuration:**

Connection names are used to enable per-connection reloads in Tier 2 (instead of reloading all tunnels). The script automatically discovers connection names from `swanctl` if not configured, but you can also manually configure them for better control.

**Important:** Connection names must match actual connection names in your swanctl configuration. They are not arbitrary - they must exactly match what `swanctl --list-conns` shows. If you configure a name that doesn't exist (e.g., "hot dog" when no such connection exists), the reload will fail and fall back to reloading all connections.

**Automatic Discovery (Recommended):**
- If `CONNECTION_NAME_<sanitized_peer_ip>` is not configured, the script automatically discovers the connection name from `swanctl --list-sas`
- Discovered connection names are cached in state files for performance
- Auto-discovery happens on first use and is logged for visibility
- **This is the recommended approach** as it ensures the connection name matches what swanctl actually has

**When Auto-Discovery May Fail:**
- **No active SA**: If the VPN tunnel is down and there's no active Security Association, `swanctl --list-sas` won't show the connection, so discovery fails
- **swanctl not available**: If swanctl command is not installed or not in PATH
- **Output format variations**: If swanctl output format differs from expected format (rare, but possible with different versions)
- **Multiple connections with same peer IP**: If multiple connections share the same peer IP, discovery may pick the wrong one

**Note:** Yes, every connection in swanctl configuration has a name (it's required), but discovery requires an active SA to find it. If discovery fails, the script gracefully falls back to reloading all connections.

**Manual Configuration (Optional):**
To manually configure connection names, use the format `CONNECTION_NAME_<sanitized_peer_ip>`. The sanitized peer IP replaces dots/colons with underscores.

**Example:**
```bash
# First, find the actual connection names:
swanctl --list-conns
swanctl --list-sas

# Then configure using the EXACT connection name from swanctl:
# For peer IP 203.0.113.1, if swanctl shows connection "site-to-site-1":
CONNECTION_NAME_203_0_113_1="site-to-site-1"

# For peer IP 198.51.100.1, if swanctl shows connection "remote-office-vpn":
CONNECTION_NAME_198_51_100_1="remote-office-vpn"
```

**Finding Connection Names:**
```bash
# List all configured connections
swanctl --list-conns

# List active Security Associations (shows connection names with peer IPs)
swanctl --list-sas
```

**Note:** If connection names cannot be discovered (e.g., swanctl not available or no active SA), or if a manually configured name doesn't match swanctl, Tier 2 will fall back to reloading all IPsec connections (affects all tunnels). See the [Tiered Recovery](#tiered-recovery) section for details.

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

**Important Notes:**
- **Per-Peer Failure Counter**: Each peer IP has its own independent failure counter tracked in `logs/failure_counter_<peer_ip>`. Failures are tracked separately per peer, allowing independent recovery actions. Recovery of one peer does not affect other peers' failure counters.
- **⚠️ Tier 2 Recovery Scope - CRITICAL**: Tier 2 recovery scope depends on connection name configuration:
  - **✅ With connection name (configured or auto-discovered)**: Uses `swanctl --reload-conn <connection-name>` to reload **only the specific failing connection**. This is true per-connection recovery with minimal impact on other tunnels.
  - **⚠️ Without connection name**: Uses `swanctl --reload` which reloads **ALL IPsec connections**, temporarily affecting **all Site-to-Site and remote user VPNs**. This makes Tier 2 less "surgical" than intended.
  - Connection names are automatically discovered from `swanctl --list-sas` if available (recommended), or you can manually configure `CONNECTION_NAME_<sanitized_peer_ip>` in the config file (see [Configuration](#configuration) section)
- **Tier 3 Impact**: Tier 3 recovery always affects **all IPsec tunnels** (full restart) regardless of configuration

1. **Tier 1 (Logging)**: After first failure, logs the issue
2. **Tier 2 (Surgical Cleanup)**: After 3 failures, attempts to delete specific SA states and reload configuration.
   - **With connection name**: Uses `swanctl --reload-conn <connection-name>` for targeted per-connection recovery ✅
   - **Without connection name**: Uses `swanctl --reload` which affects all tunnels ⚠️
   - See [Configuration](#configuration) section for connection name setup
3. **Tier 3 (Full Restart)**: After 5 failures, performs full `ipsec restart` (always affects all tunnels)

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
tail -f /data/vpn-monitor/logs/vpn-monitor.log

# View recent entries
tail -n 100 /data/vpn-monitor/logs/vpn-monitor.log

# Check for errors
grep ERROR /data/vpn-monitor/logs/vpn-monitor.log
```

### Log Analysis and Reporting

The `analyze-logs.sh` script provides detailed analysis of VPN monitor logs, generating reports on failure frequency and recovery success rates.

**Basic Usage:**

```bash
# Analyze default log file and generate reports
/data/vpn-monitor/analyze-logs.sh

# Analyze specific log file
/data/vpn-monitor/analyze-logs.sh -l /data/vpn-monitor/logs/vpn-monitor.log

# Analyze logs for a specific date range
/data/vpn-monitor/analyze-logs.sh -d 2025-01-01:2025-01-31

# Output reports to custom directory
/data/vpn-monitor/analyze-logs.sh -o /tmp/reports -v
```

**Output Files:**

- **Text Report** (`reports/vpn-monitor-report.txt`): Human-readable summary with statistics and event timeline
- **CSV Export** (`reports/vpn-monitor-analysis.csv`): Detailed event data for spreadsheet analysis

**Report Contents:**

- **Summary Statistics**: Total failures, recoveries, failure frequency per day, recovery success rate
- **Tier Action Analysis**: Tier 1/2/3 action counts and success rates
- **Event Timeline**: Chronological list of failures, recoveries, and recovery actions
- **CSV Data**: All events exported with timestamps, peer IPs, failure counts, and event types

**Example Output:**

```
Summary:
  Total Failures: 15
  Total Recoveries: 12
  Recovery Success Rate: 80.00%
  Failures per Day: 2.14
  
Tier Actions:
  Tier 1 (Logging): 15
  Tier 2 (Surgical Cleanup):
    Attempted: 8
    Completed: 7
    Success Rate: 87.50%
  Tier 3 (Full Restart):
    Attempted: 3
    Completed: 3
    Success Rate: 100.00%
```

The CSV export can be imported into spreadsheet applications (Excel, Google Sheets, etc.) for further analysis, charting, and trend visualization.

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
- **Lockfile Format**: The lockfile uses `timestamp:pid` format (e.g., `1234567890:12345`)
  - **Format**: `<unix_timestamp>:<process_id>`
  - **Purpose**: Prevents concurrent script executions and detects hung processes
  - **Interpretation**: 
    - The timestamp indicates when the lockfile was created
    - The PID is the process ID of the running script instance
    - If the lockfile is older than `LOCKFILE_TIMEOUT` seconds, it's considered stale (hung process)
  - **Debugging**: 
    - View lockfile contents: `cat /data/vpn-monitor/vpn-monitor.lock`
    - Check if PID is still running: `ps -p <pid>` (replace `<pid>` with the PID from lockfile)
    - Calculate lockfile age: `echo $(($(date +%s) - $(stat -c %Y /data/vpn-monitor/vpn-monitor.lock)))` seconds
    - Remove stale lockfile manually if needed: `rm /data/vpn-monitor/vpn-monitor.lock` (only if PID is not running)
- Check logs: `tail /data/vpn-monitor/logs/vpn-monitor.log`

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

1. **⚠️ Tier 2 Recovery Impact - READ THIS**: 
   - **Without connection name configured (or auto-discovery fails)**: Tier 2 recovery uses `swanctl --reload` which reloads **ALL IPsec connections**, temporarily affecting **all Site-to-Site and remote user VPNs**. This is less "surgical" than intended.
   - **With connection name configured (or auto-discovered)**: Tier 2 recovery uses `swanctl --reload-conn <connection-name>` which reloads **only the specific failing connection**. This is true per-connection recovery with minimal impact.
   - **Recommendation**: Ensure connection names are available (auto-discovery is enabled by default) to minimize impact on other tunnels.
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

### Running Tests

```bash
# Run all tests
./tests/run_tests.sh

# Run tests with coverage reporting (requires kcov)
./tests/run_tests.sh --coverage

# Run specific test file
bats tests/test_install.sh
bats tests/test_uninstall.sh
bats tests/test_vpn_monitor.sh
bats tests/test_integration.sh
bats tests/test_high_risk.sh
```

**High-Risk Tests**: The project includes a dedicated high-risk test suite (`test_high_risk.sh`) with 31 tests covering critical paths, error handling, and edge cases. See [tests/HIGH_RISK_TESTS.md](tests/HIGH_RISK_TESTS.md) for details.

### Prerequisites

Install bats-core:
- macOS: `brew install bats-core`
- Linux: Install from source (see [bats-core documentation](https://github.com/bats-core/bats-core#installation))

Optional helper libraries (recommended):
```bash
./tests/install_bats_helpers.sh
```

**Coverage Reporting**: The test suite supports code coverage reporting using kcov. Run tests with `--coverage` flag to generate coverage reports. See [tests/README.md](tests/README.md) for detailed testing documentation and coverage reporting instructions.

## CI/CD

This project uses GitHub Actions for continuous integration and continuous deployment. The CI pipeline automatically runs on every push and pull request to the main/master branches.

### CI Pipeline

The CI pipeline includes:

1. **Linting**: Runs ShellCheck to detect shell script errors and security issues
2. **Format Checking**: Verifies code formatting using shfmt
3. **Testing**: Runs the full test suite using bats
4. **Coverage Reporting**: Generates test coverage reports using kcov

### Workflow Status

Check the [Actions](https://github.com/YOUR_USERNAME/udm-vpn-monitor/actions) tab to view the status of CI runs.

**Note:** Update the badge URL in the README header with your actual GitHub username/repository name to display the CI status badge correctly.

### Local CI Checks

Before pushing code, you can run the same checks locally:

```bash
# Format code
shfmt -w *.sh lib/*.sh tests/*.sh

# Check for errors
shellcheck --severity=error *.sh lib/*.sh tests/*.sh

# Run tests
./tests/run_tests.sh

# Run tests with coverage
./tests/run_tests.sh --coverage
```

See [DEVELOPER.md](DEVELOPER.md) for detailed development workflow instructions.

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
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System architecture, design decisions, and component interactions
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and release notes
- **[DEVELOPER.md](DEVELOPER.md)** - Developer guide with tooling setup, workflows, and code quality standards
- **[ENHANCEMENTS.md](ENHANCEMENTS.md)** - Future enhancement ideas and roadmap
- **[tests/README.md](tests/README.md)** - Comprehensive testing documentation

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a detailed history of changes and version information.

## Future Enhancements

See [ENHANCEMENTS.md](ENHANCEMENTS.md) for a comprehensive list of potential improvements and future development ideas.

## Acknowledgments

Designed based on real-world UDM VPN monitoring needs and UniFi OS 4.3+ constraints.

