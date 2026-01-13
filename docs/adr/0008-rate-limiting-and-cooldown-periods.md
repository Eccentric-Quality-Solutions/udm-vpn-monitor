# ADR-0008: Rate Limiting and Cooldown Periods

## Status
Accepted (Updated 2026-01-12)

## Context
Recovery actions, especially full restarts (Tier 3), can be disruptive:
- Restarting IPsec affects all VPN tunnels
- Multiple rapid restarts can cause service disruption
- If underlying issue persists, restart loops may occur
- VPN tunnels need time to stabilize after restart

Without rate limiting:
- Persistent VPN issues could trigger restart loops
- System could restart VPNs excessively
- No time for VPN to stabilize after recovery actions
- Risk of making problems worse through excessive restarts

**Original Implementation (v0.5.0 and earlier):**
- Fixed "per hour" rate limiting (`MAX_RESTARTS_PER_HOUR=3`)
- Cooldown period that prevented all monitoring for 15 minutes after restart
- Cooldown behavior was problematic (prevented monitoring, delayed failure detection)

**Refactored Implementation (v0.6.0+):**
- Configurable sliding window rate limiting
- Minimum restart interval to prevent rapid-fire restarts
- Cooldown deprecated and replaced by minimum interval mechanism

## Decision
We will implement a three-parameter rate limiting system:
1. **Sliding Window Rate Limiting**: Limit the number of Tier 3 (full restart) actions within a configurable time window
2. **Minimum Restart Interval**: Enforce minimum spacing between consecutive restarts to prevent rapid-fire restarts
3. **Cooldown Deprecated**: Cooldown mechanism removed (replaced by minimum interval, which allows monitoring to continue)

## Consequences

### Positive
- **Prevents Restart Loops**: Rate limiting stops excessive restarts
- **Allows Stabilization**: Minimum interval gives VPN time to stabilize between restarts
- **Protects System**: Prevents system from being overwhelmed by recovery actions
- **Configurable**: Users can adjust limits and window size based on their needs
- **Flexible Time Windows**: Configurable window size (5 minutes to 24 hours) allows adaptation to different scenarios
- **Monitoring Continues**: Unlike cooldown, monitoring continues during rate limiting (only restart actions are blocked)
- **Per-System Limits**: Rate limiting applies globally (not per-peer) to prevent system-wide disruption
- **Sliding Window**: More accurate than fixed windows - counts restarts in last N minutes from current time
- **Backward Compatible**: `MAX_RESTARTS_PER_HOUR` automatically migrated to new parameters

### Negative
- **Complexity**: Requires tracking restart timestamps and window calculations
- **State Management**: Additional state files needed for tracking
- **Window Calculation Overhead**: Sliding window requires filtering timestamps (minimal performance impact)

## Implementation Details

### Three-Parameter Rate Limiting System

**1. Maximum Restarts Per Window** (`MAX_RESTARTS_PER_WINDOW`):
- **Type**: Integer
- **Range**: 1-20
- **Default**: 3
- **Description**: Maximum number of Tier 3 restarts allowed within the time window
- **Backward Compatibility**: `MAX_RESTARTS_PER_HOUR` automatically migrated to `MAX_RESTARTS_PER_WINDOW` with `RATE_LIMIT_WINDOW_MINUTES=60`

**2. Rate Limit Window** (`RATE_LIMIT_WINDOW_MINUTES`):
- **Type**: Integer
- **Range**: 5-1440 (5 minutes to 24 hours)
- **Default**: 60 (1 hour)
- **Description**: Time window (in minutes) for the rate limit. Uses sliding window (counts restarts in last N minutes from current time)
- **Examples**: 
  - `15` = 15-minute window (allows rapid recovery during system-wide failures)
  - `60` = 1-hour window (default, matches original behavior)
  - `120` = 2-hour window (more conservative)

**3. Minimum Restart Interval** (`MIN_RESTART_INTERVAL_SECONDS`):
- **Type**: Integer
- **Range**: 0-300 (0 = disabled, 5 minutes max)
- **Default**: 30
- **Description**: Minimum time (in seconds) that must pass between consecutive Tier 3 restarts. Prevents rapid-fire restarts even if within rate limit window.
- **Examples**:
  - `0` = No minimum spacing (allows all restarts to occur immediately if within window)
  - `30` = 30-second minimum (default, allows rapid recovery but prevents thrashing)
  - `60` = 1-minute minimum (more conservative, gives tunnels more time to stabilize)

