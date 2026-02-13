# Coverage Analysis Guide

**Date:** 2026-01-19  
**Purpose:** Guide for analyzing test coverage for functions listed in UNTESTED_FUNCTIONS_REVIEW.md

---

## Overview

This guide explains how to use the coverage analysis script to verify integration test coverage for functions that may need additional testing.

## Quick Start

### 1. Run Integration Tests with Coverage

```bash
./scripts/analyze-function-coverage.sh --run-tests
```

This will:
- Run integration tests that exercise the target functions
- Generate coverage data in `coverage/` directory
- Show overall coverage statistics
- Indicate which functions have coverage data available

### 2. Analyze Existing Coverage Data

If you already have coverage data:

```bash
./scripts/analyze-function-coverage.sh
```

### 3. View Detailed HTML Report

```bash
./scripts/analyze-function-coverage.sh --html-report
```

This opens the interactive HTML coverage report where you can:
- See line-by-line coverage (green = covered, red = uncovered)
- Navigate to specific functions
- Identify uncovered branches and edge cases

## Target Functions

The script analyzes coverage for these functions from `UNTESTED_FUNCTIONS_REVIEW.md`:

### Phase 1: Critical Recovery Functions
- `check_vpn_status_for_location` (lib/recovery/recovery_orchestration.sh:734-783)
- `update_location_state` (lib/recovery/recovery_orchestration.sh:806-936)

### Phase 3: Config Functions
- `apply_backward_compatibility_migrations` (lib/config/config_loading.sh:698-728)
- `validate_config_schema` (lib/config/config_validation.sh:566-587)

### Medium Value Functions
- `compute_log_file_path` (lib/config/config_loading.sh:782-841)
- `ensure_config_directories_exist` (lib/config/config_loading.sh:865-911)

## Interpreting Results

### Coverage Data Available ✓
- Function was executed during test runs
- Check HTML report for line-by-line coverage details
- Look for uncovered lines (red) to identify gaps

### No Coverage Data Found ⚠
- Function was not executed by any tests
- **Action Required**: Add integration tests that exercise this function
- This indicates a significant coverage gap

### Coverage Percentage
- Shows overall coverage across all instrumented code
- Individual function coverage may vary
- Use HTML report for function-specific details

## Using the HTML Report

1. Open `coverage/index.html` in a web browser
2. Navigate to the source file (e.g., `lib/recovery/recovery_orchestration.sh`)
3. Find the function by line number range
4. Review coverage:
   - **Green lines**: Covered by tests
   - **Red lines**: Not covered (potential gaps)
   - **Yellow lines**: Partially covered (some branches executed)

## Next Steps After Analysis

### If Coverage is Adequate (>80%)
- Document coverage in `UNTESTED_FUNCTIONS_REVIEW.md`
- Mark function as "covered by integration tests"
- Focus testing efforts elsewhere

### If Coverage is Inadequate (<80%)
1. Identify specific uncovered branches/lines
2. Add targeted integration tests for gaps
3. Re-run coverage analysis to verify improvement

### If No Coverage Data
1. Review integration tests to see why function isn't executed
2. Add integration tests that exercise the function
3. Consider unit tests if integration tests don't cover edge cases

## Integration Tests Analyzed

The script runs coverage on these integration test files:
- `tests/test_integration.sh`
- `tests/test_integration_location.sh`
- `tests/test_integration_e2e_recovery.sh`
- `tests/test_recovery_network_partition.sh`
- `tests/test_config_loading.sh`
- `tests/test_config_schema.sh`

## Example Workflow

```bash
# Step 1: Run tests with coverage
./scripts/analyze-function-coverage.sh --run-tests

# Step 2: Review results
# Note which functions have no coverage data

# Step 3: Open HTML report for detailed analysis
./scripts/analyze-function-coverage.sh --html-report

# Step 4: For functions with gaps, add targeted tests
# (Edit test files, add new test cases)

# Step 5: Re-run to verify coverage improved
./scripts/analyze-function-coverage.sh --run-tests
```

## Notes

- Coverage analysis focuses on **integration tests** as recommended in `UNTESTED_FUNCTIONS_REVIEW.md`
- The script uses kcov for coverage instrumentation
- Coverage data is cumulative - multiple test runs merge coverage
- HTML reports provide the most detailed view of coverage gaps

## Related Documentation

- [UNTESTED_FUNCTIONS_REVIEW.md](./UNTESTED_FUNCTIONS_REVIEW.md) - Original analysis of untested functions
- [TEST_INFRASTRUCTURE_REVIEW.md](./TEST_INFRASTRUCTURE_REVIEW.md) - Test infrastructure overview
- [BATS_GUIDE.md](./BATS_GUIDE.md) - BATS testing framework guide
