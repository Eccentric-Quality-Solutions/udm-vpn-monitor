# Developer Guide

This guide provides information for developers contributing to the UDM VPN Monitor project, including tooling setup, development workflows, and code quality standards.

## Documentation Overview

- **[README.md](README.md)** - User-facing documentation, installation, and usage instructions
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System architecture, design decisions, and component interactions
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and release notes
- **[ENHANCEMENTS.md](ENHANCEMENTS.md)** - Future enhancement ideas and roadmap
- **[tests/README.md](tests/README.md)** - Comprehensive testing documentation

## Development Tooling

This project uses several tools for code quality, testing, and formatting. All tools should be installed before contributing code.

### Required Tools

#### ShellCheck - Static Analysis Tool

**Purpose**: Lints shell scripts for common errors, security issues, and best practices.

**Installation**:

```bash
# macOS (Homebrew)
brew install shellcheck

# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y shellcheck

# Fedora/RHEL
sudo dnf install -y ShellCheck

# From source (latest version)
# See: https://github.com/koalaman/shellcheck#installing
```

**Usage**:
```bash
# Check all shell scripts
shellcheck *.sh lib/*.sh tests/*.sh

# Check specific file
shellcheck vpn-monitor.sh

# Check with specific severity
shellcheck --severity=error *.sh
```

**Documentation**: https://www.shellcheck.net/

#### shfmt - Shell Script Formatter

**Purpose**: Formats shell scripts consistently using tabs for indentation.

**Installation**:

```bash
# macOS (Homebrew)
brew install shfmt

# Linux (Snap)
sudo snap install shfmt

# Linux (Go install)
go install mvdan.cc/sh/v3/cmd/shfmt@latest

# Or download binary from GitHub releases
# https://github.com/mvdan/sh/releases
```

**Usage**:
```bash
# Format all shell scripts (in-place)
shfmt -w *.sh lib/*.sh tests/*.sh

# Check formatting without modifying files
shfmt -d *.sh

# Format specific file
shfmt -w vpn-monitor.sh
```

**Documentation**: https://github.com/mvdan/sh

#### bats - Bash Automated Testing System

**Purpose**: Testing framework for shell scripts.

**Installation**:

```bash
# macOS (Homebrew)
brew install bats-core

# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y bats

# Fedora/RHEL
sudo dnf install -y bats

# From source
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

**Usage**:
```bash
# Run all tests
./tests/run_tests.sh

# Run specific test file
bats tests/test_vpn_monitor.sh

# Run with verbose output
bats --verbose tests/test_*.sh
```

**Documentation**: https://github.com/bats-core/bats-core

### Optional Tools (Recommended)

#### kcov - Code Coverage Tool

**Purpose**: Generates test coverage reports for shell scripts.

**Installation**:

```bash
# macOS (Homebrew)
brew install kcov

# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y kcov

# Fedora/RHEL
sudo dnf install -y kcov

# From source
git clone https://github.com/SimonKagstrom/kcov.git
cd kcov
mkdir build && cd build
cmake ..
make
sudo make install
```

**Usage**:
```bash
# Run tests with coverage
./tests/run_tests.sh --coverage

# Generate coverage report
./tests/generate_coverage_report.sh

# View HTML report
open coverage/index.html  # macOS
xdg-open coverage/index.html  # Linux
```

**Documentation**: https://github.com/SimonKagstrom/kcov

#### jq - JSON Processor

**Purpose**: Parses JSON data (useful for coverage reports and data processing).

**Installation**:

```bash
# macOS (Homebrew)
brew install jq

# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y jq

# Fedora/RHEL
sudo dnf install -y jq
```

**Usage**:
```bash
# Parse JSON file
jq '.merged_percent_covered' coverage/index.json

