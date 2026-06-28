# Acceptable Risks

This document tracks bugs and potential issues that have been reviewed and determined to be acceptable risks given their low likelihood and/or limited impact.

**Purpose**: To prevent re-adding these items to bug reviews or issue trackers in the future.

---

## Race Condition Between `check_rate_limit()` and `record_restart()`

**Location**: `lib/state/global_state.sh:178-285` and `lib/state/global_state.sh:339-347`

**Issue**: `check_rate_limit()` reads `RESTART_COUNT_FILE` while `record_restart()` modifies it, potentially causing a race condition.

**Why Acceptable**:
- Very low likelihood (< 0.1% in normal operation) - lockfile mechanism prevents concurrent execution
- Both functions run sequentially in the same process after lockfile is acquired
- Limited impact: worst case is one extra restart per hour if race occurs exactly at limit boundary
- Self-correcting: subsequent executions see correct count

**Date Accepted**: 2025-12-31

---

## Race Condition in Lockfile Stale Removal

**Location**: `lib/lockfile.sh:396-400` (primary flock path) and `lib/lockfile.sh:462-476`, `492-494` (fallback retry)

**Issue**: Window between removing stale lockfile and retrying flock where another process could acquire the lock.

**Why Acceptable**:
- This is intentional and correct behavior, not a bug
- Code comment (lines 397-399) explicitly acknowledges this scenario on the flock path
- If Process B legitimately acquires lock after Process A removes stale lockfile, Process A exiting is the correct response
- Non-blocking flock design intentionally prioritizes avoiding concurrent execution over waiting
- No actual negative impact - one process exits (as designed), other process continues normally

**Date Accepted**: 2025-12-31

---

## Lockfile Write Race Condition

**Location**: `lib/lockfile.sh:302-314`, `373-379` (primary flock path); `lib/lockfile.sh:452-494` (fallback)

**Issue**: On the fallback path, atomic file creation has TOCTOU windows between check, read, and create. The primary flock path opens the lockfile with `exec 9<>"$LOCKFILE"` without truncating until after `flock -n` succeeds (lines 373-379), which mitigates the older pre-flock truncation race.

**Why Acceptable**:
- Primary flock path (UDM default): pre-check reads PID before open/flock (302-314); content is written only after lock acquisition (379)
- Fallback is used only when `flock` is unavailable (rare on UDM OS 4.3+); documented TOCTOU limits at lines 417-435
- Even if another process reads between open and flock, it sees prior lock content, not an empty file
- Impact is minimal: duplicate-start attempts exit via conflict handling (correct behavior)

**Date Accepted**: 2025-12-31

---

## Lockfile Acquisition Timing Window (Issue #18)

**Location**: `vpn-monitor.sh:617-618` and `lib/lockfile.sh:649-695`

**Issue**: Lockfile acquisition happens after script initialization (library sourcing, directory creation, config loading), creating a timing window where multiple instances can start before the lockfile is acquired. This can cause "Another instance is already running" warnings when cron triggers before the previous instance completes.

**Why Acceptable**:
- **Low impact**: System correctly handles duplicates (exits gracefully), no data corruption observed
- **Minimal race window**: Window is limited to initialization time (typically < 1 second)
- **Proper protection in place**: `flock` with non-blocking locks (`flock -n`) is already implemented and prevents actual concurrent execution
- **Dependency constraints**: Lockfile path depends on `STATE_DIR` which can be overridden in config, and lockfile error logging requires `LOG_FILE` which also depends on config. Moving lockfile earlier would require:
  - Using a fixed location (e.g., `/tmp`) which has reliability issues (cleared on reboot, doesn't respect custom STATE_DIR)
  - Minimal config parsing (fragile, duplicates logic, still needs directory creation)
  - Wrapper script (adds deployment complexity)
- **Complexity vs. benefit**: Fix complexity (MEDIUM-HIGH) outweighs the benefit given the low impact (log noise and minor wasted resources)
- **Self-limiting**: Race window is small and only occurs when cron triggers before previous instance completes, which is rare in normal operation

**Date Accepted**: 2026-01-13

---
