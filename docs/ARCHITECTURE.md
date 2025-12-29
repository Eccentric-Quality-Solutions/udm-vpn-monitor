# Architecture Documentation

This document describes the architecture and design of the UDM VPN Monitor system.

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    UniFi Dream Machine (UDM)                    │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Cron Scheduler (every 1 min)                │  │
│  └────────────────────┬─────────────────────────────────────┘  │
│                       │                                         │
│                       ▼                                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              vpn-monitor.sh (Main Script)                 │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │  lib/lockfile.sh - Lockfile Protection            │  │  │
│  │  │  (flock or atomic file)                           │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                       │                                     │  │
│  │                       ▼                                     │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │  lib/config.sh - Configuration Loading            │  │  │
│  │  │  lib/config_schema.sh - Schema Validation        │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                       │                                     │  │
│  │                       ▼                                     │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │  lib/state.sh - State Initialization              │  │  │
│  │  │  lib/logging.sh - Logging Functions              │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                       │                                     │  │
│  │                       ▼                                     │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │  For Each Peer IP: monitor_peer()                  │  │  │
│  │  │  ┌──────────────────────────────────────────────┐ │  │  │
│  │  │  │  lib/detection.sh - VPN Status Check        │ │  │  │
│  │  │  └──────────────────────────────────────────────┘ │  │  │
│  │  │  ┌──────────────────────────────────────────────┐ │  │  │
│  │  │  │  lib/recovery.sh - Recovery Actions         │ │  │  │
│  │  │  └──────────────────────────────────────────────┘ │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Optional: VPN Keepalive Daemon                           │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │  vpn-keepalive.sh (systemd service)              │  │  │
│  │  │  Sends periodic ping traffic through VPN tunnels │  │  │
│  │  │  Prevents idle timeout, keeps tunnels alive     │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  State Files (/data/vpn-monitor/)                        │  │
│  │  • last_bytes_<peer_ip>                                  │  │
│  │  • cooldown_until                                        │  │
│  │  • vpn-monitor.lock                                      │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Log Files (/data/vpn-monitor/logs/)                     │  │
│  │  • vpn-monitor.log                                       │  │
│  │  • failure_counter_<peer_ip>  # Per-peer failure count │  │
│  │  • restart_count                                         │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Component Architecture

```mermaid
graph TB
    subgraph "UDM System"
        Cron[Cron Scheduler<br/>Every 1 minute]
        MainScript[vpn-monitor.sh<br/>Main Script]
        Config[vpn-monitor.conf<br/>Configuration]
        StateDir[State Directory<br/>/data/vpn-monitor/]
        LogDir[Log Files]
        Keepalive[vpn-keepalive.sh<br/>Optional Daemon]
    end
    
    subgraph "Library Modules"
        LockfileLib[lib/lockfile.sh<br/>Lockfile Management]
        ConfigLib[lib/config.sh<br/>Config Loading]
        SchemaLib[lib/config_schema.sh<br/>Schema Validation]
        StateLib[lib/state.sh<br/>State Management]
        LoggingLib[lib/logging.sh<br/>Logging Functions]
        DetectionLib[lib/detection.sh<br/>VPN Detection]
        RecoveryLib[lib/recovery.sh<br/>Recovery Actions]
        CommonLib[lib/common.sh<br/>Shared Utilities]
        ConstantsLib[lib/constants.sh<br/>Named Constants]
    end
    
    subgraph "Detection Layer"
        XfrmCheck[ip xfrm state<br/>SA & Byte Counters]
        IpsecCheck[ipsec status<br/>Fallback Check]
        PingCheck[ping check<br/>Connectivity Test]
    end
    
    subgraph "Recovery Layer"
        Tier1[Tier 1: Logging]
        Tier2[Tier 2: Surgical Cleanup<br/>xfrm recovery (default)<br/>ipsec reload (fallback)<br/>Per-Connection]
        Tier3[Tier 3: Full Restart<br/>xfrm recovery (default)<br/>ipsec restart (fallback)<br/>Per-Connection]
    end
    
    subgraph "Safety Mechanisms"
        Lockfile[Lockfile Protection]
        Cooldown[Cooldown Period]
        RateLimit[Rate Limiting]
        Validation[Input Validation]
    end
    
    Cron --> MainScript
    MainScript --> LockfileLib
    LockfileLib --> ConfigLib
    ConfigLib --> SchemaLib
    ConfigLib --> StateLib
    MainScript --> LoggingLib
    MainScript --> DetectionLib
    MainScript --> RecoveryLib
    MainScript --> CommonLib
    MainScript --> ConstantsLib
    
    DetectionLib --> XfrmCheck
    XfrmCheck -->|No SA| IpsecCheck
    XfrmCheck -->|SA Found| PingCheck
    PingCheck -->|Pass| Tier1
    XfrmCheck -->|Fail| Tier1
    
    RecoveryLib --> Tier1
    Tier1 -->|Threshold| Tier2
    Tier2 -->|Threshold| Tier3
    Tier3 --> Cooldown
    Tier2 --> RateLimit
    Tier3 --> RateLimit
    
    StateLib --> Cooldown
    StateLib --> RateLimit
    CommonLib --> Validation
    
    MainScript --> StateDir
    MainScript --> LogDir
    Keepalive -.->|Optional| XfrmCheck
```

