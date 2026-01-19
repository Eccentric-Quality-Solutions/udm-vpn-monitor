Considerations for the future, but want to avoid overarchitecting and premature optimization, as YAGNI.

**Note:** Items marked with ✅ COMPLETED have been finished and can be considered resolved.

- Optimize detection module sourcing (optional)
  - Currently, modules source dependencies even when already sourced by parent `detection.sh`
  - Could add checks to avoid redundant sourcing: `if ! type validate_ipv4 >/dev/null 2>&1; then source ...; fi`
  - Low priority: bash sourcing is fast and idempotent, redundancy is minimal overhead
  - Benefit: Slightly faster sourcing, cleaner dependency graph
  - Effort: LOW (add type checks before sourcing)
  - Note: Split completed 2026-01-15, this is a post-split optimization opportunity

- Enhanced recovery type analysis in log reports
    - Add recovery type breakdown to report summary statistics (app-managed vs self-healed percentages)
    - Add recovery type trends over time analysis (track how recovery types change over time)
    - Add location-specific recovery type statistics (which locations require more intervention)
    - Note: Basic recovery type distinction implemented in analyze-logs.sh (2026-01-06)

- Log rate limiting
    - e.g., for duplicate messages occurring within x time span we only log once, then log again sum of messages received within timeframe at expiration of window
    - or we retroactively clean up logs when we notice there is a pattern of log entries recurring continuously or the same log entry repeatedly
    - Note: Partial fix implemented - `check_vpn_status()` combines diagnostic messages when both xfrm and ipsec checks fail (see `lib/detection.sh:2410,2474`)
    - Still needed: General message combining across codebase for related events (recovery sequences, detection failures, verification steps)

- Standardize output parameter passing patterns
    - Currently uses mixed patterns: namerefs for arrays, eval for scalars
    - Consider standardizing on namerefs for all output parameters (scalars and arrays)
    - Would improve consistency and reduce reliance on eval
    - Note: Refactoring of `delete_stale_sas()` uses namerefs for scalars, which is a step in this direction
    - Benefit: More consistent codebase, easier to understand
    - Effort: MEDIUM (requires updating multiple functions)

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

- System-wide failure detection enhancements
  - Consider making coordinator selection more robust (e.g., use location order instead of first-check-wins)
  - Consider adding metrics/statistics for system-wide failures (e.g., count, duration, frequency)
  - Consider alerting integration for system-wide failures (e.g., email, webhook, syslog)
  - Consider different recovery strategies for system-wide failures (e.g., infrastructure-level recovery like restarting IPsec daemon, checking kernel state)
  - Consider rate limiting exceptions for system-wide failures (allow more restarts during system-wide failures)
  - Note: Basic system-wide failure detection implemented 2026-01-12

- Continue migrating test data to use test data helpers
    - Many test files still have embedded xfrm state output, ipsec status output, and config files
    - Files with significant embedded data include: `test_recovery.sh`, `test_detection.sh`, `test_integration_location.sh`, and others
    - Pattern is established: use `generate_xfrm_state_output()`, `generate_config_file()`, etc. from `helpers/test_data`
    - Benefits: Centralized maintenance, consistency, easier to update test data formats
    - Note: Migration started 2026-01-11 with `test_recovery_partial_failures.sh` and `test_config.sh`
    - Note: Key instances migrated 2026-01-27 in `test_recovery.sh`, `test_detection.sh`, and `test_integration_location.sh`
    - Pattern for mock scripts: Generate output using helpers, store in file, use placeholders in mock script, replace with sed after creation
    - Note: Additional migrations completed 2026-01-28: Migrated 2 more test cases in `test_recovery.sh`:
      - "xfrm recovery - Verification timeout exceeded" - migrated static xfrm state outputs
      - "xfrm recovery - Mixed SAs with and without marks" - migrated static outputs (including mark handling via sed post-processing)
    - Remaining: ~110 embedded instances in `test_recovery.sh` (mostly complex dynamic cases with calculated counters, marks, or state transitions), can be migrated gradually

