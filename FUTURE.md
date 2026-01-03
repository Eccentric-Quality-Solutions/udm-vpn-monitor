Considerations for the future, but want to avoid overarchitecting and premature optimization, as YAGNI.

- Optional migration script for state file location changes
    - When state files are moved (e.g., logs/ to state/), create optional migration script to move existing files
    - Low priority - system creates new files automatically, old files are ignored
    - Would preserve historical state (failure counters, restart counts) during location changes
    - Note: Current approach (recreate files) is simpler and acceptable

- Add timeout wrapping to ping commands in vpn-keepalive.sh
    - Currently, `vpn-keepalive.sh` uses ping commands without timeout wrapping (unlike `check_ping_connectivity()` in `lib/detection.sh`)
    - While less critical than the main monitoring script (it's a daemon), adding timeout wrapping would provide consistency and prevent potential hangs
    - The ping commands use `-W` flag which has its own timeout, but if the ping command itself hangs before starting, it could still block
    - This would follow the same pattern as `check_ping_connectivity()`: wrap ping with `timeout` command using calculated timeout value

- Log rate limiting
    - e.g., for duplicate messages occurring within x time span we only log once, then log again sum of messages received within timeframe at expiration of window
    - or we retroactively clean up logs when we notice there is a pattern of log entries recurring continuously or the same log entry repeatedly

- Use interface name instead of IP address for ping source selection
    - When LOCAL_UDM_IP is configured and confirmed to be on br0, use `ping -I br0` instead of `ping -I <ip_address>`
    - This is more reliable when the IP address exists on multiple interfaces, ensuring ping uses the correct interface
    - Requires: Verify IP is on br0 before using interface name, fallback to IP address if not on br0
    - Note: This was attempted but rolled back because routing issues need to be resolved first (some routes go through VTI interfaces, not br0)

- Reduce location name comment duplication in tests
    - The comment `# Location name is "TEST" (extracted from LOCATION_TEST_EXTERNAL)` is repeated 7 times in `test_recovery_tier3.sh`
    - Consider creating a helper function like `get_test_location_name()` or extracting location name dynamically from config
    - Could also create a helper function for setting up failure counters with correct location name to reduce duplication
    - Note: Current approach is explicit and readable, but could be DRYed up if this pattern spreads to more tests

- Optimize VPN checks when network partition is detected
    - Currently, VPN checks still run even when network partition is detected, which is wasteful
    - Consider skipping VPN checks entirely when partition is detected to avoid unnecessary work
    - This is a minor performance optimization, not a bug, as recovery code correctly skips recovery actions when partitioned
    - Recovery functions (`surgical_cleanup`, `full_restart`) already check partition state before acting, so this would be an additional optimization

- Investigate test failures
    - The "VPN flapping with rate limiting" test is still failing
    - May need to verify that test scripts are being regenerated with the latest fixes
    - Or investigate if there are other issues preventing the test from passing
    - Related to `NO_ESCALATE` validation bug fix and `values:0,1` rule parsing fix

- Extract permission restoration pattern to helper function
    - Tests that make directories/files unwritable repeat the same pattern:
      - Save original permissions
      - Make unwritable
      - Run test
      - Restore permissions
    - Could create `restore_permissions_after_test()` helper function
    - Current approach is explicit and readable, so this is a minor improvement
    - See `test_recovery_cascading_failures.sh`, `test_state_atomic_write_failures.sh` for examples

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

- Extract rule splitting logic to helper function
    - Rule splitting logic is duplicated in `validate_config_rules()` and `validate_config_var()`
    - Both functions split rules by `|||` separator with fallback to comma
    - Extract to `split_rules_string()` helper function to reduce duplication
    - Low priority: current duplication is acceptable but makes maintenance slightly harder
    - See `lib/config.sh` lines 1211-1226 and 1375-1390

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