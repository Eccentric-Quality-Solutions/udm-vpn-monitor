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