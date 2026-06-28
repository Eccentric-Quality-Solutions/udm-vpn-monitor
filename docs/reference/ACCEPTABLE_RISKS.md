# Acceptable Risks

This document tracks bugs and potential issues that have been reviewed and determined to be acceptable risks given their low likelihood and/or limited impact.

**Purpose**: To prevent re-adding these items to bug reviews or issue trackers in the future.

---

## Fallback Lockfile Stale Removal Race

**Location**: `lib/lockfile.sh:462-508` (`acquire_lockfile_fallback`)

**Issue**: On the fallback path (used only when `flock` is unavailable), there is a window between removing a stale lockfile and retrying atomic creation where another process could acquire the lock.

**Not applicable on primary path**: `acquire_lockfile_flock` reclaims stale locks via `flock` on the existing inode (lines 373-387) and does not remove the path after a failed `flock` (lines 396-400). Concurrent stale-lock contention on the flock path was fixed; see regression tests in `tests/test_lockfile.sh` (`acquire_lockfile_flock: loser must not unlink the winner's lockfile path`, `concurrent stale-lock contenders allow only one winner`).

**Why Acceptable (fallback only)**:
- Fallback is used only when `flock` is unavailable (rare on UDM OS 4.3+)
- If Process B legitimately acquires the lock after Process A removes a stale lockfile, Process A exiting is the correct response
- No actual negative impact — one process exits (as designed), the other continues normally

**Date Accepted**: 2025-12-31 (updated 2026-06-28 — primary flock path no longer applies)

---

## Lockfile Write Race Condition

**Location**: `lib/lockfile.sh:302-314`, `373-379` (primary flock path); `lib/lockfile.sh:452-508` (fallback)

**Issue**: On the fallback path, atomic file creation has TOCTOU windows between check, read, and create. The primary flock path opens the lockfile with `exec 9<>"$LOCKFILE"` without truncating until after `flock -n` succeeds (lines 373-379), which mitigates the older pre-flock truncation race.

**Why Acceptable**:
- Primary flock path (UDM default): pre-check reads PID before open/flock (302-314); content is written only after lock acquisition (379)
- Fallback is used only when `flock` is unavailable (rare on UDM OS 4.3+); documented TOCTOU limits at lines 417-435
- Even if another process reads between open and flock, it sees prior lock content, not an empty file
- Impact is minimal: duplicate-start attempts exit via conflict handling (correct behavior)

**Date Accepted**: 2025-12-31

---

## Lockfile Acquisition Timing Window (Issue #18)

**Location**: `vpn-monitor.sh:106-153` (top-level init before lock) and `vpn-monitor.sh:628`; `lib/lockfile.sh:649-695` (`acquire_lockfile`)

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

## Removed: Rate Limit Read/Write Race

**Previously**: Race between `check_rate_limit()` reading and `record_restart()` modifying `RESTART_COUNT_FILE`.

**Status**: Mitigated — no longer listed as an acceptable risk. `record_restart()` uses append-only writes (no read-modify-write); `compact_restart_count_file()` runs once per run at startup under the main lock; `check_rate_limit()` and `record_restart()` run sequentially in the same process after lock acquisition. Same pattern applies to Tier 2 rate limiting (`record_tier2_recovery()` / `check_tier2_rate_limit()`).

**Date Removed**: 2026-06-28
