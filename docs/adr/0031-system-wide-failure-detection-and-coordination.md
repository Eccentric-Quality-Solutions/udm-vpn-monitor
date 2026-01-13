# ADR-0031: System-Wide Failure Detection and Coordination

## Status
Accepted

## Context
VPN tunnel failures can occur for multiple reasons:
- Individual VPN tunnel problems (SA failures, routing issues, etc.)
- Infrastructure-level issues (ISP outage, router problems, network-wide connectivity issues)
- Remote network issues (remote site down, remote VPN gateway unreachable)

**The Problem:**
When multiple VPN locations fail simultaneously (indicating an infrastructure-level issue rather than individual VPN problems), the existing per-location recovery system would attempt recovery for each failed location independently. This leads to:

1. **Recovery Cascades**: All locations attempt recovery simultaneously, potentially overwhelming the system
2. **Rate Limiting**: Multiple recovery attempts can trigger rate limiting mechanisms, preventing effective recovery
3. **Resource Waste**: Recovery actions cannot succeed during infrastructure outages (ISP down, router problems, etc.), wasting resources
4. **False Positives**: Individual recovery attempts during infrastructure outages are ineffective and create noise

**Example Scenario:**
- 10 VPN locations configured
- ISP outage causes all 10 locations to fail simultaneously
- Without coordination: All 10 locations attempt recovery independently
- Result: 10x recovery attempts, rate limiting, resource waste, no actual recovery possible until infrastructure is restored

**Alternative Approaches Considered:**

1. **No Coordination (Original Approach)**: Each location attempts recovery independently
   - **Pros**: Simple, no coordination logic needed
   - **Cons**: Recovery cascades, rate limiting, resource waste during infrastructure outages

2. **Complex Coordination (Leader Election, Consensus)**: Use distributed consensus algorithm to elect a single coordinator
   - **Pros**: More robust coordination, handles edge cases better
   - **Cons**: Significant complexity, requires additional infrastructure, overkill for this use case

3. **Simple Coordination (First Location Wins)**: First location to detect system-wide failure becomes coordinator
   - **Pros**: Simple, effective, minimal overhead, handles common case well
   - **Cons**: Potential race condition if two locations check simultaneously (acceptable risk - worst case is both attempt recovery, still better than all locations)

## Decision
We will implement system-wide failure detection with a simple coordination approach:

1. **System-Wide Failure Detection**: Detect when all (or a configured majority) of VPN locations fail simultaneously
   - Configurable threshold (default: 100%, all locations must fail)
   - Tracks system-wide failure state globally (not per-peer, since infrastructure issues affect all peers)
   - Maintains timestamp of when system-wide failure was first detected

2. **Recovery Coordination**: When system-wide failure is detected, only one location (the coordinator) attempts recovery
   - First location to check during system-wide failure becomes the coordinator
   - Coordinator designation stored in state file (atomic writes for safety)
   - Non-coordinator locations skip recovery actions during system-wide failures
   - Coordinator persists until system-wide failure is resolved

3. **Simple Coordination Mechanism**: "First location wins" approach
   - Uses atomic file writes to designate coordinator
   - No complex leader election or consensus algorithms
   - Acceptable race condition: If two locations check simultaneously, both may become coordinator (still better than all locations attempting recovery)

4. **Configurable**: Can be disabled if not needed
   - `ENABLE_SYSTEM_WIDE_FAILURE_DETECTION` (default: 1, enabled)
   - `SYSTEM_WIDE_FAILURE_THRESHOLD` (default: 100, range: 50-100, percentage of locations that must fail)
   - `COORDINATE_SYSTEM_WIDE_RECOVERY` (default: 1, enabled)

## Consequences

### Positive
- **Prevents Recovery Cascades**: Only one location attempts recovery during system-wide failures, preventing overwhelming the system
- **Avoids Rate Limiting**: Single recovery attempt prevents rate limiting mechanisms from blocking recovery
- **Saves Resources**: Prevents unnecessary recovery actions during infrastructure outages when recovery cannot succeed
- **Better User Experience**: Users see coordinated recovery attempts instead of chaotic simultaneous attempts
- **Automatic Recovery**: Automatically resumes per-location recovery when system-wide failure is resolved
- **Configurable**: Can be disabled or tuned via configuration options
- **Simple Implementation**: "First location wins" approach is simple and effective for this use case
- **Global State**: Single system-wide failure state for all peers (infrastructure issues affect all peers equally)

### Negative
- **Additional Overhead**: Adds system-wide failure detection check to each monitor run (reads failure status for all locations)
- **Double VPN Checking**: VPNs are checked twice per cycle (once for system-wide failure detection, once for actual monitoring) - acceptable trade-off for accurate detection
- **Race Condition Risk**: Two locations could simultaneously check for coordinator and both become coordinator (acceptable risk - worst case is both attempt recovery, still better than all locations)
- **State Files**: Requires additional state files for tracking system-wide failure state, timestamp, and coordinator
- **Complexity**: Adds new detection logic, state management, and coordination mechanism
- **Potential False Negatives**: Could miss system-wide failures if threshold is set too high (mitigated by configurable threshold)

## Implementation Details

### Detection Module
- **Location**: `lib/detection/system_wide_failure.sh`
- **Function**: `detect_system_wide_failure()`
- **Detection Logic**:
  1. Counts total locations and failed locations
  2. Calculates percentage of failed locations
  3. Compares to configured threshold (default: 100%)
  4. Requires at least 2 locations to detect system-wide failure (single location failure is not "system-wide")