## Execution Flow

```mermaid
flowchart TD
    Start([Cron Trigger]) --> LockCheck{Lockfile<br/>Available?}
    LockCheck -->|No| Exit1([Exit: Another<br/>instance running])
    LockCheck -->|Yes| AcquireLock[Acquire Lockfile]
    AcquireLock --> LoadConfig[Load Configuration]
    LoadConfig --> InitState[Initialize State Files]
    InitState --> CooldownCheck{In<br/>Cooldown?}
    CooldownCheck -->|Yes| Exit2([Exit: In<br/>cooldown period])
    CooldownCheck -->|No| ValidateConfig{EXTERNAL_PEER_IPS<br/>Configured?}
    ValidateConfig -->|No| Exit3([Exit: Config<br/>Error])
    ValidateConfig -->|Yes| NetworkPartitionCheck{Network<br/>Partition<br/>Check<br/>Enabled?}
    NetworkPartitionCheck -->|Yes| CheckPartition[Check Network<br/>Partition Status]
    NetworkPartitionCheck -->|No| ForEachPeer[For Each Peer IP]
    CheckPartition -->|Partitioned| Exit5([Exit: Network<br/>Partitioned<br/>Skip VPN Checks])
    CheckPartition -->|Healthy| ForEachPeer
    
    ForEachPeer --> ValidateIP{Valid<br/>IP Format?}
    ValidateIP -->|No| NextPeer[Next Peer]
    ValidateIP -->|Yes| CheckVPN[check_vpn_status]
    
    CheckVPN --> XfrmCheck{ip xfrm state<br/>SA Found?}
    XfrmCheck -->|Yes| ByteCheck{Bytes<br/>Increasing?}
    XfrmCheck -->|No| IpsecCheck{ipsec status<br/>Found?}
    
    ByteCheck -->|Yes| PingCheck{Enable<br/>Ping Check?}
    ByteCheck -->|No| VPNFail[VPN Failed]
    
    PingCheck -->|Yes| PingTest{ping<br/>Success?}
    PingCheck -->|No| VPNOK[VPN OK]
    PingTest -->|Yes| VPNOK
    PingTest -->|No| VPNFail
    
    IpsecCheck -->|Yes| VPNOK
    IpsecCheck -->|No| VPNFail
    
    VPNOK --> ResetCounter[Reset Failure Counter]
    VPNFail --> NetworkPartitionCheck2{Network<br/>Partitioned?}
    NetworkPartitionCheck2 -->|Yes| SkipRecovery[Skip Recovery<br/>Actions]
    NetworkPartitionCheck2 -->|No| IncrementCounter[Increment Failure Counter]
    
    SkipRecovery --> NextPeer
    IncrementCounter --> TierCheck{Failure<br/>Count?}
    TierCheck -->|>= TIER1| Tier1[Log Failure]
    TierCheck -->|>= TIER2| Tier2[Surgical Cleanup]
    TierCheck -->|>= TIER3| RateLimitCheck{Rate Limit<br/>OK?}
    
    Tier1 --> NextPeer
    Tier2 --> NextPeer
    
    RateLimitCheck -->|No| Exit4([Exit: Rate<br/>Limited])
    RateLimitCheck -->|Yes| Tier3[Full Restart]
    Tier3 --> RecordRestart[Record Restart]
    RecordRestart --> SetCooldown[Set Cooldown Period]
    
    ResetCounter --> NextPeer
    SetCooldown --> NextPeer
    Exit4 --> NextPeer
    
    NextPeer --> MorePeers{More<br/>Peers?}
    MorePeers -->|Yes| ForEachPeer
    MorePeers -->|No| ReleaseLock[Release Lockfile]
    ReleaseLock --> End([End])
    
    Exit1 --> End
    Exit2 --> End
    Exit3 --> End
    Exit5 --> End
```

