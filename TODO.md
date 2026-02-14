# TODO

This file tracks planned improvements and tasks for the UDM VPN Monitor project.

**Last Reviewed:** 2026-01-20  
**Last Updated:** 2026-01-20

## Human

- ~~Ask for internal IP for remote VPN as well~~ (done: install "Configure a location now?" prompts for remote internal IP)
- ~~Ask for internal IP for local UDM~~ (done: same flow prompts for LOCAL_UDM_IP)
- When creating a new location using the interactive installer it adds the locations to the end but also keeps the NYC locations at the beginning
- It seems like if it loads config again it starts over from the top for the networks it is testing
- Need to make sure that after code changes Cursor updates any related tests.
- Need Cursor to be better at grepping and replacing things, it often only fixes one or a few tests.
- Need to regularly identify and mitigate slow tests
- Interactive mode doesn't seem to trigger auto?
- If you don't enter a locaiton it seems like the app doesn't fully install/start (makes sense, but probably want to handle differently).

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