### State Management
- **Location**: `lib/detection/system_wide_failure.sh`
- **Functions**:
  - `get_system_wide_failure_state()` - Retrieves system-wide failure state (0 = no failure, 1 = failure detected)
  - `set_system_wide_failure_state()` - Sets system-wide failure state
  - `get_system_wide_failure_timestamp()` - Retrieves timestamp when failure was first detected
  - `set_system_wide_failure_timestamp()` - Sets failure detection timestamp
  - `get_system_wide_failure_coordinator_file()` - Returns coordinator file path
  - `should_location_attempt_recovery()` - Checks if current location should attempt recovery
  - `clear_system_wide_failure_coordinator()` - Clears coordinator when failure is resolved
- **State Files**:
  - `${STATE_DIR}/system_wide_failure_state` - System-wide failure state (0 or 1)
  - `${STATE_DIR}/system_wide_failure_timestamp` - Unix timestamp when failure was first detected
  - `${STATE_DIR}/system_wide_failure_coordinator` - Location name of recovery coordinator
- **Global State**: Single state files (not per-peer) since infrastructure issues affect all peers

### Configuration Options
- `ENABLE_SYSTEM_WIDE_FAILURE_DETECTION` (default: 1) - Enable/disable system-wide failure detection
- `SYSTEM_WIDE_FAILURE_THRESHOLD` (default: 100) - Percentage of locations that must fail to trigger detection (range: 50-100)
- `COORDINATE_SYSTEM_WIDE_RECOVERY` (default: 1) - Enable/disable recovery coordination during system-wide failures

### Integration Points
1. **Detection** (`vpn-monitor.sh`):
   - Runs in `process_locations()` before per-location monitoring
   - Checks all locations for failures (read-only, doesn't update per-location state)
   - Updates system-wide failure state and timestamp
   - Logs system-wide failure events

2. **Recovery Actions** (`lib/recovery/recovery_orchestration.sh`):
   - `monitor_location()` checks `should_location_attempt_recovery()` before attempting recovery
   - Coordinator location attempts recovery normally
   - Non-coordinator locations skip recovery actions during system-wide failures
   - Logs informative messages about skipped recovery

### Coordination Mechanism
- **First Location Wins**: First location to check during system-wide failure becomes the coordinator
- **Atomic File Writes**: Uses `atomic_write_file()` to safely designate coordinator
- **Race Condition Handling**: If two locations check simultaneously, both may become coordinator (acceptable - still better than all locations)
- **Coordinator Persistence**: Coordinator persists until system-wide failure is resolved
- **Automatic Cleanup**: Coordinator is cleared when system-wide failure state is cleared

### Behavior
- **When System-Wide Failure Detected**:
  - System-wide failure state is set to 1
  - Timestamp is recorded (first detection only)
  - First location to check becomes coordinator
  - Only coordinator attempts recovery
  - Non-coordinator locations skip recovery actions
  - Warning logged on first detection, info logged on subsequent detections

- **When System-Wide Failure Resolved**:
  - System-wide failure state is set to 0
  - Coordinator is cleared
  - Duration of failure is calculated and logged
  - Per-location recovery resumes normally

## Why Coordination Approach Was Chosen

The "first location wins" coordination approach was chosen over alternatives for the following reasons:

1. **Simplicity**: No complex leader election or consensus algorithms needed - simple file-based coordination is sufficient
2. **Effectiveness**: Handles the common case (infrastructure outages) very well - prevents cascades and rate limiting
3. **Minimal Overhead**: Atomic file writes are fast and reliable, no network communication needed
4. **Acceptable Race Condition**: If two locations check simultaneously and both become coordinator, worst case is both attempt recovery (still better than all 10 locations)
5. **No Additional Infrastructure**: Works with existing state file system, no need for additional services or infrastructure
6. **Proven Pattern**: Similar to network partition detection (ADR-0025) - follows established patterns in the codebase

**Alternative Approaches Rejected:**

- **No Coordination**: Would cause recovery cascades and rate limiting during infrastructure outages
- **Complex Leader Election**: Overkill for this use case, adds significant complexity without proportional benefit
- **Location-Based Priority**: Adds complexity (priority configuration) without clear benefit over simple "first wins" approach

## Related ADRs
- ADR-0003: Tiered Recovery System (system-wide failure coordination prevents cascades during infrastructure outages)
- ADR-0025: Network Partition Detection (similar pattern for global state tracking, runs before system-wide failure detection)
- ADR-0012: Atomic File Operations (coordination uses atomic file writes for safety)
- ADR-0015: File-Based State Storage (uses state files for system-wide failure state, timestamp, and coordinator)
- ADR-0008: Rate Limiting and Cooldown Periods (coordination prevents rate limiting during system-wide failures)

## References
- `docs/ARCHITECTURE.md` - "System-Wide Failure State" section
- `docs/code-review-system-wide-failure.md` - Code review documentation
- `lib/detection/system_wide_failure.sh` - System-wide failure detection implementation
- `lib/recovery/recovery_orchestration.sh` - Recovery coordination integration
- `vpn-monitor.sh` - System-wide failure detection integration
- `vpn-monitor.conf` - Configuration options documentation
- `tests/test_detection_system_wide_failure.sh` - Test coverage
