# ADR-0025: Network Partition Detection

## Status
Accepted

## Context
VPN tunnel failures can occur for multiple reasons:
- Actual VPN tunnel problems (SA failures, routing issues, etc.)
- Local network connectivity issues (network partition, ISP outage, router problems)
- Remote network issues (remote site down, remote VPN gateway unreachable)

Without network partition detection:
- VPN checks would fail when the local network is down, even though the VPN tunnel itself may be healthy
- Recovery actions would be attempted during network outages, wasting resources and potentially causing disruption
- False positives would occur during legitimate network outages (ISP issues, router problems)
- Recovery actions cannot succeed without network connectivity anyway

The problem: How do we distinguish between VPN tunnel failures and local network connectivity failures?

## Decision
We will implement network partition detection that:

1. **Checks Local Network Connectivity**: Performs multiple checks before assuming VPN failure:
   - Default route exists (`ip route show default`)
   - DNS resolution works (queries public DNS server)
   - Critical interfaces are UP (`ip link show` for br0, eth0)

2. **Skips VPN Checks When Partitioned**: When network partition is detected, VPN checks are skipped to prevent false positives

3. **Skips Recovery Actions When Partitioned**: Recovery actions are skipped when network is partitioned since they cannot succeed without connectivity

4. **Tracks Partition State**: Maintains global partition state (not per-peer) since network issues affect all peers

5. **Automatic Recovery**: Automatically resumes VPN monitoring when network connectivity is restored

6. **Runs Before Cooldown Check**: Network partition check occurs before cooldown check to ensure partition detection works even during cooldown periods

## Consequences

### Positive
- **Prevents False Positives**: Avoids triggering VPN recovery during legitimate network outages
- **Saves Resources**: Prevents unnecessary recovery actions that cannot succeed without network connectivity
- **Better User Experience**: Users don't see VPN recovery attempts during network outages
- **Automatic Recovery**: Automatically resumes monitoring when connectivity is restored
- **Configurable**: Can be disabled if not needed (`ENABLE_NETWORK_PARTITION_CHECK=0`)
- **Global State**: Single partition state for all peers (network issues affect all peers equally)

### Negative
- **Additional Overhead**: Adds network checks (DNS query, route check, interface check) to each monitor run
- **Potential False Negatives**: Could miss VPN failures if network checks pass but VPN-specific connectivity is down (mitigated by multi-method detection)
- **State File**: Requires additional state file for tracking partition state
- **Complexity**: Adds new detection logic and state management

## Implementation Details

### Detection Module
- **Location**: `lib/detection/failure_analysis.sh`
- **Function**: `check_network_partition()`
- **Checks**:
  1. Default route exists (`check_default_route()`)
  2. DNS resolution works (`check_dns_resolution()`)
  3. Critical interfaces are UP (`check_interface_state()`)

### State Management
- **Location**: `lib/state.sh`
- **Functions**:
  - `get_network_partition_state()` - Retrieves partition state (0 = healthy, 1 = partitioned)
  - `set_network_partition_state()` - Sets partition state
  - `get_network_partition_state_file()` - Returns state file path
- **State File**: `${STATE_DIR}/network_partition_state`
- **State Values**: 0 = healthy, 1 = partitioned
- **Global State**: Single state file (not per-peer) since network issues affect all peers

### Configuration Options
- `ENABLE_NETWORK_PARTITION_CHECK` (default: 1) - Enable/disable network partition detection
- `NETWORK_PARTITION_DNS_SERVER` (default: 8.8.8.8) - DNS server to query for DNS check
- `NETWORK_PARTITION_DNS_HOSTNAME` (default: google.com) - Hostname to resolve for DNS check
- `NETWORK_PARTITION_DNS_TIMEOUT` (default: 2) - DNS query timeout in seconds
- `NETWORK_PARTITION_INTERFACES` (default: br0,eth0) - Comma-separated list of interfaces to check

### Integration Points
1. **Early Detection** (`vpn-monitor.sh`):
   - Runs in `validate_monitor_state()` before cooldown check
   - Updates partition state but does not exit early (allows recovery code to check partition state)
   - Logs warnings when partition detected

2. **Recovery Actions** (`lib/recovery.sh`):
   - `monitor_location()` checks partition state before attempting recovery
   - Skips recovery actions when network is partitioned
   - Logs informative messages about skipped recovery

### Timing
- Network partition check runs **before** cooldown check
- This ensures partition detection works even during cooldown periods
- If network is partitioned, VPN checks are skipped regardless of cooldown status

### Behavior
- **When Partition Detected**:
  - VPN checks are skipped
  - Recovery actions are skipped
  - Partition state is updated to 1
  - Warning logged on first detection, info logged on subsequent detections

- **When Network Restored**:
  - Partition state is updated to 0
  - Info logged when connectivity restored
  - VPN monitoring resumes automatically

## Related ADRs
- ADR-0003: Tiered Recovery System (network partition prevents unnecessary recovery)
- ADR-0006: Multi-Method Detection with Fallback (network partition is separate from VPN detection)
- ADR-0023: Resource Monitoring and Throttling (runs before network partition check)
- ADR-0015: File-Based State Storage (uses state files for partition state)

## References
- ARCHITECTURE.md: "Network Partition Check" section
- CODEBASE_REVIEW.md: Section 6.3 "Network Partition Detection"
- lib/detection/failure_analysis.sh: `check_network_partition()` implementation
- lib/state.sh: Network partition state management functions
- vpn-monitor.conf: Configuration options documentation
- tests/test_detection_network_partition.sh: Test coverage
- tests/test_recovery_network_partition.sh: Recovery behavior during partition
