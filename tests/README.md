# UDM VPN Monitor Test Suite

This directory contains comprehensive tests for the UDM VPN Monitor scripts using [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

## Quick Start

### Run Fast Tests (Default)
```bash
./tests/run_tests.sh
```

### Run All Tests (Including Slow Tests)
```bash
./tests/run_tests.sh --slow
```

### Run Specific Test File
```bash
bats tests/test_install.sh
```

### Run with Coverage
```bash
./tests/run_tests.sh --coverage
```

## Test Structure

### Core Test Infrastructure
- `test_helper.bash` - Common test utilities and helper functions
- `test_helper_functions.sh` - Unit tests for individual helper functions (130 tests)
- `run_tests.sh` - Test runner script
- `generate_coverage_report.sh` - Generates test coverage reports
- `detect_flaky_tests.sh` - Flaky test detection script

### Test Files by Category

**Script-Specific Tests**: `test_install.sh`, `test_uninstall.sh`, `test_vpn_monitor.sh`, `test_analyze_logs.sh`, `test_check_config.sh`, `test_compare_config.sh`, `test_check_utilities.sh`, `test_vpn_keepalive.sh`, `test_prepare_install_package.sh`, `test_migration.sh`

**Integration Tests**: `test_integration.sh`, `test_integration_e2e_recovery.sh`, `test_integration_location.sh`

**Configuration Tests**: `test_config.sh`, `test_config_loading.sh`, `test_config_validation.sh`, `test_config_large_values.sh`, `test_config_overrides.sh`, `test_config_security.sh`, `test_config_order.sh`, `test_config_schema.sh`, `test_config_location.sh`

**Detection Tests**: `test_detection.sh`, `test_detection_status.sh`, `test_detection_fallback.sh`, `test_detection_network_partition.sh`, `test_detection_rekey.sh`, `test_detection_failure_type.sh`, `test_detection_idle.sh`, `test_detection_xfrm_edge_cases.sh`, `test_detection_ping_multiple.sh`, `test_multiple_peer_edge_cases.sh`

**Recovery Tests**: `test_recovery.sh`, `test_recovery_tier1.sh`, `test_recovery_tier2.sh`, `test_recovery_tier3.sh`, `test_recovery_rate_limiting.sh`, `test_recovery_network_partition.sh`, `test_recovery_partial_failures.sh`

**Other High-Risk Tests**: `test_lockfile.sh`, `test_state.sh`, `test_state_concurrent_updates.sh`, `test_state_location.sh`, `test_logging.sh`, `test_connection.sh`, `test_errors.sh`, `test_main.sh`, `test_rapid_state_changes.sh`, `test_resources.sh`

**Total**: ~827 tests (~605 fast, ~222 slow)

## Test Categories

- **Fast Tests** (default): Run quickly, exclude slow integration and high-risk tests
- **Slow Tests**: Integration tests and high-risk tests that take longer to run

See [BATS Guide](../docs/BATS_GUIDE.md#test-categories) for detailed test categorization.

## Basic Requirements

- **bats-core** 1.x or higher
- **bash** version 4.0 or higher

Optional (recommended):
- **bats-support**, **bats-assert**, **bats-file** - Helper libraries (install via `./tests/install_bats_helpers.sh`)
- **GNU parallel** or **rush** - For parallel execution (3-4x faster)
- **kcov** - For coverage reporting

See [BATS Guide - Test Environment Requirements](../docs/BATS_GUIDE.md#test-environment-requirements) for detailed installation instructions.

## Common Commands

```bash
# Run fast tests only (default)
./tests/run_tests.sh

# Run all tests including slow tests
./tests/run_tests.sh --slow

# Run with coverage reporting
./tests/run_tests.sh --coverage

# Run specific test file
bats tests/test_config.sh

# Run specific test by name
bats tests/test_install.sh -t "install.sh creates installation directory"

# Run tests in parallel (auto-detect cores)
./tests/run_tests.sh --jobs auto

# Run tests individually with checkpoint/resume
./tests/run_tests.sh --individual
./tests/run_tests.sh --individual --resume
```

See [BATS Guide - Running Tests](../docs/BATS_GUIDE.md#running-tests) for all available options.

## Troubleshooting

**Tests fail with "bats: command not found":**
- Install bats-core: `brew install bats-core` (macOS) or `sudo apt-get install bats` (Linux)

**Tests fail with permission errors:**
- Install/uninstall tests may need root: `sudo bats tests/test_install.sh`
- Or use `--dev` mode in tests to avoid root requirement

**Coverage reporting fails:**
- Install kcov: `brew install kcov` (macOS) or `sudo apt-get install kcov` (Linux)
- Coverage is optional - tests can run without it

See [BATS Guide - Troubleshooting](../docs/BATS_GUIDE.md#troubleshooting) for detailed troubleshooting information.

## Related Documentation

- **[fixtures/README.md](fixtures/README.md)** - Reusable test fixtures for common VPN monitoring scenarios
- **[Test Patterns](../docs/testing/TEST_PATTERNS.md)** - Standardized test patterns and best practices for writing tests
- **[BATS Guide](../docs/testing/BATS_GUIDE.md)** - Complete BATS framework guide, test environment setup, running tests, and advanced features
- **[Test Strategy](../docs/testing/TEST_STRATEGY.md)** - Test strategy, philosophy, and approach
- **[Test Maintenance](../docs/testing/TEST_MAINTENANCE.md)** - Test maintenance procedures and guidelines

## Test Fixtures

The `fixtures/` directory contains reusable test fixtures for common VPN monitoring scenarios. These fixtures combine multiple setup steps into single function calls, reducing duplication and ensuring consistent test environments.

**Quick Example:**
```bash
load test_helper
load fixtures/vpn_active

@test "VPN active test" {
    setup_vpn_active_fixture "192.168.1.1"
    run bash "$TEST_SCRIPT" --fake
    assert_success
    remove_mock_from_path
}
```

**Available Fixtures:**
- `vpn_active.bash` - VPN is active and healthy
- `vpn_down.bash` - VPN is down, no SA found
- `vpn_failing.bash` - VPN has recorded failures
- `vpn_rekey.bash` - VPN has undergone a rekey
- `vpn_flapping.bash` - VPN can transition between up/down states
- `vpn_multiple_peers.bash` - Multiple VPN peers scenario
- `vpn_mixed_peers.bash` - Multiple peers with mixed states
- `vpn_recovery_disabled.bash` - Recovery actions disabled
- `vpn_at_tier.bash` - VPN at specific tier threshold
- `vpn_idle.bash` - VPN idle tunnel scenario
- `vpn_network_partition.bash` - Network partition scenario
- `vpn_rate_limited.bash` - Rate limiting scenario
- `vpn_xfrm_recovery.bash` - XFRM recovery scenario
- `vpn_bytes_zero.bash` - VPN SA exists but bytes=0 (suspect condition)
- `vpn_recovery_test.bash` - Recovery test setup with pass-through mocks

For complete fixture documentation, see:
- **[fixtures/README.md](fixtures/README.md)** - Complete fixture reference and usage guide
- **[Test Patterns - Test Fixtures](../docs/testing/TEST_PATTERNS.md#4-test-fixtures)** - Detailed fixture documentation with all arguments and examples
- **[BATS Guide - Test Fixtures](../docs/testing/BATS_GUIDE.md#7-test-fixtures---reusable-test-scenarios)** - BATS framework usage with fixtures

## Writing New Tests

For comprehensive guidance on writing new tests, see:

- **[Test Patterns](../docs/testing/TEST_PATTERNS.md)** - Standardized patterns, best practices, and examples
- **[BATS Guide - Writing Tests](../docs/testing/BATS_GUIDE.md#writing-new-tests)** - BATS framework usage and patterns
- **[BATS Guide - Test Helper Infrastructure](../docs/testing/BATS_GUIDE.md#test-helper-infrastructure)** - Available helper functions
- **[fixtures/README.md](fixtures/README.md)** - Reusable test fixtures for common scenarios

## Test Coverage

Current test coverage: **46.9%** (1141/2433 lines)

See [Test Patterns - Test Coverage](../docs/TEST_PATTERNS.md#test-coverage) for coverage goals, module-specific targets, and improvement strategy.

## External Resources

- [bats-core documentation](https://github.com/bats-core/bats-core)
- [BATS Official Documentation](https://bats-core.readthedocs.io/en/stable/)
- [bats-assert documentation](https://github.com/bats-core/bats-assert)
- [bats-file documentation](https://github.com/bats-core/bats-file)
