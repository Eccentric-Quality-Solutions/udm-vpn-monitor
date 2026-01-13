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

### Rate Limiting Refactoring - Test Updates
**Source:** Rate Limiting Refactoring (2026-01-12)
**Status:** Pending
**Action:** Update or remove tests that reference cooldown functionality
**Files Affected:**
- `tests/test_recovery_cooldown_rate_limit_interaction.sh` - Entire file needs update
- `tests/test_integration.sh` - Test "Cooldown period prevents immediate restart" needs update
- `tests/test_rapid_state_changes.sh` - Test "VPN flapping - cooldown expires but rate limit still active" needs update
- `tests/test_helper_functions.sh` - `check_cooldown` tests need update or removal
- `tests/fixtures/vpn_cooldown.bash` - Fixture may need update
**Effort:** MEDIUM (update multiple test files)
**Benefit:** Tests will pass after cooldown removal

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