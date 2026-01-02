# UDM VPN Monitor Test Suite

This directory contains comprehensive tests for the UDM VPN Monitor scripts using [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

## Related Documentation

For additional test documentation, see:

- **[Test Patterns](TEST_PATTERNS.md)** - Standardized test patterns and best practices
- **[BATS Guide](../docs/BATS_GUIDE.md)** - BATS framework usage, patterns, and advanced features
- **[Test Strategy](../docs/TEST_STRATEGY.md)** - Test strategy, philosophy, and approach
- **[Test Maintenance](../docs/TEST_MAINTENANCE.md)** - Test maintenance procedures and guidelines

## Test Structure

### Core Test Infrastructure
- `test_helper.bash` - Common test utilities and helper functions
- `test_helper_functions.sh` - Unit tests for individual helper functions in `vpn-monitor.sh` (130 tests)
- `run_tests.sh` - Test runner script
- `generate_coverage_report.sh` - Generates test coverage reports from kcov output
- `detect_flaky_tests.sh` - Flaky test detection script (runs tests multiple times to identify inconsistent tests)

### Script-Specific Tests
- `test_install.sh` - Tests for `install.sh` script (18 tests)
- `test_uninstall.sh` - Tests for `uninstall.sh` script (40 tests)
- `test_vpn_monitor.sh` - Tests for `vpn-monitor.sh` script (33 tests)
- `test_analyze_logs.sh` - Tests for `analyze-logs.sh` script (28 tests)
- `test_check_config.sh` - Tests for `check-config.sh` script (18 tests)
- `test_check_utilities.sh` - Tests for `check-utilities.sh` script (17 tests)
- `test_vpn_keepalive.sh` - Tests for `vpn-keepalive.sh` script (18 tests)
- `test_prepare_install_package.sh` - Tests for `prepare_install_package.sh` script (12 tests)
- `test_migration.sh` - Tests for configuration migration (18 tests)

### Integration Tests
- `test_integration.sh` - Integration tests for full monitoring flow with mock VPN states (18 tests)
- `test_integration_e2e_recovery.sh` - End-to-end recovery integration tests (6 tests)
- `test_integration_location.sh` - Location-based configuration integration tests (10 tests)

### Configuration Tests
- `test_config.sh` - Main configuration tests (53 tests)
- `test_config_loading.sh` - Configuration loading and validation tests (6 tests)
- `test_config_validation.sh` - Configuration variable validation tests (10 tests)
- `test_config_large_values.sh` - Very large values validation tests (3 tests)
- `test_config_overrides.sh` - Path and environment variable overrides tests (4 tests)
- `test_config_security.sh` - Security-related tests (dangerous content detection) (12 tests)
- `test_config_order.sh` - Validation order dependencies tests (5 tests)
- `test_config_schema.sh` - Schema default application tests (5 tests)
- `test_config_location.sh` - Location-based configuration tests (26 tests)

### Detection Tests
- `test_detection.sh` - Main detection tests (47 tests)
- `test_detection_status.sh` - VPN status detection tests (9 tests)
- `test_detection_fallback.sh` - Fallback chain edge cases tests (6 tests)
- `test_detection_network_partition.sh` - Network partition detection tests (11 tests)
- `test_detection_rekey.sh` - SA rekey detection tests (7 tests)
- `test_detection_failure_type.sh` - Failure type detection tests (8 tests)
- `test_detection_idle.sh` - Idle tunnel detection tests (6 tests)
- `test_detection_xfrm_edge_cases.sh` - XFRM edge cases and error handling tests (13 tests)
- `test_detection_ping_multiple.sh` - Multiple ping target detection tests (16 tests)
- `test_multiple_peer_edge_cases.sh` - Multiple peer IP edge cases tests (4 tests)

### Recovery Tests
- `test_recovery.sh` - Recovery strategy selection, XFRM recovery, and fallback logic tests (17 tests)
- `test_recovery_tier1.sh` - Tier 1 (logging) recovery tests (1 test)
- `test_recovery_tier2.sh` - Tier 2 (surgical cleanup) recovery tests (7 tests)
- `test_recovery_tier3.sh` - Tier 3 (full restart) recovery tests (10 tests)
- `test_recovery_rate_limiting.sh` - Rate limiting tests (6 tests)
- `test_recovery_cooldown_rate_limit_interaction.sh` - Cooldown and rate limiting interaction tests (3 tests)
- `test_recovery_network_partition.sh` - Network partition recovery tests (3 tests)
- `test_recovery_partial_failures.sh` - Partial failure recovery tests (4 tests)

### Other High-Risk Tests
- `test_lockfile.sh` - Lockfile management tests (18 tests)
- `test_state.sh` - State file management tests (25 tests)
- `test_state_concurrent_updates.sh` - Concurrent state update tests (9 tests)
- `test_state_location.sh` - Location-based state file management tests (22 tests)
- `test_logging.sh` - Logging failure scenario tests (8 tests)
- `test_connection.sh` - Connection name discovery and caching tests (8 tests)
- `test_errors.sh` - Error handling during critical operations tests (3 tests)
- `test_main.sh` - Main execution edge cases tests (25 tests)
- `test_rapid_state_changes.sh` - Rapid state change handling tests (6 tests)
- `test_resources.sh` - Resource monitoring tests (CPU, RAM, disk) (35 tests)

## Test Environment Requirements

This section documents the complete requirements for running the test suite. The test suite is designed to work on both development machines (Linux, macOS) and CI/CD environments.

### System Requirements

**Operating System:**
- **Linux**: Ubuntu 18.04+, Debian 10+, Fedora 30+, or similar distributions
- **macOS**: macOS 10.15+ (Catalina or later)
- **CI/CD**: Ubuntu 20.04+ (GitHub Actions default)

**Shell:**
- **bash** version 4.0 or higher (required for test execution)
- Most modern Linux distributions and macOS include compatible bash versions

**Disk Space:**
- **Minimum**: 100 MB free space for test execution
- **Recommended**: 500 MB+ for coverage reports and test artifacts
- Coverage reports can generate significant data (HTML reports, JSON data)

**Memory:**
- **Minimum**: 512 MB RAM
- **Recommended**: 1 GB+ RAM for parallel test execution
- Coverage reporting (kcov) requires additional memory

**CPU:**
- Single core works but is slow
- **Recommended**: Multi-core CPU for parallel test execution
- Parallel execution can reduce test time by 3-4x on multi-core systems

### Required Tools

#### bats-core

**Version**: 1.x or higher

**Installation:**

**macOS (Homebrew):**
```bash
brew install bats-core
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y bats
```

**Fedora/RHEL:**
```bash
sudo dnf install -y bats
```

**From Source:**
```bash
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

**Verification:**
```bash
bats --version
```

**Note**: The test suite requires bats-core 1.x. Older versions (0.x) are not supported.

### Optional Tools (Recommended)

#### BATS Helper Libraries

These libraries provide additional assertion functions and utilities that improve test readability and maintainability:

- **bats-support** - Output and error handling helpers
- **bats-assert** - Additional assertion functions
- **bats-file** - File system assertions

**Installation:**
```bash
cd tests
./install_bats_helpers.sh
```

This script automatically installs the helper libraries to the `tests/` directory. The test suite will work without these helpers, but some tests may be less readable.

#### GNU parallel or rush

**Purpose**: Parallel test execution (significantly faster)

**GNU parallel Installation:**

**macOS:**
```bash
brew install parallel
```

**Ubuntu/Debian:**
```bash
sudo apt-get install parallel
```

**Fedora/RHEL:**
```bash
sudo dnf install parallel
```

**rush Installation:**
```bash
# rush is a Rust-based alternative to GNU parallel
cargo install rush
# or download from: https://github.com/shenwei356/rush
```

**Performance Impact:**
- Without parallel: ~15 minutes (all tests)
- With parallel (8 jobs): ~3-5 minutes (all tests)
- With parallel (fast tests only): ~1-2 minutes

The test runner automatically detects and uses parallel execution if available (see [Parallel Execution](#parallel-execution) below).

### Coverage Reporting Tools

#### kcov

**Purpose**: Code coverage reporting for bash scripts

**Installation:**

**macOS (Homebrew):**
```bash
brew install kcov
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y kcov
```

**Fedora/RHEL:**
```bash
sudo dnf install -y kcov
```

**From Source (if package not available):**

kcov requires build dependencies:
```bash
# Install build dependencies
sudo apt-get install -y \
  cmake \
  build-essential \
  libcurl4-openssl-dev \
  libelf-dev \
  libdw-dev \
  binutils-dev \
  libiberty-dev \
  zlib1g-dev \
  git

# Build and install kcov
git clone https://github.com/SimonKagstrom/kcov.git
cd kcov
mkdir build && cd build
cmake ..
make -j$(nproc)
sudo make install
```

**Verification:**
```bash
kcov --version
```

**Note**: Coverage reporting is optional. Tests can run without kcov, but coverage reports will not be generated.

### Development Environment Requirements

For contributing to the project, additional tools are recommended:

#### ShellCheck

**Purpose**: Static analysis for shell scripts

**Installation:**

**macOS:**
```bash
brew install shellcheck
```

**Ubuntu/Debian:**
```bash
sudo apt-get install -y shellcheck
```

**Fedora/RHEL:**
```bash
sudo dnf install -y ShellCheck
```

#### shfmt

**Purpose**: Shell script formatter

**Installation:**

**macOS:**
```bash
brew install shfmt
```

**From Source:**
```bash
# Download pre-built binary from releases
# https://github.com/mvdan/sh/releases
```

**Note**: shfmt is not available in most Linux package managers. Use Homebrew on Linux or download from releases.

**Setup Script:**
```bash
# Configure PATH for development tools
./scripts/setup-dev-env.sh
```

This script automatically detects tools installed via `apt` or Homebrew and configures your PATH accordingly.

### CI/CD Environment Requirements

The test suite is designed to work in CI/CD environments (GitHub Actions, GitLab CI, etc.). Additional requirements for CI/CD:

**Required:**
- `bats` - Test framework
- `bash` - Shell interpreter
- `jq` - JSON processor (for coverage extraction in CI)

**Optional:**
- `kcov` - For coverage reporting
- `parallel` or `rush` - For parallel execution
- `bats-support`, `bats-assert`, `bats-file` - Helper libraries

**CI/CD Setup Example:**

See `.github/workflows/ci.yml` for a complete CI/CD setup example. The workflow:
1. Installs bats from package manager
2. Installs bats helper libraries
3. Optionally builds and installs kcov from source
4. Runs tests with appropriate environment variables

### Environment Variables

The test suite respects the following environment variables:

**Test Execution:**
- `RUN_SLOW_TESTS` - Set to `1` to include slow tests (default: `0`)
- `PARALLEL_JOBS` - Number of parallel jobs (default: `0` = auto-detect)
- `TEST_TIMEOUT` - Timeout for individual tests in seconds (default: `120`)
- `FAST_FAIL` - Set to `1` to stop on first failure (default: `0`)

**Coverage:**
- Coverage is enabled via `--coverage` flag, not environment variable

**See Also:**
- [Running Tests](#running-tests) section for usage examples
- [Parallel Execution](#parallel-execution) section for parallel configuration

### Verification

To verify your test environment is properly configured:

```bash
# Check required tools
bats --version

# Check optional tools
command -v parallel >/dev/null && echo "GNU parallel: installed" || echo "GNU parallel: not installed"
command -v kcov >/dev/null && echo "kcov: installed" || echo "kcov: not installed"

# Run a simple test
bats tests/test_helper_functions.sh -t "test_helper_functions.sh exists"
```

### Troubleshooting

**Tests fail with "bats: command not found":**
- Install bats-core (see [Required Tools](#required-tools) above)
- Verify bats is in your PATH: `which bats`

**Tests fail with permission errors:**
- Most tests don't require root, but install/uninstall tests may need root
- Run with `sudo` if needed: `sudo bats tests/test_install.sh`
- Or use `--dev` mode in tests to avoid root requirement

**Coverage reporting fails:**
- Verify kcov is installed: `kcov --version`
- Check kcov build dependencies if building from source
- Coverage is optional - tests can run without it

**Parallel execution not working:**
- Verify GNU parallel or rush is installed
- Check PATH includes the tool: `which parallel` or `which rush`
- Parallel execution is optional - tests will run sequentially if not available

**Tests leave temporary files:**
- Tests should clean up automatically
- Check `/tmp/bats-test-*` directories if cleanup fails
- Manually clean if needed: `rm -rf /tmp/bats-test-*`

For more troubleshooting information, see the [Troubleshooting](#troubleshooting) section below.

## Running Tests

### Run Fast Tests (Default)

By default, slow tests are excluded to speed up local development:

```bash
./tests/run_tests.sh
```

This runs all test files except the slow test files listed below. Fast tests include:
- Script-specific tests: `test_analyze_logs.sh`, `test_check_config.sh`, `test_check_utilities.sh`, `test_helper_functions.sh`, `test_install.sh`, `test_uninstall.sh`, `test_vpn_monitor.sh`, `test_prepare_install_package.sh`, `test_vpn_keepalive.sh`, `test_migration.sh`
- Configuration tests (split files): `test_config_loading.sh`, `test_config_validation.sh`, `test_config_large_values.sh`, `test_config_overrides.sh`, `test_config_security.sh`, `test_config_order.sh`, `test_config_schema.sh`, `test_config_location.sh`
- Detection tests (split files): `test_detection_status.sh`, `test_detection_fallback.sh`, `test_detection_network_partition.sh`, `test_detection_rekey.sh`, `test_detection_failure_type.sh`, `test_detection_idle.sh`, `test_detection_xfrm_edge_cases.sh`, `test_detection_ping_multiple.sh`, `test_multiple_peer_edge_cases.sh`
- Recovery tests (split files): `test_recovery_tier1.sh`, `test_recovery_tier2.sh`, `test_recovery_tier3.sh`, `test_recovery_rate_limiting.sh`, `test_recovery_cooldown_rate_limit_interaction.sh`, `test_recovery_network_partition.sh`, `test_recovery_partial_failures.sh`
- Integration tests: `test_integration_e2e_recovery.sh`, `test_integration_location.sh`
- Other tests: `test_state_concurrent_updates.sh`, `test_state_location.sh`, `test_rapid_state_changes.sh`, `test_resources.sh`

**Total**: ~605 fast tests

### Run All Tests (Including Slow Tests)

To include slow tests (integration and high-risk tests):

```bash
./tests/run_tests.sh --slow
# or
RUN_SLOW_TESTS=1 ./tests/run_tests.sh
```

Slow tests include:
- `test_integration.sh` - Integration tests for full monitoring flow (18 tests)
- `test_config.sh` - Main configuration tests (53 tests)
- `test_detection.sh` - Main detection tests (47 tests)
- `test_recovery.sh` - Recovery strategy selection, XFRM recovery, and fallback logic tests (17 tests)
- `test_lockfile.sh` - Lockfile management tests (18 tests)
- `test_state.sh` - State file management tests (25 tests)
- `test_logging.sh` - Logging failure scenario tests (8 tests)
- `test_connection.sh` - Connection name discovery and caching tests (8 tests)
- `test_errors.sh` - Error handling during critical operations tests (3 tests)
- `test_main.sh` - Main execution edge cases tests (25 tests)

**Total**: ~222 slow tests

### Run with Coverage

```bash
./tests/run_tests.sh --coverage          # Fast tests only
./tests/run_tests.sh --slow --coverage    # All tests with coverage
```

See [Test Coverage Reporting](#test-coverage-reporting) section for details.

### Run Tests Individually

Run each test case separately with detailed per-test output. This mode is useful for debugging specific test failures and provides timing information for each test:

```bash
./tests/run_tests.sh --individual                # Fast tests only, individual mode
./tests/run_tests.sh --individual --slow          # All tests including slow tests
./tests/run_tests.sh --individual --coverage      # With coverage reporting
```

Individual mode provides:
- Per-test timing information
- Detailed results saved to `logs/test_results_TIMESTAMP.txt`
- Clear pass/fail/timeout status for each test
- Useful for debugging specific test failures
- **Checkpoint/resume support** - Automatically saves progress and can resume from where you left off

**Note:** Individual mode runs tests sequentially (parallel execution is disabled in this mode).

#### Checkpoint and Resume

When running tests individually, the test runner automatically saves a checkpoint file (`logs/test_checkpoint.txt`) after each test completes. This allows you to resume test execution from where you left off if tests fail or are interrupted.

**How it works:**
- Each test result (PASSED, FAILED, TIMEOUT) is saved to the checkpoint file
- When resuming, tests that already passed are automatically skipped
- Failed and timed-out tests are re-run when resuming
- Checkpoint persists between terminal sessions

**Usage:**

```bash
# Run tests normally (checkpoint is saved automatically)
./tests/run_tests.sh --individual

# If tests fail or are interrupted, resume from checkpoint
./tests/run_tests.sh --individual --resume

# Resume with slow tests included
./tests/run_tests.sh --individual --resume --slow

# Resume with coverage reporting
./tests/run_tests.sh --individual --resume --coverage
```

**Checkpoint file format:**
- Location: `logs/test_checkpoint.txt`
- Format: `test_file::test_name|status|timestamp`
- Example: `test_config.sh::config file contains syntax errors|PASSED|1234567890`

**Benefits:**
- **Time savings**: Skip tests that already passed, only re-run failures
- **Resilience**: Resume after interruptions without losing progress
- **Debugging**: Focus on fixing failures without re-running successful tests
- **Long test suites**: Especially useful for large test suites that take a long time

**Clearing checkpoint:**
The checkpoint is automatically cleared when you start a fresh run (without `--resume`). To manually clear it:

```bash
rm logs/test_checkpoint.txt
```

### Parallel Execution

The test runner supports parallel execution to significantly reduce test time. By default, parallel execution is enabled if GNU parallel or rush is installed.

```bash
# Auto-detect CPU cores (default)
./tests/run_tests.sh

# Use specific number of parallel jobs
./tests/run_tests.sh --jobs 8

# Disable parallel execution
./tests/run_tests.sh --jobs 0

# Set via environment variable
PARALLEL_JOBS=4 ./tests/run_tests.sh
```

**Performance Impact:**
- Without parallel: ~15 minutes (all tests)
- With parallel (8 jobs): ~3-5 minutes (all tests)
- With parallel (fast tests only): ~1-2 minutes

**Requirements:**
- GNU parallel or rush must be installed
- If not available, tests run sequentially (still works, just slower)

**Note:** Coverage reporting may be slower with parallel execution due to kcov overhead, but is still supported.

### Run Specific Test File

```bash
# Script-specific tests
bats tests/test_install.sh
bats tests/test_uninstall.sh
bats tests/test_vpn_monitor.sh
bats tests/test_analyze_logs.sh
bats tests/test_check_config.sh
bats tests/test_prepare_install_package.sh

# Integration tests
bats tests/test_integration.sh
bats tests/test_integration_e2e_recovery.sh

# Configuration tests
bats tests/test_config.sh
bats tests/test_config_loading.sh
bats tests/test_config_validation.sh
bats tests/test_config_security.sh
# ... or run all config tests: bats tests/test_config*.sh

# Detection tests
bats tests/test_detection.sh
bats tests/test_detection_status.sh
bats tests/test_detection_network_partition.sh
bats tests/test_detection_xfrm_edge_cases.sh
# ... or run all detection tests: bats tests/test_detection*.sh

# Recovery tests
bats tests/test_recovery.sh
bats tests/test_recovery_tier1.sh
bats tests/test_recovery_cooldown_rate_limit_interaction.sh
bats tests/test_recovery_network_partition.sh
bats tests/test_recovery_partial_failures.sh
# ... or run all recovery tests: bats tests/test_recovery*.sh

# Other high-risk tests
bats tests/test_lockfile.sh
bats tests/test_state.sh
bats tests/test_state_concurrent_updates.sh
bats tests/test_main.sh
bats tests/test_rapid_state_changes.sh
```

## Test Categories

### Fast Tests (run by default)
Fast tests include all test files except the slow test files listed below. This includes:
- Script-specific tests: `test_analyze_logs.sh`, `test_check_config.sh`, `test_check_utilities.sh`, `test_helper_functions.sh`, `test_install.sh`, `test_uninstall.sh`, `test_vpn_monitor.sh`, `test_prepare_install_package.sh`, `test_vpn_keepalive.sh`, `test_migration.sh`
- Configuration tests (split files): `test_config_loading.sh`, `test_config_validation.sh`, `test_config_large_values.sh`, `test_config_overrides.sh`, `test_config_security.sh`, `test_config_order.sh`, `test_config_schema.sh`, `test_config_location.sh`
- Detection tests (split files): `test_detection_status.sh`, `test_detection_fallback.sh`, `test_detection_network_partition.sh`, `test_detection_rekey.sh`, `test_detection_failure_type.sh`, `test_detection_idle.sh`, `test_detection_xfrm_edge_cases.sh`, `test_detection_ping_multiple.sh`, `test_multiple_peer_edge_cases.sh`
- Recovery tests (split files): `test_recovery_tier1.sh`, `test_recovery_tier2.sh`, `test_recovery_tier3.sh`, `test_recovery_rate_limiting.sh`, `test_recovery_cooldown_rate_limit_interaction.sh`, `test_recovery_network_partition.sh`, `test_recovery_partial_failures.sh`
- Integration tests: `test_integration_e2e_recovery.sh`, `test_integration_location.sh`
- Other tests: `test_state_concurrent_updates.sh`, `test_state_location.sh`, `test_rapid_state_changes.sh`, `test_resources.sh`

**Total**: ~605 fast tests

### Slow Tests (excluded by default)
Slow tests are high-risk tests and integration tests that take longer to run:
- `test_integration.sh` - Integration tests for full monitoring flow (18 tests)
- `test_config.sh` - Main configuration tests (53 tests)
- `test_detection.sh` - Main detection tests (47 tests)
- `test_recovery.sh` - Recovery strategy selection, XFRM recovery, and fallback logic tests (17 tests)
- `test_lockfile.sh` - Lockfile management tests (18 tests)
- `test_state.sh` - State file management tests (25 tests)
- `test_logging.sh` - Logging failure scenario tests (8 tests)
- `test_connection.sh` - Connection name discovery and caching tests (8 tests)
- `test_errors.sh` - Error handling during critical operations tests (3 tests)
- `test_main.sh` - Main execution edge cases tests (25 tests)

**Total Test Count**: 827 tests across all test files (~605 fast, ~222 slow)

**Note**: Slow tests are automatically included in CI/CD via the `RUN_SLOW_TESTS=1` environment variable (see `.github/workflows/tests.yml`).

### Run Specific Test

```bash
bats tests/test_install.sh -t "install.sh creates installation directory"
```

### Run Tests Starting from a Specific Test Number

**Note**: BATS does not natively support starting from a specific test number. After reviewing the [official BATS documentation](https://bats-core.readthedocs.io/en/stable/) and community discussions, there is no built-in feature for this. However, there are several practical workarounds:

#### Method 1: Run Specific Test Files (Recommended)

The most straightforward approach is to run only the test files that contain tests starting from your desired test number.

**Test File Ranges:**

To find which test file contains a specific test number, use the script provided below. Test files are run in alphabetical order, so the ranges depend on the execution order.

**Example: Run from a specific test file onwards**

If you know which test file contains the test you want to start from:

```bash
# Run specific test files and all subsequent ones
bats tests/test_detection.sh tests/test_recovery.sh tests/test_state.sh

# With parallelization (if GNU parallel is installed)
bats --jobs auto tests/test_detection.sh tests/test_recovery.sh tests/test_state.sh

# Or using the test runner (includes slow tests by default)
./tests/run_tests.sh --slow
```

#### Method 2: Filter by Test Name Pattern

If your test names follow a pattern, you can use BATS' `--filter` option with regex:

```bash
# Run tests matching a pattern (regex)
bats tests/test_helper_functions.sh -f "check_xfrm_status"

# Run tests NOT matching a pattern
bats tests/test_helper_functions.sh --negative-filter "skip"

# Example: Run tests with names containing "147" or higher numbers
bats tests/test_*.sh -f "test.*(14[7-9]|1[5-9][0-9]|[2-9][0-9][0-9])"
```

#### Method 3: Use Test Tags (Requires Pre-tagging)

BATS supports tagging tests (version 1.8.0+). You can tag tests and filter by tags:

```bash
# In your test file, add tags:
# bats test_tags=number:147
@test "check_xfrm_status detects rekey when SPI changes" {
  # test code
}

# Then run with:
bats --filter-tags number:147 tests/test_helper_functions.sh
```

**Note**: This method requires manually tagging tests beforehand, which may not be practical for large test suites.

#### Method 4: Resume Failed Tests

If tests failed previously and you want to rerun only failed tests:

```bash
# Rerun only tests that failed in the last completed run
bats --filter-status failed tests/test_*.sh

# Or use the test runner
./tests/run_tests.sh --failed
```

**Note:** For individual test mode, the `--resume` flag provides a more robust checkpoint-based resume mechanism that automatically skips passed tests and re-runs failures. See [Checkpoint and Resume](#checkpoint-and-resume) section above for details.

**Finding Which Test File Contains a Specific Test Number:**

```bash
# Count tests in each file to find test ranges
total=0
for f in tests/test_*.sh; do
  count=$(grep -c '^@test' "$f" 2>/dev/null || echo 0)
  echo "$f: $count (tests $((total + 1))-$((total + count)))"
  total=$((total + count))
done
```

**References:**
- [BATS Official Documentation](https://bats-core.readthedocs.io/en/stable/)
- [BATS Writing Tests Guide](https://bats-core.readthedocs.io/en/latest/writing-tests.html)

### Verbose Output

```bash
bats --verbose tests/test_*.sh
```

### Tap Format (for CI)

```bash
bats --tap tests/test_*.sh
```

## Test Coverage

Current test coverage: **46.9%** (1141/2433 lines) as of latest run.

### Coverage Goals

**Overall Coverage Targets**:
- **Minimum Overall Coverage**: 50% (current: 46.9%)
- **Target Overall Coverage**: 60%
- **Stretch Goal**: 70%

**Module-Specific Coverage Targets**:

| Module | Current | Minimum Target | Target | Priority |
|--------|---------|----------------|--------|----------|
| `lib/detection.sh` | - | 70% | 80% | P0 (Critical) |
| `lib/recovery.sh` | - | 70% | 80% | P0 (Critical) |
| `lib/state.sh` | - | 70% | 80% | P0 (Critical) |
| `lib/lockfile.sh` | - | 70% | 80% | P0 (Critical) |
| `lib/config.sh` | - | 60% | 70% | P1 (High) |
| `lib/config_schema.sh` | - | 60% | 70% | P1 (High) |
| `lib/logging.sh` | - | 60% | 70% | P1 (High) |
| `lib/common.sh` | - | 50% | 60% | P2 (Medium) |
| `lib/resources.sh` | - | 50% | 60% | P2 (Medium) |
| `lib/constants.sh` | - | 40% | 50% | P3 (Low) |
| `vpn-monitor.sh` | - | 60% | 70% | P1 (High) |
| `vpn-keepalive.sh` | - | 60% | 70% | P1 (High) |
| `install.sh` | - | 50% | 60% | P2 (Medium) |
| `uninstall.sh` | - | 50% | 60% | P2 (Medium) |

**Coverage Priorities**:

1. **P0 (Critical)**: Core functionality that could cause production failures
   - Detection logic
   - Recovery actions
   - State management
   - Lockfile handling

2. **P1 (High)**: Important functionality that affects reliability
   - Configuration loading and validation
   - Logging
   - Main script execution

3. **P2 (Medium)**: Supporting functionality
   - Common utilities
   - Resource monitoring
   - Installation/uninstallation

4. **P3 (Low)**: Less critical functionality
   - Constants
   - Simple utilities

**Coverage Measurement**:
- **Tool**: kcov for line coverage
- **Frequency**: Measured in CI on every commit
- **Reporting**: Coverage reports generated in `coverage/` directory
- **Review**: Coverage gaps reviewed quarterly

**Coverage Improvement Strategy**:
1. **Focus on Critical Paths First**: Prioritize P0 modules
2. **Test Error Paths**: Ensure error handling is covered
3. **Test Edge Cases**: Cover boundary conditions and edge cases
4. **Maintain Coverage**: Ensure new code has tests
5. **Regular Review**: Review coverage reports to identify gaps

**Coverage Goals Review**:
- **Quarterly**: Review and update coverage goals
- **After Major Changes**: Reassess goals when codebase changes significantly
- **When Issues Arise**: Update goals to address coverage gaps

### High-Risk Tests

The test suite includes comprehensive tests for critical paths and error handling scenarios that could cause production failures. These tests are distributed across multiple test files for better organization:

#### Test Categories

**1. Lockfile Management** (`test_lockfile.sh` - 18 tests)
Tests lockfile cleanup, error handling, race conditions, and edge cases.

**2. Configuration Loading and Validation** (`test_config.sh` and split files - 120 tests total)
Tests configuration file error handling, security, validation, location-based configuration, and edge cases.

**3. VPN Status Detection** (`test_detection.sh` and split files - 105 tests total)
Tests VPN detection edge cases, byte counter handling, fallback mechanisms, network partitions, rekey detection, and XFRM edge cases.

**4. Recovery Actions** (`test_recovery.sh` and split files - 51 tests total)
Tests recovery action execution, error handling, tier-based recovery, rate limiting, cooldown interactions, and partial failures.

**5. State and File Management** (`test_state.sh`, `test_state_concurrent_updates.sh`, and `test_state_location.sh` - 56 tests total)
Tests state file handling, permissions, corruption, concurrent updates, location-based state management, and edge cases.

**6. Logging** (`test_logging.sh` - 8 tests)
Tests logging failure scenarios and error handling.

**7. Connection Management** (`test_connection.sh` - 8 tests)
Tests connection name discovery, caching, and edge cases.

**8. Error Handling** (`test_errors.sh` - 3 tests)
Tests error handling during critical operations.

**9. Main Execution** (`test_main.sh` - 25 tests)
Tests main execution edge cases and error scenarios.

**10. Rapid State Changes** (`test_rapid_state_changes.sh` - 6 tests)
Tests handling of rapid state changes and race conditions.

#### Test Statistics

- **Total High-Risk Tests**: ~222 tests across multiple files (marked as slow tests)
- **Test Categories**: 10 main categories
- **Focus Areas**: Critical error handling, edge cases, security, race conditions, resource management

#### CI Integration

The high-risk tests are automatically included in CI when `RUN_SLOW_TESTS=1` is set because:
1. `run_tests.sh` automatically discovers all `test_*.sh` files
2. High-risk test files are marked as slow tests
3. CI runs `./tests/run_tests.sh --slow` which includes all test files

For more information on test coverage gaps, see [TEST_COVERAGE_GAPS.md](../TEST_COVERAGE_GAPS.md).

### install.sh Tests

- ✅ Script existence and executability
- ✅ Help message display
- ✅ Root user requirement (non-dev mode)
- ✅ Dev mode functionality
- ✅ Installation directory creation
- ✅ Script installation
- ✅ Config file handling (create, preserve, overwrite)
- ✅ Cron job setup and skipping
- ✅ Cron schedule from config
- ✅ Installation verification
- ✅ Error handling

### uninstall.sh Tests

- ✅ Script existence and executability
- ✅ Root user requirement
- ✅ Missing installation handling
- ✅ Installation directory removal
- ✅ Cron entry removal
- ✅ Uninstallation verification
- ✅ Interactive confirmation prompts
- ✅ Non-interactive mode (`--yes` flag)
- ✅ CI environment detection
- ✅ Lockfile cleanup

### vpn-monitor.sh Tests

- ✅ Script existence and executability
- ✅ Help message display
- ✅ Configuration loading
- ✅ State file initialization
- ✅ Log file creation
- ✅ Peer IP validation
- ✅ Multiple peer IPs handling
- ✅ Failure counter management
- ✅ Cooldown period handling
- ✅ Lockfile management
- ✅ Ping check functionality
- ✅ Debug mode
- ✅ Cron persistence checking

### vpn-keepalive.sh Tests

- ✅ Script existence and executability
- ✅ Help message display
- ✅ Version information
- ✅ Start daemon functionality
- ✅ Stop daemon functionality
- ✅ Status check functionality
- ✅ Restart functionality
- ✅ Configuration validation
- ✅ Multiple peer IPs handling
- ✅ IPv6 support
- ✅ Disabled keepalive handling
- ✅ Already running daemon handling

### check-utilities.sh Tests

- ✅ Script existence and executability
- ✅ Utility availability checking
- ✅ Available utilities reporting
- ✅ Missing utilities reporting
- ✅ Summary statistics
- ✅ Colored output
- ✅ Common utilities checking
- ✅ Network utilities checking
- ✅ System monitoring utilities checking
- ✅ Text processing utilities checking

### lib/resources.sh Tests

- ✅ Library file existence
- ✅ CPU usage calculation
- ✅ Memory usage calculation
- ✅ Disk usage calculation
- ✅ Free disk space calculation
- ✅ Resource constraint tracking
- ✅ System resource throttling
- ✅ Log file rotation on low disk
- ✅ Configuration threshold usage
- ✅ Error handling

## Writing New Tests

For comprehensive guidance on writing new tests, including standardized patterns, best practices, and helper functions, see:

- **[Test Patterns](TEST_PATTERNS.md)** - Standardized test patterns, best practices, and examples
- **[BATS Guide](../docs/BATS_GUIDE.md)** - BATS framework usage and patterns
- **[Test Helper Functions](../docs/BATS_GUIDE.md#test-helper-infrastructure)** - Available helper functions

**Quick Start**:
- Use standardized patterns from [Test Patterns](TEST_PATTERNS.md)
- Follow best practices for test isolation, mocking, and cleanup
- Use helper functions from `test_helper.bash` for common setup tasks
- See [Test Patterns](TEST_PATTERNS.md) for examples of proper test structure

## Test Coverage Reporting

The test suite supports code coverage reporting using [kcov](https://github.com/SimonKagstrom/kcov).

### Running Tests with Coverage

```bash
# Enable coverage reporting
./tests/run_tests.sh --coverage
```

Coverage reports include:
- **HTML Report**: Interactive browser-based report showing line-by-line coverage
- **Text Summary**: Coverage percentages and statistics
- **JSON Data**: Machine-readable coverage data for CI/CD integration

### Coverage Reports Location

All coverage reports are generated in the `coverage/` directory:
- `coverage/index.html` - Main HTML report (open in browser)
- `coverage/summary.txt` - Text summary
- `coverage/index.json` - JSON data for programmatic access

### Generating Coverage Summary

After running tests with coverage, generate a summary report:

```bash
./tests/generate_coverage_report.sh
```

This creates a text summary with coverage percentages per file.

### What Gets Covered

Coverage reporting tracks execution of:
- `vpn-monitor.sh` - Main monitoring script
- `install.sh` - Installation script
- `uninstall.sh` - Uninstallation script
- `lib/common.sh` - Shared library functions

Test files and helper scripts are excluded from coverage reports.

## Continuous Integration

Tests can be run in CI environments. The test suite:

- Works in non-interactive mode
- Cleans up after itself
- Uses temporary directories
- Doesn't require root (for most tests)
- Can run in parallel (with proper isolation)
- Complete test isolation - each test gets a fresh environment

## Flaky Test Detection

The test suite includes automated flaky test detection to identify tests that pass inconsistently. Flaky tests are tests that pass in some runs but fail in others, indicating unreliable tests that need fixing.

### Running Flaky Test Detection

```bash
# Run flaky test detection with default settings (3 runs, fast tests only)
./tests/detect_flaky_tests.sh

# Run with more iterations for better detection
./tests/detect_flaky_tests.sh --runs 5

# Include slow tests in detection
./tests/detect_flaky_tests.sh --slow

# Combine options
./tests/detect_flaky_tests.sh --runs 5 --slow
```

### How It Works

The flaky test detection script:
1. Runs the test suite multiple times (default: 3 runs)
2. Tracks test results across all runs
3. Identifies tests with inconsistent results (flaky tests)
4. Generates a detailed analysis report

### Output

The script generates:
- **Console Summary**: Colored summary showing stable and flaky tests
- **Analysis Report**: Detailed report saved to `logs/flaky_detection_<timestamp>/flaky_analysis.txt`
- **CI Integration**: Automatically runs on pull requests in CI

### CI Integration

Flaky test detection runs automatically on pull requests via GitHub Actions. When flaky tests are detected:
- A warning is posted in the workflow
- Results are uploaded as artifacts
- A comment is posted on the PR with details

## Test Isolation

The test suite implements **complete test isolation** to ensure tests don't affect each other. This prevents flaky tests and makes debugging easier.

### How It Works

Each test runs in a completely isolated environment:

1. **Fresh Environment Variables**: All test-related environment variables are saved before each test and restored after each test
2. **Isolated Test Directory**: Each test gets its own temporary directory (`TEST_DIR`) that is automatically cleaned up
3. **PATH Restoration**: Mock commands added to PATH are automatically removed after each test
4. **State Cleanup**: All state files, log files, and temporary files are cleaned up

### Environment Variables Tracked

The following environment variables are automatically saved and restored for each test:

- `CONFIG_FILE` - Configuration file path
- `STATE_DIR` - State directory path
- `LOGS_DIR` - Logs directory path
- `LOCKFILE` - Lockfile path
- `LOG_FILE` - Log file path
- `RESTART_COUNT_FILE` - Restart count file path
- `COOLDOWN_UNTIL_FILE` - Cooldown file path
- `MOCK_IP`, `MOCK_PING`, `MOCK_IPSEC` - Mock command paths
- `NO_ESCALATE` - Error handling flag
- `DEBUG` - Debug mode flag
- `BASE_TIME` - Controllable time for testing
- `TEST_CONFIG_FILE`, `TEST_SCRIPT` - Test-specific paths
- `MOCK_DATA_DIR`, `MOCK_INSTALL_DIR` - Mock directory paths
- `TEST_DIR` - Test temporary directory
- `PATH` - Command search path

### Verifying Test Isolation

Use the test isolation verification script to detect if any tests are leaving state:

```bash
# Verify all test files
./tests/verify_test_isolation.sh

# Verify specific test files
./tests/verify_test_isolation.sh test_config.sh test_detection.sh
```

The verification script:
- Captures environment state before and after each test
- Compares environment variables to detect modifications
- Checks for files created outside `TEST_DIR`
- Reports any state leakage detected

### Best Practices

To maintain test isolation:

1. **Use Helper Functions**: Use `setup_test_environment()`, `setup_test_vpn_monitor()`, etc. instead of manually setting environment variables
2. **Clean Up in Tests**: If your test creates files outside `TEST_DIR`, clean them up explicitly
3. **Don't Modify Global State**: Avoid modifying system-wide configuration or files outside `TEST_DIR`
4. **Use Mocks**: Use mock commands instead of modifying system commands
5. **Verify Isolation**: Run `verify_test_isolation.sh` periodically to catch isolation issues early
- Supports coverage reporting with kcov

### CI/CD Integration

Example GitHub Actions workflow:

```yaml
- name: Install bats
  run: |
    git clone https://github.com/bats-core/bats-core.git
    cd bats-core
    sudo ./install.sh /usr/local

- name: Install kcov for coverage
  run: |
    sudo apt-get update && sudo apt-get install -y kcov

- name: Run tests with coverage
  run: |
    RUN_SLOW_TESTS=1 ./tests/run_tests.sh --coverage

- name: Upload coverage report
  uses: codecov/codecov-action@v3
  with:
    files: ./coverage/index.json
    flags: unittests
```

## Troubleshooting

### Tests Fail with Permission Errors

- Some tests require root access (install/uninstall tests)
- Run with `sudo` if needed: `sudo bats tests/test_install.sh`
- Or use `--dev` mode in tests to avoid root requirement

### Tests Fail Due to Missing Commands

- Tests use mocks for system commands
- Ensure mock functions are properly set up
- Check PATH includes test directory with mocks

### Tests Leave Temporary Files

- Tests should clean up in teardown
- Check `TEST_TMPDIR` environment variable
- Manually clean `/tmp/bats-test-*` if needed

### Bats Helpers Not Found

- Install optional helper libraries
- Or modify tests to not require them
- Tests will work without helpers but with fewer assertions

## Contributing

When adding new features:

1. Add tests for new functionality
2. Ensure all tests pass
3. Update this README if adding new test utilities
4. Follow existing test patterns and conventions

## See Also

**Internal Documentation**:
- [Test Patterns](TEST_PATTERNS.md) - Standardized test patterns and best practices
- [BATS Guide](../docs/BATS_GUIDE.md) - BATS framework usage and patterns
- [Test Strategy](../docs/TEST_STRATEGY.md) - Test strategy and approach
- [Test Maintenance](../docs/TEST_MAINTENANCE.md) - Test maintenance procedures

**External BATS Documentation**:
- [bats-core documentation](https://github.com/bats-core/bats-core)
- [bats-assert documentation](https://github.com/bats-core/bats-assert)
- [bats-file documentation](https://github.com/bats-core/bats-file)
- [BATS Official Documentation](https://bats-core.readthedocs.io/en/stable/)

