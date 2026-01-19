Considerations for the future, but want to avoid overarchitecting and premature optimization, as YAGNI.

**Note:** Items marked with ✅ COMPLETED have been finished and can be considered resolved.

- Consider additional state keys in cleanup_peer_state()
  - Currently cleans up: failure_count, last_bytes, spi, idle_detected, connection_name
  - Missing: last_status_log, failure_type, recovery_method
  - Note: These keys may be intentionally excluded (cleared on recovery, not peer removal)
  - Low priority: Only relevant if cleanup_peer_state() is used in production (currently only in tests)
  - Decision needed: Should these be cleaned up when peers are removed, or are they intentionally location-scoped?

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

- Standardize `handle_error_or_exit_fake_mode()` return value checking pattern
    - Some places check return value explicitly: `if ! handle_error_or_exit_fake_mode() ... then return 1`
    - Other places call it and then always `return 1` with a comment (works but inconsistent)
    - Standardize to explicit check pattern for consistency and clarity
    - Low priority: current code works correctly, this is a style consistency improvement
    - See `lib/config.sh` lines 1108, 1154, 1179, 1212, 1405 for examples that could be refactored

- Standardize non-critical state write error handling
    - Currently 28+ instances of `atomic_write_file ... 2>/dev/null || true` silently ignore errors
    - Pattern used for non-critical statistics/logging state files (ping summaries, resource monitoring stats, network partition stats, etc.)
    - Issue: Silent failures can mask real problems (permission errors, disk full conditions)
    - Proposed: Add DEBUG-level logging for state file write failures in non-critical paths
    - Pattern: `if ! atomic_write_file "$file" "$value" 2>/dev/null; then log_message "DEBUG" "SYSTEM" "Failed to update state file: $file (non-fatal)"; fi`
    - Benefit: Better diagnostic visibility without cluttering logs (DEBUG level only visible when DEBUG=1)
    - Cost: MEDIUM - requires updating 28+ instances across codebase for consistency
    - Priority: LOW - current pattern works, failures are non-fatal, but diagnostic value would be helpful
    - Note: Pilot implementation added to `log_ping_summary_if_due()` in `ping_detection.sh` (2026-01-18)
    - See: `docs/reviews/ping_detection_review.md` issue #7 for detailed analysis

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

- Review and fix ip xfrm state mock patterns in tests
    - Issue: Many test mocks only handle `ip xfrm state` but not `ip -s xfrm state` (with -s flag)
    - `execute_xfrm_state_command` calls `ip -s xfrm state` first, then falls back to `ip xfrm state`
    - Tests that mock `ip` command need to handle both formats to work correctly
    - Found 43+ instances of old pattern `if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]` that may need updating
    - Helper functions like `mock_ip_xfrm_state()` already handle both formats correctly
    - Low priority: Tests may still work if they don't call `check_ipsec_phase2` or if fallback path is used
    - Action: Review tests that use inline `ip xfrm state` mocks and update to handle `-s` flag or use helper functions
    - Note: Fixed in `test_detection_ping_optional.sh` 2026-01-28

- Refactor error handling argument parsing to use explicit argument order
    - Current pattern: `handle_error "ERROR" "SYSTEM" "message" 2` (last arg is optional exit code)
    - Issue: Ambiguous when message ends with a number (e.g., "Retry count: 3" vs exit code "3")
    - Proposed: `handle_error "ERROR" "SYSTEM" "message" 2` (explicit 4th argument for exit code)
    - Benefit: Eliminates ambiguity, clearer API, easier to understand
    - Cost: Breaking change - requires updating all call sites across codebase
    - Priority: LOW - current pattern works, just has edge case limitations
    - Note: Duplication issue resolved 2026-01-27, but ambiguous design remains
    - See: `docs/reviews/logging_review.md` issue #2 for detailed analysis

- Improve error handling for file sourcing (stderr suppression refactor)
    - Current pattern: `source "${LIB_DIR}/constants.sh" 2>/dev/null || { fallback }` used in 47+ places
    - Issue: Suppressing stderr hides syntax errors and other real problems, making debugging harder
    - Impact: Low probability (files are stable), but medium impact if syntax errors occur silently
    - Proposed: Add simple error reporting when sourcing fails (echo to stderr directly, or use helper function)
    - Pattern example: `if ! source "${LIB_DIR}/constants.sh" 2>/dev/null; then echo "WARNING: Failed to source constants.sh, using fallback" >&2; fallback; fi`
    - Benefit: Better error visibility without complex process substitution or dependency on logging infrastructure
    - Cost: MEDIUM - requires updating 47+ instances across codebase for consistency
    - Priority: LOW - current pattern works, fallback values are correct, issue is rare
    - Note: Review identified issue in `config.sh` but pattern is widespread; consider codebase-wide refactor if prioritizing
    - See: `docs/reviews/config_sh_review.md` issue #2 for detailed analysis

- Remove redundant defensive fallbacks in state.sh and config.sh
    - Current state: `lib/state.sh` (lines 22-34) and `lib/config.sh` (lines 32-50) have defensive fallback constants
    - Issue: These fallbacks were needed to avoid "readonly variable already set" errors when constants.sh was sourced multiple times
    - Status: Now redundant since `lib/constants.sh` was made idempotent (2026-01-27)
    - Proposed: Remove fallback blocks, simplify to: `source "${LIB_DIR}/constants.sh" 2>/dev/null || { echo "ERROR: Failed to source constants.sh" >&2; exit 1; }`
    - Benefit: Reduces code duplication, simplifies maintenance, removes ~20 lines of redundant code
    - Cost: LOW - simple removal, but removes safety net if constants.sh file is missing/corrupted
    - Priority: LOW - fallbacks don't hurt and provide safety net for edge cases (file not found, syntax errors)
    - Note: Fallbacks are harmless but redundant. Consider removing if prioritizing code simplification.
    - See: Code review 2026-01-27 for constants.sh idempotency fix