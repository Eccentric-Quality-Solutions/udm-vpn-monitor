# ADR-0002: Lockfile Protection Mechanism

## Status
Accepted

## Context
Since the monitoring script runs via cron, there is a risk of concurrent execution if:
- A previous execution takes longer than the cron interval
- Multiple cron jobs are accidentally configured
- Manual execution occurs while cron is running
- System clock issues cause cron to trigger multiple times

Concurrent execution could lead to:
- Race conditions in state file updates
- Multiple recovery actions running simultaneously
- Corrupted state files
- Unpredictable behavior

## Decision
We will implement lockfile protection using `flock` (preferred) with atomic file creation fallback to prevent concurrent script execution.

## Consequences

### Positive
- **Prevents Race Conditions**: Ensures only one instance runs at a time
- **Atomic Operations**: Lockfile acquisition is atomic, preventing race conditions
- **Stale Lockfile Detection**: Automatically detects and cleans up lockfiles from hung processes
- **Cross-Platform**: Works on systems with or without `flock` command
- **Timeout Protection**: Detects hung processes via lockfile timestamp checking

### Negative
- **Additional Complexity**: Requires lockfile management code
- **Potential False Positives**: Stale lockfile detection may incorrectly identify active processes as hung
- **File System Dependency**: Requires writable file system for lockfile creation

## Implementation Details
- **Preferred Method**: Uses `flock` command with file descriptor locking
- **Fallback Method**: Atomic file creation using `set -C` (noclobber mode)
- **Lockfile Format**: `timestamp:pid` for timeout detection
- **Timeout Detection**: Checks lockfile age against `LOCKFILE_TIMEOUT` (default: 300 seconds)
- **Stale Cleanup**: Automatically removes stale lockfiles from hung processes
- **Module**: Implemented in `lib/lockfile.sh` with `acquire_lockfile()` and `release_lockfile()` functions

## Related ADRs
- ADR-0001: Cron-Based Execution Instead of Daemon
- ADR-0012: Atomic File Operations

## References
- ARCHITECTURE.md: "Key Design Decisions #2: Lockfile Protection"
- lib/lockfile.sh: Implementation details

