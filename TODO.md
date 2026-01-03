# TODO

This file tracks planned improvements and tasks for the UDM VPN Monitor project.

## Medium Priority

### 1. Document Config Parsing Behavior
**Source:** Codebase Review (Section 8.2.1)  
**Action:** Document whether partial configuration loading in `lib/config.sh:safe_parse_config_file()` is intentional or should fail fast  
**Effort:** LOW (documentation only)  
**Benefit:** Clarifies expected behavior for future maintainers

### 2. Add Explicit File Permissions
**Source:** Codebase Review (Section 8.2.2)  
**Action:** Add `chmod` calls for state and log files (e.g., `chmod 600` for state files)  
**Effort:** LOW (add a few lines)  
**Benefit:** Explicit permissions improve security posture

### 3. Automated Documentation Checks
**Action:** Consider adding automated checks to detect duplicated content  
**Action:** Consider adding tests to verify reference links are valid  
**Action:** Schedule periodic reviews to ensure documentation stays aligned with recommendations


## Low Priority

### 4. Refactor Long Functions (Opportunistic)
**Source:** Codebase Review (Section 8.3.1)  
**Action:** Refactor `attempt_xfrm_recovery()`, `monitor_location()`, `parse_location_config()` when modifying them  
**Effort:** MEDIUM (when touching these functions)  
**Benefit:** Improves maintainability and testability  
**Note:** Only refactor when already modifying these functions

### 5. Extract Common Test Patterns
**Source:** Codebase Review (Section 8.3.2)  
**Action:** Extract mock command creation patterns if duplication exceeds 10 occurrences  
**Effort:** LOW (when needed)  
**Benefit:** Reduces test maintenance burden

### 6. Add Unit Tests for Safe Timestamp Functions
**Action:** Add comprehensive unit tests for `validate_timestamp()`, `safe_timestamp_subtract()`, `safe_timestamp_add()`, and `safe_timestamp_diff()` to cover edge cases:
   - Invalid inputs (negative, too large, non-numeric, empty)
   - Overflow scenarios (addition exceeding max timestamp)
   - Underflow scenarios (subtraction resulting in negative)
   - Boundary conditions (year 2100 limit, zero values)

### 7. Add Tests for anonymize-logs.sh
**Source:** Code Review (ANONYMIZE_LOGS_REVIEW.md)  
**Action:** Create test file `tests/test_anonymize_logs.sh` similar to `test_analyze_logs.sh` with tests for:
   - Basic anonymization (IPs and locations)
   - Consistency across multiple runs
   - Empty file handling
   - Missing file error handling
   - Unreadable file error handling
   - Help/usage output
   - Verbose mode output
   - Output to file vs stdout
**Effort:** MEDIUM (create test file with 8-10 test cases)  
**Benefit:** Ensures anonymization script works correctly and maintains consistency

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
