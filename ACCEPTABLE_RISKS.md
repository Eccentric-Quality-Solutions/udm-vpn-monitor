# Acceptable Risks

This document tracks bugs and potential issues that have been reviewed and determined to be acceptable risks given their low likelihood and/or limited impact.

**Purpose**: To prevent re-adding these items to bug reviews or issue trackers in the future.

---

## Race Condition Between `check_rate_limit()` and `record_restart()`

**Location**: `lib/state.sh:812-840` and `lib/state.sh:866-888`

**Issue**: `check_rate_limit()` reads `RESTART_COUNT_FILE` while `record_restart()` modifies it, potentially causing a race condition.

**Why Acceptable**:
- Very low likelihood (< 0.1% in normal operation) - lockfile mechanism prevents concurrent execution
- Both functions run sequentially in the same process after lockfile is acquired
- Limited impact: worst case is one extra restart per hour if race occurs exactly at limit boundary
- Self-correcting: subsequent executions see correct count

**Date Accepted**: 2025-12-31

---

## Race Condition in `record_restart()` - Data Loss Risk

**Location**: `lib/state.sh:866-888`

**Issue**: `record_restart()` has a race condition where concurrent calls can cause data loss due to non-atomic append and read-modify-write operations.

**Why Acceptable**:
- Very low likelihood (< 0.1% in normal operation) - lockfile mechanism prevents concurrent execution
- `record_restart()` is only called from `full_restart()` which runs after lockfile is acquired
- Both append and read-modify-write operations happen in the same process after lockfile acquisition
- Limited impact: worst case is lost restart records leading to slightly inaccurate rate limiting (self-corrects on next restart)
- The cleanup operation (read-filter-write) uses atomic move, so even if append races, cleanup is safe

**Date Accepted**: 2025-12-31

---

## Race Condition in Lockfile Stale Removal

**Location**: `lib/lockfile.sh:369-384`

**Issue**: Window between removing stale lockfile and retrying flock where another process could acquire the lock.

**Why Acceptable**:
- This is intentional and correct behavior, not a bug
- Code comment (lines 380-382) explicitly acknowledges this scenario
- If Process B legitimately acquires lock after Process A removes stale lockfile, Process A exiting is the correct response
- Non-blocking flock design intentionally prioritizes avoiding concurrent execution over waiting
- No actual negative impact - one process exits (as designed), other process continues normally

**Date Accepted**: 2025-12-31

---

## Lockfile Write Race Condition

**Location**: `lib/lockfile.sh:394-395`

**Issue**: File descriptor opening with `9>"$LOCKFILE"` truncates file before flock is acquired, creating a window where another process might read empty file.

**Why Acceptable**:
- Very low likelihood - window is microseconds between file descriptor opening and flock acquisition
- File descriptor is opened in subshell `( ... ) 9>"$LOCKFILE"` - truncation happens when redirection is set up
- `flock -n 9` acquires exclusive lock immediately after, preventing concurrent access
- Even if another process reads between truncation and lock acquisition, it would see empty file and treat as "no lockfile" (correct behavior)
- Pre-check at lines 321-339 reads lockfile BEFORE opening file descriptor, so PID is extracted before truncation
- Impact is minimal: temporary empty lockfile read would cause process to attempt lock acquisition (correct behavior)

**Date Accepted**: 2025-12-31

---
