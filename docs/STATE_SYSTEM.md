# State System Documentation

This document provides a comprehensive overview of all state managed throughout the UDM VPN Monitor application. State is organized into several categories based on persistence, scope, and purpose.

## Table of Contents

1. [State Categories](#state-categories)
2. [Persistent File-Based State](#persistent-file-based-state)
3. [Runtime State Variables](#runtime-state-variables)
4. [Configuration State](#configuration-state)
5. [Execution Control State](#execution-control-state)
6. [State Management Patterns](#state-management-patterns)
7. [State File Locations](#state-file-locations)
8. [State Initialization](#state-initialization)
9. [State Validation and Recovery](#state-validation-and-recovery)

## State Categories

State in the application falls into four main categories:

1. **Persistent File-Based State**: State that survives reboots and script restarts, stored in files
2. **Runtime State Variables**: Temporary state passed between functions during a single execution
3. **Configuration State**: Loaded from configuration files and environment variables
4. **Execution Control State**: Lockfiles and PID files for preventing concurrent execution

## Persistent File-Based State

All persistent state is stored in `${STATE_DIR}` (defaults to `${SCRIPT_DIR}/state`, typically `/data/vpn-monitor/state/` when installed). State files use atomic write operations (write-tmp-move pattern) to prevent corruption.

### Per-Location, Per-Peer State Files

These files track state for a specific location and peer IP combination. Format: `<key>_<sanitized_location>_<sanitized_peer_ip>`

#### 1. Failure Counter (`failure_counter_<location>_<peer_ip>`)

- **Purpose**: Tracks consecutive failure count for each location independently
- **Format**: Integer (0 or positive number)
- **Creation**: Created on-demand when a location first fails
- **Usage**: Determines which recovery tier to trigger (Tier 1, 2, or 3)
- **Independence**: Each location has its own counter tracked independently
- **Reset**: Counter resets to 0 when VPN check succeeds for that location
- **Example**: `failure_counter_NYC_203_0_113_1` contains `3` if NYC location has failed 3 times consecutively

#### 2. Last Bytes (`last_bytes_<location>_<peer_ip>`)

- **Purpose**: Stores the last known byte counter value from `ip xfrm state` for each location
- **Format**: Integer (byte count)
- **Creation**: Created on-demand when byte counters are first read for a location
- **Usage**: Used to detect if byte counters are increasing (indicating active traffic flow)
- **Independence**: Each location has its own byte counter file
- **Update**: Updated each time a successful check reads increasing byte counters
- **Example**: `last_bytes_NYC_203_0_113_1` contains `12345678` (last known byte count)

#### 3. Failure Type (`failure_type_<location>_<peer_ip>`)

- **Purpose**: Tracks the type of failure for diagnostic purposes
- **Format**: String (e.g., "tunnel_down", "routing_issue")
- **Creation**: Created on-demand when failure type is determined during VPN check failure
- **Usage**: Provides detailed failure information in logs
- **Independence**: Each location has its own failure type file
- **Clear**: Automatically cleared (deleted) when VPN recovers after failures
- **Example**: `failure_type_NYC_203_0_113_1` contains `tunnel_down`

#### 4. SPI (Security Parameter Index) (`spi_<location>_<peer_ip>`)

- **Purpose**: Stores the SPI value extracted from `ip xfrm state` output
- **Format**: Hex (0x12345678) or decimal (12345678)
- **Creation**: Created on-demand when SPI is first extracted from xfrm state
- **Usage**: Detects SA (Security Association) rekeys - when SPI changes, byte counters may have been reset
- **Independence**: Each location has its own SPI file
- **Update**: Updated when SPI is read from xfrm state
- **Example**: `spi_NYC_203_0_113_1` contains `0x12345678`

#### 5. Idle Detection (`idle_detected_<location>_<peer_ip>`)

- **Purpose**: Tracks when a tunnel is detected as idle (bytes not increasing but tunnel is healthy)
- **Format**: Integer (0 or 1)
- **Creation**: Created on-demand when idle state is detected
- **Usage**: Set to "1" when tunnel is idle but healthy (SA exists, bytes not increasing, but ping check succeeds)
- **Independence**: Each location has its own idle detection state
- **Clear**: Automatically cleared when traffic resumes or SA rekeys
- **Example**: `idle_detected_NYC_203_0_113_1` contains `1` if tunnel is idle

#### 6. Last Status Log (`last_status_log_<location>_<peer_ip>`)

- **Purpose**: Stores the Unix timestamp of the last periodic "VPN OK" status log entry
- **Format**: Integer (Unix timestamp)
- **Creation**: Created on-demand when first periodic status log is written
- **Usage**: Throttles periodic status logging - prevents log spam by only logging "VPN OK" messages at configured intervals
- **Independence**: Each location has its own last status log timestamp
- **Update**: Updated each time a periodic status log entry is written
- **Example**: `last_status_log_NYC_203_0_113_1` contains `1703616000` (timestamp)

#### 7. Recovery Method (`recovery_method_<location>_<peer_ip>`)

- **Purpose**: Tracks which recovery method was used when recovery was attempted
- **Format**: String (e.g., "xfrm", "ipsec_reload", "ipsec_restart")
- **Creation**: Created on-demand when a recovery action is attempted (Tier 2 or Tier 3)
- **Usage**: Included in "VPN restored" log messages for visibility
- **Independence**: Each location has its own recovery method tracking
- **Update**: Updated when recovery is attempted, cleared after VPN restoration is logged
- **Values**:
  - `"xfrm"`: xfrm-based per-connection recovery
  - `"ipsec_reload"`: ipsec reload recovery
  - `"ipsec_restart"`: ipsec restart recovery
- **Example**: `recovery_method_NYC_203_0_113_1` contains `xfrm`

### Per-Peer State Files (No Location)

These files track state per peer IP only, without location context. Format: `<key>_<sanitized_peer_ip>`

#### 1. Connection Name (`connection_name_<peer_ip>`)

- **Purpose**: Caches IPsec connection name discovered from `ipsec status` output
- **Format**: String (connection name)
- **Creation**: Created on-demand when connection name is first discovered
- **Usage**: Enhanced logging to show connection names in log messages
- **Scope**: Per-peer only (no location context)
- **Example**: `connection_name_203_0_113_1` contains `"NYC-VPN"`

### Global State Files

These files track system-wide state shared across all peers and locations.

#### 1. Restart Count (`restart_count`)

- **Purpose**: Tracks Tier 3 recovery action timestamps for rate limiting
- **Format**: One Unix timestamp per line (timestamp list)
- **Creation**: Created during state initialization
- **Usage**: Rate limiting prevents restart loops by limiting how frequently Tier 3 recovery actions can occur
- **Update**: New timestamp appended when Tier 3 recovery is executed
- **Cleanup**: Old entries (older than 24 hours) are automatically cleaned up
- **Example**: Contains multiple timestamps, one per line:
  ```
  1703616000
  1703616300
  1703616600
  ```

#### 2. Network Partition State (`network_partition_state`)

- **Purpose**: Tracks network partition status (affects all peers)
- **Format**: Integer (0 = healthy, 1 = partitioned)
- **Creation**: Created during state initialization (defaults to 0)
- **Usage**: Detects network connectivity issues that affect all peers
- **Update**: Set to 1 when network partition is detected, 0 when network is healthy
- **Example**: Contains `1` if network is partitioned

#### 3. Network Partition Statistics

These files track statistics for network partition checks (hourly summaries):

- **`network_partition_dns_success_count`**: DNS resolution check success counter
- **`network_partition_dns_fail_count`**: DNS resolution check failure counter
- **`network_partition_route_success_count`**: Default route check success counter
- **`network_partition_route_fail_count`**: Default route check failure counter
- **`network_partition_interface_success_count`**: Interface state check success counter
- **`network_partition_interface_fail_count`**: Interface state check failure counter
- **`network_partition_summary_last_time`**: Timestamp of last hourly statistics summary

**Format**: Integer (counter values), Unix timestamp (for last_time)
**Usage**: Hourly summary logging of network partition check statistics
**Reset**: Counters reset to 0 after hourly summary is logged

#### 4. Resource Monitoring Statistics

These files track statistics for resource monitoring checks (hourly summaries):

- **`resource_cpu_check_success_count`**: CPU check success counter
- **`resource_cpu_check_fail_count`**: CPU check failure counter
- **`resource_ram_check_success_count`**: RAM check success counter
- **`resource_ram_check_fail_count`**: RAM check failure counter
- **`resource_disk_check_success_count`**: Disk check success counter
- **`resource_disk_check_fail_count`**: Disk check failure counter
- **`resource_cpu_constrained_count`**: CPU constrained event counter
- **`resource_ram_constrained_count`**: RAM constrained event counter
- **`resource_disk_critical_count`**: Disk critical event counter
- **`resource_monitoring_summary_last_time`**: Timestamp of last resource monitoring summary

**Format**: Integer (counter values), Unix timestamp (for last_time)
**Usage**: Hourly summary logging of resource monitoring statistics
**Reset**: Counters reset to 0 after hourly summary is logged

#### 5. System-Wide Failure State (`system_wide_failure_state`)

- **Purpose**: Tracks system-wide failure state (affects all peers)
- **Format**: Integer (0 = no failure, 1 = system-wide failure detected)
- **Creation**: Created during state initialization (defaults to 0)
- **Usage**: Coordinates recovery actions across multiple locations during system-wide failures
- **Update**: Set to 1 when system-wide failure is detected, 0 when resolved
- **Example**: Contains `1` if system-wide failure is detected

## Runtime State Variables

These are temporary variables passed between functions during a single script execution. They are not persisted to disk.

### 1. `primary_check_passed`

- **Type**: Integer (0 or 1)
- **Purpose**: Indicates whether the VPN check passed
- **Meaning**:
  - `1`: VPN check passed (either xfrm check passed OR ipsec fallback passed)
  - `0`: VPN check failed (both xfrm check AND ipsec fallback failed)
- **Invariant**: If `primary_check_passed=1`, then SA MUST exist (fundamental invariant)
- **Usage**: Passed through detection pipeline to downstream functions
- **Scope**: Per-execution (not persisted)

### 2. `sa_exists`

- **Type**: Integer (0 or 1)
- **Purpose**: Indicates whether Security Association (SA) exists
- **Meaning**:
  - `1`: SA exists (detected via xfrm or ipsec)
  - `0`: SA does not exist (or couldn't be detected)
- **Relationship**: If `primary_check_passed=1`, then `sa_exists` MUST be 1 (invariant)
- **Usage**: Passed through detection pipeline to avoid duplicate SA checks
- **Scope**: Per-execution (not persisted)
- **Note**: This variable may be eliminated in future refactoring (see STATE_SYSTEM_ANALYSIS.md)

### 3. `xfrm_output`

- **Type**: String
- **Purpose**: Caches `ip xfrm state` output to avoid duplicate system calls
- **Usage**: Passed to downstream functions that need xfrm state information
- **Scope**: Per-execution (not persisted)
- **Benefit**: Reduces system calls by reusing xfrm output

## Configuration State

Configuration state is loaded from configuration files and environment variables. This state is read-only during execution and determines application behavior.

### Configuration Variables

Configuration is loaded from:
- Configuration file: `${CONFIG_FILE}` (defaults to `vpn-monitor.conf`)
- Environment variables (override config file values)

Key configuration variables include:
- `STATE_DIR`: Directory for state files
- `LOGS_DIR`: Directory for log files
- `LOCKFILE`: Path to lockfile
- `RESTART_COUNT_FILE`: Path to restart count file
- `MAX_RESTARTS_PER_WINDOW`: Maximum restarts allowed in time window
- `RATE_LIMIT_WINDOW_MINUTES`: Time window for rate limiting
- `MIN_RESTART_INTERVAL_SECONDS`: Minimum interval between restarts
- `STATUS_LOG_INTERVAL_SECONDS`: Interval for periodic status logging
- Location-specific variables: `LOCATION_<NAME>_EXTERNAL`, `LOCATION_<NAME>_INTERNAL`
- And many more (see `lib/config/config_defaults.sh`)

**Note**: Configuration state is separate from persistent state files. Configuration determines behavior, while persistent state tracks runtime history.

## Execution Control State

These files control script execution and prevent concurrent runs.

### 1. Lockfile (`vpn-monitor.lock`)

- **Path**: `${STATE_DIR}/vpn-monitor.lock`
- **Purpose**: Prevents concurrent script execution
- **Format**: `timestamp:pid` (e.g., `1703616000:12345`)
- **Mechanism**: Uses file locking (`flock`) and atomic creation
- **Staleness Detection**: Lockfiles older than `LOCKFILE_TIMEOUT` seconds are considered stale and removed
- **Usage**: Acquired at script start, released at script end
- **Example**: Contains `1703616000:12345` (timestamp:process_id)

### 2. PID File (`vpn-keepalive.pid`)

- **Path**: `${STATE_DIR}/vpn-keepalive.pid`
- **Purpose**: Tracks PID of keepalive daemon process
- **Format**: Integer (process ID)
- **Usage**: Used by keepalive daemon to track its own process ID
- **Example**: Contains `12345` (process ID)

### 3. Cron Check Flag (`.cron_checked`)

- **Path**: `${STATE_DIR}/.cron_checked`
- **Purpose**: Flag file to prevent repeated cron persistence checks
- **Format**: Empty file (existence indicates check was performed)
- **Usage**: Prevents redundant cron persistence verification

## State Management Patterns

### Atomic File Operations

All state file writes use atomic operations (write-tmp-move pattern) to prevent corruption:

1. Write to temporary file (`$file.tmp`)
2. Verify write succeeded
3. Atomically move temp file to final location (`mv $file.tmp $file`)

This ensures:
- Files are never partially written
- No race conditions during concurrent access
- Safe recovery from crashes

### State File Abstraction Layer

The application uses an abstraction layer for state file operations:

- **`get_peer_state_file_path()`**: Generates state file paths with proper sanitization
- **`get_peer_state()`**: Unified getter for per-peer state values
- **`set_peer_state()`**: Unified setter for per-peer state values with atomic writes
- **`delete_peer_state()`**: Removes per-peer state files

**Benefits**:
- Consistent path generation and sanitization
- Centralized validation and error handling
- Atomic write operations
- Easy to extend with new state keys

### State Passing Pattern

Runtime state variables are passed explicitly between functions to:
- Avoid duplicate system calls (e.g., `ip xfrm state`)
- Ensure consistent state across function calls
- Make data dependencies explicit

**Pattern**:
- Source function performs system check and exposes state via output variable
- Downstream functions receive state as explicit parameters
- Functions maintain backward compatibility with optional parameters

See `docs/adr/0028-state-passing-pattern-for-detection-functions.md` for details.

## State File Locations

### Default Locations

- **State Directory**: `${SCRIPT_DIR}/state` (defaults to `/data/vpn-monitor/state/` when installed)
- **Logs Directory**: `${SCRIPT_DIR}/logs` (defaults to `/data/vpn-monitor/logs/` when installed)

### Path Resolution

Paths are relative to script location (`${SCRIPT_DIR}/`) to survive reboots and allow dev mode operation. When installed to `/data/vpn-monitor`, paths resolve to:
- State files: `/data/vpn-monitor/state/`
- Log files: `/data/vpn-monitor/logs/`

### Customization

State and log directories can be customized via configuration:
- `STATE_DIR`: Override state directory
- `LOGS_DIR`: Override logs directory

## State Initialization

State initialization occurs at script startup via `init_state()` function:

1. **Directory Creation**: Ensures `STATE_DIR` and `LOGS_DIR` exist
2. **Global State Files**: Creates required global state files:
   - `restart_count` (empty file, timestamps added on-demand)
   - `network_partition_state` (defaults to 0)
   - `system_wide_failure_state` (defaults to 0)
3. **Per-Peer Files**: Created on-demand when first accessed

**Note**: Per-peer state files are created automatically when first needed (e.g., when a failure occurs or byte counters are read).

## State Validation and Recovery

### State File Validation

State files are validated for:
- **Readability**: Files must be readable before access
- **Format**: Values must match expected format (integer, timestamp, string, etc.)
- **Corruption**: Corrupted files are automatically recovered

### Corruption Recovery

When corruption is detected:

1. **Backup**: Corrupted file is backed up to `${file}.corrupted.<timestamp>`
2. **Recovery**: File is reset to safe default value
3. **Logging**: Recovery action is logged for analysis

### Validation Functions

- **`validate_state_file()`**: Validates individual state file format
- **`validate_state_files_by_pattern()`**: Validates all files matching a pattern
- **`validate_state()`**: Validates all state files at startup

### Recovery Functions

- **`backup_corrupted_state_file()`**: Creates backup of corrupted file
- **`recover_corrupted_state_file()`**: Recovers corrupted file to default value

## State File Naming Conventions

### Sanitization

- **Location Names**: Invalid characters replaced with underscores, max 64 chars
- **IP Addresses**: Dots and colons replaced with underscores
  - Example: `192.168.1.1` → `192_168_1_1`
  - Example: `2001:db8::1` → `2001_db8__1`

### File Naming Patterns

- **Per-Location, Per-Peer**: `<key>_<location>_<peer_ip>`
- **Per-Peer Only**: `<key>_<peer_ip>`
- **Global**: `<key>` (no location or peer)

### Examples

- `failure_counter_NYC_203_0_113_1` (per-location, per-peer)
- `connection_name_203_0_113_1` (per-peer only)
- `restart_count` (global)

## State Scope and Independence

### Per-Location Independence

Each location's state is tracked independently:
- Failure counters are separate per location
- Recovery actions are independent per location
- State files are isolated per location

**Example**: If NYC location fails 3 times and DC location fails 2 times:
- `failure_counter_NYC_203_0_113_1` = 3
- `failure_counter_DC_198_51_100_1` = 2
- These are tracked completely independently

### Global State

Some state is shared across all locations:
- Restart count (rate limiting affects all locations)
- Network partition state (affects all locations)
- System-wide failure state (affects all locations)

## State Lifecycle

### Creation

- **Global State Files**: Created during `init_state()` at script startup
- **Per-Peer State Files**: Created on-demand when first accessed
- **Runtime Variables**: Created during function execution

### Updates

- **Failure Counters**: Incremented on failure, reset on success
- **Byte Counters**: Updated when byte counters are read
- **SPI**: Updated when SPI is extracted from xfrm state
- **Recovery Method**: Updated when recovery is attempted
- **Statistics**: Incremented on each check, reset after hourly summary

### Cleanup

- **Failure Type**: Cleared when VPN recovers
- **Recovery Method**: Cleared after restoration is logged
- **Idle Detection**: Cleared when traffic resumes or SA rekeys
- **Restart Count**: Old entries (24+ hours) cleaned up automatically
- **Statistics**: Reset to 0 after hourly summary

## Related Documentation

- **`STATE_SYSTEM_ANALYSIS.md`**: Analysis of runtime state variables (`primary_check_passed`, `sa_exists`)
- **`docs/ARCHITECTURE.md`**: Architecture overview including state management section
- **`docs/adr/0015-file-based-state-storage.md`**: Decision to use file-based state storage
- **`docs/adr/0016-state-file-location-data-vpn-monitor.md`**: Decision on state file location
- **`docs/adr/0012-atomic-file-operations.md`**: Decision on atomic file operations
- **`docs/adr/0028-state-passing-pattern-for-detection-functions.md`**: Pattern for passing runtime state
- **`docs/CODE_PATTERNS.md`**: Code patterns including state management patterns

## Summary

The UDM VPN Monitor application manages state across multiple dimensions:

1. **Persistence**: Persistent file-based state survives reboots, runtime variables exist only during execution
2. **Scope**: Per-location/per-peer state is independent, global state is shared
3. **Purpose**: Failure tracking, recovery coordination, rate limiting, statistics, execution control
4. **Management**: Atomic operations, abstraction layer, validation, and recovery mechanisms ensure reliability

All state is managed through consistent patterns and abstractions, ensuring reliability, maintainability, and correctness.
