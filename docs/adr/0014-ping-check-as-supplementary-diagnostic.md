# ADR-0014: Ping Check as Supplementary Diagnostic Tool

## Status
Accepted

## Context
VPN tunnel health detection needs to distinguish between different failure scenarios:
- Tunnel down (no SA exists)
- Tunnel established but routing broken (SA exists but no traffic flowing)
- Tunnel healthy but idle (SA exists, no current traffic, but tunnel is functional)
- Transient network issues causing temporary ping failures

If ping checks were used as a hard failure condition:
- Transient ping failures (firewall rules, network congestion) would trigger false positives
- Healthy idle tunnels would be incorrectly detected as failed
- Recovery actions would be triggered unnecessarily
- SA state and byte counters are more reliable indicators of tunnel health

## Decision
We will design ping checks as a **supplementary diagnostic tool** that:
- Provides warnings but does not cause VPN failures
- SA state + byte counters remain the authoritative source for tunnel health
- Ping failures log warnings to help diagnose connectivity issues
- Ping successes when SA doesn't exist help identify alternative connectivity routes

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
  - **Scenario 1**: SA exists but ping fails → VPN marked as OK, WARNING logged
  - **Scenario 2**: SA doesn't exist but ping succeeds → VPN marked as FAILED, WARNING logged (indicates alternative route)
- **Ping Check Purpose**:
  - Early warning of connectivity issues
  - Diagnostic information for troubleshooting
  - Helps distinguish between different failure types
- **Failure Detection**: Based on SA state and byte counter analysis, not ping results
- **Module**: Implemented in `lib/detection.sh` with `check_ping_connectivity()` function

## Related ADRs
- ADR-0006: Multi-Method Detection with Fallback
- ADR-0003: Tiered Recovery System

## References
- README.md: "Ping Check Behavior" section
- README.md: "Why This Design?" explanation
- lib/detection.sh: Implementation details

