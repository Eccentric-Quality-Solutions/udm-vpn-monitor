# TODO

This file tracks planned improvements and tasks for the UDM VPN Monitor project.

## Medium Priority

### 1. Update Mock IP Commands in Tests to Handle Both Variants
**Source:** Bug fix (2026-01-15)
**Action:** Update other tests in `test_detection_idle.sh` (and potentially other test files) to handle both `ip xfrm state` and `ip -s xfrm state` in mocks
**Effort:** LOW (update mock scripts)
**Benefit:** Ensures tests work correctly regardless of which command variant is called first
**Note:** `get_xfrm_state_for_peer()` tries `ip -s xfrm state` first, then falls back to `ip xfrm state`. The `mock_ip_xfrm_state()` helper function in `test_helper.bash` already handles both variants, but individual tests that create custom mocks should also handle both for consistency and reliability.

### 2. Add Explicit File Permissions
**Source:** Codebase Review (Section 8.2.2)
**Action:** Add `chmod` calls for state and log files (e.g., `chmod 600` for state files)
**Effort:** LOW (add a few lines)
**Benefit:** Explicit permissions improve security posture

### 3. Extract Duplicate Awk Deduplication Logic
**Source:** Code Review (2026-01-15)
**Action:** Extract duplicate awk deduplication logic in `get_xfrm_state_for_peer()` to helper function
**Effort:** LOW (extract ~20 lines to helper function)
**Benefit:** Reduces code duplication, improves maintainability
**Note:** Not critical for production - code works correctly as-is. The awk script appears twice (lines 631-651 and 674-690) with identical logic for deduplicating SA blocks. Can be refactored when touching this function next.

### 4. Automated Documentation Checks
**Action:** Consider adding automated checks to detect duplicated content
**Action:** Consider adding tests to verify reference links are valid
**Action:** Schedule periodic reviews to ensure documentation stays aligned with recommendations


## Low Priority

### 5. Refactor Long Functions (Opportunistic)
**Source:** Codebase Review (Section 8.3.1)
**Action:** Refactor `attempt_xfrm_recovery()`, `monitor_location()`, `parse_location_config()` when modifying them
**Effort:** MEDIUM (when touching these functions)
**Benefit:** Improves maintainability and testability
**Note:** Only refactor when already modifying these functions

### 6. Add Unit Tests for Safe Timestamp Functions
**Action:** Add comprehensive unit tests for `validate_timestamp()`, `safe_timestamp_subtract()`, `safe_timestamp_add()`, and `safe_timestamp_diff()` in `lib/common.sh` to cover edge cases:
   - Invalid inputs (negative, too large, non-numeric, empty)
   - Overflow scenarios (addition exceeding max timestamp)
   - Underflow scenarios (subtraction resulting in negative)
   - Boundary conditions (year 2100 limit, zero values)
**Effort:** MEDIUM (create test file with comprehensive edge case coverage)
**Benefit:** Ensures timestamp operations handle edge cases correctly and prevent bugs

## Optional / Future

### 7. State File Migration Cleanup (Optional)
**Action:** After state file migration (failure_counter and restart_count moved from logs/ to state/), existing installations may have old files in logs/ directory. These can be manually cleaned up after verifying the new system works:
   - Old files: `logs/failure_counter_*` and `logs/restart_count`
   - Impact: Low - system creates new files automatically, old files are ignored
   - Action: Optional cleanup script or manual removal after verification

### 8. Documentation Versioning
**Action:** Consider versioning for major documentation changes

---

**Note:** For additional future considerations that are less immediate, see [FUTURE.md](FUTURE.md).
