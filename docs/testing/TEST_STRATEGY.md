# Test Strategy and Approach

**Date**: 2026-01-02  
**Last Updated**: 2026-01-02  
**Status**: Active

---

## Overview

This document outlines the comprehensive test strategy for the UDM VPN Monitor project. It describes our testing philosophy, approach, test types, coverage strategy, and how testing integrates with development and deployment.

## Testing Philosophy

### Core Principles

1. **Test Critical Paths First**: Focus on functionality that could cause production failures or data loss
2. **Test in Isolation**: Each test should be independent and not rely on other tests
3. **Test Behavior, Not Implementation**: Tests should verify expected behavior, not internal implementation details
4. **Maintain Testability**: Code should be written to be testable, with clear interfaces and minimal dependencies
5. **Fast Feedback Loop**: Fast tests run by default, slow tests can be included when needed
6. **Comprehensive Coverage**: Aim for high coverage of critical paths, with reasonable coverage of all code

### Testing Goals

- **Prevent Regressions**: Catch bugs before they reach production
- **Document Behavior**: Tests serve as executable documentation of expected behavior
- **Enable Refactoring**: High test coverage allows safe refactoring
- **Support Debugging**: Tests help identify where bugs are introduced
- **Guide Development**: Test-first or test-driven development for critical features

## Test Types and Hierarchy

### 1. Unit Tests

**Purpose**: Test individual functions and modules in isolation

**Scope**:
- Individual library functions (`lib/*.sh`)
- Helper functions
- Configuration parsing and validation
- State management functions
- Detection logic
- Recovery actions

**Characteristics**:
- Fast execution (< 1 second per test)
- High isolation (mocked dependencies)
- Focused on single function/module behavior
- Examples: `test_helper_functions.sh`, `test_config_validation.sh`

**Tools**: BATS with function sourcing and mocking

### 2. Integration Tests

**Purpose**: Test interactions between multiple components

**Scope**:
- Full script execution with mocked system commands
- Configuration loading and validation flow
- Detection → Recovery flow
- State file persistence across runs
- Multi-location monitoring
- End-to-end recovery scenarios

**Characteristics**:
- Moderate execution time (1-5 seconds per test)
- Tests component interactions
- Uses mocks for external dependencies
- Examples: `test_integration.sh`, `test_integration_e2e_recovery.sh`, `test_integration_location.sh`

**Tools**: BATS with comprehensive mocking infrastructure

### 3. High-Risk Tests

**Purpose**: Test critical paths that could cause production failures

**Scope**:
- Lockfile management and race conditions
- State file corruption and recovery
- Configuration error handling
- VPN detection edge cases
- Recovery action execution
- Error handling during critical operations
- Resource monitoring and throttling
- Concurrent state updates

**Characteristics**:
- Marked as slow tests (excluded from default runs)
- Comprehensive error scenario coverage
- Edge case and boundary condition testing
- Examples: `test_lockfile.sh`, `test_state.sh`, `test_detection.sh`, `test_recovery.sh`, `test_main.sh`

**Tools**: BATS with extensive mocking and state manipulation

### 4. Script-Specific Tests

**Purpose**: Test individual scripts in isolation

**Scope**:
- `install.sh` - Installation process
- `uninstall.sh` - Uninstallation process
- `vpn-monitor.sh` - Main monitoring script
- `vpn-keepalive.sh` - Keepalive daemon
- `analyze-logs.sh` - Log analysis script
- `check-config.sh` - Configuration validation script
- `check-utilities.sh` - Utility availability checking
- `prepare_install_package.sh` - Package preparation

**Characteristics**:
- Fast execution
- Tests script-specific functionality
- Examples: `test_install.sh`, `test_uninstall.sh`, `test_vpn_monitor.sh`, `test_vpn_keepalive.sh`

**Tools**: BATS with script execution and output validation

## Test Organization

For detailed information about test structure, file organization, test categories, and fast vs. slow tests, see:

- **[Test Structure](../tests/README.md#test-structure)** - Test file organization and structure overview
- **[Test Categories](../docs/BATS_GUIDE.md#test-categories)** - Fast vs. slow tests, test categorization, and test counts
- **[Test Environment Requirements](../docs/BATS_GUIDE.md#test-environment-requirements)** - System requirements and tool installation

**Summary**: The test suite consists of ~900 tests organized by functionality (configuration, detection, recovery, integration, etc.) and categorized as fast (~605 tests, run by default) or slow (~295 tests, excluded by default for faster development feedback).

## Testing Approach

### Test-Driven Development (TDD)

**When to Use**:
- New critical features
- Bug fixes (write test first, then fix)
- Refactoring (ensure tests pass before and after)

**Process**:
1. Write failing test
2. Implement minimal code to pass
3. Refactor while keeping tests green
4. Repeat

### Test-First Development

**When to Use**:
- High-risk features
- Complex logic
- Error handling paths

**Process**:
1. Design test cases for expected behavior
2. Write tests
3. Implement feature
4. Verify tests pass

### Test-After Development

**When to Use**:
- Low-risk features
- Simple additions
- Documentation updates

**Process**:
1. Implement feature
2. Write tests to verify behavior
3. Ensure tests pass

### Bug-Driven Testing

**When to Use**:
- Production bugs
- Reported issues
- Edge cases discovered in production

**Process**:
1. Reproduce bug in test
2. Fix bug
3. Verify test passes
4. Add additional edge case tests

## Mocking Strategy

For comprehensive mocking documentation including patterns, best practices, helper functions, and common pitfalls, see:

- **[Test Patterns](../tests/TEST_PATTERNS.md)** - Standardized mock patterns and best practices
- **[BATS Guide - Mock Patterns](../docs/BATS_GUIDE.md#common-mock-patterns)** - Detailed mock examples and patterns
- **[BATS Guide - Mock Setup Debugging](../docs/BATS_GUIDE.md#mock-setup-debugging-checklist)** - Troubleshooting mock issues

**Summary**:
- **Mock External Dependencies**: System commands (`ip`, `ipsec`, `ping`, `dig`, `date`)
- **Don't Mock Internal Functions**: Test internal functions directly by sourcing modules
- **Use Fixtures**: Reusable mock setups for common VPN states (see [Test Patterns](../tests/TEST_PATTERNS.md#4-test-fixtures))
- **Always Clean Up**: Pair `add_mock_to_path()` with `remove_mock_from_path()`

## Test Execution Strategy

For comprehensive information about running tests, including all command-line options, parallel execution, coverage reporting, and CI/CD integration, see:

- **[Running Tests](../docs/BATS_GUIDE.md#running-tests)** - Complete guide to running tests with all options
- **[Test Coverage Reporting](../docs/BATS_GUIDE.md#coverage-reports-location)** - Coverage reporting setup and usage
- **[Flaky Test Detection](../docs/BATS_GUIDE.md#flaky-test-detection)** - Automated flaky test detection
- **[CI/CD Integration](../docs/BATS_GUIDE.md#cicd-integration)** - CI/CD integration details

**Quick Reference**:
- **Local Development**: `./tests/run_tests.sh` (fast tests only)
- **Before Committing**: `./tests/run_tests.sh --slow` (all tests)
- **With Coverage**: `./tests/run_tests.sh --coverage`
- **CI/CD**: `RUN_SLOW_TESTS=1 ./tests/run_tests.sh --coverage`

## Coverage Strategy

For detailed coverage information including goals, measurement, reporting, and analysis, see:

- **[Test Coverage](../docs/TEST_PATTERNS.md#test-coverage)** - Complete coverage documentation including goals, current coverage, and module-specific targets
- **[Test Coverage Reporting](../docs/BATS_GUIDE.md#coverage-reports-location)** - How to generate and view coverage reports

**Summary**:
- **Tool**: kcov for line coverage
- **Current Coverage**: 46.9% (1141/2433 lines)
- **Coverage Goals**: See [Test Coverage Goals](../docs/TEST_PATTERNS.md#test-coverage) for detailed targets by module
- **Strategy**: Focus on critical paths (P0) first, then high priority (P1), with reasonable coverage for all code

## Test Maintenance Strategy

### Regular Maintenance

- **Review Test Failures**: Investigate and fix failing tests promptly
- **Update Tests for Code Changes**: Update tests when code behavior changes
- **Refactor Tests**: Improve test clarity and maintainability
- **Remove Obsolete Tests**: Remove tests for removed functionality
- **Update Documentation**: Keep test documentation current

### Test Review Process

- **Code Review**: Review tests along with code changes
- **Test Coverage**: Ensure adequate coverage for new features
- **Test Quality**: Verify tests follow patterns and best practices
- **Test Performance**: Identify and optimize slow tests

### Test Refactoring

- **Extract Common Patterns**: Create helper functions for repeated patterns
- **Use Fixtures**: Replace duplicate setup code with fixtures
- **Simplify Complex Tests**: Break down complex tests into smaller, focused tests
- **Improve Test Names**: Use descriptive test names that explain the scenario

## Test Documentation

### Test File Documentation

Each test file should include:
- File header describing what is tested
- Section headers for organization
- Test comments with Purpose, Expected, and Importance

### Test Case Documentation

Each test case should include:
- Descriptive test name
- Purpose comment (what is being tested)
- Expected comment (what should happen)
- Importance comment (why this test matters)

### Test Patterns Documentation

For detailed test patterns and standards, see:

- **[Test Patterns](../tests/TEST_PATTERNS.md)**: Standardized test patterns and best practices
- **[BATS Guide](../docs/BATS_GUIDE.md)**: BATS framework usage and patterns
- **[tests/README.md](../tests/README.md)**: Test suite overview and usage

## Test Quality Metrics

### Test Metrics

For current test metrics including test counts, execution times, and quality indicators, see:

- **[Test Categories](../docs/BATS_GUIDE.md#test-categories)** - Current test counts and organization
- **[Running Tests](../docs/BATS_GUIDE.md#running-tests)** - Test execution times and performance

**Summary**:
- **Test Pass Rate**: Target 100% (all tests should pass)
- **Flaky Test Rate**: Target 0% (no flaky tests)

### Test Quality Indicators

- **Test Isolation**: Tests should not depend on each other
- **Test Clarity**: Tests should be easy to understand
- **Test Maintainability**: Tests should be easy to update
- **Test Coverage**: Adequate coverage of critical paths
- **Test Performance**: Tests should run in reasonable time

## Integration with Development Workflow

### Pre-Commit

- Run fast tests locally
- Fix any test failures
- Ensure new code has tests

### Pull Request

- CI runs all tests including slow tests
- Coverage reports generated
- Flaky test detection runs
- All tests must pass before merge

### Pre-Release

- Full test suite execution
- Coverage analysis
- Flaky test detection and fixing
- Test documentation review

## Continuous Improvement

### Test Suite Evolution

- **Regular Review**: Review test suite for gaps and improvements
- **Pattern Updates**: Update test patterns as best practices evolve
- **Tool Updates**: Keep testing tools and frameworks up to date
- **Documentation Updates**: Keep test documentation current

### Learning and Adaptation

- **Learn from Bugs**: Add tests for production bugs
- **Learn from Test Failures**: Improve tests based on failure patterns
- **Learn from Coverage**: Identify and test uncovered code paths
- **Learn from Performance**: Optimize slow tests

## Test Strategy Review

This test strategy should be reviewed and updated:
- **Quarterly**: Review overall strategy and approach
- **After Major Changes**: Update strategy when testing approach changes
- **When Issues Arise**: Update strategy to address testing gaps or issues

---

**Document Version**: 1.0  
**Last Updated**: 2026-01-02  
**Next Review**: 2026-04-02
