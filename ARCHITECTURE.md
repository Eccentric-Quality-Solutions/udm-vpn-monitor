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
│  │  │  Lockfile Protection (flock or atomic file)        │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                       │                                     │  │
│  │                       ▼                                     │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │  Configuration Loading (vpn-monitor.conf)          │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                       │                                     │  │
│  │                       ▼                                     │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │  State Initialization & Cooldown Check            │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                       │                                     │  │
│  │                       ▼                                     │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │  For Each Peer IP: monitor_peer()                  │  │  │
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
│  │  • cron.log                                             │  │
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
    end
    
    subgraph "Detection Layer"
        XfrmCheck[ip xfrm state<br/>SA & Byte Counters]
        SwanctlCheck[swanctl --list-sas<br/>Fallback Check]
        IpsecCheck[ipsec status<br/>Fallback Check]
        PingCheck[ping check<br/>Connectivity Test]
    end
    
    subgraph "Recovery Layer"
        Tier1[Tier 1: Logging]
        Tier2[Tier 2: Surgical Cleanup<br/>SA Deletion + Reload<br/>Per-Connection or All Tunnels]
        Tier3[Tier 3: Full Restart<br/>ipsec restart<br/>Affects All Tunnels]
    end
    
    subgraph "Safety Mechanisms"
        Lockfile[Lockfile Protection]
        Cooldown[Cooldown Period]
        RateLimit[Rate Limiting]
        Validation[Input Validation]
    end
    
    Cron --> MainScript
    MainScript --> Lockfile
    Lockfile --> Config
    Config --> StateDir
    MainScript --> XfrmCheck
    XfrmCheck -->|No SA| SwanctlCheck
    SwanctlCheck -->|No SA| IpsecCheck
    XfrmCheck -->|SA Found| PingCheck
    PingCheck -->|Pass| Tier1
    XfrmCheck -->|Fail| Tier1
    Tier1 -->|Threshold| Tier2
    Tier2 -->|Threshold| Tier3
    Tier3 --> Cooldown
    Tier2 --> RateLimit
    Tier3 --> RateLimit
    MainScript --> LogDir
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
    CooldownCheck -->|No| ValidateConfig{PEER_IPS<br/>Configured?}
    ValidateConfig -->|No| Exit3([Exit: Config<br/>Error])
    ValidateConfig -->|Yes| ForEachPeer[For Each Peer IP]
    
    ForEachPeer --> ValidateIP{Valid<br/>IP Format?}
    ValidateIP -->|No| NextPeer[Next Peer]
    ValidateIP -->|Yes| CheckVPN[check_vpn_status]
    
    CheckVPN --> XfrmCheck{ip xfrm state<br/>SA Found?}
    XfrmCheck -->|Yes| ByteCheck{Bytes<br/>Increasing?}
    XfrmCheck -->|No| SwanctlCheck{swanctl<br/>SA Found?}
    
    ByteCheck -->|Yes| PingCheck{Enable<br/>Ping Check?}
    ByteCheck -->|No| VPNFail[VPN Failed]
    
    PingCheck -->|Yes| PingTest{ping<br/>Success?}
    PingCheck -->|No| VPNOK[VPN OK]
    PingTest -->|Yes| VPNOK
    PingTest -->|No| VPNFail
    
    SwanctlCheck -->|Yes| VPNOK
    SwanctlCheck -->|No| IpsecCheck{ipsec status<br/>Found?}
    IpsecCheck -->|Yes| VPNOK
    IpsecCheck -->|No| VPNFail
    
    VPNOK --> ResetCounter[Reset Failure Counter]
    VPNFail --> IncrementCounter[Increment Failure Counter]
    
    IncrementCounter --> TierCheck{Failure<br/>Count?}
    TierCheck -->|>= TIER1| Tier1[Log Failure]
    TierCheck -->|>= TIER2| Tier2[Surgical Cleanup]
    TierCheck -->|>= TIER3| Tier3[Full Restart]
    
    Tier1 --> RateLimitCheck{Rate Limit<br/>OK?}
    Tier2 --> RateLimitCheck
    Tier3 --> RateLimitCheck
    
    RateLimitCheck -->|No| Exit4([Exit: Rate<br/>Limited])
    RateLimitCheck -->|Yes| RecordRestart[Record Restart]
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
```

## Detection Method Flow

```mermaid
sequenceDiagram
    participant Script as vpn-monitor.sh
    participant Xfrm as ip xfrm state
    participant Swanctl as swanctl
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
        Script->>Swanctl: Fallback: Check SA
        Swanctl-->>Script: SA found/not found
        alt Swanctl Found SA
            Script->>Script: VPN OK
        else Swanctl No SA
            Script->>Ipsec: Fallback: Check status
            Ipsec-->>Script: Connection found/not found
            alt Ipsec Found
                Script->>Script: VPN OK
            else Ipsec Not Found
                Script->>Script: VPN Failed
            end
        end
    end
```

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
        [*] --> DeleteSA
        DeleteSA --> ReloadSwanctl
        ReloadSwanctl --> [*]
    }
    
    state Tier3 {
        [*] --> CheckRateLimit
        CheckRateLimit --> RateLimited: Limit Exceeded
        CheckRateLimit --> RecordRestart: Within Limit
        RecordRestart --> RestartIpsec
        RestartIpsec --> SetCooldown
        SetCooldown --> [*]
        RateLimited --> [*]
    }
    
    Tier3 --> Cooldown: After Restart
    Cooldown --> Monitoring: Cooldown Expired
```

