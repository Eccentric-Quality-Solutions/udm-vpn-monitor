# ADR-0019: Byte Counter Detection Method

## Status
Accepted

## Context
VPN tunnel health detection faces a critical challenge: distinguishing between "tunnel exists but idle" and "tunnel exists but broken". Simply checking for Security Association (SA) existence is insufficient because:

- SAs can exist even when tunnels are not passing traffic
- Idle VPN tunnels may have valid SAs but no active data flow
- Network issues can cause SAs to exist while traffic fails to flow
- False positives from idle tunnels would trigger unnecessary recovery actions

Alternative detection methods considered:
- SA existence only (too many false positives for idle tunnels)
- Ping checks only (can fail due to firewall rules, not authoritative)
- Connection status only (doesn't indicate actual traffic flow)

## Decision
We will use byte counters from `ip xfrm state` as the primary method for detecting actual traffic flow through VPN tunnels. Byte counters provide authoritative evidence that data is actively flowing through the tunnel.

## Consequences

### Positive
- **Traffic Flow Detection**: Byte counters indicate actual data transmission, not just tunnel existence
- **Idle Tunnel Handling**: Distinguishes healthy idle tunnels from broken tunnels (idle tunnels have non-zero but static counters)
- **Authoritative Source**: Byte counters come directly from kernel IPsec state, providing reliable traffic flow evidence
- **Reduces False Positives**: Prevents unnecessary recovery actions for idle but healthy tunnels
- **Per-Peer Tracking**: Each peer's byte counters tracked independently, enabling accurate multi-peer monitoring
- **Baseline Comparison**: Compares current bytes to previous values to detect if traffic is actively flowing

### Negative
- **First Check Limitation**: First check after installation cannot detect if bytes are increasing (no baseline)
- **Rekey Handling Required**: SA rekey events reset byte counters to 0, requiring special handling (see ADR-0020)
- **Counter Extraction Dependency**: Relies on parsing `ip xfrm state` output, which may vary across UDM OS versions
- **Zero Byte Edge Case**: Tunnels with exactly 0 bytes may be flagged as suspect even if healthy (mitigated by allowing non-zero static counters)

## Implementation Details
- **Detection Flow**:
  1. Extract byte counters from `ip xfrm state` output for the peer IP
  2. Compare current bytes to last known bytes (stored in `last_bytes_<peer_ip>`)
  3. If bytes are increasing: VPN is healthy (traffic flowing)
  4. If bytes are non-zero but static: VPN is idle but healthy (no failure)
  5. If bytes are zero or decreasing: VPN is suspect (may indicate failure)
- **Baseline Management**:
  - First check: Any non-zero bytes accepted as baseline
  - Subsequent checks: Bytes must be >= previous value (allows static non-zero for idle tunnels)
  - Rekey events: Baseline reset to 0 (see ADR-0020)
- **State Storage**: Per-peer byte counters stored in `last_bytes_<peer_ip>` files
- **Validation Logic**:
  - `current_bytes > 0`: Required for healthy tunnel
  - `current_bytes >= last_bytes`: Required for active traffic flow (or idle tunnel with static counters)
  - `last_bytes == 0`: First check or after rekey (accepts any non-zero)
- **Module**: Implemented in `lib/detection.sh` with `check_byte_counters()` function

## Related ADRs
- ADR-0006: Multi-Method Detection with Fallback (byte counters are primary method)
- ADR-0014: Ping Check as Supplementary Diagnostic (ping supplements byte counter detection)
- ADR-0020: SA Rekey Detection and Handling (handles byte counter resets during rekey)
- ADR-0004: Per-Peer State Tracking (byte counters tracked per-peer)

## References
- ARCHITECTURE.md: "Detection Method Flow" section
- ARCHITECTURE.md: "State Management" section (byte counter storage)
- lib/detection.sh: `check_byte_counters()` function implementation
- lib/detection.sh: `check_xfrm_status()` function (byte counter extraction)

