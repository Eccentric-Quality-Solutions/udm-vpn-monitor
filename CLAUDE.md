# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

UDM VPN Monitor monitors Site-to-Site VPN connections on UniFi Dream Machines (UDM/UDM-Pro/UDM-SE) and automatically attempts recovery when VPN tunnels appear active but are non-functional. It runs via cron (more resilient than long-running daemons on UDM) and uses IPsec xfrm state byte counters combined with optional ping connectivity checks.

**Target Platform:** UniFi Dream Machine with UniFi OS 4.3+ (no backwards compatibility needed - single deployment)

## Build and Test Commands

```bash
# Run fast tests (default, ~605 tests)
./tests/run_tests.sh

# Run all tests including slow integration tests (~222 additional tests)
./tests/run_tests.sh --slow

# Run tests with coverage reporting
./tests/run_tests.sh --coverage

# Run specific test file
bats tests/test_detection.sh

# Run specific test by name
bats tests/test_install.sh -t "install.sh creates installation directory"

# Run tests in parallel
./tests/run_tests.sh --jobs auto

# Linting and formatting
shellcheck --severity=error *.sh lib/*.sh lib/**/*.sh
shfmt -d *.sh lib/*.sh  # Check formatting (no changes)
shfmt -w *.sh lib/*.sh  # Format in-place

# Create installation package
./scripts/prepare_install_package.sh        # Creates zip
./scripts/prepare_install_package.sh --tar  # Creates tar.gz
```

## Architecture

### Detection Flow
Primary: `ip xfrm state` (byte counters) → Fallback: `ipsec status` → Optional: Ping checks

### Recovery Tiers
1. **Tier 1** (TIER1_THRESHOLD): Logging only
2. **Tier 2** (TIER2_THRESHOLD): xfrm-based per-connection recovery (affects only failing tunnel), falls back to `ipsec reload`
3. **Tier 3** (TIER3_THRESHOLD): xfrm-based per-connection recovery, falls back to `ipsec restart`

### Module Structure
```
lib/
├── common.sh, constants.sh, logging.sh, lockfile.sh, resources.sh
├── config.sh         # Compatibility layer → sources lib/config/
├── detection.sh      # Compatibility layer → sources lib/detection/
├── recovery.sh       # Compatibility layer → sources lib/recovery/
├── state.sh          # Compatibility layer → sources lib/state/
├── config/           # Config loading, validation, schema, location parsing
├── detection/        # xfrm, ping, network validation, failure analysis, system-wide failure
├── recovery/         # Orchestration, verification, xfrm/ipsec recovery
└── state/            # Location state, global state, peer state, state paths
```

### State Files
Per-location state in `state/` directory:
- `failure_count_<location>_<peer_ip_sanitized>` - Failure count
- `last_bytes_<location>_<peer_ip_sanitized>` - Byte counter tracking
- `failure_type_<location>_<peer_ip_sanitized>` - tunnel_down/no_traffic/idle/unknown

## Key Patterns

### Error Handling
```bash
# Fatal errors needing fake mode support (for testing)
handle_error_or_exit_fake_mode "SYSTEM" "Error message" "${EXIT_CONFIG_ERROR:-2}"

# Truly fatal errors (even in fake mode)
die "Error message" "${EXIT_COMMAND_NOT_FOUND:-5}"

# Non-fatal errors (return codes)
if ! validate_ip_address "$peer_ip"; then
    log_message "ERROR" "SYSTEM" "Invalid peer IP: $peer_ip"
    return 1
fi
```

### Logging
```bash
log_message "INFO" "SYSTEM" "System-level message"
log_message "WARNING" "NYC" "Location-specific message for NYC"
log_message "DEBUG" "SYSTEM" "Debug info (only if DEBUG=1)"
```

### Atomic File Writes
```bash
if ! (echo "$data" > "${file}.tmp" && mv "${file}.tmp" "$file"); then
    log_message "ERROR" "SYSTEM" "Failed to write: $file"
    return 1
fi
```

### Function Documentation
```bash
# Brief description
#
# Arguments:
#   $1: parameter_name (type) - Description
#
# Returns:
#   0: Success case
#   1: Failure case
function_name() {
    local param="$1"
    # ...
}
```

## Testing

- Use BATS framework with helpers in `tests/helpers/` and fixtures in `tests/fixtures/`
- Test fixtures provide common scenarios: `vpn_active`, `vpn_down`, `vpn_failing`, `vpn_at_tier`, etc.
- Tag slow tests with `# bats test_tags=slow` to exclude from default runs
- When tests are slow, tag them appropriately

## Important Guidelines

1. **Platform-specific**: Only target UDM OS 4.3+. Use only tools available on UDM (no python3, node, jq)
2. **No backwards compatibility needed**: Single deployment, can move forward without maintaining backwards compatibility
3. **Ask clarifying questions** for significant implementation choices with multiple valid paths
4. **Minimize changes when debugging**: Revert changes that don't fix the problem. Add suggestions to FUTURE.md instead
5. **Run relevant tests** after altering functionality
6. **DO NOT fit code to tests**: Tests run the code. If there's a bug, fix the bug - don't change code just to pass tests
7. **Debugging markers**: Add `# AGENT {NAME} DEBUGGING` comment before functions when debugging, remove when done
8. **Update git hooks**: If git commit hooks or associated scripts are updated, run `./scripts/setup-git-hooks.sh`
9. **Test case filtering**: When asked to run "some subset of tests", clarify if we want test files or test cases (usually cases, use BATS filtering)
10. **Stream test output**: Always ensure tests stream output to terminal and aren't buffered
11. **Document learnings**: When discovering UDM-specific limitations or BATS behaviors, update relevant documentation

## Exit Code Constants (lib/constants.sh)
- `EXIT_SUCCESS=0`, `EXIT_GENERAL_ERROR=1`, `EXIT_CONFIG_ERROR=2`
- `EXIT_VALIDATION_ERROR=3`, `EXIT_PERMISSION_ERROR=4`
- `EXIT_COMMAND_NOT_FOUND=5`, `EXIT_STATE_ERROR=6`
