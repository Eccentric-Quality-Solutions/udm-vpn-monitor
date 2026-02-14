Considerations for the future, but want to avoid overarchitecting and premature optimization, as YAGNI.

**Note:** Items marked with ✅ COMPLETED have been finished and can be considered resolved.

- Deploy scripts: tail -f moved into deploy-to-udm.sh (2026-02-14); now uses same SSH_USERNAME as deploy. See deploy-advanced-auth branch for --password-file/env-var options if automation is needed later.

- Deploy registry: Semantic version comparison (e.g. skip if deployed 0.8.1 when deploying 0.8.0) could be added to `host_has_version()`. Currently exact match only.

- Reintroduce `lib/state/location_state.sh` only if we add location-specific state not tied to individual peers (e.g. location-level flags or aggregates). Removed 2026-02-14 as an empty stub; per-location state is currently handled via per-peer state with location as a parameter.

- Consider routing issue detection during ipsec status fallback periods
  - Current state: When xfrm unavailable, system falls back to ipsec status (no byte counters)
  - Issue: Routing issues (ping failures) may go undetected longer when byte counters unavailable
  - Gap: During ipsec status fallback, routing_issue is detected but silently ignored if primary_check_passed=1
  - Proposed: Consider treating persistent ping failures (e.g., 3+ consecutive) as VPN failures even when SA exists and byte counters unavailable
  - Benefit: Better detection of routing issues during fallback periods
  - Cost: MEDIUM - requires tracking ping failure duration and adjusting failure detection logic
  - Priority: LOW - current design is reasonable trade-off, routing issues often resolve themselves
  - See: ADR-0014 already documents "May Miss Some Issues" but this is a more specific gap during fallback periods

- Enhanced recovery type analysis in log reports
    - Add recovery type breakdown to report summary statistics (app-managed vs self-healed percentages)
    - Add recovery type trends over time analysis (track how recovery types change over time)
    - Add location-specific recovery type statistics (which locations require more intervention)
    - Note: Basic recovery type distinction implemented in analyze-logs.sh (2026-01-06)

- Log rate limiting
    - e.g., for duplicate messages occurring within x time span we only log once, then log again sum of messages received within timeframe at expiration of window
    - or we retroactively clean up logs when we notice there is a pattern of log entries recurring continuously or the same log entry repeatedly

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
    - See `lib/config/` modules (config_loading.sh, config_validation.sh, location_parsing.sh, config_defaults.sh) for examples that could be refactored

- DNS resolution enhancements
    - Add DNS cache TTL support to handle DNS changes during long-running scripts
    - Add IPv6 resolution support (currently only IPv4 via `ahostsv4` and `host -t A`)
    - Consider partial resolution for multiple internal IPs (continue with successfully resolved IPs instead of failing entirely)
    - Add DNS resolution retry logic for transient DNS failures
    - Note: Basic DNS support completed 2026-01-27, these are enhancements for edge cases

- System-wide failure detection enhancements
  - Consider making coordinator selection more robust (e.g., use location order instead of first-check-wins)
  - Consider adding metrics/statistics for system-wide failures (e.g., count, duration, frequency)
  - Consider alerting integration for system-wide failures (e.g., email, webhook, syslog)
  - Consider different recovery strategies for system-wide failures (e.g., infrastructure-level recovery like restarting IPsec daemon, checking kernel state)
  - Consider rate limiting exceptions for system-wide failures (allow more restarts during system-wide failures)

- Rate limiting enhancements
  - Consider per-location rate limiting (currently global)
  - Add rate limit metrics tracking (track rate limit hits for monitoring)
  - Dynamic rate limiting (adjust limits based on failure patterns)
  - Note: Basic rate limiting refactored 2026-01-12 to remove cooldown and add configurable window + minimum interval

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
    - See: `docs/reference/CODE_REVIEW_LESSONS_LEARNED.md` for related analysis

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
    - See: `docs/reference/CODE_REVIEW_LESSONS_LEARNED.md` for related analysis