**Note**: Network partition check (if enabled via `ENABLE_NETWORK_PARTITION_CHECK`) occurs before processing peer IPs. If network is partitioned, all VPN checks are skipped to avoid false positives and unnecessary recovery actions.

## Detection Method Flow

```mermaid
sequenceDiagram
    participant Script as vpn-monitor.sh
    participant Xfrm as ip xfrm state
    participant Ipsec as ipsec
    participant Ping as ping
    participant State as State Files
    
    Script->>Xfrm: Check SA for peer IP
    Xfrm-->>Script: SA exists + byte counters
    
    alt SA Found with Byte Counters
        Script->>State: Read last_bytes_<peer_ip>
        State-->>Script: Previous byte count
        Script->>Script: Compare bytes (increasing?)
        
        alt Bytes Increasing
            Script->>State: Update last_bytes_<peer_ip>
            Script->>Ping: Check connectivity (if enabled)
            Ping-->>Script: Success/Failure
            alt Ping Success
                Script->>Script: VPN OK
            else Ping Failed
                Script->>Script: VPN Suspect (log warning)
            end
        else Bytes Not Increasing
            Script->>Script: VPN Failed
        end
    else SA Found but No Byte Counters
        Script->>Script: VPN OK (assume working)
    else No SA Found
        Script->>Ipsec: Fallback: Check status
        Ipsec-->>Script: Connection found/not found
        alt Ipsec Found
            Script->>Script: VPN OK
        else Ipsec Not Found
            Script->>Script: VPN Failed
        end
    end
```

### Ping Check Behavior

The ping check provides additional connectivity verification beyond SA state checks. It's important to understand how ping failures interact with SA state:

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

**Design Rationale**:
The ping check is designed as a **supplementary diagnostic tool**, not a hard failure condition. The primary detection method (SA state + byte counters) remains the authoritative source for tunnel health. Ping checks provide early warning of connectivity issues while allowing the more reliable byte counter method to confirm actual traffic flow problems before triggering recovery actions.

If validation fails (based on SA state and byte counters), it escalates through recovery tiers. The ping check helps distinguish between "tunnel exists but broken" and "tunnel exists and working but idle".

## Recovery Tier Flow

```mermaid
stateDiagram-v2
    [*] --> Monitoring: Start
    Monitoring --> Tier1: Failure Count >= TIER1_THRESHOLD
    Monitoring --> [*]: VPN OK
    
    Tier1 --> Tier2: Failure Count >= TIER2_THRESHOLD
    Tier1 --> Monitoring: Continue Monitoring
    
    Tier2 --> Tier3: Failure Count >= TIER3_THRESHOLD
    Tier2 --> Monitoring: After Cleanup
    
    state Tier1 {
        [*] --> LogFailure
        LogFailure --> [*]
    }
    
    state Tier2 {
        [*] --> CheckXfrm{Xfrm Recovery<br/>Enabled?}
        CheckXfrm -->|Yes| AttemptXfrm[xfrm recovery<br/>Per-Connection<br/>Default]
        CheckXfrm -->|No| ReloadIpsec[ipsec reload<br/>All Connections<br/>Fallback]
        AttemptXfrm -->|Success| [*]
        AttemptXfrm -->|Failure| ReloadIpsec
        ReloadIpsec --> [*]
    }
    
    state Tier3 {
        [*] --> CheckRateLimit
        CheckRateLimit --> RateLimited: Limit Exceeded
        CheckRateLimit --> CheckXfrm3: Within Limit
        CheckXfrm3 --> AttemptXfrm3: Xfrm Enabled
        CheckXfrm3 --> RestartIpsec: Xfrm Disabled
        AttemptXfrm3 --> RestartIpsec: Failure
        AttemptXfrm3 --> SetCooldown: Success
        RestartIpsec --> SetCooldown
        SetCooldown --> [*]
        RateLimited --> [*]
    }
    
    Tier3 --> Cooldown: After Restart
    Cooldown --> Monitoring: Cooldown Expired
    
    Monitoring --> SkipRecovery: Network Partitioned
    SkipRecovery --> Monitoring: Continue Monitoring
```

**Note**: Network partition check also occurs after VPN check fails. If network is partitioned when a VPN failure is detected, recovery actions are skipped to avoid unnecessary disruption. Network partition state is checked before incrementing failure counters and triggering recovery tiers.

## Data Flow

