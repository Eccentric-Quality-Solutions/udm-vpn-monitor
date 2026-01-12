# ADR-0020: SA Rekey Detection and Handling

## Status
Accepted

## Context
IPsec Security Associations (SAs) periodically rekey to maintain security. During rekey events:

- The SA's Security Parameter Index (SPI) changes to a new value
- Byte counters reset to 0 (new SA starts with fresh counters)
- The tunnel remains healthy and functional
- The peer IP address remains the same

Without rekey detection:
- Byte counter baseline comparison would fail (0 bytes vs previous non-zero)
- Healthy tunnels would be incorrectly flagged as failed
- False positives would trigger unnecessary recovery actions
- System would treat rekey events as tunnel failures

## Decision
We will detect SA rekey events by tracking SPI (Security Parameter Index) changes and automatically reset byte counter baselines when rekey occurs. This prevents false positives during normal SA rekey operations.

## Consequences

### Positive
- **Prevents False Positives**: Rekey events no longer trigger false failure detections
- **Automatic Baseline Reset**: Byte counter baseline automatically resets to 0 after rekey
- **Transparent Handling**: Rekey events are handled automatically without user intervention
- **Monitoring Support**: Rekey events are logged for monitoring purposes (not treated as failures)
- **Seamless Operation**: System continues monitoring normally through rekey events
- **SPI Tracking**: SPI values tracked per-peer for accurate rekey detection

### Negative
- **State File Overhead**: Additional state file (`spi_<peer_ip>`) required per peer
- **SPI Extraction Dependency**: Relies on parsing `ip xfrm state` output to extract SPI values
- **First Check Limitation**: First check cannot detect rekey (no previous SPI to compare)
- **SPI Format Variations**: Must handle both hex (0x...) and decimal SPI formats

## Implementation Details
- **Detection Method**:
  1. Extract current SPI from `ip xfrm state` output for the peer IP
  2. Compare current SPI to stored SPI (from `spi_<peer_ip>` file)
  3. If SPI changed: Rekey detected
  4. If SPI unchanged: No rekey (normal operation)
- **Rekey Handling**:
  - Reset byte counter baseline to 0 (`last_bytes_<location>_<peer_ip>` set to 0)
  - Update stored SPI to new value
  - Log rekey event for monitoring
  - Treat as first check for byte counter validation (accept any non-zero bytes)
- **SPI Storage**: Per-location, per-peer SPI values stored in `spi_<location>_<peer_ip>` files
- **Format Support**: Handles both hex format (0x12345678) and decimal format (305419896)
- **Integration Points**:
  - `check_byte_counters()`: Checks for rekey before validating byte counters
  - `detect_failure_type()`: Detects rekey events for failure type classification
  - `check_vpn_status()`: Handles rekey events during VPN status checks
- **Functions**:
  - `detect_sa_rekey()`: Detects rekey and resets baseline
  - `check_sa_rekey_occurred()`: Read-only check for rekey (doesn't modify state)
- **Module**: Implemented in `lib/detection/xfrm_detection.sh` with rekey detection functions

## Related ADRs
- ADR-0019: Byte Counter Detection Method (rekey handling prevents false positives in byte counter detection)
- ADR-0004: Per-Peer State Tracking (SPI tracked per-location, per-peer)
- ADR-0015: File-Based State Storage (SPI stored in state files)
- ADR-0012: Atomic File Operations (SPI updates use atomic writes)
- ADR-0024: Location-Based Configuration Format (location names included in state file names)

## References
- ARCHITECTURE.md: "State Management" section (SPI storage)
- lib/detection/xfrm_detection.sh: `detect_sa_rekey()` function implementation
- lib/detection/xfrm_detection.sh: `check_sa_rekey_occurred()` function implementation
- lib/detection/xfrm_detection.sh: `check_byte_counters()` function (rekey integration)
- lib/state.sh: SPI state management functions