# Pretty print JSON
jq . coverage/index.json
```

**Documentation**: https://stedolan.github.io/jq/

#### bats Helper Libraries

**Purpose**: Additional assertion functions for bats tests.

**Installation**:
```bash
# Install helper libraries
./tests/install_bats_helpers.sh
```

This installs:
- `bats-support` - Output and error handling helpers
- `bats-assert` - Additional assertion functions
- `bats-file` - File system assertions

## Development Workflow

### 1. Code Quality Checks

Before committing code, run both ShellCheck and shfmt:

```bash
# Format code
shfmt -w *.sh lib/*.sh tests/*.sh

# Check for errors
shellcheck --severity=error *.sh lib/*.sh tests/*.sh

# Check all warnings (review and fix as needed)
shellcheck *.sh lib/*.sh tests/*.sh
```

### 2. Running Tests

Always run tests before committing:

```bash
# Run all tests
./tests/run_tests.sh

# Run tests with coverage
./tests/run_tests.sh --coverage

# Run specific test file
bats tests/test_vpn_monitor.sh

# Run specific test
bats tests/test_vpn_monitor.sh -t "test name pattern"
```

### 3. CI/CD Pipeline

This project uses GitHub Actions for continuous integration. The CI pipeline runs automatically on every push and pull request.

**CI Pipeline Steps:**

1. **Linting** - Runs ShellCheck to detect errors and security issues
2. **Format Checking** - Verifies code formatting with shfmt
3. **Testing** - Runs the full test suite with bats
4. **Coverage Reporting** - Generates test coverage reports with kcov

**Workflow File:** `.github/workflows/ci.yml`

**Viewing CI Results:**

- Check the [Actions](https://github.com/YOUR_USERNAME/udm-vpn-monitor/actions) tab on GitHub
- CI status badges appear on pull requests
- Coverage reports are uploaded as artifacts

**Local CI Checks:**

Before pushing, ensure all CI checks pass locally:

```bash
# Format code
shfmt -w *.sh lib/*.sh tests/*.sh

# Check formatting (should produce no output)
shfmt -d *.sh lib/*.sh tests/*.sh

# Run linting
shellcheck --severity=error *.sh lib/*.sh tests/*.sh

# Run tests
./tests/run_tests.sh
```

**CI Failure:**

If CI fails:
1. Check the Actions tab for detailed error messages
2. Run the failing step locally to reproduce the issue
3. Fix the issue and push again
4. CI will automatically re-run on push

### 4. Code Style Guidelines

#### Indentation
- Use **tabs** for indentation (enforced by shfmt)
- Tab width: 8 spaces (default)

#### Variable Naming
- Use `UPPERCASE` for constants and environment variables
- Use `lowercase_with_underscores` for local variables
- Use descriptive names: `failure_count` not `fc`

#### Function Naming
- Use `lowercase_with_underscores` for function names
- Use descriptive names: `check_vpn_status()` not `check()`

#### Error Handling
- Use `set -euo pipefail` at the top of scripts
- Check return codes explicitly: `if ! command; then ...`
- Provide meaningful error messages

#### Documentation
- Document all functions with comments describing:
  - Purpose
  - Parameters
  - Return values
  - Side effects

Example:
```bash
# Check if VPN peer is active
# Parameters:
#   $1: Peer IP address
# Returns:
#   0: Peer is active
#   1: Peer is inactive or error
check_vpn_peer() {
	local peer_ip="$1"
	# ... implementation ...
}
```

### 5. ShellCheck Guidelines

#### Addressing Warnings

- **SC2034** (unused variable): Remove if truly unused, or mark with `# shellcheck disable=SC2034` if intentionally unused
- **SC2155** (declare and assign separately): Split declaration and assignment for better error handling
- **SC2162** (read without -r): Add `-r` flag to `read` commands
- **SC2129** (multiple redirects): Use `{ cmd1; cmd2; } >> file` for multiple redirects

#### Disabling Checks

Use sparingly and document why:

```bash
# shellcheck disable=SC2034
# This variable is used by sourced scripts
CONFIG_VAR="value"
```

### 6. Testing Guidelines

#### Writing Tests

- Place tests in `tests/test_*.sh` files
- Use descriptive test names: `@test "vpn-monitor.sh detects VPN failure"`
- Test both success and failure cases
- Use test helpers from `tests/test_helper.bash`
- Mock external commands when possible

#### Test Structure

```bash
#!/usr/bin/env bats

load test_helper

@test "function_name handles valid input" {
	# Arrange
	local input="test"
	
	# Act
	local result=$(function_name "$input")
	
	# Assert
	assert_equal "$result" "expected"
}
```

### 7. Commit Guidelines

- Write clear, descriptive commit messages
- Reference issue numbers if applicable
- Keep commits focused on a single change
- Run tests and linting before committing

Example commit message:
```
Fix lockfile race condition in vpn-monitor.sh

- Remove 'local' keywords used outside functions
- Fix ShellCheck SC2168 errors
- Add proper error handling for lockfile creation

Fixes #123
```

## Project Structure

```
udm-vpn-monitor/
├── analyze-logs.sh          # Log analysis utility
├── install.sh                # Installation script
├── uninstall.sh              # Uninstallation script
├── vpn-monitor.sh            # Main monitoring script
├── vpn-monitor.conf          # Configuration template
├── lib/
│   └── common.sh            # Shared library functions
├── tests/
│   ├── test_*.sh            # Test files
│   ├── test_helper.bash     # Test utilities
│   ├── run_tests.sh         # Test runner
│   └── generate_coverage_report.sh
├── README.md                 # User documentation
├── ARCHITECTURE.md           # Architecture documentation
├── CHANGELOG.md              # Version history
├── DEVELOPER.md              # This file
└── ENHANCEMENTS.md           # Future enhancements
```

## Contributing

### Before Submitting

1. **Install all required tools** (see above)
2. **Run code quality checks**:
   ```bash
   shfmt -w *.sh lib/*.sh tests/*.sh
   shellcheck --severity=error *.sh lib/*.sh tests/*.sh
   ```
3. **Run all tests**:
   ```bash
   ./tests/run_tests.sh
   ```
4. **Check test coverage** (if kcov is installed):
   ```bash
   ./tests/run_tests.sh --coverage
   ```
5. **Update documentation** if adding features or changing behavior
6. **Update CHANGELOG.md** with your changes

### Pull Request Checklist

- [ ] All tests pass
- [ ] ShellCheck passes with no errors
- [ ] Code is formatted with shfmt
- [ ] Documentation is updated
- [ ] CHANGELOG.md is updated
- [ ] Code follows style guidelines
- [ ] Changes are tested on UDM system (if applicable)

## Troubleshooting

### ShellCheck Errors

If ShellCheck reports errors:

1. Read the error message and SC code
2. Check the ShellCheck wiki: https://www.shellcheck.net/wiki/
3. Fix the issue or document why it's disabled
4. Re-run ShellCheck to verify

### Test Failures

If tests fail:

1. Run tests with verbose output: `bats --verbose tests/test_*.sh`
2. Check test output for specific failures
3. Verify test environment setup
4. Check `tests/test_helper.bash` for helper functions

### Formatting Issues

If shfmt makes unexpected changes:

1. Review the diff: `shfmt -d file.sh`
2. Check shfmt configuration (if using `.editorconfig` or similar)
3. Adjust code to match shfmt's expectations
4. Re-run shfmt to verify

## Additional Resources

- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [shfmt Documentation](https://github.com/mvdan/sh)
- [bats-core Documentation](https://github.com/bats-core/bats-core)
- [Bash Guide](https://mywiki.wooledge.org/BashGuide)
- [Shell Script Best Practices](https://github.com/koalaman/shellcheck/wiki)

## Getting Help

- Check existing documentation in this repository
- Review [ARCHITECTURE.md](ARCHITECTURE.md) for design decisions
- Review [ENHANCEMENTS.md](ENHANCEMENTS.md) for planned features
- Open an issue on GitHub for bugs or questions