```mermaid
graph LR
    subgraph "Input"
        ConfigFile[Config File<br/>EXTERNAL_PEER_IPS, INTERNAL_PEER_IPS, thresholds]
        XfrmState[System State<br/>ip xfrm state]
    end
    
    subgraph "Processing"
        Validation[Input Validation]
        Detection[VPN Detection]
        Decision[Recovery Decision]
    end
    
    subgraph "State Storage"
        FailureCounter[failure_counter_<peer_ip>]
        ByteFiles[last_bytes_*]
        RestartLog[restart_count]
        CooldownFile[cooldown_until]
    end
    
    subgraph "Output"
        LogFile[vpn-monitor.log]
        Actions[Recovery Actions]
    end
    
    ConfigFile --> Validation
    XfrmState --> Detection
    Validation --> Detection
    Detection --> Decision
    Decision --> FailureCounter
    Decision --> ByteFiles
    Decision --> RestartLog
    Decision --> CooldownFile
    Decision --> LogFile
    Decision --> Actions
    FailureCounter --> Decision
    ByteFiles --> Detection
    RestartLog --> Decision
    CooldownFile --> Decision
```

## State Management

The system uses file-based state management to track VPN health, failure counts, recovery actions, and system state across execution cycles. All state is persisted in `/data/vpn-monitor/` to survive reboots.

### State Files Overview

State files are organized into two categories:

**Per-Peer State Files** (tracked independently for each VPN peer):
- `logs/failure_counter_<peer_ip>`: Consecutive failure count per peer (sanitized IP in filename)
- `last_bytes_<peer_ip>`: Last known byte counter value per peer (sanitized IP in filename)

