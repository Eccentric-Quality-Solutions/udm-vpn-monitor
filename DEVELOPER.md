# Developer Guide

This guide provides information for developers contributing to the UDM VPN Monitor project, including tooling setup, development workflows, and code quality standards.

> **Note**: This guide focuses on **development setup** (tooling, git hooks, testing). For general installation instructions for end users, see the [Installation section in README.md](README.md#installation).

> **Important**: The prerequisites listed in this guide are for **development** (building, testing, contributing code). For **runtime requirements** (what's needed to run the VPN monitor on a UDM), see the [Requirements section in README.md](README.md#requirements).

## Getting Started

### First Time Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd udm-vpn-monitor
   ```

2. **Install development tools** (see [Development Tooling](#development-tooling) below)
   - ShellCheck (required)
   - shfmt (required)
   - bats (required)
   - kcov (optional, for coverage)

3. **Set up development environment PATH**:
   ```bash
   ./scripts/setup-dev-env.sh
   ```
   This script:
   - Checks for tools in standard system paths (`/usr/bin`, `/usr/local/bin`, `/bin`) for apt-installed tools
   - Checks for tools in Homebrew paths if Homebrew is installed
   - Adds Homebrew to PATH in your shell config (`.bashrc`, `.zshrc`, or `.profile`) if needed
   - Provides installation instructions for missing tools
   
   **Note**: The script works whether tools are installed via `apt` or Homebrew. It only modifies PATH if tools aren't already accessible. After running, reload your shell: `source ~/.bashrc` (or open a new terminal).

4. **Set up git hooks**:
   ```bash
   ./scripts/setup-git-hooks.sh
   ```
   This installs pre-commit hooks that:
   - Run ShellCheck linting on staged shell scripts (if ShellCheck is installed)
   - Check code formatting with shfmt on staged shell scripts (if shfmt is installed)
   - Automatically regenerate the installer package before each commit
   
   **Note**: The hooks will warn if ShellCheck or shfmt are not installed, but will still proceed with package regeneration. For best results, install both tools (see [Required Tools](#required-tools) below).

5. **Run tests to verify setup**
   ```bash
   ./tests/run_tests.sh
   ```
   All tests should pass. If not, check tool installation.

6. **Read the architecture documentation**
   - Start with [ARCHITECTURE.md](docs/ARCHITECTURE.md) to understand system design, component interactions, and technical implementation
   - Review [Architecture Decision Records](docs/adr/README.md) to understand design decisions
   - Review [docs/CODEBASE_REVIEW.md](docs/CODEBASE_REVIEW.md) for comprehensive codebase review and code quality analysis
   - Review [docs/ACCEPTABLE_RISKS.md](docs/ACCEPTABLE_RISKS.md) for documented acceptable risks and limitations
   - Check [TODO.md](TODO.md) for planned features

7. **Understand the codebase structure**
   - **Main Script**: `vpn-monitor.sh` - Entry point, orchestrates monitoring
   - **Library Modules**: Modular architecture with dedicated modules in `lib/` directory
     - See [ARCHITECTURE.md](docs/ARCHITECTURE.md) "Modular Library Architecture" section for complete module documentation
     - See [ADR-0005](docs/adr/0005-modular-library-architecture.md) for design decision rationale

8. **Pick a small issue to start**
   - Check [docs/CODEBASE_REVIEW.md](docs/CODEBASE_REVIEW.md) for improvement recommendations
   - Review [TODO.md](TODO.md) for planned features
   - Start with documentation improvements or small refactorings

### Understanding the Codebase

For comprehensive architecture information including:
- System architecture and component interactions
- Detection method flow and implementation details
- Recovery tier flow and technical details
- State management and file structure
- Code flow diagrams
- Library module documentation

See [ARCHITECTURE.md](docs/ARCHITECTURE.md).

For design decisions and rationale behind architectural choices, see [Architecture Decision Records](docs/adr/README.md).

**Testing:**

For comprehensive testing documentation including test structure, running tests, writing new tests, coverage reporting, and CI/CD integration, see [tests/README.md](tests/README.md).

The test suite includes **827 tests** across multiple test files:
- **Fast tests** (~605 tests): Run by default, include unit tests, script-specific tests, and split high-risk test files
- **Slow tests** (~222 tests): High-risk tests and integration tests, excluded by default (use `--slow` flag to include)

For test patterns and best practices, see [docs/TEST_PATTERNS.md](docs/TEST_PATTERNS.md).
For BATS framework guide and advanced features, see [docs/BATS_GUIDE.md](docs/BATS_GUIDE.md).

### Common Development Tasks

**Adding a New Feature:**
1. Create feature branch: `git checkout -b feature/new-feature`
2. Write tests first (TDD approach)
3. Implement feature
4. Run tests (see [tests/README.md](tests/README.md) for details)
5. Check code quality: `shellcheck` and `shfmt`
6. Update documentation
7. Submit pull request

**Fixing a Bug:**
1. Reproduce the bug
2. Write a test that fails (demonstrates the bug)
3. Fix the bug
4. Verify test passes
5. Run full test suite (see [tests/README.md](tests/README.md) for details)
6. Update CHANGELOG.md

**Refactoring:**
1. Ensure tests pass before refactoring (see [tests/README.md](tests/README.md) for details)
2. Make small, incremental changes
3. Run tests after each change
4. Keep functionality identical (no behavior changes)

## Documentation Overview

For a complete list of documentation files and their descriptions, see the [Documentation section in README.md](README.md#documentation).

All source files include comprehensive in-code function documentation with function purpose, parameters, return values, side effects, examples, and notes. When reading the codebase, refer to function documentation blocks for detailed information about each function's behavior, parameters, and usage.

## Development Tooling

> **Note**: These are **development prerequisites** for contributing to the project. For runtime requirements (what's needed to run the VPN monitor on a UDM), see the [Requirements section in README.md](README.md#requirements).

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

**Usage**: See [tests/README.md](tests/README.md) for detailed usage instructions.

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

**Usage**: See [tests/README.md](tests/README.md) for detailed coverage reporting instructions.

**Quick reference**:
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

### 0. Initial Setup

If you haven't already, set up your development environment:

```bash
# Configure PATH for development tools (shfmt, shellcheck)
./scripts/setup-dev-env.sh

# Set up git hooks
./scripts/setup-git-hooks.sh
```

The `setup-dev-env.sh` script automatically detects tools installed via `apt` or Homebrew and configures your PATH accordingly. After running it, reload your shell configuration or open a new terminal.

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

Always run tests before committing. For comprehensive testing documentation including all test options, parallel execution, and test categories, see [tests/README.md](tests/README.md).

**Quick workflow commands:**

```bash
# Run all tests
./tests/run_tests.sh

# Run tests with coverage
./tests/run_tests.sh --coverage

# Run specific test file
bats tests/test_vpn_monitor.sh
```

See [tests/README.md](tests/README.md) for complete testing documentation including test structure, writing new tests, coverage reporting, and CI/CD integration.

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

**Error Handling Strategy**

The codebase uses a consistent error handling strategy to ensure predictable behavior and maintainability. Follow these patterns when writing or modifying code:

**1. Fatal Errors (Script Should Exit)**

Use `die()` for fatal errors that prevent the script from continuing:

```bash
# When to use die():
# - Configuration errors (required config missing)
# - Critical system errors (cannot create required directories)
# - Security violations (invalid input that could be exploited)
# - Missing required dependencies (critical commands not available)

if [[ ! -f "$CONFIG_FILE" ]] && [[ -z "${EXTERNAL_PEER_IPS:-}" ]]; then
    die "Configuration file not found and EXTERNAL_PEER_IPS not set"
fi

if ! command -v ip >/dev/null 2>&1; then
    die "Required command 'ip' not found in PATH"
fi
```

**Pattern**: `die()` logs the error and exits the script with code 1. Use descriptive error messages that help users understand what went wrong and how to fix it.

**2. Non-Fatal Errors (Function Should Return Error Code)**

Functions that can fail gracefully should return error codes (0 = success, 1 = failure):

```bash
# When to return error codes:
# - Validation failures (invalid input, but script can continue)
# - Optional operations that fail (fallback available)
# - Operations that may fail but don't prevent script execution
# - Detection/check operations (VPN status checks, etc.)

check_vpn_status() {
    local peer_ip="$1"
    
    if ! validate_ip_address "$peer_ip"; then
        log_message "ERROR" "Invalid peer IP format: $peer_ip"
        return 1  # Return error code, don't die
    fi
    
    # ... check logic ...
    
    if [[ $vpn_ok -eq 0 ]]; then
        return 1  # VPN check failed
    fi
    
    return 0  # VPN is healthy
}

# Caller handles the error:
if ! check_vpn_status "$peer_ip"; then
    log_message "WARNING" "VPN check failed for $peer_ip"
    increment_failure "$peer_ip"
fi
```

**Pattern**: Return 0 for success, 1 for failure. Callers check the return code and handle errors appropriately.

**3. Warnings (Non-Fatal, Logged)**

Use `log_message "WARNING"` for non-fatal issues that should be logged but don't prevent execution:

```bash
# When to log warnings:
# - Optional features unavailable (fallback available)
# - Degraded functionality (works but not optimal)
# - Recoverable errors (can continue with reduced functionality)
# - Informational warnings (user should be aware)

if ! command -v ipsec >/dev/null 2>&1; then
    log_message "WARNING" "ipsec command not available"
    # Handle missing ipsec command
fi

if [[ ! -f "$cache_file" ]]; then
    log_message "WARNING" "Cache file not found: $cache_file (will recreate)"
    # Continue and recreate cache
fi
```

**Pattern**: Log the warning and continue execution. The warning alerts users to potential issues but doesn't stop the script.

**4. Error Handling Helper Functions**

For consistent error handling, use the provided helper functions:

```bash
# Logging (always available)
# System-level messages use "SYSTEM" prefix
log_message "INFO" "SYSTEM" "Operation completed successfully"
log_message "WARNING" "SYSTEM" "Optional feature unavailable"
log_message "ERROR" "SYSTEM" "Operation failed but continuing"
log_message "DEBUG" "SYSTEM" "Debug information"  # Only if DEBUG=1

# Location-specific messages use location name prefix
log_message "INFO" "NYC" "VPN check OK for NYC (192.168.1.1)"
log_message "WARNING" "NYC" "VPN check failed for NYC (192.168.1.1)"

# Unified error handling (recommended for consistency)
handle_error "WARNING" "SYSTEM" "Optional feature unavailable, using fallback"
handle_error "ERROR" "SYSTEM" "Critical configuration missing" 1  # Logs and exits
handle_error "INFO" "SYSTEM" "Operation completed with minor issues"
handle_error "WARNING" "NYC" "VPN check failed for NYC (192.168.1.1)"

# Fatal errors (direct call)
die "Fatal error message"  # Logs and exits with code 1 (uses SYSTEM prefix automatically)

# Check if command exists (logs warning if missing)
if ! warn_if_missing "ipsec"; then
    # Command not available, handle error
fi

# Check if command exists (returns error code, no logging)
if ! check_command_available "ip"; then
    return 1  # Command not available
fi
```

**`handle_error()` Function**:
The `handle_error()` function provides a unified interface for error handling:
- **Severity levels**: ERROR, WARNING, INFO
- **For ERROR severity**: Logs the message and exits if exit_code is non-zero
- **For WARNING/INFO severity**: Logs the message and continues execution
- **Usage**: `handle_error "SEVERITY" "message" [exit_code]`

This function standardizes error handling patterns and makes it easier to maintain consistent error handling across the codebase.

**`handle_error_or_exit_fake_mode()` Function**:
The `handle_error_or_exit_fake_mode()` function provides consistent error handling for fatal errors that need fake mode support:
- **Fake mode (NO_ESCALATE=1)**: Logs error and exits with code 0 (graceful exit for testing)
- **Normal mode**: Logs error and exits with specified exit code (default: 1)
- **Usage**: `handle_error_or_exit_fake_mode "prefix" "message" [exit_code]`
- **Location**: Defined in `lib/logging.sh` (centralized error handling)

**Important**: The prefix argument is REQUIRED. Use "SYSTEM" for system-level errors, or a location name for location-specific errors.

This function should be used instead of manually checking `is_fake_mode()` for fatal errors. It standardizes the pattern of handling errors differently based on fake mode.

**Error Code Constants**:
Standard exit codes are defined in `lib/constants.sh` for consistent error handling:
- `EXIT_SUCCESS=0` - Successful operation
- `EXIT_GENERAL_ERROR=1` - General error (default)
- `EXIT_CONFIG_ERROR=2` - Configuration file error
- `EXIT_VALIDATION_ERROR=3` - Validation error
- `EXIT_PERMISSION_ERROR=4` - Permission error
- `EXIT_COMMAND_NOT_FOUND=5` - Required command not found
- `EXIT_STATE_ERROR=6` - State file error

Use these constants instead of magic numbers for better readability:
```bash
handle_error_or_exit_fake_mode "SYSTEM" "Configuration validation failed" "${EXIT_VALIDATION_ERROR:-3}"
handle_error_or_exit_fake_mode "NYC" "Failed to get external IP" "${EXIT_VALIDATION_ERROR:-3}"
```

**5. Error Handling Patterns by Function Type**

**Validation Functions**:
```bash
# Return error codes, don't die
validate_ip_address() {
    local ip="$1"
    if [[ -z "$ip" ]]; then
        return 1  # Invalid
    fi
    # ... validation logic ...
    return 0  # Valid
}
```

**Detection Functions**:
```bash
# Return error codes, log warnings for failures
check_vpn_status() {
    # ... detection logic ...
    if [[ $detection_failed -eq 1 ]]; then
        log_message "WARNING" "VPN detection failed for $peer_ip"
        return 1
    fi
    return 0
}
```

**Recovery Functions**:
```bash
# Log errors/warnings, return error codes
surgical_cleanup() {
    if [[ "${ENABLE_XFRM_RECOVERY:-1}" -eq 1 ]]; then
        if ! attempt_xfrm_recovery "$peer_ip"; then
            log_message "WARNING" "xfrm recovery failed, falling back"
            # Try fallback
            if ! ipsec reload 2>/dev/null; then
                log_message "ERROR" "ipsec reload also failed"
                return 1  # Return error, don't die
            fi
        fi
    else
        if ! ipsec reload 2>/dev/null; then
            log_message "ERROR" "ipsec reload failed"
            return 1  # Return error, don't die
        fi
    fi
    return 0
}
```

**State Management Functions**:
```bash
# Log errors but continue (state operations shouldn't fail script)
increment_failure() {
    if ! (echo "$new_count" > "${counter_file}.tmp" && mv "${counter_file}.tmp" "$counter_file"); then
        log_message "ERROR" "Failed to update failure counter for $peer_ip"
        # Continue execution but log the error
        # Return error code so caller knows it failed
        return 1
    fi
    return 0
}
```

**6. Error Handling Best Practices**

- **Always check return codes**: Don't ignore return values from functions
  ```bash
  # Good
  if ! check_vpn_status "$peer_ip"; then
      handle_failure
  fi
  
  # Bad
  check_vpn_status "$peer_ip"  # Return value ignored
  ```

- **Provide context in error messages**: Include relevant information
  ```bash
  # Good
  log_message "ERROR" "Failed to update failure counter for $peer_ip (file: $counter_file)"
  
  # Bad
  log_message "ERROR" "Update failed"
  ```

- **Use appropriate log levels**: 
  - `ERROR`: Something went wrong but script continues
  - `WARNING`: Potential issue, degraded functionality
  - `INFO`: Normal operation, informational
  - `DEBUG`: Detailed debugging information (only if DEBUG=1)

- **Handle errors at the right level**: 
  - Low-level functions return error codes
  - High-level functions handle errors and decide whether to die() or continue

- **Don't suppress errors unnecessarily**: 
  ```bash
  # Good - explicit error handling
  if ! command 2>/dev/null; then
      log_message "WARNING" "Command failed, using fallback"
      fallback_command
  fi
  
  # Bad - silently ignoring errors
  command 2>/dev/null  # Errors hidden, no handling
  ```

**7. Standardized Error Handling Patterns**

**Pattern: Fake Mode Support (for fatal errors)**
```bash
# Use handle_error_or_exit_fake_mode() instead of manual is_fake_mode() checks
# OLD (don't use):
if is_fake_mode; then
    handle_error "ERROR" "Config error" 0
    exit 0
else
    die "Config error"
fi

# NEW (use this):
handle_error_or_exit_fake_mode "Config error" "${EXIT_CONFIG_ERROR:-2}"
```

**Pattern: Try-Fallback**
```bash
if command -v ipsec >/dev/null 2>&1; then
    ipsec reload
else
    die "ipsec command not available"
fi
```

**Pattern: Validate-Continue**
```bash
if ! validate_ip_address "$peer_ip"; then
    log_message "ERROR" "Invalid peer IP: $peer_ip"
    return 1  # Return error, don't die
fi
# Continue with validated input
```

**Pattern: Optional-Feature**
```bash
if [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
    if ! check_ping_connectivity "$target_ip"; then
        log_message "WARNING" "Ping check failed (optional feature)"
        # Continue - ping is optional
    fi
fi
```

**Pattern: Atomic-Write**
```bash
if ! (echo "$data" > "${file}.tmp" && mv "${file}.tmp" "$file"); then
    log_message "ERROR" "Failed to write state file: $file"
    return 1  # Return error, don't die (state operations shouldn't kill script)
fi
```

**8. Error Handling Checklist**

When writing or reviewing code, ensure:
- [ ] Fatal errors use `die()` or `handle_error_or_exit_fake_mode()` with descriptive messages
- [ ] Fatal errors that need fake mode support use `handle_error_or_exit_fake_mode()` instead of manual `is_fake_mode()` checks
- [ ] Error codes use constants from `lib/constants.sh` (EXIT_*) instead of magic numbers
- [ ] Non-fatal errors return error codes (0/1)
- [ ] Warnings are logged with `log_message "WARNING"`
- [ ] Return codes are checked by callers
- [ ] Error messages include context (peer IP, file path, etc.)
- [ ] Appropriate log levels are used (ERROR/WARNING/INFO/DEBUG)
- [ ] Errors are handled at the right level (low-level returns, high-level handles)
- [ ] Fallback mechanisms are used when appropriate
- [ ] State operations don't kill the script (log errors but continue)

**9. Examples of Good Error Handling**

See these functions for reference:
- `check_vpn_status()` in `lib/detection.sh` - Returns error codes, logs warnings
- `surgical_cleanup()` in `lib/recovery.sh` - Tries multiple methods, logs failures
- `validate_config()` in `lib/config.sh` - Uses `handle_error_or_exit_fake_mode()` for fatal config errors
- `ensure_directory_exists()` in `lib/config.sh` - Uses `handle_error_or_exit_fake_mode()` for fake mode support
- `handle_config_error()` in `lib/config.sh` - Uses `handle_error_or_exit_fake_mode()` for config parsing errors
- `increment_failure()` in `lib/state.sh` - Logs errors but continues execution

#### Documentation
- Document all functions with comprehensive comments describing:
  - Purpose and behavior
  - Parameters (with types and descriptions)
  - Return values and exit codes
  - Side effects (file operations, logging, etc.)
  - Usage examples (for complex functions)
  - Notes about dependencies and requirements

**Documentation Format:**
All functions follow a consistent documentation format with sections for Arguments, Returns, Side effects, Examples, and Notes.

Example:
```bash
# Check if VPN peer is active
#
# Verifies VPN tunnel health by checking IPsec Security Association state.
# Uses multiple detection methods with automatic fallback:
#   - Primary: ip xfrm state (SA state and byte counters)
#   - Fallback: ipsec status (if xfrm unavailable)
#   - Optional: Ping connectivity check (if enabled)
#
# Arguments:
#   $1: Peer IP address (external/public IP of remote VPN gateway)
#
# Returns:
#   0: VPN is healthy (SA exists, bytes increasing or non-zero)
#   1: VPN check failed (no SA found or bytes not increasing)
#
# Side effects:
#   - Creates/updates per-peer last_bytes file if byte counters found
#   - Logs debug/warning messages about VPN state
#
# Examples:
#   if check_vpn_status "203.0.113.1"; then
#       echo "VPN is healthy"
#   fi
#
# Note:
#   Requires validate_ip_address, sanitize_peer_ip, log_message, STATE_DIR,
#   ENABLE_PING_CHECK to be set.
#   Automatically detects available tools (xfrm, ipsec) and uses
#   appropriate fallbacks for compatibility across different UDM configurations.
check_vpn_status() {
	local peer_ip="$1"
	# ... implementation ...
}
```

**Documentation Standards:**
- All functions must have documentation blocks
- Use descriptive function names and parameter names
- Include examples for complex or commonly-used functions
- Document all side effects (file operations, logging, etc.)
- Note dependencies on other functions or global variables

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

For comprehensive testing documentation including:
- How to run tests
- Writing new tests
- Test structure and best practices
- Test coverage reporting
- CI/CD integration

See [tests/README.md](tests/README.md) for complete details.

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

### 8. Git Pre-commit Hook

This repository includes a pre-commit hook that runs code quality checks and automatically regenerates the installer package (`udm-vpn-monitor.zip`) before each commit. This ensures code quality and that the installer package is always up-to-date with the current codebase.

**Setup:**

The hooks are stored in `scripts/hooks/` (version controlled) and must be installed to `.git/hooks/`:

```bash
./scripts/setup-git-hooks.sh
```

This should be run once after cloning the repository (see [First Time Setup](#first-time-setup) above).

**What the hook does:**

1. **Code Quality Checks** (if tools are installed):
   - Runs ShellCheck on staged shell scripts to catch errors and security issues
   - Checks code formatting with shfmt on staged shell scripts
   - Validates function documentation standards (enforces ADR-0007)
   - Blocks commit if errors are found (with helpful error messages)
   - Warns if ShellCheck or shfmt are not installed (but allows commit to proceed)

2. **Package Regeneration**:
   - Runs `prepare_install_package.sh` to regenerate the installer package
   - Adds the generated `udm-vpn-monitor.zip` file to the commit
   - Ensures the package is always synchronized with source code changes

**Note**: The hook will warn if ShellCheck or shfmt are not installed, but will still proceed with package regeneration. For best results and to catch issues early, install both tools (see [Required Tools](#required-tools) above).

**Hook files:**
- **Source (version controlled)**: `scripts/hooks/pre-commit`
- **Installed location**: `.git/hooks/pre-commit`

**To bypass the hook** (not recommended):
```bash
git commit --no-verify -m "commit message"
```

**To manually test the hook:**
```bash
.git/hooks/pre-commit
```

**To reinstall hooks** (if hooks are updated):
```bash
./scripts/setup-git-hooks.sh
```

**Note:** The hook will fail if `prepare_install_package.sh` fails or if the package file cannot be created. Fix any issues before committing.

## Project Structure

```
udm-vpn-monitor/
├── analyze-logs.sh          # Log analysis utility
├── install.sh                # Installation script
├── uninstall.sh              # Uninstallation script
├── vpn-monitor.sh            # Main monitoring script
├── vpn-monitor.conf          # Configuration template
├── prepare_install_package.sh # Creates installer package
├── lib/
│   ├── common.sh            # Shared utilities (logging, validation)
│   ├── config.sh            # Configuration loading and validation
│   ├── config_schema.sh     # Configuration schema definitions
│   ├── constants.sh          # Named constants for magic numbers
│   ├── detection.sh          # VPN detection logic
│   ├── lockfile.sh           # Lockfile management
│   ├── logging.sh            # Centralized logging functionality
│   ├── recovery.sh           # Recovery action implementations
│   └── state.sh              # State file management
├── scripts/
│   ├── hooks/               # Git hooks (version controlled)
│   │   └── pre-commit       # Pre-commit hook
│   ├── setup-dev-env.sh    # Development environment setup (configures PATH)
│   └── setup-git-hooks.sh  # Hook installation script
├── tests/
│   ├── test_*.sh            # Test files
│   ├── test_helper.bash     # Test utilities
│   ├── run_tests.sh         # Test runner
│   └── generate_coverage_report.sh
├── README.md                 # User documentation
├── docs/
│   ├── ARCHITECTURE.md       # Architecture documentation
│   ├── CODEBASE_REVIEW.md    # Comprehensive codebase review
│   ├── ACCEPTABLE_RISKS.md   # Documented acceptable risks and limitations
│   └── ...                   # Additional documentation files
├── CHANGELOG.md              # Version history
├── DEVELOPER.md              # This file
├── QUICK_START.md            # 5-minute setup guide
├── TODO.md                   # Planned features and improvements
└── TROUBLESHOOTING.md        # Troubleshooting guide
```

## Contributing

### Before Submitting

1. **Install all required tools** (see above)
2. **Run code quality checks**:
   ```bash
   shfmt -w *.sh lib/*.sh tests/*.sh
   shellcheck --severity=error *.sh lib/*.sh tests/*.sh
   ```
3. **Run all tests** (see [tests/README.md](tests/README.md) for details):
   ```bash
   ./tests/run_tests.sh
   ```
4. **Check test coverage** (if kcov is installed; see [tests/README.md](tests/README.md) for details):
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

For comprehensive troubleshooting guidance and test failure diagnosis, see [tests/README.md](tests/README.md).

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
- Review [ARCHITECTURE.md](docs/ARCHITECTURE.md) for design decisions
- Review [docs/CODEBASE_REVIEW.md](docs/CODEBASE_REVIEW.md) for comprehensive codebase review and code quality analysis
- Review [docs/ACCEPTABLE_RISKS.md](docs/ACCEPTABLE_RISKS.md) for documented acceptable risks and limitations
- Review [TODO.md](TODO.md) for planned features
- Open an issue on GitHub for bugs or questions

