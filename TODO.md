# TODO

This file tracks planned improvements and tasks for the UDM VPN Monitor project.

**Last Reviewed:** 2026-01-15  
**Last Updated:** 2026-01-15

## Human

- Ask for internal IP for remote VPN as well
- ASk for internal IP for local UDM
- When creating a new location using the interactive installer it adds the locations to the end but also keeps the NYC locations at the beginning
- Is `VPN_NAME` as found in `vpn-monitor.conf` actually used anywhere?
- Should we support DNS names for pinging (e.g. DDNS)
    - Seems to get stuck when given invalid IP
- It seems like if it loads config again it starts over from the top for the networks it is testing
- Need to make sure that after code changes Cursor updates any related tests.
- Need Cursor to be better at grepping and replacing things, it often only fixes one or a few tests.
- Need to regularly identify and mitigate slow tests

## High Priority

### Documentation Updates - Fallback System Removal
**Source:** Code Review (2026-01-18)
**Status:** Pending
**Action:** Update documentation to reflect removal of fallback system
**Files:**
- `docs/adr/0030-centralized-fallback-functions.md` - Mark as deprecated/superseded
- `docs/CODE_PATTERNS.md` - Remove "Pattern: Centralized Fallback Functions" section (lines 2190-2372)
- `docs/ARCHITECTURE.md` - Remove `lib/fallbacks.sh` from module list (lines 982-999)
- `docs/code-diagrams/fallbacks-flow.md` - Deprecate or remove
**Priority:** High - Documentation should match codebase

## High Priority

### xfrm Recovery Refactoring - Test Fixes Needed
**Source:** Code Review (2026-01-18)
**Status:** In Progress
**Action:** Fix test mocks and verify refactored `delete_stale_sas()` function works correctly
**Issue:** After refactoring `delete_stale_sas()` into smaller functions, several xfrm recovery tests are failing. The refactoring is structurally correct, but test mocks may need updates to handle the new function call patterns.
**Tests Affected:**
- xfrm recovery - SA re-establishment verification succeeds
- xfrm recovery - Byte counter verification after re-establishment
- xfrm recovery - Multiple SAs deleted and re-established
- xfrm recovery - Policy deletion with DIR parameter
- And several others
**Next Steps:**
1. Verify mock_ip_xfrm_state_transition handles "ip xfrm state delete" correctly
2. Check if nameref variable passing is working correctly in test environment
3. Add debug logging to identify where deletion is failing
4. Verify all tests pass after fixes

### System-Wide Failure Detection - Test Coverage
**Source:** System-Wide Failure Detection Implementation (2026-01-12)
**Status:** Pending
**Action:** Add tests for system-wide failure detection and recovery coordination
**Test Cases Needed:**
- All locations fail simultaneously → system-wide failure detected
- Majority of locations fail → system-wide failure detected (if threshold < 100)
- Individual failures → no system-wide failure detected
- System-wide failure resolved when failures drop below threshold
- Only coordinator location attempts recovery during system-wide failure
- Non-coordinator locations skip recovery during system-wide failure
- Coordinator cleared when system-wide failure resolved
- System-wide failure state persists across script runs
- Corrupted state files are recovered
- Detection can be disabled via `ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=0`
- Threshold configuration works (50%, 80%, 100%)
- Coordination can be disabled via `COORDINATE_SYSTEM_WIDE_RECOVERY=0`
**Effort:** MEDIUM (add comprehensive test coverage)
**Benefit:** Ensures critical new functionality works correctly

### System-Wide Failure Detection - Fix Failing Test
**Source:** Optimization - Removing Double VPN Checking (2026-01-12)
**Status:** Pending
**Action:** Debug and fix failing test: `system-wide failure detection: all locations fail simultaneously → system-wide failure detected`
**Issue:** Test sets failure counts manually but detection isn't working
**Investigation Needed:**
- Verify location names match between test setup and detection code
- Verify IP addresses match between test setup and detection code
- Verify detection function is being called with correct data
- Check if failure counts are being read correctly
**Effort:** LOW-MEDIUM (debug test, fix if needed)
**Benefit:** Ensures optimization works correctly

