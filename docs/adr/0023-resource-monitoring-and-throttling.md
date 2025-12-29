# ADR-0023: Resource Monitoring and Throttling

## Status
Accepted

## Context
The UDM VPN Monitor runs periodically via cron and performs various system operations (VPN checks, recovery actions, logging). On resource-constrained UDM systems, the monitor could potentially:

- Overload the system if CPU is already pegged at 100%
- Cause memory pressure if RAM is already high
- Fill up disk space with log files, potentially causing system issues
- Make system problems worse by continuing to run when resources are constrained

Without resource monitoring:
- The monitor could continue running even when the system is under heavy load
- Log files could grow unbounded and fill disk space
- The monitor could contribute to system resource exhaustion
- No visibility into resource constraints affecting monitor execution

## Decision
We will implement resource monitoring that:

1. **Monitors CPU, RAM, and Disk Space**: Tracks resource usage and detects when resources are constrained
2. **Throttles Execution**: Exits early when resources have been constrained for a sustained period (CPU/RAM) or are critically low (disk space)
3. **Manages Log Files**: Automatically rotates and cleans up log files when disk space is low
4. **Tracks State Over Time**: Uses state files to remember when resources first became constrained (for CPU/RAM duration tracking)
5. **Provides Warnings**: Logs warnings when resources are low but not yet critical

## Consequences

### Positive
- **Prevents System Overload**: Throttles execution when CPU/RAM are pegged, preventing the monitor from adding to system load
- **Prevents Disk Space Issues**: Automatically manages log files to prevent disk space exhaustion
- **Self-Healing**: Automatically cleans up log files when disk space is critical
- **Configurable**: All thresholds and durations are configurable via configuration file
- **Graceful Degradation**: Falls back gracefully if monitoring commands are unavailable
- **State Tracking**: Tracks resource constraint state over time to detect sustained pressure (not just momentary spikes)
- **Early Warning**: Logs warnings before resources become critical

### Negative
- **Execution Delay**: CPU usage calculation adds ~1 second to script execution (acceptable for cron-based execution)
- **Additional State Files**: Creates state files for tracking resource constraint state
- **Complexity**: Adds new module and configuration options
- **Potential False Throttling**: Could throttle execution during legitimate system load spikes (mitigated by duration-based tracking)

## Implementation Details

### Resource Monitoring Module
- **Location**: `lib/resources.sh`
- **Functions**:
  - `get_cpu_usage()` - Calculates CPU usage percentage using `/proc/stat` sampling
  - `get_memory_usage()` - Calculates RAM usage percentage using `free` command
  - `get_free_disk_space()` - Calculates free disk space percentage using `df` command
  - `check_resource_constrained()` - Tracks resource constraint state over time
  - `check_system_resources()` - Main function that checks all resources and implements throttling
  - `manage_log_files_on_low_disk()` - Rotates and cleans up log files when disk space is low

### Configuration Options
- `ENABLE_RESOURCE_MONITORING` (default: 1) - Enable/disable resource monitoring
- `RESOURCE_CPU_THRESHOLD` (default: 90) - CPU usage threshold percentage (50-100)
- `RESOURCE_CPU_DURATION` (default: 60) - CPU constraint duration in seconds (10-600)
- `RESOURCE_RAM_THRESHOLD` (default: 90) - RAM usage threshold percentage (50-100)
- `RESOURCE_RAM_DURATION` (default: 60) - RAM constraint duration in seconds (10-600)
- `RESOURCE_DISK_WARNING_THRESHOLD` (default: 20) - Disk space warning threshold (% free, 5-50)
- `RESOURCE_DISK_CRITICAL_THRESHOLD` (default: 10) - Disk space critical threshold (% free, 1-20)

### State Files
- `resource_cpu_constrained` - Timestamp when CPU first became constrained
- `resource_ram_constrained` - Timestamp when RAM first became constrained
- `resource_disk_warning_logged` - Marker that disk warning has been logged (prevents log spam)

### Integration
- Resource checks are performed early in `validate_monitor_state()` function
- Runs before network partition check and cooldown check
- Exits gracefully (exit code 0) when resources are constrained

### Log File Management
- Rotates log files when they exceed 10MB
- Removes old rotated log files (`.old` files) when disk space is critical (< 10% free)
- Uses atomic file operations for state file writes

## Related ADRs
- ADR-0001: Cron-Based Execution Instead of Daemon
- ADR-0008: Rate Limiting and Cooldown Periods
- ADR-0012: Atomic File Operations
- ADR-0015: File-Based State Storage
- ADR-0018: Centralized Logging Module

## References
- README.md: "Resource Monitoring" section
- lib/resources.sh: Implementation details
- vpn-monitor.conf: Configuration options documentation