**System-Wide State Files** (shared across all peers):
- `cooldown_until`: Cooldown expiration timestamp (prevents immediate re-restarts)
- `logs/restart_count`: Unix timestamps of Tier 3 recovery actions (one timestamp per line, for rate limiting) - see [Rate Limiting](#rate-limiting-logsrestart_count) section below for details
- `network_partition_state`: Network partition status (0 = healthy, 1 = partitioned) - used to detect network connectivity issues that affect all peers
- `vpn-monitor.lock`: Lockfile for execution control (format: `timestamp:pid` for timeout detection)
- `.cron_checked`: Flag file to prevent repeated cron persistence checks

### Per-Peer State Tracking

The monitor tracks state independently for each configured peer IP, enabling independent monitoring and recovery actions for multiple VPN tunnels. This is essential when monitoring multiple Site-to-Site VPN connections, as failures in one tunnel should not affect the monitoring or recovery of other tunnels.

**File Naming Convention**:
All per-peer state files use sanitized peer IP addresses in their filenames. Dots and colons are replaced with underscores (e.g., `192.168.1.1` becomes `192_168_1_1`, `2001:db8::1` becomes `2001_db8__1`). This ensures safe filenames while maintaining uniqueness per peer.

**Per-Peer State Files**:

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

**Benefits of Per-Peer Tracking**:
- **Independent Recovery**: Each tunnel can be recovered independently based on its own failure count
- **Accurate Detection**: Byte counter tracking per peer ensures accurate detection of traffic flow issues for each tunnel
- **Multi-Tunnel Support**: Enables monitoring of multiple VPN peers without interference between them
- **Granular Logging**: Failure counters and recovery actions are tracked per peer, making troubleshooting easier

**Example Scenario**:
If monitoring three VPN peers (`203.0.113.1`, `198.51.100.1`, `192.0.2.1`), the monitor creates separate state files:
- `logs/failure_counter_203_0_113_1` - tracks failures for first peer
- `logs/failure_counter_198_51_100_1` - tracks failures for second peer  
- `logs/failure_counter_192_0_2_1` - tracks failures for third peer
- `last_bytes_203_0_113_1` - tracks byte counters for first peer
- `last_bytes_198_51_100_1` - tracks byte counters for second peer
- `last_bytes_192_0_2_1` - tracks byte counters for third peer

Each peer's monitoring and recovery actions operate completely independently.

### System-Wide State Files

**Cooldown Period** (`cooldown_until`):
- **Purpose**: Prevents immediate re-restarts after a recovery action
- **Mechanism**: After Tier 3 recovery (full restart), a cooldown period is set
- **Duration**: Configurable via `COOLDOWN_MINUTES` (default: 15 minutes)
- **Behavior**: During cooldown, monitoring continues but recovery actions are skipped

**Rate Limiting** (`logs/restart_count`):
- **Purpose**: Prevents restart loops if VPN has persistent issues
- **Mechanism**: Tracks Unix timestamps (one per line) of Tier 3 recovery actions only
  - Records full IPsec restarts (`ipsec restart`) that affect all tunnels
  - Also records successful xfrm-based per-connection recovery (when enabled)
  - Does NOT record Tier 1 (logging) or Tier 2 (surgical cleanup) actions
  - Automatically cleans up entries older than 24 hours
- **Limit**: Configurable via `MAX_RESTARTS_PER_HOUR` (default: 3 restarts per hour)
- **Behavior**: If limit exceeded, Tier 3 recovery actions are skipped until rate limit window expires

**Network Partition State** (`network_partition_state`):
- **Purpose**: Tracks network connectivity status to distinguish VPN failures from network partition issues
- **Mechanism**: Stores a single integer value (0 = healthy, 1 = partitioned)
- **Usage**: Used by recovery logic to avoid unnecessary VPN recovery actions when network connectivity is down
- **Detection**: Network partition check uses DNS queries to external servers (configurable via `NETWORK_PARTITION_DNS_SERVER`, `NETWORK_PARTITION_DNS_HOSTNAME`)
- **Behavior**: When network is partitioned, recovery actions are skipped to avoid unnecessary disruption
- **Configuration**: Controlled via `ENABLE_NETWORK_PARTITION_CHECK` (default: 1, enabled)

**Lockfile** (`vpn-monitor.lock`):
- **Purpose**: Prevents concurrent script execution
- **Format**: `timestamp:pid` for timeout detection
- **Mechanism**: Uses `flock` (preferred) or atomic file creation (fallback)
- **Timeout**: Configurable via `LOCKFILE_TIMEOUT` (default: 300 seconds)
- **Behavior**: Stale lockfiles from hung processes are automatically detected and cleaned up

### State File Operations

All state file operations use atomic patterns to prevent corruption and race conditions:

**Atomic Writes**:
- Write-tmp-move pattern: Write to temporary file, then atomically move to final location
- Ensures state files are never partially written

**Checksum Validation**:
- State files include checksums for corruption detection
- Corrupted files are detected and handled gracefully

**Per-Peer Isolation**:
- Each peer's state files are completely independent
- Operations on one peer's state files don't affect other peers

For implementation details, see the [`lib/state.sh`](#libstatesh) module documentation below.

## File Structure

```
/data/vpn-monitor/
├── vpn-monitor.sh              # Main monitoring script
├── vpn-monitor.conf            # Configuration file
├── vpn-monitor.lock            # Lockfile (timestamp:pid format)
│
├── lib/                        # Library modules
│   ├── common.sh               # Shared utilities (logging, validation, helpers)
│   ├── config.sh               # Configuration loading and management
│   ├── config_schema.sh        # Configuration schema definitions and validation
│   ├── constants.sh            # Named constants for magic numbers
│   ├── detection.sh             # VPN status detection (xfrm, ipsec, ping)
│   ├── lockfile.sh             # Lockfile management (flock/atomic)
│   ├── logging.sh               # Centralized logging functionality
│   ├── recovery.sh              # Tiered recovery actions
│   └── state.sh                # State file management (counters, cooldown, rate limiting)
│
├── logs/                       # Logs directory
│   ├── vpn-monitor.log         # Main log file
│   ├── failure_counter_<peer_ip>  # Per-peer failure count (sanitized IP in filename)
│   └── restart_count           # Unix timestamps of Tier 3 recovery actions (one per line)
│
├── State Files:
├── cooldown_until              # Cooldown expiration timestamp
├── network_partition_state     # Network partition status (0=healthy, 1=partitioned)
├── last_bytes_192_168_1_1     # Per-peer byte counters
├── last_bytes_192_168_2_1     # (sanitized IP in filename)
└── .cron_checked              # Flag file for cron check
```

## Modular Library Architecture

The system uses a modular library architecture where functionality is organized into dedicated modules in the `lib/` directory. This design provides:

- **Separation of Concerns**: Each module has a single, well-defined responsibility
- **Code Reusability**: Shared functions can be used across multiple scripts
- **Maintainability**: Changes to one module don't affect others
- **Testability**: Each module can be tested independently

### Library Modules

#### `lib/common.sh`
**Purpose**: Shared utility functions used across installation, uninstallation, and monitoring scripts.

**Key Functions**:
- `get_formatted_timestamp()` - Consistent date/time formatting
- `ensure_directory_exists()` - Centralized directory creation
- `check_command_available()` - Check if command is available (returns error code)
- `file_exists_and_readable()` - Check file existence and readability
- `directory_exists()` / `directory_writable()` - Directory checks
- `atomic_write_file()` - Atomic file write operations
- `sanitize_peer_ip()` - IP address sanitization for filenames
- `safe_set_variable()` - Safe variable assignment (prevents code injection)
- `validate_ip_address()` - Robust IP address validation (IPv4/IPv6)
- `get_file_mtime()` - Cross-platform file modification time
- `is_process_running()` - Process existence checking
- `log_info()`, `log_warn()`, `log_error()` - Colored console logging

**Used By**: `vpn-monitor.sh`, `install.sh`, `uninstall.sh`

#### `lib/config.sh`
**Purpose**: Configuration file loading, validation, and management.

**Key Functions**:
- `load_config()` - Loads and validates configuration from `vpn-monitor.conf`
- `recalculate_log_paths()` - Updates log paths after config changes
- `validate_config()` - Validates configuration against schema

**Dependencies**: `lib/config_schema.sh`, `lib/logging.sh`, `lib/common.sh`

#### `lib/config_schema.sh`
**Purpose**: Defines configuration schema, validation rules, and default values.

**Key Features**:
- Schema definitions for all configuration variables
- Type checking (string, integer, boolean)
- Range validation for numeric values
- Default value application
- Single source of truth for configuration defaults

**Used By**: `lib/config.sh`

#### `lib/constants.sh`
**Purpose**: Named constants for magic numbers used throughout the codebase.

**Key Constants**:
- Timeout values
- Retry counts
- File size limits
- Default thresholds

**Benefit**: Eliminates magic numbers, improves readability and maintainability

#### `lib/detection.sh`
**Purpose**: VPN status detection using multiple methods with automatic fallback.

**Key Functions**:
- `check_vpn_status()` - Main detection function
- `check_xfrm_state()` - Checks Security Associations via `ip xfrm state`
- `check_ipsec_status()` - Fallback detection via `ipsec status`
- `check_ping_connectivity()` - Optional ping-based connectivity verification

**Dependencies**: `lib/logging.sh`, `lib/common.sh`, `lib/state.sh`

**Note**: See Design Decision #5 for detection strategy details.

#### `lib/lockfile.sh`
**Purpose**: Lockfile management to prevent concurrent script execution.

**Key Functions**:
- `acquire_lockfile()` - Acquires lockfile using `flock` (preferred) or atomic file creation (fallback)
- `release_lockfile()` - Releases lockfile on script exit
- `check_stale_lockfile()` - Detects and handles stale lockfiles from hung processes

**Dependencies**: `lib/logging.sh`, `lib/common.sh`

**Note**: See Design Decision #2 for implementation details.

#### `lib/logging.sh`
**Purpose**: Centralized logging functionality with timestamp and level support.

**Key Functions**:
- `log_message()` - Main logging function with level and timestamp
- `get_formatted_timestamp()` - Consistent timestamp formatting
- Log level support: INFO, WARN, ERROR, DEBUG

**Features**:
- Automatic timestamp prefix
- Log level filtering
- File and console output support

**Used By**: All modules for consistent logging

#### `lib/recovery.sh`
**Purpose**: Tiered recovery actions (logging → surgical cleanup → full restart).

**Key Functions**:
- `surgical_cleanup()` - Tier 2 recovery (per-connection xfrm recovery or ipsec reload)
- `full_restart()` - Tier 3 recovery (per-connection xfrm recovery or ipsec restart)
- `attempt_xfrm_recovery()` - Per-connection xfrm state recovery
- `reload_ipsec()` - Reload all IPsec connections
- `restart_ipsec()` - Full IPsec restart

**Dependencies**: `lib/logging.sh`, `lib/state.sh`, `lib/common.sh`, `lib/detection.sh`

**Note**: See Design Decision #3 and Recovery Tier Flow diagram for recovery strategy details.

#### `lib/state.sh`
**Purpose**: State file management for failure counters, cooldown periods, and rate limiting.

**Key Functions**:
- `increment_failure_counter()` - Increments per-peer failure counter
- `reset_failure_counter()` - Resets per-peer failure counter
- `get_failure_count()` - Retrieves current failure count
- `check_cooldown()` - Checks if system is in cooldown period
- `set_cooldown()` - Sets cooldown period after restart
- `check_rate_limit()` - Validates restart rate limiting
- `record_restart()` - Records restart timestamp
- `update_byte_counter()` - Updates per-peer byte counter
- `get_last_byte_count()` - Retrieves last byte count

**Features**:
- Atomic file operations (write-tmp-move pattern)
- Checksum validation for corruption detection
- Per-peer state isolation

**Dependencies**: `lib/logging.sh`, `lib/common.sh`

**Note**: See File Structure section and Design Decision #4 for state file details.

## VPN Keepalive Daemon

The system includes an optional VPN keepalive daemon (`vpn-keepalive.sh`) that runs as a systemd service. This daemon helps prevent false positives by keeping VPN tunnels active.

> **For user-facing documentation** including configuration, management commands, and usage instructions, see the [Keepalive Daemon section in README.md](README.md#keepalive-daemon).

**Purpose**: Sends periodic ping traffic through VPN tunnels to prevent idle timeout and maintain tunnel activity.

**Architecture**: 
- Service file: `vpn-keepalive.service` (systemd unit)
- Script: `vpn-keepalive.sh` (daemon implementation)
- Configuration: Uses same `vpn-monitor.conf` configuration
- Operation: Runs continuously, sends pings at configured intervals

**Integration**: Optional component that works alongside the main monitoring script. Can be enabled/disabled separately via systemd.

**Note**: See Design Decision #10 for additional details.

## Component Interactions

```mermaid
graph TB
    subgraph "External Commands"
        IP[ip xfrm state]
        Ipsec[ipsec]
        PingCmd[ping/ping6]
    end
    
    subgraph "Main Script"
        MainScript[vpn-monitor.sh]
        MonitorPeer[monitor_peer]
    end
    
    subgraph "Library Modules"
        DetectionLib[lib/detection.sh<br/>check_vpn_status]
        RecoveryLib[lib/recovery.sh<br/>surgical_cleanup<br/>full_restart]
        StateLib[lib/state.sh<br/>check_rate_limit<br/>check_cooldown]
        LockfileLib[lib/lockfile.sh<br/>acquire_lockfile]
        ConfigLib[lib/config.sh<br/>load_config]
        LoggingLib[lib/logging.sh<br/>log_message]
        CommonLib[lib/common.sh<br/>validate_ip_address<br/>get_formatted_timestamp]
    end
    
    MainScript --> LockfileLib
    MainScript --> ConfigLib
    MainScript --> StateLib
    MainScript --> LoggingLib
    MainScript --> MonitorPeer
    
    MonitorPeer --> DetectionLib
    MonitorPeer --> RecoveryLib
    MonitorPeer --> StateLib
    
    DetectionLib --> IP
    DetectionLib --> Ipsec
    DetectionLib --> PingCmd
    DetectionLib --> CommonLib
    
    RecoveryLib -->|Tier 2| IP
    RecoveryLib -->|Tier 2| Ipsec
    RecoveryLib -->|Tier 3| Ipsec
    RecoveryLib --> StateLib
    RecoveryLib --> LoggingLib
    
    StateLib --> LoggingLib
    CommonLib --> LoggingLib
```

## Key Design Decisions

### 1. Cron-Based Execution
- **Why**: More resilient than long-running daemons on UDM
- **Trade-off**: Less frequent checks (5 min vs continuous)
- **Benefit**: Survives system restarts, simpler error handling

### 2. Lockfile Protection
- **Why**: Prevent multiple instances from running simultaneously
- **Implementation**: `flock` (preferred) or atomic file creation (fallback)
- **Enhancement**: Timeout detection for hung processes

### 3. Tiered Recovery
- **Why**: Gradual escalation prevents unnecessary disruption
- **Tiers**: Log → Cleanup → Restart
- **Tier 2 Details**: 
  - Default: xfrm-based per-connection recovery (uses `ip xfrm state delete`) if `ENABLE_XFRM_RECOVERY=1` (enabled by default for UDM OS 4.3+) - affects only the failing tunnel
  - Fallback: Falls back to `ipsec reload` (affects all connections) if xfrm recovery fails or is disabled
- **Tier 3 Details**: 
  - Default: xfrm-based per-connection recovery attempted first if `ENABLE_XFRM_RECOVERY=1` (enabled by default for UDM OS 4.3+) - affects only the failing tunnel
  - Fallback: Falls back to `ipsec restart` (affects all tunnels) if xfrm recovery fails or is disabled
- **Benefit**: Most issues resolved without full restart. Per-connection recovery is enabled by default, providing surgical recovery that affects only the failing tunnel.

### 4. Per-Peer State Tracking
- **Why**: Multiple peers need independent monitoring and recovery
- **Implementation**: Separate state files per peer (sanitized IP)
  - Per-peer failure counters: `failure_counter_<peer_ip>`
  - Per-peer byte counters: `last_bytes_<peer_ip>`
- **Benefit**: Accurate detection and independent recovery for multi-peer setups
- **Note**: Both failure counters and byte counters are tracked per-peer, allowing independent failure tracking and recovery actions

### 5. Multi-Method Detection with Fallback
- **Why**: Robust detection across different UDM configurations
- **Implementation**: 
  - Primary: `ip xfrm state` (SA state and byte counters)
  - Fallback: `ipsec status` (if xfrm unavailable)
  - Optional: Ping checks verify end-to-end connectivity
- **Benefit**: Works across different UDM configurations, distinguishes "idle" from "broken"

### 6. Modular Library Architecture
- **Why**: Reduce code duplication, improve maintainability, enable code reuse
- **Implementation**: Complete modularization with dedicated library modules in `lib/` directory
- **Benefits**: 
  - Single responsibility per module
  - Code reuse across scripts (install, uninstall, monitor)
  - Easier testing and maintenance
  - Reduced main script from ~1900 lines to ~530 lines
  - Better separation of concerns
- **Note**: See "Modular Library Architecture" section above for detailed module documentation

### 7. Comprehensive In-Code Documentation
- **Why**: Improve code readability and maintainability
- **Implementation**: All functions include detailed documentation blocks with:
  - Function purpose and behavior description
  - Parameter descriptions with types
  - Return value documentation
  - Side effects documentation (file operations, logging, etc.)
  - Usage examples for complex functions
  - Notes about dependencies and requirements
- **Benefit**: Easier onboarding for new developers, better code understanding, reduced need for external documentation

### 8. Rate Limiting
- **Why**: Prevent restart loops if VPN has persistent issues
- **Implementation**: Track restart timestamps, limit per hour
- **Benefit**: Protects system from excessive restarts

### 9. Cooldown Period
- **Why**: Allow VPN to stabilize after restart
- **Implementation**: Skip checks for configured minutes after restart
- **Benefit**: Prevents false positives immediately after recovery

### 10. VPN Keepalive Daemon (Optional)
- **Why**: Prevent idle VPN tunnels from triggering false positives
- **Implementation**: Optional systemd service (`vpn-keepalive.service`) that sends periodic ping traffic through VPN tunnels
- **Benefits**: 
  - Maintains tunnel activity to prevent idle timeouts
  - Ensures byte counters continue incrementing
  - Reduces false positive detections for idle VPNs
- **Note**: See "VPN Keepalive Daemon" section above for architecture and integration details

## Error Handling Strategy

1. **Fail-Safe Defaults**: Script exits gracefully on errors
2. **Logging**: All errors logged with context via centralized logging module
3. **Fallbacks**: 
   - Detection: Multiple methods with automatic fallback (see Design Decision #5)
   - Recovery: Tiered recovery with fallback strategies (see Design Decision #3)
4. **Validation**: Input validation prevents injection attacks (see Security Considerations)
5. **State Recovery**: Stale lockfiles automatically cleaned up (see Design Decision #2)
6. **Graceful Degradation**: If preferred tool unavailable, falls back to alternative without failing

## Performance Considerations

- **Execution Time**: Typically < 30 seconds per run
- **Resource Usage**: Minimal (bash script, no daemon)
- **State File Size**: Small (few KB per peer)
- **Log Rotation**: Automatic via logrotate configuration (installed during setup)
- **Modular Architecture**: Reduced main script complexity improves performance and maintainability (see Design Decision #6)
- **Library Loading**: Library modules are sourced once at startup, minimal overhead

## Security Considerations

- **Input Validation**: Peer IPs validated before use via `validate_ip_address()` function (see `lib/common.sh`)
- **Fixed-String Matching**: Uses `grep -F` for IP matching to prevent regex injection
- **File Permissions**: State files readable/writable by script only (should be enhanced with explicit `chmod`)
- **No External Network**: Only local system commands (except ping)
- **Config Sourcing**: Configuration validated against schema before use (see `lib/config_schema.sh`)
- **Atomic Operations**: Lockfile and state file operations use atomic patterns to prevent race conditions (see Design Decision #2)
- **Command Injection Prevention**: Peer IPs validated and sanitized before use in shell commands
- **Modular Security**: Security-sensitive operations isolated in dedicated modules for easier auditing (see Design Decision #6)