- Improve lockfile removal failure test reliability
    - Current test "lockfile cleanup fails - lockfile removal fails" attempts to make directory read-only during script execution
    - This may not work reliably on all systems due to timing and permission handling
    - Consider finding a better way to simulate lockfile removal failures (e.g., mock `rm` command, use filesystem that doesn't support removal, etc.)
    - Low priority: Current test still verifies that script doesn't crash, which is the important behavior
    - Note: Test includes comment acknowledging limitation - "Note: This may not work on all systems, but tests the error handling path"
    - See: `tests/test_lockfile.sh:966-1010` for current implementation

- Make network partition summary interval configurable
    - Currently fixed at 1 hour (3600 seconds)
    - Could be made configurable similar to `PING_SUMMARY_INTERVAL_MINUTES` if users want different intervals
    - Example: `NETWORK_PARTITION_SUMMARY_INTERVAL_MINUTES=60` (default: 60, range: 1-1440)
    - Low priority: Current 1-hour interval meets requirements
    - Note: Pattern established 2026-01-15 with network partition statistics tracking

- Review and fix ip xfrm state mock patterns in tests
    - Issue: Many test mocks only handle `ip xfrm state` but not `ip -s xfrm state` (with -s flag)
    - `execute_xfrm_state_command()` in `lib/detection/xfrm_detection.sh` calls `ip -s xfrm state` first, then falls back to `ip xfrm state`
    - Tests that mock `ip` command need to handle both formats to work correctly
    - Found 43+ instances of old pattern `if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]` that may need updating
    - Helper functions like `mock_ip_xfrm_state()` already handle both formats correctly
    - Low priority: Tests may still work if they don't call `check_ipsec_phase2` or if fallback path is used
    - Action: Review tests that use inline `ip xfrm state` mocks and update to handle `-s` flag or use helper functions
    - Note: Fixed in `test_detection_ping_optional.sh` 2026-01-28

- Refactor error handling argument parsing to use explicit argument order
    - Current: 3 or 4 args; last arg is optional exit code. Example: `handle_error "ERROR" "SYSTEM" "message"` or `handle_error "ERROR" "SYSTEM" "message" 2`. Parser cannot tell whether a 4th token is exit code or part of the message.
    - Issue: Ambiguous when message ends with a number (e.g., `"Retry count: 3"` parsed as exit code 3).
    - Proposed: Always 4 arguments; 4th is always exit code. Example: `handle_error "ERROR" "SYSTEM" "message" 2`. No optional 4th arg—callers must pass exit code (or a sentinel for "use default"), so message can safely contain numbers.
    - Benefit: Eliminates ambiguity, clearer API, easier to understand
    - Cost: Breaking change - requires updating all call sites across codebase
    - Priority: LOW - current pattern works, just has edge case limitations
    - Note: Duplication issue resolved 2026-01-27, but ambiguous design remains
    - See: `docs/reference/CODE_REVIEW_LESSONS_LEARNED.md` for related analysis

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
    - See: `docs/CODEBASE_REVIEW.md` for related analysis

- Remove redundant defensive fallbacks in state.sh and config.sh
    - Current state: `lib/state.sh` (lines 21-33) and `lib/config.sh` (lines 31-50) have defensive fallback constants
    - Issue: These fallbacks were needed to avoid "readonly variable already set" errors when constants.sh was sourced multiple times
    - Status: Now redundant since `lib/constants.sh` was made idempotent (2026-01-27)
    - Proposed: Remove fallback blocks, simplify to: `source "${LIB_DIR}/constants.sh" 2>/dev/null || { echo "ERROR: Failed to source constants.sh" >&2; exit 1; }`
    - Benefit: Reduces code duplication, simplifies maintenance, removes ~20 lines of redundant code
    - Cost: LOW - simple removal, but removes safety net if constants.sh file is missing/corrupted
    - Priority: LOW - fallbacks don't hurt and provide safety net for edge cases (file not found, syntax errors)
    - Note: Fallbacks are harmless but redundant. Consider removing if prioritizing code simplification.
    - See: Code review 2026-01-27 for constants.sh idempotency fix

- Consider helper functions for array size checks to reduce set +u/set -u verbosity
    - Current pattern: `set +u; if [[ ${#ARRAY[@]} -gt 0 ]]; then ...; fi; set -u` used 55+ times across anonymization scripts
    - Issue: Verbose pattern required due to `set -euo pipefail` and empty array handling
    - Proposed: Create helper function like `is_array_empty ARRAY_NAME` that handles `set +u`/`set -u` internally
    - Benefit: Reduces code verbosity, improves readability, centralizes array checking logic
    - Cost: LOW - simple helper function, but requires updating 55+ call sites
    - Priority: LOW - current pattern works correctly, just verbose
    - Note: Pattern established during unified anonymization refactoring (2026-01-20)

- Consider extracting sed script building into shared functions if duplication increases
    - Current state: Similar sed script building patterns exist across anonymize-firewall.sh, anonymize-ip-rules.sh, anonymize-logs.sh, anonymize-ipset.sh
    - Issue: Each script builds sed scripts for IP/interface/set name replacements with similar logic
    - Proposed: Extract common sed script building into helper functions in lib/anonymize.sh
    - Benefit: Reduces duplication, centralizes sed script building logic, easier to maintain
    - Cost: MEDIUM - requires refactoring multiple scripts, but pattern is well-established
    - Priority: LOW - current duplication is acceptable, scripts are readable and maintainable
    - Note: Pattern established during unified anonymization refactoring (2026-01-20)

- Enhance network address normalization for `/8` and `/16` networks
    - Current state: Network normalization only normalizes the last octet (works correctly for `/24` networks)
    - Issue: `/8` and `/16` networks should normalize more octets for proper network address semantics:
      - `/8` networks should normalize last 3 octets: `10.0.0.0/8` (currently only normalizes last octet)
      - `/16` networks should normalize last 2 octets: `10.199.0.0/16` (currently only normalizes last octet)
      - `/24` networks work correctly: `172.31.22.0/24` ✓
    - Example: `172.16.0.0/16` currently maps to `10.199.248.0/16` but should map to `10.199.0.0/16`
    - Proposed: Add CIDR-specific normalization logic based on prefix length
    - Benefit: More realistic anonymized network addresses, better readability
    - Cost: MEDIUM - requires parsing CIDR prefix length and normalizing appropriate octets
    - Priority: LOW - current implementation is acceptable for most use cases, `/24` networks (most common) work correctly
    - Note: `/12` and other non-octet-boundary CIDR lengths are more complex to handle
    - See: `docs/reference/CODE_REVIEW_LESSONS_LEARNED.md` for related analysis