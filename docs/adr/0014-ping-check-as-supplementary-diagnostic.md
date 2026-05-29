# ADR-0014: Ping Check as Supplementary Diagnostic Tool

## Status
Accepted

## Context
VPN tunnel health detection needs to distinguish between different failure scenarios:
- Tunnel down (no SA exists)
- Tunnel established but routing broken (SA exists but no traffic flowing)
- Tunnel healthy but idle (SA exists, no current traffic, but tunnel is functional)
- Transient network issues causing temporary ping failures

Byte counters from `ip xfrm state` are the primary signal for traffic flow (see ADR-0019). Ping adds end-to-end connectivity verification — especially for idle tunnels where bytes are static.

**Historical note:** Ping was originally warning-only (failures did not count toward recovery). That left a gap: SA up + ping failing + bytes static could not escalate tiers reliably. **v0.8.0** changed behavior when `ENABLE_PING_CHECK=1`.

## Decision
When **`ENABLE_PING_CHECK=1`** (and internal IPs are configured), ping results **participate in failure determination** alongside byte counters and SA state:

- Ping failure with SA present can mark the VPN as failed (`routing_issue` or idle/broken) and count toward tier thresholds
- Ping success with no SA logs a warning about alternative routing (VPN already failed due to missing SA)
- When **`ENABLE_PING_CHECK=0`** or no internal IPs are configured, ping is not run; detection relies on xfrm/byte counters only

Ping is still **optional** and **supplementary** in the sense that it is not the sole signal — it combines with byte counter analysis rather than replacing it.

## Consequences

### Positive
- **Prevents False Positives**: Transient ping failures don't trigger recovery actions
- **More Reliable Detection**: SA state + byte counters are more reliable than ping
- **Better Diagnostics**: Ping warnings help identify routing issues without causing failures
- **Natural Escalation**: If routing is broken, byte counters will eventually stop increasing, triggering proper failure detection
- **Distinguishes Failure Types**: Helps identify "connectivity via alternative route" scenarios

### Negative
- **Potential Delay**: Routing issues may take longer to detect (until byte counters stop increasing)
- **Requires Understanding**: Users need to understand ping warnings don't cause failures
- **May Miss Some Issues**: Routing problems that don't affect byte counters may go undetected longer

## Implementation Details
- **Ping Check Behavior**:
  - **Scenario 1a**: SA exists, byte counters **increasing**, ping fails → VPN marked as **FAILED** (routing issue), recovery can trigger after consecutive failures (see tier thresholds).
  - **Scenario 1b**: SA exists, byte counters **static/zero**, ping fails → VPN marked as **FAILED** (idle/broken), recovery can trigger.
  - **Scenario 1c**: SA exists, ping fails, but **ENABLE_PING_CHECK=0** or **no internal IPs** configured → Ping is not run; VPN marked OK when bytes show traffic. Ping timeouts (e.g. manual tests) do not affect the monitor.
  - **Scenario 2**: SA doesn't exist but ping succeeds → VPN marked as FAILED, WARNING logged (indicates alternative route)
- **Ping Check Purpose**:
  - Early warning of connectivity issues
  - Diagnostic information for troubleshooting
  - Helps distinguish between different failure types
- **Failure Detection**: Combines SA state, byte counter analysis, and ping (when enabled); ipsec fallback is skipped when xfrm reports SA exists but ping/bytes indicate failure (v0.8.0)
- **Route Detection**:
  - When ping succeeds but SA doesn't exist (Scenario 2), the system attempts to identify the alternative route being used
  - Uses `ip route get` command to determine gateway and interface for the destination IP
  - Route information is included in warning messages: "VPN tunnel is down (no SA found), but connectivity exists via alternative route (route: via <gateway> dev <interface>)"
  - Route detection gracefully handles failures - if route info cannot be determined, warning still logs without route information
  - Helps administrators understand how traffic is flowing when VPN tunnel is down
  - Implemented via `get_route_info()` and `build_route_message()` functions in `lib/detection/network_validation.sh`
- **Multiple Internal IPs Support**:
  - For locations with **single internal IP**: Requires 100% success (ping must succeed)
  - For locations with **multiple internal IPs**: VPN considered healthy if ≥30% respond to pings (rounded up)
  - Example: 3 internal IPs need at least 1 successful ping, 10 internal IPs need at least 3 successful pings
  - Rationale: Allows for partial connectivity while still detecting complete failures
  - Route detection uses first IP in multiple IP configurations
- **Module**: Implemented in `lib/detection/ping_detection.sh` (`check_ping_connectivity()`) and `lib/detection/network_validation.sh` (`get_route_info()`, `build_route_message()`)

## Change History
- **v0.8.0 (2026-02-14)**: When `ENABLE_PING_CHECK=1`, ping failure counts toward failure/tier escalation (previously warning-only). See CHANGELOG.md v0.8.0.

## Related ADRs
- ADR-0006: Multi-Method Detection with Fallback
- ADR-0003: Tiered Recovery System
- ADR-0019: Byte Counter Detection Method
- ADR-0024: Location-Based Configuration Format

## References
- README.md: "Ping Check Behavior" section
- README.md: "Why This Design?" explanation
- TROUBLESHOOTING.md: "Ping timeouts but VPN never restarts"
- lib/detection/ping_detection.sh: Ping check implementation
- lib/detection/network_validation.sh: Route detection implementation