- Rate limiting enhancements
  - Consider per-location rate limiting (currently global)
  - Add rate limit metrics tracking (track rate limit hits for monitoring)
  - Dynamic rate limiting (adjust limits based on failure patterns)
  - Note: Basic rate limiting refactored 2026-01-12 to remove cooldown and add configurable window + minimum interval

- Migrate more tests to use test data helpers
    - Many test files still have embedded test data (xfrm state, ipsec status, config templates)
    - Gradual migration as tests are updated or refactored
    - See `MOCK_REFACTORING_OPPORTUNITIES.md` for candidates (file does not exist)
    - Test data helpers available in `helpers/test_data.bash` and `tests/data/`
    - Low priority: existing tests work fine, migration is optional improvement
    - Status: Test data management infrastructure completed 2026-01-11
    - Current state: Migration in progress - significant progress made 2026-01-27:
      - `test_detection_error_recovery.sh`: Migrated static xfrm outputs to use helpers
      - `test_recovery_tier2.sh`: Migrated ipsec status outputs to use helpers
      - `test_detection.sh`: Already uses helpers for most cases (some edge cases remain with special formats)
      - `test_recovery.sh`: Still has many embedded outputs, mostly in dynamic contexts or with special fields (e.g., "mark" attribute)
        - Many tests already use helpers for static initial states (pattern established)
        - Remaining embedded outputs are mostly in dynamic mock scripts that generate different outputs based on state
        - Some embedded outputs include special fields (e.g., "mark") that helpers don't currently support
    - Note: This is a gradual, ongoing migration task. Dynamic outputs and special fields may require helper extensions in the future.

- Add module-level unit tests for recovery modules
  - Each recovery module (`recovery_verification.sh`, `recovery_state.sh`, `recovery_orchestration.sh`, `ipsec_recovery.sh`, `xfrm_recovery.sh`) could have focused unit tests
  - Would allow testing modules in isolation without full integration test setup
  - Low priority: existing integration tests cover functionality well
  - Benefit: Faster test execution, easier debugging of module-specific issues
  - Status: Decomposition completed 2026-01-11, enables this future enhancement
  - Pattern documented in `docs/CODE_PATTERNS.md` under "Fake Mode Support" section
  - Current coverage:
    - `recovery_verification.sh`: ⚠️ No dedicated unit tests (functions tested via integration tests in `test_recovery.sh`)
    - `recovery_state.sh`: ⚠️ No dedicated unit tests (functions tested via integration tests)
    - `recovery_orchestration.sh`: ⚠️ Partial coverage (some unit tests for `select_recovery_strategy` in `test_helper_functions.sh` and `test_recovery.sh`)
    - `ipsec_recovery.sh`: ⚠️ No dedicated unit tests (functions tested via integration tests)
    - `xfrm_recovery.sh`: ⚠️ No dedicated unit tests (functions tested via integration tests)

- Add module-level unit tests for config modules
  - Each config module (`config_loading.sh`, `config_validation.sh`, `config_defaults.sh`, `location_parsing.sh`) could have focused unit tests
  - Would allow testing modules in isolation without full integration test setup
  - Low priority: existing integration tests cover functionality well
  - Benefit: Faster test execution, easier debugging of module-specific issues
  - Note: Decomposition completed 2026-01-11, enables this future enhancement
  - Current coverage:
    - `location_parsing.sh`: ✅ Has dedicated unit tests in `test_config_location.sh`
    - `config_defaults.sh`: ⚠️ Partial coverage (some tests in `test_config_schema.sh` and `test_helper_functions.sh`)
    - `config_loading.sh`: ⚠️ Mostly integration tests, not focused module-level unit tests
    - `config_validation.sh`: ⚠️ Partial coverage (some tests in `test_config_validation.sh`)


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

