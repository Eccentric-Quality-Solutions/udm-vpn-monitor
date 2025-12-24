# ADR-0008: Rate Limiting and Cooldown Periods

## Status
Accepted

## Context
Recovery actions, especially full restarts (Tier 3), can be disruptive:
- Restarting IPsec affects all VPN tunnels
- Multiple rapid restarts can cause service disruption
- If underlying issue persists, restart loops may occur
- VPN tunnels need time to stabilize after restart

Without rate limiting and cooldown:
- Persistent VPN issues could trigger restart loops
- System could restart VPNs excessively
- No time for VPN to stabilize after recovery actions
- Risk of making problems worse through excessive restarts

## Decision
We will implement:
1. **Rate Limiting**: Limit the number of Tier 3 (full restart) actions per hour
2. **Cooldown Period**: Skip monitoring checks for a configured period after Tier 3 actions

## Consequences

### Positive
- **Prevents Restart Loops**: Rate limiting stops excessive restarts
- **Allows Stabilization**: Cooldown period gives VPN time to recover
- **Protects System**: Prevents system from being overwhelmed by recovery actions
- **Configurable**: Users can adjust limits based on their needs
- **Per-System Limits**: Rate limiting applies globally (not per-peer) to prevent system-wide disruption

### Negative
- **Recovery Delay**: Cooldown period delays detection of new failures
- **Complexity**: Requires tracking restart timestamps and cooldown state
- **State Management**: Additional state files needed for tracking

## Implementation Details
- **Rate Limiting**:
  - Tracks restart timestamps in `logs/restart_count` file
  - Default limit: `MAX_RESTARTS_PER_HOUR=3` (configurable)
  - Applies only to Tier 3 (full restart) actions
  - Checks restart count in last hour before allowing Tier 3 action
- **Cooldown Period**:
  - Tracks cooldown expiration in `cooldown_until` file
  - Default duration: `COOLDOWN_MINUTES=15` (configurable)
  - Set after Tier 3 actions
  - Script exits early if in cooldown period
- **Module**: Implemented in `lib/state.sh` with `check_rate_limit()` and `check_cooldown()` functions

## Related ADRs
- ADR-0003: Tiered Recovery System
- ADR-0004: Per-Peer State Tracking
- ADR-0012: Atomic File Operations

## References
- ARCHITECTURE.md: "Key Design Decisions #8: Rate Limiting"
- ARCHITECTURE.md: "Key Design Decisions #9: Cooldown Period"
- lib/state.sh: Implementation details

