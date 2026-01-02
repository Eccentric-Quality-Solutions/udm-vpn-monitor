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
- **Traffic Pattern Analysis**: Tracks historical byte counter values over time to calculate traffic rate (bytes/second)
- **Idle Tunnel Handling**: Distinguishes healthy idle tunnels from broken tunnels using ping checks when traffic is static
- **Authoritative Source**: Byte counters come directly from kernel IPsec state, providing reliable traffic flow evidence
- **Reduces False Positives**: Prevents unnecessary recovery actions for idle but healthy tunnels
- **Per-Peer Tracking**: Each peer's byte counters tracked independently, enabling accurate multi-peer monitoring
- **Baseline Comparison**: Compares current bytes to previous values to detect if traffic is actively flowing
- **Keepalive Integration**: Automatically suggests enabling/starting keepalive daemon when idle tunnels are detected

### Negative
- **First Check Limitation**: First check after installation cannot detect if bytes are increasing (no baseline)
- **Traffic Pattern Window**: Requires minimum time window (60 seconds) and multiple samples to calculate meaningful traffic rate
- **Rekey Handling Required**: SA rekey events reset byte counters to 0 and clear traffic history, requiring special handling (see ADR-0020)
- **Counter Extraction Dependency**: Relies on parsing `ip xfrm state` output, which may vary across UDM OS versions
- **Zero Byte Edge Case**: Tunnels with exactly 0 bytes may be flagged as suspect even if healthy (mitigated by allowing non-zero static counters)
- **Ping Check Dependency**: Idle detection requires ping checks to be enabled and internal peer IPs to be configured

## Implementation Details
- **Detection Flow**:
  1. Extract byte counters from `ip xfrm state` output for the peer IP
  2. Compare current bytes to last known bytes (stored in `last_bytes_<location>_<peer_ip>`)
  3. If bytes are increasing: VPN is healthy (traffic flowing)
  4. If bytes are static and ping fails: VPN is broken (failure detected)
  5. If bytes are static and ping succeeds: VPN is idle but healthy (no failure, keepalive suggested)
  6. If bytes are zero or decreasing: VPN is suspect (may indicate failure)
- **Idle Detection**:
  - When tunnel is idle (static bytes for extended period), ping checks are used to verify tunnel health
  - If ping succeeds: Tunnel is idle but healthy (no failure, keepalive suggested)
  - If ping fails: Tunnel is likely broken (failure detected)
  - Keepalive daemon status is checked and suggestions provided when idle tunnels are detected
- **Baseline Management**:
  - First check: Any non-zero bytes accepted as baseline
  - Subsequent checks: Use simple byte counter comparison and ping checks for idle detection
  - Rekey events: Baseline reset to 0 (see ADR-0020)
- **State Storage**: 
  - Per-location, per-peer byte counters stored in `last_bytes_<location>_<peer_ip>` files
  - Idle state tracked in `idle_detected_<location>_<peer_ip>` files
- **Validation Logic**:
  - `current_bytes > 0`: Required for healthy tunnel (except first check)
  - `current_bytes > last_bytes`: Indicates active traffic flow
  - `current_bytes == last_bytes && ping_succeeds`: Idle but healthy
  - `current_bytes == last_bytes && ping_fails`: Likely broken
  - `last_bytes == 0`: First check or after rekey (accepts any non-zero)
- **Module**: Implemented in `lib/detection.sh` with `check_byte_counters()` function

## Related ADRs
- ADR-0006: Multi-Method Detection with Fallback (byte counters are primary method)
- ADR-0014: Ping Check as Supplementary Diagnostic (ping supplements byte counter detection for idle tunnels)
- ADR-0020: SA Rekey Detection and Handling (handles byte counter resets during rekey)
- ADR-0004: Per-Peer State Tracking (byte counters tracked per-location, per-peer)
- ADR-0009: VPN Keepalive Daemon (keepalive prevents idle tunnel timeouts)
- ADR-0024: Location-Based Configuration Format (location names included in state file names)

## References
- ARCHITECTURE.md: "Detection Method Flow" section
- ARCHITECTURE.md: "State Management" section (byte counter storage)
- lib/detection.sh: `check_byte_counters()` function implementation
- lib/detection.sh: `check_xfrm_status()` function (byte counter extraction)
- lib/state.sh: State file management functions

