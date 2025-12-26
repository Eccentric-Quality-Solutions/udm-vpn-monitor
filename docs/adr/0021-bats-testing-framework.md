# ADR-0021: BATS Testing Framework

## Status
Accepted

## Context

The monitoring system requires comprehensive testing to ensure reliability and correctness. We need a testing framework that:

- Works with Bash scripts (our implementation language)
- Runs on UDM OS without requiring additional software installation
- Supports mocking system commands (`ip`, `ipsec`, `ping`)
- Integrates with code coverage tools (kcov)
- Supports parallel test execution for faster runs
- Integrates well with CI/CD pipelines
- Has a mature ecosystem with helper libraries

We currently have **389 tests** written using BATS (Bash Automated Testing System) with:
- Comprehensive test helper infrastructure (`test_helper.bash`)
- Custom mocking system for VPN commands
- Coverage reporting with kcov integration
- Test runner with parallel execution support
- Well-established patterns and conventions

Alternative testing frameworks considered:
- **ShellSpec**: Modern BDD-style framework with built-in mocking
- **shUnit2**: xUnit-style framework, older but lightweight
- **Roundup**: Minimal testing framework
- **Custom framework**: Building our own testing solution

## Decision

We will continue using **BATS (Bash Automated Testing System)** as our testing framework.

## Consequences

### Positive

- **Already Implemented**: 389 tests already written and working with BATS
- **No Installation Required**: BATS runs on UDM OS using bash-only (no external dependencies)
- **Mature Ecosystem**: Well-established helper libraries (bats-assert, bats-file, bats-support)
- **Proven Infrastructure**: Our test helper system and mocking infrastructure work well
- **CI/CD Integration**: TAP format output integrates well with CI/CD pipelines
- **Coverage Support**: kcov integration already working
- **Parallel Execution**: Supported (currently disabled for output streaming, but can be enabled)
- **Active Community**: Well-maintained with good documentation and community support
- **Team Familiarity**: Team already knows BATS syntax and patterns
- **Zero Migration Cost**: Continue using existing tests without rewriting

### Negative

- **Syntax Quirks**: Some learning curve for new team members
- **Less Modern**: Not as modern as ShellSpec (but more mature)
- **Parallel Execution**: Currently disabled (but can be enabled when needed)

### Alternatives Considered

#### ShellSpec
- **Pros**: Modern BDD syntax, built-in mocking, better error messages
- **Cons**: Requires installation (not available on UDM OS), different syntax (would require rewriting all 389 tests), migration cost too high
- **Verdict**: Not suitable - requires installation, migration cost too high

#### shUnit2
- **Pros**: xUnit-style (familiar), lightweight, no external dependencies
- **Cons**: Less active development, limited features (no built-in mocking), no parallel execution, migration cost too high
- **Verdict**: Not suitable - older, less features, migration cost too high

#### Roundup
- **Pros**: Extremely simple, no dependencies
- **Cons**: Too minimal (lacks required features), no mocking support, no coverage reporting, no parallel execution
- **Verdict**: Not suitable - too minimal, lacks required features

#### Custom Framework
- **Pros**: Full control, no external dependencies
- **Cons**: Reinventing the wheel, maintenance burden, no ecosystem, migration cost very high
- **Verdict**: Not suitable - unnecessary effort

## Implementation Details

- **Framework**: BATS (Bash Automated Testing System)
- **Test Files**: 8 test files with 389 total tests
  - `test_helper_functions.sh`: 119 unit tests
  - `test_high_risk.sh`: 127 critical path tests
  - `test_integration.sh`: 18 integration tests
  - `test_vpn_monitor.sh`: 33 main script tests
  - `test_install.sh`: 18 installation tests
  - `test_uninstall.sh`: 34 uninstallation tests
  - `test_analyze_logs.sh`: 28 log analysis tests
  - `test_prepare_install_package.sh`: 12 package preparation tests
- **Helper Libraries**: bats-assert, bats-file, bats-support
- **Coverage Tool**: kcov for code coverage reporting
- **Test Runner**: Custom `run_tests.sh` with parallel execution support
- **Mocking**: Custom mock functions for system commands (`mock_ip_xfrm_state`, `mock_ping`, `mock_ipsec`)

## Future Improvements

Based on analysis in `BATS_GUIDE.md`, we can improve our BATS usage by:

1. **Leveraging More Features**: Use more advanced bats-assert features (regex matching, line assertions)
2. **Better File Assertions**: Use more bats-file assertions (permissions, ownership, size)
3. **Test Organization**: Use test tags (BATS 1.8.0+) for better organization
4. **Parallel Execution**: Optimize parallel execution for faster test runs
5. **Test Documentation**: Improve test names and inline documentation
6. **Standardization**: Standardize on helper library functions consistently

## Migration Considerations

We will **not** migrate to an alternative framework unless:

1. BATS becomes unmaintained (currently very active)
2. Critical feature missing that cannot be worked around (not the case)
3. Major breaking changes in BATS (hasn't happened)
4. New project with different constraints (not applicable)

**Estimated migration cost**: 2-4 weeks of development time plus risk of bugs/regressions, team retraining, and lost productivity. Benefits of alternatives do not justify these costs.

## Related ADRs

- ADR-0017: Bash Scripting Language (testing framework choice follows from language choice)
- ADR-0005: Modular Library Architecture (test structure mirrors code structure)

## References

- [BATS Core Documentation](https://bats-core.readthedocs.io/)
- [BATS Guide](../BATS_GUIDE.md): Comprehensive guide on BATS usage
- [Test README](../../tests/README.md): Test suite documentation
- [bats-assert](https://github.com/bats-core/bats-assert): Assertion library
- [bats-file](https://github.com/bats-core/bats-file): File system assertions
- [bats-support](https://github.com/bats-core/bats-support): Support utilities

