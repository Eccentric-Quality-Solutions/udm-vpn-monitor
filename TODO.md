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

## High Priority

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