### Rate Limit Check Logic

1. **Minimum Interval Check** (checked first):
   - If `MIN_RESTART_INTERVAL_SECONDS > 0`, checks time since last restart
   - Blocks restart if less than minimum interval has elapsed
   - Provides clear error message with remaining time

2. **Sliding Window Check**:
   - Calculates window start time: `now - RATE_LIMIT_WINDOW_MINUTES`
   - Filters restart timestamps in `RESTART_COUNT_FILE` to only those within window
   - Counts filtered timestamps
   - Blocks restart if count >= `MAX_RESTARTS_PER_WINDOW`
   - Provides detailed error message with reset time, countdown, and restart list

3. **Restart Recording**:
   - Records current timestamp to `RESTART_COUNT_FILE` after successful restart
   - Automatically cleans up entries older than 24 hours to prevent file growth
   - Uses atomic file operations to prevent corruption

### State File Management

- **Restart Tracking**: `state/restart_count` file (Unix timestamps, one per line)
  - Records Tier 3 recovery actions only:
    - Full IPsec restarts (`ipsec restart`) that affect all tunnels
    - Successful xfrm-based per-connection recovery (when enabled)
    - Does NOT record Tier 1 (logging) or Tier 2 (surgical cleanup) actions
  - Timestamps are sorted numerically when read (handles unsorted files, clock skew, etc.)
  - Automatically cleans up entries older than 24 hours

### Cooldown Status

**Deprecated (v0.6.0+)**: Cooldown mechanism has been replaced by the minimum restart interval system. Cooldown functions (`check_cooldown()`, `set_cooldown()`) remain in code for backward compatibility but are no longer called by the main script or recovery modules.

**Why Cooldown Was Removed:**
- Cooldown prevented all monitoring for 15 minutes (problematic - delayed failure detection)
- Minimum restart interval provides same protection (prevents rapid restarts) while allowing monitoring to continue
- Redundant with `MIN_RESTART_INTERVAL_SECONDS` (cooldown was just a longer version of minimum interval)
- Simpler system with fewer mechanisms = less complexity

### Module Location
- **Implementation**: `lib/state/global_state.sh` with `check_rate_limit()` and `record_restart()` functions
- **Configuration**: Defined in `lib/config_schema.sh` with validation rules
- **Backward Compatibility**: `lib/config/config_loading.sh` handles migration from `MAX_RESTARTS_PER_HOUR` to new parameters

### Logging Behavior
- "Tier 3: Attempting..." log messages appear before the rate limit check
- If rate limiting blocks the restart, detailed warning is logged including:
  - Reset timestamp (when oldest restart will expire)
  - Countdown (time remaining until reset)
  - List of restart timestamps that count toward the limit
- The restart command only executes if rate limiting allows it

## Related ADRs
- ADR-0003: Tiered Recovery System
- ADR-0004: Per-Peer State Tracking
- ADR-0012: Atomic File Operations

## Change History
- **2026-01-12**: Refactored rate limiting system:
  - Replaced fixed "per hour" window with configurable sliding window (`RATE_LIMIT_WINDOW_MINUTES`)
  - Replaced `MAX_RESTARTS_PER_HOUR` with `MAX_RESTARTS_PER_WINDOW`
  - Added `MIN_RESTART_INTERVAL_SECONDS` to prevent rapid-fire restarts
  - Deprecated cooldown mechanism (replaced by minimum interval)
  - Maintained backward compatibility with automatic migration from old parameters

## References
- ARCHITECTURE.md: "Key Design Decisions #8: Rate Limiting"
- `lib/state/global_state.sh`: Implementation details (`check_rate_limit()`, `record_restart()`)
- `lib/config_schema.sh`: Configuration parameter definitions
- `docs/working/RATE_LIMITING_REFACTOR_RECOMMENDATIONS.md`: Design rationale for refactoring
- `docs/working/RATE_LIMITING_REFACTOR_CODE_REVIEW.md`: Code review and implementation details

