# ADR-0006: Multi-Method Detection with Fallback

## Status
Accepted

## Context
VPN tunnel health detection on UDM systems faces challenges:
- Different UDM OS versions may have different tools available
- Some detection methods may be unreliable in certain configurations
- Need to distinguish between "tunnel down" vs "tunnel idle but healthy"
- Must work across different UDM configurations and network setups

A single detection method would:
- Fail if that method is unavailable
- Not distinguish between different failure types
- Be vulnerable to false positives (e.g., idle tunnels)

## Decision
We will implement a multi-method detection system with automatic fallback:
1. **Primary**: `ip xfrm state` - Checks Security Associations (SAs) and byte counters
2. **Fallback**: `ipsec status` - Checks for connections via ipsec command (if xfrm unavailable)
3. **Optional**: Ping checks - Verifies end-to-end connectivity through tunnel

## Consequences

### Positive
- **Robust Detection**: Works across different UDM configurations
- **Automatic Fallback**: If primary method fails, automatically uses fallback
- **Traffic Flow Detection**: Byte counters distinguish "idle" from "broken"
- **Connectivity Verification**: Ping checks verify end-to-end connectivity
- **Failure Type Detection**: Can distinguish "tunnel down" vs "routing issue"

### Negative
- **Complexity**: Multiple detection methods require coordination logic
- **Performance**: Multiple checks may take longer
- **False Positives**: Ping checks may fail due to firewall rules (mitigated by making ping optional and non-blocking)

## Implementation Details
- **Detection Flow**:
  1. Check `ip xfrm state` for SA existence and byte counters
  2. If SA found: Check if byte counters are increasing
  3. If SA not found: Fall back to `ipsec status` check
  4. If ping enabled: Perform ping check (warns but doesn't fail if ping fails)
- **Failure Types**:
  - "Tunnel Down": No Phase 2 SA exists
  - "Routing Issue": SA exists but byte counters not increasing
  - "Unknown": Unable to determine failure type
- **Ping Check Behavior**:
  - Ping failures log warnings but don't cause VPN failure
  - SA state + byte counters are authoritative
  - Ping provides supplementary diagnostic information
- **Module**: Implemented in `lib/detection.sh` with `check_vpn_status()` function

## Related ADRs
- ADR-0004: Per-Peer State Tracking
- ADR-0003: Tiered Recovery System

## References
- ARCHITECTURE.md: "Key Design Decisions #5: Multi-Method Detection with Fallback"
- ARCHITECTURE.md: "Detection Method Flow" diagram
- lib/detection.sh: Implementation details