## Data Flow

```mermaid
graph LR
    subgraph "Input"
        ConfigFile[Config File<br/>PEER_IPS, thresholds]
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

## File Structure

```
/data/vpn-monitor/
├── vpn-monitor.sh              # Main monitoring script
├── vpn-monitor.conf            # Configuration file
├── vpn-monitor.lock            # Lockfile (timestamp:pid format)
│
├── logs/                       # Logs directory
│   ├── vpn-monitor.log         # Main log file
│   ├── failure_counter_<peer_ip>  # Per-peer failure count (sanitized IP in filename)
│   └── restart_count           # Timestamps of all restarts
│
├── State Files:
├── last_restart                # Last restart timestamp
├── cooldown_until              # Cooldown expiration timestamp
├── last_bytes_192_168_1_1     # Per-peer byte counters
├── last_bytes_192_168_2_1     # (sanitized IP in filename)
└── .cron_checked              # Flag file for cron check
```

## Component Interactions

```mermaid
graph TB
    subgraph "External Commands"
        IP[ip xfrm state]
        Swanctl[swanctl]
        Ipsec[ipsec]
        PingCmd[ping/ping6]
    end
    
    subgraph "Script Functions"
        CheckVPN[check_vpn_status]
        MonitorPeer[monitor_peer]
        SurgicalCleanup[surgical_cleanup]
        FullRestart[full_restart]
    end
    
    subgraph "Safety Functions"
        RateLimit[check_rate_limit]
        Cooldown[check_cooldown]
        Lockfile[Lockfile Management]
    end
    
    MonitorPeer --> CheckVPN
    CheckVPN --> IP
    CheckVPN --> Swanctl
    CheckVPN --> Ipsec
    CheckVPN --> PingCmd
    
    MonitorPeer -->|Tier 2| SurgicalCleanup
    MonitorPeer -->|Tier 3| FullRestart
    
    SurgicalCleanup --> IP
    SurgicalCleanup --> Swanctl
    
    FullRestart --> Ipsec
    FullRestart --> Swanctl
    FullRestart --> RateLimit
    FullRestart --> Cooldown
    
    MonitorPeer --> RateLimit
    MonitorPeer --> Cooldown
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
- **Benefit**: Most issues resolved without full restart

### 4. Per-Peer State Tracking
- **Why**: Multiple peers need independent monitoring and recovery
- **Implementation**: Separate state files per peer (sanitized IP)
  - Per-peer failure counters: `failure_counter_<peer_ip>`
  - Per-peer byte counters: `last_bytes_<peer_ip>`
- **Benefit**: Accurate detection and independent recovery for multi-peer setups
- **Note**: Both failure counters and byte counters are tracked per-peer, allowing independent failure tracking and recovery actions

### 5. Dual Detection Method
- **Why**: xfrm shows tunnel state, ping verifies connectivity
- **Implementation**: xfrm primary, ping optional verification
- **Benefit**: Distinguishes "idle" from "broken"

### 6. Shared Library and Helper Functions
- **Why**: Reduce code duplication and improve maintainability
- **Implementation**: `lib/common.sh` provides shared logging and utility functions
- **Helper Functions**: 
  - `get_formatted_timestamp()` - Consistent date formatting
  - `ensure_directory_exists()` - Centralized directory creation
  - `log_and_exit_lockfile_conflict()` - Consistent lockfile conflict handling
  - `extract_lockfile_pid()` - Lockfile PID extraction
  - `is_process_running()` - Process existence checking
  - `create_lockfile_atomically()` - Atomic lockfile creation
  - `get_file_mtime()` - Cross-platform file modification time
  - `validate_ip_address()` - Robust IP address validation (IPv4/IPv6)
- **Benefit**: Consistent error handling, reduced duplication, easier maintenance

### 7. Rate Limiting
- **Why**: Prevent restart loops if VPN has persistent issues
- **Implementation**: Track restart timestamps, limit per hour
- **Benefit**: Protects system from excessive restarts

### 7. Cooldown Period
- **Why**: Allow VPN to stabilize after restart
- **Implementation**: Skip checks for configured minutes after restart
- **Benefit**: Prevents false positives immediately after recovery

## Error Handling Strategy

1. **Fail-Safe Defaults**: Script exits gracefully on errors
2. **Logging**: All errors logged with context
3. **Fallbacks**: Multiple detection methods (xfrm → swanctl → ipsec)
4. **Validation**: Input validation prevents injection attacks
5. **State Recovery**: Stale lockfiles automatically cleaned up

## Performance Considerations

- **Execution Time**: Typically < 30 seconds per run
- **Resource Usage**: Minimal (bash script, no daemon)
- **State File Size**: Small (few KB per peer)
- **Log Rotation**: Manual (could be enhanced with logrotate)

## Security Considerations

- **Input Validation**: Peer IPs validated before use
- **File Permissions**: State files readable/writable by script only
- **No External Network**: Only local system commands (except ping)
- **Config Sourcing**: Validated before sourcing config file

