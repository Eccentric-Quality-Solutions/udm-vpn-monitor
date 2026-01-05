Considerations for the future, but want to avoid overarchitecting and premature optimization, as YAGNI.

- Add timeout wrapping to ping commands in vpn-keepalive.sh
    - Currently, `vpn-keepalive.sh` uses ping commands without timeout wrapping (unlike `check_ping_connectivity()` in `lib/detection.sh`)
    - While less critical than the main monitoring script (it's a daemon), adding timeout wrapping would provide consistency and prevent potential hangs
    - The ping commands use `-W` flag which has its own timeout, but if the ping command itself hangs before starting, it could still block
    - This would follow the same pattern as `check_ping_connectivity()`: wrap ping with `timeout` command using calculated timeout value

- Log rate limiting
    - e.g., for duplicate messages occurring within x time span we only log once, then log again sum of messages received within timeframe at expiration of window
    - or we retroactively clean up logs when we notice there is a pattern of log entries recurring continuously or the same log entry repeatedly
    - Note: Partial fix implemented - `check_vpn_status()` combines diagnostic messages when both xfrm and ipsec checks fail (see `lib/detection.sh:2410,2474`)
    - Still needed: General message combining across codebase for related events (recovery sequences, detection failures, verification steps)

- Add tests for test isolation functionality itself
    - Test that `setup()` saves environment variables correctly (including empty strings)
    - Test that `teardown()` restores environment variables correctly
    - Test that unset variables remain unset after teardown
    - Test that sentinel value `__UNSET__` is handled correctly
    - Test that multiple tests in sequence don't interfere with each other
    - This would provide additional verification beyond the `verify_test_isolation.sh` script
    - Note: Current verification script provides good coverage, but unit tests would be more comprehensive

- Automate mock cleanup verification in CI/CD
    - Run `scripts/audit_mock_cleanup.sh` as part of CI/CD pipeline to catch missing cleanup calls early
    - Could be integrated into pre-commit hooks or as a CI check
    - Prevents regression of mock cleanup issues
    - Note: Audit script already exists and works well, just needs integration

- Standardize `handle_error_or_exit_fake_mode()` return value checking pattern
    - Some places check return value explicitly: `if ! handle_error_or_exit_fake_mode() ... then return 1`
    - Other places call it and then always `return 1` with a comment (works but inconsistent)
    - Standardize to explicit check pattern for consistency and clarity
    - Low priority: current code works correctly, this is a style consistency improvement
    - See `lib/config.sh` lines 1108, 1154, 1179, 1212, 1405 for examples that could be refactored
    - Pattern documented in `docs/CODE_PATTERNS.md` under "Fake Mode Support" section

- Add tests for uninstall.sh logs and state retention features
    - Tests for `--keep-logs` / `--remove-logs` flags
    - Tests for `--keep-state` / `--remove-state` flags
    - Tests for interactive prompts for logs/state directories
    - Tests for combined retention scenarios (config + logs + state)
    - Tests for verification of preserved logs/state directories
    - Note: Existing tests pass, but new retention features need coverage

- Add IPv6 support to anonymize-logs.sh
    - Currently, `anonymize-logs.sh` only handles IPv4 addresses
    - `analyze-logs.sh` already supports IPv6 addresses in logs
    - Would need to add IPv6 address extraction and anonymization functions
    - Low priority - IPv6 is less common in VPN logs, but would improve completeness
    - See `docs/ANONYMIZE_LOGS_REVIEW.md` for details

- Make routes persistent across reboots
    - Routes added via `ip addr add` are not persistent across reboots
    - Currently, routes are automatically re-added during config validation on each script execution, which handles the reboot case
    - For true persistence, routes could be added to a startup script or systemd service
    - This would ensure routes are available immediately on boot, before the first VPN monitor execution
    - Low priority - current approach (re-adding on each execution) works well and handles reboots

- Investigate SA count mismatch and asymmetric SA state
    - Issue: Inconsistent SA counts found during recovery - sometimes 2 SAs (bidirectional) are found, sometimes only 1 SA
    - After deleting 2 SAs, only 1 SA is sometimes reported as re-established
    - Enhanced diagnostics added (2026-01-04): `count_sas_for_peer()` now logs detailed SA information with direction (forward vs reverse)
    - SA re-establishment verification improved to track initial SA count and continue checking for multiple iterations
    - Session 7 finding: Only 1 SA found during recovery (not 2 bidirectional) - suggests asymmetric SA state or discovery issue
    - May explain CHICAGO routing issue: If only one direction SA exists, traffic may not flow properly
    - Investigation ongoing: Monitor diagnostic output to understand why only 1 SA exists in some cases vs 2 bidirectional SAs
    - Possible causes: Timing issue (second SA takes longer to establish), counting logic bug, incomplete re-establishment, or asymmetric SA state
    - Current status: Enhanced diagnostics in place to track SA state and direction; verification checks multiple times to catch second SA if it appears later
    - See: `analyze/LOG_ANALYSIS_ISSUES.md` Issue #15 for detailed analysis

- Investigate CHICAGO routing issue
    - Issue: CHICAGO location has routing issue where VPN tunnel is established (SA exists, bytes increasing) but ping checks timeout
    - Detection correctly identifies as "routing issue" but recovery cannot resolve it
    - Notable discrepancy: `ipsec status` shows "No connection found" for CHICAGO, but `ip xfrm state` shows SA exists - suggests asymmetric or incomplete connection state
    - Session 7 finding: Only 1 SA found during recovery (not 2 bidirectional) - may indicate asymmetric SA state preventing proper traffic flow
    - Correlation with SA count mismatch: Asymmetric SA state (only 1 direction) may explain routing failures
    - Root cause likelihood: 60% asymmetric SA state (only 1 direction SA exists), 30% network config, 10% code issue
    - Investigation needed: Check why only 1 SA exists in kernel vs 2 bidirectional SAs, investigate network config (firewall rules, routing tables, ACLs)
    - Action priority: Investigate SA state first (why only 1 SA exists vs 2 bidirectional), then network config
    - Likely root cause: Network configuration issue or asymmetric SA state, not code bug, but understanding SA state may enable proper recovery
    - Code changes may be needed: Possibly SA discovery/recovery logic if asymmetric state is the issue
    - See: `analyze/LOG_ANALYSIS_ISSUES.md` Issue #3 for detailed analysis