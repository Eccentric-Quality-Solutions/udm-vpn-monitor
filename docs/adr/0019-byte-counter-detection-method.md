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
- **Simple Heuristics**: Uses straightforward logic: bytes increasing = healthy, bytes not increasing + ping fails = broken
- **Idle Tunnel Handling**: Distinguishes healthy idle tunnels from broken tunnels using ping checks when traffic is static
- **Authoritative Source**: Byte counters come directly from kernel IPsec state, providing reliable traffic flow evidence
- **Reduces False Positives**: Prevents unnecessary recovery actions for idle but healthy tunnels
- **Per-Peer Tracking**: Each peer's byte counters tracked independently, enabling accurate multi-peer monitoring
- **Baseline Comparison**: Compares current bytes to previous values to detect if traffic is actively flowing
- **Keepalive Integration**: Automatically suggests enabling/starting keepalive daemon when idle tunnels are detected
- **Maintainability**: Simple approach reduces complexity and improves maintainability for single-deployment use case

### Negative
- **First Check Limitation**: First check after installation cannot detect if bytes are increasing (no baseline)
- **Rekey Handling Required**: SA rekey events reset byte counters to 0, requiring special handling (see ADR-0020)
- **Counter Extraction Dependency**: Relies on parsing `ip xfrm state` output, which may vary across UDM OS versions
- **Zero Byte Edge Case**: Tunnels with exactly 0 bytes may be flagged as suspect even if healthy (mitigated by allowing non-zero static counters)
- **Ping Check Dependency**: Idle detection requires ping checks to be enabled and internal peer IPs to be configured
- **Format Variations**: UDM OS uses `ip -s xfrm state` format where byte counters appear as `  39492(bytes)` on a separate line after `lifetime current:`, requiring format-specific parsing

## Implementation Details
- **Detection Flow** (Simplified in v0.2.0):
  1. Extract byte counters from `ip xfrm state` output for the peer IP (uses `ip -s xfrm state` first for UDM OS compatibility)
  2. Check for SA rekey events (SPI changes) - if detected, reset baseline to 0
  3. Compare current bytes to last known bytes (stored in `last_bytes_<location>_<peer_ip>`)
  4. If bytes are increasing: VPN is healthy (traffic flowing)
  5. If bytes are static and ping fails: VPN is broken (failure detected)
  6. If bytes are static and ping succeeds: VPN is idle but healthy (no failure, keepalive suggested)
  7. If bytes are zero or decreasing: VPN is suspect (may indicate failure)
  8. If byte counters unavailable but SA exists and ping succeeds: VPN is idle but healthy (fallback to ping check)
- **Simplified Heuristics** (v0.2.0):
  - Removed complex traffic pattern analysis (historical samples, automatic pruning, rate calculations)
  - Uses simple logic: bytes increasing = healthy, bytes not increasing + ping fails = broken
  - Maintains ping-based idle detection for static byte counters
  - Reduces complexity and improves maintainability for single-deployment use case
- **XFRM Output Format (UDM OS)**:
  - Uses `ip -s xfrm state` command which provides detailed statistics
  - Format: `lifetime current:` appears on one line, followed by `  39492(bytes), 609(packets)` on the next line
  - Example:
    ```
    lifetime current:
      39492(bytes), 609(packets)
      add 2026-01-03 12:19:25 use 2026-01-03 12:19:34
    ```
  - Extraction handles both single-line format (`lifetime current: 123456 bytes`) and multi-line UDM format (`  39492(bytes)`)
  - Falls back to ping check when byte counter extraction fails but SA exists
- **Idle Detection**:
  - When tunnel is idle (static bytes), ping checks are used to verify tunnel health
  - If ping succeeds: Tunnel is idle but healthy (no failure, keepalive suggested)
  - If ping fails: Tunnel is likely broken (failure detected)
  - Keepalive daemon status is checked and suggestions provided when idle tunnels are detected
- **Baseline Management**:
  - First check: Any non-zero bytes accepted as baseline (or zero bytes with successful ping)
  - Subsequent checks: Use simple byte counter comparison and ping checks for idle detection
  - Rekey events: Baseline reset to 0 (see ADR-0020)
- **State Storage**: 
  - Per-location, per-peer byte counters stored in `last_bytes_<location>_<peer_ip>` files
  - Idle state tracked in `idle_detected_<location>_<peer_ip>` files
- **Validation Logic**:
  - `current_bytes > 0`: Required for healthy tunnel (except first check or after rekey)
  - `current_bytes > last_bytes`: Indicates active traffic flow
  - `current_bytes == last_bytes && ping_succeeds`: Idle but healthy
  - `current_bytes == last_bytes && ping_fails`: Likely broken
  - `last_bytes == 0`: First check or after rekey (accepts any non-zero, or zero with successful ping)
  - `current_bytes < last_bytes`: Abnormal decrease, logged as warning, then checked with ping
- **Module**: Implemented in `lib/detection.sh` with `check_byte_counters()` function

## Related ADRs
- ADR-0006: Multi-Method Detection with Fallback (byte counters are primary method)
- ADR-0014: Ping Check as Supplementary Diagnostic (ping supplements byte counter detection for idle tunnels)
- ADR-0020: SA Rekey Detection and Handling (handles byte counter resets during rekey)
- ADR-0004: Per-Peer State Tracking (byte counters tracked per-location, per-peer)
- ADR-0009: VPN Keepalive Daemon (keepalive prevents idle tunnel timeouts)
- ADR-0024: Location-Based Configuration Format (location names included in state file names)

## Change History
- **v0.2.0 (2025-12-26)**: Simplified byte counter detection by removing complex traffic pattern analysis (historical samples, automatic pruning, rate calculations). Replaced with simple heuristics: bytes increasing = healthy, bytes not increasing + ping fails = broken. See CHANGELOG.md v0.2.0 for details.

## References
- ARCHITECTURE.md: "Detection Method Flow" section
- ARCHITECTURE.md: "State Management" section (byte counter storage)
- lib/detection.sh: `check_byte_counters()` function implementation (lines 1372-1546)
- lib/detection.sh: `check_xfrm_status()` function (byte counter extraction)
- lib/state.sh: State file management functions
- CHANGELOG.md: v0.2.0 "Simplified Byte Counter Detection" entry

