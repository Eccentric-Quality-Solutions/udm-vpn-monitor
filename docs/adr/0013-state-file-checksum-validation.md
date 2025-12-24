# ADR-0013: State File Checksum Validation

## Status
Accepted

## Context
State files contain critical system state:
- Failure counters determine recovery actions
- Byte counters track VPN traffic flow
- Corrupted state files could cause:
  - Incorrect recovery actions (wrong failure counts)
  - False positives or false negatives
  - System misbehavior
  - Data loss

Without checksum validation:
- Corrupted files may be read as valid data
- Silent data corruption goes undetected
- System operates on incorrect state
- Difficult to diagnose corruption issues

## Decision
We will implement checksum validation for state files to:
- Detect corruption when reading state files
- Prevent operating on corrupted data
- Log corruption events for troubleshooting
- Provide early warning of file system issues

## Consequences

### Positive
- **Corruption Detection**: Catches corrupted files before use
- **Data Integrity**: Ensures state files contain valid data
- **Early Warning**: Logs corruption events for troubleshooting
- **Reliability**: Prevents system misbehavior from corrupted state

### Negative
- **Performance Overhead**: Checksum calculation adds processing time (minimal)
- **Code Complexity**: Requires checksum generation and validation logic
- **Recovery Needed**: Corrupted files need recovery mechanism (currently resets to defaults)

## Implementation Details
- **Checksum Method**: Simple checksum (sum of bytes modulo 256) stored with data
- **Validation Points**: Checksum validated when reading state files
- **Corruption Handling**: 
  - Corrupted files detected and logged
  - State reset to safe defaults (0 for counters)
  - Corruption event logged for troubleshooting
- **Files Protected**: 
  - Failure counter files
  - Byte counter files
  - Cooldown file
  - Restart count file
- **Module**: Implemented in `lib/state.sh` for state file operations

## Related ADRs
- ADR-0012: Atomic File Operations
- ADR-0004: Per-Peer State Tracking

## References
- ARCHITECTURE.md: "State File Management" section
- ARCHITECTURAL_REVIEW.md: "Reliability & Resilience" section (State File Corruption Recovery)
- CHANGELOG.md: "State Checksum Validation" entry
- lib/state.sh: Implementation details

