# UDM VPN Monitor

[![CI](https://github.com/eccentric-quality-solutions/udm-vpn-monitor/workflows/CI/badge.svg)](https://github.com/eccentric-quality-solutions/udm-vpn-monitor/actions)

## Overview

This tool monitors Site-to-Site VPN connections on UniFi Dream Machines (UDM/UDM-Pro/UDM-SE) and automatically attempts recovery when VPN tunnels appear active but are non-functional. It uses IPsec xfrm state byte counters combined with optional ping connectivity checks to detect actual traffic flow and verify end-to-end connectivity, which is more reliable than checking IKE status alone.

## Quick Start

- See [QUICK_START.md](QUICK_START.md) for a 5-minute setup guide.
- See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common problems and solutions.
- See [DEVELOPER.md](DEVELOPER.md) for development setup and [ARCHITECTURE.md](docs/ARCHITECTURE.md) for architecture and design details.

## Recovery Behavior

- **Detection**: Uses `ip xfrm state` (primary) → `ipsec status` (fallback). For detailed detection flow, see [ARCHITECTURE.md](docs/ARCHITECTURE.md#detection-method-flow)
- **Tier 2 Recovery**: 
  - **Default**: xfrm-based per-connection recovery (enabled by default, `ENABLE_XFRM_RECOVERY=1`) - affects only the failing tunnel
  - **Fallback**: `ipsec reload` (affects **all connections**) if xfrm recovery fails or is disabled
- **Tier 3 Recovery**: 
  - **Default**: xfrm-based per-connection recovery (enabled by default, `ENABLE_XFRM_RECOVERY=1`) - affects only the failing tunnel
  - **Fallback**: `ipsec restart` (affects **all tunnels**) if xfrm recovery fails or is disabled

For detailed recovery tier flow diagrams and technical implementation, see the [Recovery Tier Flow section in ARCHITECTURE.md](docs/ARCHITECTURE.md#recovery-tier-flow).

## Features

- **Robust Detection**: Uses `ip xfrm state` byte counters to detect actual VPN traffic flow
- **Connectivity Verification**: Optional ping checks verify end-to-end tunnel connectivity
- **Network Partition Detection**: Automatically detects when local network connectivity is down and skips VPN checks until connectivity is restored
- **Resource Monitoring**: Monitors CPU, RAM, and disk space usage and throttles execution when resources are constrained to prevent system overload
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
- ✅ Per-tunnel precise recovery by default (Tier 2 and Tier 3 use xfrm-based per-connection recovery, affecting only the failing tunnel)

## What This Is NOT

- ❌ A fully reliable daemon (best-effort)
- ❌ Upgrade-proof (may require re-installation after UniFi OS upgrades)
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
   
   If using `INTERNAL_PEER_IPS` for ping checks, also set `LOCAL_UDM_IP` to your local UDM's internal IP address:
   ```bash
   LOCAL_UDM_IP="192.168.1.1"
   ```
   The installer will attempt to auto-detect this from the br0 interface if not configured.
   
   **Important**: Use the external/public IP address that the VPN tunnel is established with, not the internal/private IP address. The script checks IPsec Security Associations (SAs) which are identified by external IP addresses. If `INTERNAL_PEER_IPS` is not set, ping checks will use `EXTERNAL_PEER_IPS` instead.

5. **Monitor logs**:
   ```bash
   tail -f /data/vpn-monitor/logs/vpn-monitor.log
   ```

## Configuration

Edit `/data/vpn-monitor/vpn-monitor.conf` to customize behavior:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `EXTERNAL_PEER_IPS` | Space-separated list of remote VPN endpoint **external/public** IPs | (required) |
| `INTERNAL_PEER_IPS` | Space-separated list of remote VPN endpoint **internal/private** IPs (for ping checks, optional) | "" |
| `LOCAL_UDM_IP` | Local UDM internal IP address (required when `ENABLE_PING_CHECK=1` and `INTERNAL_PEER_IPS` is set). Used as source IP for ping checks. The script automatically adds this IP to br0 if needed. | "" |
| `VPN_NAME` | VPN identifier for logging | "Site-to-Site VPN" |
| `TIER1_THRESHOLD` | Failures before logging starts | 1 |
| `TIER2_THRESHOLD` | Failures before surgical cleanup | 3 |
| `TIER3_THRESHOLD` | Failures before full restart | 5 |
| `COOLDOWN_MINUTES` | Minutes to wait after restart | 15 |
| `MAX_RESTARTS_PER_HOUR` | Maximum restarts per hour | 3 |
| `CRON_SCHEDULE` | Cron schedule for check frequency (cron format) | "*/1 * * * *" |
| `LOCKFILE_TIMEOUT` | Lockfile timeout in seconds (detects hung processes) | 300 |
| `ENABLE_PING_CHECK` | Enable ping connectivity verification (0 or 1) | 1 |
| `PING_COUNT` | Number of ping packets to send | 3 |
| `PING_TIMEOUT` | Ping timeout per packet (seconds) | 2 |
| `ENABLE_KEEPALIVE` | Enable VPN keepalive daemon (0 or 1, see [Keepalive Daemon](#keepalive-daemon)) | 1 |
| `KEEPALIVE_INTERVAL` | Keepalive ping interval (seconds, 10-300) | 30 |
| `KEEPALIVE_PING_COUNT` | Number of ping packets per keepalive ping (1-5) | 1 |
| `DEBUG` | Enable verbose logging (0 or 1) | 0 |
| `ENABLE_XFRM_RECOVERY` | Enable xfrm-based per-connection recovery (0 or 1, enabled by default for UDM OS 4.3+) | 1 |
| `ENABLE_NETWORK_PARTITION_CHECK` | Enable network partition detection (0 or 1). When enabled, checks default route, DNS resolution, and interface state before VPN checks. If network is partitioned, VPN checks are skipped. | 1 |
| `NETWORK_PARTITION_DNS_SERVER` | DNS server to query for network partition detection | "8.8.8.8" |
| `NETWORK_PARTITION_DNS_HOSTNAME` | Hostname to resolve for network partition detection | "google.com" |
| `NETWORK_PARTITION_DNS_TIMEOUT` | DNS query timeout in seconds (1-10) | 2 |
| `NETWORK_PARTITION_INTERFACES` | Comma-separated list of interfaces to check (e.g., "br0,eth0") | "br0,eth0" |
| `ENABLE_RESOURCE_MONITORING` | Enable resource monitoring (CPU, RAM, disk space) and throttling (0 or 1) | 1 |
| `RESOURCE_CPU_THRESHOLD` | CPU usage threshold percentage (50-100). Script throttles if CPU is at or above this threshold for RESOURCE_CPU_DURATION seconds. | 90 |
| `RESOURCE_CPU_DURATION` | CPU constraint duration in seconds (10-600). CPU must be at threshold or above for this duration before throttling. | 60 |
| `RESOURCE_RAM_THRESHOLD` | RAM usage threshold percentage (50-100). Script throttles if RAM is at or above this threshold for RESOURCE_RAM_DURATION seconds. | 90 |
| `RESOURCE_RAM_DURATION` | RAM constraint duration in seconds (10-600). RAM must be at threshold or above for this duration before throttling. | 60 |
| `RESOURCE_DISK_WARNING_THRESHOLD` | Disk space warning threshold (percentage free, 5-50). Script logs a warning when free disk space drops below this threshold. | 20 |
| `RESOURCE_DISK_CRITICAL_THRESHOLD` | Disk space critical threshold (percentage free, 1-20). Script throttles execution and takes action (e.g., rotates logs) when free disk space drops below this threshold. | 10 |
| `STATUS_LOG_INTERVAL_SECONDS` | How often to log periodic status updates for healthy VPN peers (seconds, 0-3600). Set to 0 to disable periodic status logging. Ensures monitoring activity is visible in logs even when VPNs are healthy. | 300 |
| `RECOVERY_VERIFY_TIMEOUT` | Maximum time to wait for recovery verification after xfrm-based recovery actions (seconds, 10-300). The script verifies that the VPN tunnel has recovered after performing recovery actions. | 30 |


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

For technical architecture details, systemd integration, and design decisions, see the [VPN Keepalive Daemon section in ARCHITECTURE.md](docs/ARCHITECTURE.md#vpn-keepalive-daemon).

### Resource Monitoring

The resource monitoring feature monitors CPU, RAM, and disk space usage to prevent the VPN monitor from overloading the UDM system. When resources are constrained, the script throttles execution by exiting early, allowing the system to recover.

**How It Works:**

- **CPU Monitoring**: Checks CPU usage percentage. If CPU usage is at or above `RESOURCE_CPU_THRESHOLD` (default: 90%) for `RESOURCE_CPU_DURATION` (default: 60 seconds), the script exits early to reduce load.
- **RAM Monitoring**: Checks RAM usage percentage. If RAM usage is at or above `RESOURCE_RAM_THRESHOLD` (default: 90%) for `RESOURCE_RAM_DURATION` (default: 60 seconds), the script exits early to reduce memory pressure.
- **Disk Space Monitoring**: 
  - Logs a warning when free disk space drops below `RESOURCE_DISK_WARNING_THRESHOLD` (default: 20% free)
  - At `RESOURCE_DISK_CRITICAL_THRESHOLD` (default: 10% free), the script:
    - Rotates log files if they exceed 10MB
    - Removes old rotated log files (.old files)
    - Throttles execution by exiting early if disk space remains critical

**Configuration:**

Resource monitoring is enabled by default (`ENABLE_RESOURCE_MONITORING=1`). To disable:

```bash
ENABLE_RESOURCE_MONITORING=0
```

**Example Log Output:**

```
[2025-01-15 10:00:00] WARNING: CPU usage has been at 90%+ (currently 95%) for 60s - throttling execution
[2025-01-15 10:00:00] INFO: Script exiting: system resources constrained
```

```
[2025-01-15 10:00:00] WARNING: Free disk space is low: 18% free on /dev/mapper/udm-data
[2025-01-15 10:00:00] WARNING: Free disk space is critical: 8% free on /dev/mapper/udm-data
[2025-01-15 10:00:00] WARNING: Log file is large (15360KB), rotating to free disk space
[2025-01-15 10:00:00] INFO: Log file rotated: /data/vpn-monitor/logs/vpn-monitor.log -> /data/vpn-monitor/logs/vpn-monitor.log.old
[2025-01-15 10:00:00] INFO: Removed 3 old log file(s) to free disk space
```

**When to Adjust Thresholds:**

- **Lower CPU/RAM thresholds** (e.g., 80%) if your UDM is frequently under heavy load
- **Increase durations** (e.g., 120 seconds) if you want to allow brief resource spikes without throttling
- **Adjust disk thresholds** based on your available disk space and log rotation needs

**Note:** Resource monitoring adds approximately 1 second to script execution time (for CPU usage calculation). This is acceptable since the script runs via cron (default: every 1 minute).

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
- State files are created per peer (e.g., `failure_counter_203_0_113_1`, `last_bytes_198_51_100_1`)

**Example Log Output:**
```
[2025-01-15 10:00:00] INFO: VPN check for 203.0.113.1: OK
[2025-01-15 10:00:00] INFO: VPN check for 198.51.100.1: OK
[2025-01-15 10:00:00] WARNING: VPN check for 192.0.2.1: FAILED (tunnel down)
```

**Recovery Behavior:**
Recovery actions are per-peer (each peer has independent failure tracking). See the [Important: Recovery Behavior](#-important-recovery-behavior) section above for details on Tier 2 and Tier 3 recovery actions. For detailed recovery tier flow diagrams and technical implementation, see the [Recovery Tier Flow section in ARCHITECTURE.md](docs/ARCHITECTURE.md#recovery-tier-flow).

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

For detailed diagnosis steps and solutions for false positives, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## How It Works

The monitor uses a multi-layered approach to verify VPN tunnel health and automatically recover from failures.

**Detection**: Uses `ip xfrm state` (primary) → `ipsec status` (fallback). Optional ping checks verify end-to-end connectivity.

**Recovery**: Three-tier escalation system (see [Important: Recovery Behavior](#-important-recovery-behavior) section above for details).

**Safety**: Lockfile protection, cooldown periods, rate limiting, and per-peer failure tracking prevent restart loops and ensure safe operation.

For detailed architecture information including detection flow diagrams, recovery tier details, failure type detection, ping check behavior, state management, and technical implementation, see [ARCHITECTURE.md](docs/ARCHITECTURE.md). For design decisions behind these choices, see [Architecture Decision Records](docs/adr/README.md).

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

# Show version
/data/vpn-monitor/vpn-monitor.sh --version
```

For testing without affecting production VPNs (fake mode), see the [Testing without Affecting Production VPNs](#testing-without-affecting-production-vpns) section above.

For detailed troubleshooting, log analysis patterns, and diagnostic commands, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).


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

The monitor uses a multi-method detection approach with automatic fallback:

**Primary Method**: `ip xfrm state` checks for Security Associations (SAs) and validates byte counters are increasing, indicating active traffic flow.

**Fallback Method**: If xfrm checks fail, falls back to `ipsec status` to verify connection state.

**Optional Verification**: When enabled (`ENABLE_PING_CHECK=1`), ping checks provide additional connectivity verification. Ping failures are logged as warnings but don't override SA state checks - the primary detection method (SA state + byte counters) remains authoritative.

**Key Behaviors**:
- SA existence and byte counter validation determine tunnel health
- Ping checks provide early warning of connectivity issues without triggering false positives
- Detection distinguishes between "idle but healthy" and "broken" tunnels

For detailed detection flow diagrams, sequence diagrams, ping check behavior scenarios, and technical implementation details, see the [Detection Method Flow section in ARCHITECTURE.md](docs/ARCHITECTURE.md#detection-method-flow).

### State Management

For detailed state management documentation including file structure, atomic operations, checksum validation, per-peer isolation, and technical implementation details, see the [State Management section in ARCHITECTURE.md](docs/ARCHITECTURE.md#state-management).

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

For development setup, including installation of development tools (ShellCheck, shfmt, bats, kcov), see [DEVELOPER.md](DEVELOPER.md).

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

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed architecture diagrams, component interactions, and design decisions.

## Documentation

- **[README.md](README.md)** - This file: User-facing documentation, installation, and usage
- **[QUICK_START.md](QUICK_START.md)** - 5-minute setup guide for new users
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - System architecture, design decisions, and component interactions
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and release notes
- **[DEVELOPER.md](DEVELOPER.md)** - Developer guide with tooling setup, workflows, and code quality standards
- **[TODO.md](TODO.md)** - Planned features and improvements
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

See [TODO.md](TODO.md) for a comprehensive list of potential improvements and future development ideas.