- Improve lockfile removal failure test reliability
    - Current test "lockfile cleanup fails - lockfile removal fails" attempts to make directory read-only during script execution
    - This may not work reliably on all systems due to timing and permission handling
    - Consider finding a better way to simulate lockfile removal failures (e.g., mock `rm` command, use filesystem that doesn't support removal, etc.)
    - Low priority: Current test still verifies that script doesn't crash, which is the important behavior
    - Note: Test includes comment acknowledging limitation - "Note: This may not work on all systems, but tests the error handling path"
    - See: `tests/test_lockfile.sh:1031-1063` for current implementation

- Make network partition summary interval configurable
    - Currently fixed at 1 hour (3600 seconds)
    - Could be made configurable similar to `PING_SUMMARY_INTERVAL_MINUTES` if users want different intervals
    - Example: `NETWORK_PARTITION_SUMMARY_INTERVAL_MINUTES=60` (default: 60, range: 1-1440)
    - Low priority: Current 1-hour interval meets requirements
    - Note: Pattern established 2026-01-15 with network partition statistics tracking

- Add statistics tracking for resource monitoring
    - Currently no visibility into whether resource monitoring checks (CPU, RAM, disk) are running successfully
    - Similar issue to network partition checks - only logs when resources are constrained, no visibility into successful checks
    - Would track: CPU/RAM/disk check successes/failures, and constraint events
    - Hourly summary: "Resource monitoring summary: CPU checks succeeded X times, failed Y times; RAM checks succeeded X times, failed Y times; Disk checks succeeded X times, failed Y times; CPU constrained Z times; RAM constrained Z times; Disk critical Z times"
    - Medium priority: Provides visibility into critical system checks
    - Note: Pattern established 2026-01-15 with network partition statistics tracking
    - See: `docs/working/STATISTICS_TRACKING_CANDIDATES.md` for detailed analysis

- Review and fix ip xfrm state mock patterns in tests
    - Issue: Many test mocks only handle `ip xfrm state` but not `ip -s xfrm state` (with -s flag)
    - `execute_xfrm_state_command` calls `ip -s xfrm state` first, then falls back to `ip xfrm state`
    - Tests that mock `ip` command need to handle both formats to work correctly
    - Found 43+ instances of old pattern `if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]` that may need updating
    - Helper functions like `mock_ip_xfrm_state()` already handle both formats correctly
    - Low priority: Tests may still work if they don't call `check_ipsec_phase2` or if fallback path is used
    - Action: Review tests that use inline `ip xfrm state` mocks and update to handle `-s` flag or use helper functions
    - Note: Fixed in `test_detection_ping_optional.sh` 2026-01-28

- Consider using `read_counter_file()` in `ping_detection.sh` for `ping_count` reading
    - `ping_detection.sh` lines 123-128 use manual pattern for reading counter file
    - Could use shared `read_counter_file()` helper for consistency
    - Low priority: Only one instance, works correctly as-is
    - Benefit: Consistency with other counter reading patterns
    - Effort: LOW (replace 6 lines with 1 line)
    - Note: `read_counter_file()` added to `common.sh` 2025-01-27

- Refactor error handling argument parsing to use explicit argument order
    - Current pattern: `handle_error "ERROR" "SYSTEM" "message" 2` (last arg is optional exit code)
    - Issue: Ambiguous when message ends with a number (e.g., "Retry count: 3" vs exit code "3")
    - Proposed: `handle_error "ERROR" "SYSTEM" "message" 2` (explicit 4th argument for exit code)
    - Benefit: Eliminates ambiguity, clearer API, easier to understand
    - Cost: Breaking change - requires updating all call sites across codebase
    - Priority: LOW - current pattern works, just has edge case limitations
    - Note: Duplication issue resolved 2026-01-27, but ambiguous design remains
    - See: `docs/reviews/logging_review.md` issue #2 for detailed analysis