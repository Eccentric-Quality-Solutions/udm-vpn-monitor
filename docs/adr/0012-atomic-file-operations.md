# ADR-0012: Atomic File Operations

## Status
Accepted

## Context
State files are critical for system operation:
- Failure counters determine recovery actions
- Byte counters track VPN traffic flow
- Cooldown and rate limit files control system behavior
- Corrupted or partially written files can cause:
  - Incorrect recovery actions
  - Lost state information
  - System misbehavior

Without atomic operations:
- Race conditions during file writes
- Partially written files if script crashes during write
- Corrupted state files
- Lost or incorrect state information

## Decision
We will use atomic file write patterns (write-tmp-move) for all state file operations to ensure:
- Files are never partially written
- No race conditions during concurrent access
- Atomic updates (all-or-nothing)
- Safe recovery from crashes

## Consequences

### Positive
- **Data Integrity**: Files never partially written
- **Crash Safety**: Crashes don't corrupt state files
- **Race Condition Prevention**: Atomic operations prevent race conditions
- **Reliability**: State files always in consistent state

### Negative
- **Code Complexity**: Requires write-tmp-move pattern for all writes
- **Temporary Files**: Creates temporary files during writes (cleaned up automatically)

## Implementation Details
- **Write Pattern**: Write-tmp-move pattern:
  1. Write to temporary file (`$file.tmp`)
  2. Verify write succeeded
  3. Atomically move temp file to final location (`mv $file.tmp $file`)
- **Used For**:
  - Failure counter files
  - Byte counter files
  - Cooldown file
  - Restart count file
  - Lockfile (with additional flock/atomic creation)
- **Error Handling**: If write fails, temp file cleaned up, original file unchanged
- **Module**: Implemented in `lib/state.sh` for state file operations

## Related ADRs
- ADR-0002: Lockfile Protection Mechanism
- ADR-0013: State File Checksum Validation
- ADR-0004: Per-Peer State Tracking

## References
- ARCHITECTURE.md: "Security Considerations" section (atomic operations)
- ARCHITECTURAL_REVIEW.md: "Reliability & Resilience" section
- lib/state.sh: Implementation details