### System-Wide Failure Detection - Documentation Updates
**Source:** System-Wide Failure Detection Implementation (2026-01-12)
**Status:** Pending
**Action:** Update architecture documentation to document system-wide failure detection
**Tasks:**
- Update `docs/ARCHITECTURE.md` to document system-wide failure detection mechanism
- Document state files in system-wide state section
- Document coordination mechanism
- Consider creating ADR for system-wide failure detection decision
**Effort:** LOW (documentation updates)
**Benefit:** Improves maintainability and understanding

### Rate Limiting Refactoring - New Test Coverage
**Source:** Rate Limiting Refactoring (2026-01-12)
**Status:** Pending
**Action:** Add tests for new rate limiting parameters
**Test Cases Needed:**
- Minimum restart interval blocks restart when too soon
- Minimum restart interval allows restart when enough time has passed
- Minimum interval of 0 disables the check
- Configurable window (15 min vs 60 min) allows different restart counts
- Backward compatibility: `MAX_RESTARTS_PER_HOUR` migration
**Effort:** MEDIUM (add comprehensive test coverage)
**Benefit:** Ensures new functionality works correctly

## Medium Priority

### 5. Add Explicit File Permissions
**Source:** Codebase Review (Section 8.2.2)
**Status:** Pending
**Action:** Add `chmod` calls for state and log files (e.g., `chmod 600` for state files, `chmod 644` for log files)
**Effort:** LOW (add a few lines)
**Benefit:** Explicit permissions improve security posture
**Note:** Currently, file permissions are set by default umask. Adding explicit `chmod` calls would make permissions more predictable and secure, especially for sensitive state files.

### 8. Automated Documentation Checks
**Status:** Pending
**Action:** Consider adding automated checks to detect duplicated content
**Action:** Consider adding tests to verify reference links are valid
**Action:** Schedule periodic reviews to ensure documentation stays aligned with recommendations
**Effort:** MEDIUM (implement checks, integrate into CI/CD)
**Benefit:** Improves documentation quality and consistency.

---

**Note:** For additional future considerations that are less immediate, see [FUTURE.md](FUTURE.md).

#### 3. **Complex Quote Parsing Logic Could Be Simplified**

**Location:** Lines 186-320 (`parse_quoted_value()`)

**Problem:**
The quote parsing function is 135 lines long with complex character-by-character parsing. While it works correctly, it's hard to maintain and test.

**Current Approach:**
- Character-by-character parsing with state tracking
- Separate logic for single quotes vs double quotes
- Complex escape handling

**Issues:**
1. Long function (135 lines) is hard to understand and maintain
2. Character-by-character parsing is error-prone
3. Duplicate logic for single vs double quotes
4. Hard to test all edge cases

**Recommendation:**
Consider using bash's built-in quote removal capabilities where possible, or at least extract helper functions:

```bash
# Helper: Parse double-quoted string
parse_double_quoted() {
	local input="$1"
	local result=""
	local i=0
	local len=${#input}
	local escaped=false
	
	while [[ $i -lt $len ]]; do
		local char="${input:$i:1}"
		if [[ "$escaped" == true ]]; then
			# Handle escaped characters
			case "$char" in
				\\|\"|\') result="${result}${char}" ;;
				*) result="${result}\\${char}" ;;
			esac
			escaped=false
		elif [[ "$char" == "\\" ]]; then
			escaped=true
		elif [[ "$char" == "\"" ]]; then
			# Closing quote
			break
		else
			result="${result}${char}"
		fi
		i=$((i + 1))
	done
	
	echo "$result"
	return 0
}

# Helper: Parse single-quoted string (no escaping)
parse_single_quoted() {
	local input="$1"
	local result=""
	local i=0
	local len=${#input}
	
	while [[ $i -lt $len ]]; do
		local char="${input:$i:1}"
		if [[ "$char" == "'" ]]; then
			break
		fi
		result="${result}${char}"
		i=$((i + 1))
	done
	
	echo "$result"
	return 0
}
```