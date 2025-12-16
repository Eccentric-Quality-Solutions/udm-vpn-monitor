#!/usr/bin/env bash
#
# Test helper functions for UDM VPN Monitor tests
# Provides common utilities for test scripts

# Load bats helper functions if available (optional)
# These provide additional assertion functions but tests work without them
# Helpers are located in the tests directory alongside test files
if [[ -d "${BATS_TEST_DIRNAME}/bats-support" ]]; then
    load "${BATS_TEST_DIRNAME}/bats-support/load.bash" 2>/dev/null || true
fi
if [[ -d "${BATS_TEST_DIRNAME}/bats-assert" ]]; then
    load "${BATS_TEST_DIRNAME}/bats-assert/load.bash" 2>/dev/null || true
fi
if [[ -d "${BATS_TEST_DIRNAME}/bats-file" ]]; then
    load "${BATS_TEST_DIRNAME}/bats-file/load.bash" 2>/dev/null || true
fi

# Fallback implementations for standard bats functions
# Bats-core doesn't provide these by default (they're in bats-assert)
# So we always define our own versions that work with or without bats-assert

assert_success() {
    if [[ "${status:-}" -ne 0 ]]; then
        echo "Expected success but got exit code ${status:-unknown}" >&2
        if [[ -n "${output:-}" ]]; then
            echo "Output: $output" >&2
        fi
        return 1
    fi
}

assert_failure() {
    if [[ "${status:-0}" -eq 0 ]]; then
        echo "Expected failure but got exit code 0" >&2
        if [[ -n "${output:-}" ]]; then
            echo "Output: $output" >&2
        fi
        return 1
    fi
}

assert_output() {
    local pattern=""
    local use_partial=0
    
    # Parse arguments - handle --partial flag
    if [[ "$1" == "--partial" ]]; then
        use_partial=1
        pattern="${2:-}"
    elif [[ "${2:-}" == "--partial" ]]; then
        use_partial=1
        pattern="$1"
    else
        pattern="${1:-}"
    fi
    
    if [[ -z "${output:-}" ]]; then
        echo "Expected output to contain: $pattern" >&2
        echo "Actual output: (empty)" >&2
        return 1
    fi
    
    if [[ $use_partial -eq 1 ]]; then
        # Use grep -F for fixed strings and -- to prevent --pattern from being interpreted as option
        if ! echo "$output" | grep -Fq -- "$pattern"; then
            echo "Expected output to contain: $pattern" >&2
            echo "Actual output: $output" >&2
            return 1
        fi
    else
        if [[ "$output" != "$pattern" ]]; then
            echo "Expected output: $pattern" >&2
            echo "Actual output: $output" >&2
            return 1
        fi
    fi
}

refute_output() {
    local pattern=""
    local use_partial=0
    
    # Parse arguments - handle --partial flag
    if [[ "$1" == "--partial" ]]; then
        use_partial=1
        pattern="${2:-}"
    elif [[ "${2:-}" == "--partial" ]]; then
        use_partial=1
        pattern="$1"
    else
        pattern="${1:-}"
    fi
    
    if [[ -z "${output:-}" ]]; then
        return 0  # Empty output doesn't contain pattern
    fi
    
    if [[ $use_partial -eq 1 ]]; then
        # Use grep -F for fixed strings and -- to prevent --pattern from being interpreted as option
        if echo "$output" | grep -Fq -- "$pattern"; then
            echo "Expected output to not contain: $pattern" >&2
            echo "Actual output: $output" >&2
            return 1
        fi
    else
        if [[ "$output" == "$pattern" ]]; then
            echo "Expected output to not equal: $pattern" >&2
            echo "Actual output: $output" >&2
            return 1
        fi
    fi
}

fail() {
    local message="${1:-Test failed}"
    echo "$message" >&2
    return 1
}

assert() {
    if ! eval "$@"; then
        echo "Assertion failed: $*" >&2
        return 1
    fi
}

# Test directory for temporary files
TEST_TMPDIR="${BATS_TEST_TMPDIR:-/tmp/bats-test-$$}"

# Setup function run before each test
#
# Bats framework calls this function automatically before each test.
# Creates a clean test environment with temporary directories and mock structures.
#
# Side effects:
#   - Creates TEST_DIR for this test
#   - Creates MOCK_DATA_DIR and MOCK_INSTALL_DIR
#   - Saves original PWD and HOME
#   - Sets TEST_DIR, MOCK_DATA_DIR, MOCK_INSTALL_DIR environment variables
setup() {
    # Create temporary directory for this test
    TEST_DIR="${TEST_TMPDIR}/test-$$-${BATS_TEST_NUMBER}"
    mkdir -p "$TEST_DIR"
    
    # Create mock directories
    MOCK_DATA_DIR="${TEST_DIR}/data"
    MOCK_INSTALL_DIR="${MOCK_DATA_DIR}/vpn-monitor"
    mkdir -p "$MOCK_INSTALL_DIR"
    
    # Create mock /data directory structure
    mkdir -p "${MOCK_DATA_DIR}"
    
    # Save original paths
    ORIGINAL_PWD="$PWD"
    ORIGINAL_HOME="$HOME"
    
    # Set test environment
    export TEST_DIR
    export MOCK_DATA_DIR
    export MOCK_INSTALL_DIR
}

# Teardown function run after each test
#
# Bats framework calls this function automatically after each test.
# Cleans up test environment and restores original state.
#
# Side effects:
#   - Removes TEST_DIR and all contents
#   - Restores original working directory
#   - Removes test cron entries containing "test-vpn-monitor"
teardown() {
    # Clean up test directory
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
    
    # Restore original directory
    cd "$ORIGINAL_PWD" || true
    
    # Clean up any test cron entries
    if command -v crontab >/dev/null 2>&1; then
        crontab -l 2>/dev/null | grep -v "test-vpn-monitor" | crontab - || true
    fi
}

# Create a mock config file
#
# Creates a test configuration file with default test values.
# Used by tests to set up a valid configuration without manual file creation.
#
# Arguments:
#   $1: Optional path to config file (defaults to ${MOCK_INSTALL_DIR}/vpn-monitor.conf)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created config file
create_mock_config() {
    local config_file="${1:-${MOCK_INSTALL_DIR}/vpn-monitor.conf}"
    cat > "$config_file" << 'EOF'
# Test configuration
PEER_IPS="192.168.1.1 10.0.0.1"
VPN_NAME="Test VPN"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
MAX_RESTARTS_PER_HOUR=3
LOG_FILE="/data/vpn-monitor/logs/vpn-monitor.log"
STATE_DIR="/data/vpn-monitor"
CRON_SCHEDULE="*/1 * * * *"
LOCKFILE_TIMEOUT=300
ENABLE_PING_CHECK=1
PING_TARGET_IP=""
PING_COUNT=3
PING_TIMEOUT=2
DEBUG=0
EOF
    echo "$config_file"
}

# Create a mock vpn-monitor.sh script
#
# Creates a simple mock script that exits successfully.
# Used for testing installation/uninstallation without requiring the full script.
#
# Arguments:
#   $1: Optional path to script file (defaults to ${MOCK_INSTALL_DIR}/vpn-monitor.sh)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created script file
create_mock_vpn_monitor_script() {
    local script_file="${1:-${MOCK_INSTALL_DIR}/vpn-monitor.sh}"
    cat > "$script_file" << 'EOF'
#!/bin/bash
# Mock VPN monitor script for testing
echo "Mock VPN monitor script"
exit 0
EOF
    chmod +x "$script_file"
    echo "$script_file"
}

# Mock root user
#
# Sets MOCK_ROOT environment variable to simulate root user.
# Note: EUID is readonly in bash, so actual root status cannot be changed.
# Tests that need root should be run with appropriate permissions or use wrapper scripts.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Sets MOCK_ROOT=1 environment variable
mock_root() {
    export MOCK_ROOT=1
    # For tests, we'll need to either:
    # 1. Run tests with sudo
    # 2. Modify scripts to check MOCK_ROOT env var
    # 3. Use wrapper scripts
    # For now, tests that need root should be run with appropriate permissions
}

# Mock non-root user
#
# Sets MOCK_ROOT environment variable to simulate non-root user.
# Note: EUID is readonly in bash, so actual user status cannot be changed.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Sets MOCK_ROOT=0 environment variable
mock_non_root() {
    export MOCK_ROOT=0
    # EUID is readonly, so we can't actually change it
    # Tests will need to handle this differently
}

# Mock UDM system (create /data directory)
#
# Creates mock /data directory structure to simulate UDM system.
# Sets MOCK_UDM_DATA environment variable pointing to the mock data directory.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Creates ${MOCK_DATA_DIR} directory
#   Sets MOCK_UDM_DATA environment variable
mock_udm_system() {
    mkdir -p "${MOCK_DATA_DIR}"
    # Create symlink or mount point simulation
    if [[ ! -d "/data" ]] && [[ -w "${MOCK_DATA_DIR}" ]]; then
        # In test environment, we can't create /data, so we'll use TEST_DIR
        export MOCK_UDM_DATA="${MOCK_DATA_DIR}"
    fi
}

# Mock non-UDM system (no /data directory)
#
# Removes mock /data directory to simulate non-UDM system.
# Used to test error handling when UDM-specific directories are missing.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Removes ${MOCK_DATA_DIR} directory if it exists
mock_non_udm_system() {
    # Ensure /data doesn't exist in test environment
    if [[ -d "${MOCK_DATA_DIR}" ]]; then
        rm -rf "${MOCK_DATA_DIR}"
    fi
}

# Fallback assertions if helper libraries not available
if ! type assert_file_exist >/dev/null 2>&1; then
    # Basic file existence assertion
    #
    # Verifies that a file exists. Fails the test if file doesn't exist.
    #
    # Arguments:
    #   $1: Path to file to check
    #
    # Returns:
    #   0: File exists
    #   1: File doesn't exist (fails test)
    assert_file_exist() {
        local file="$1"
        if [[ ! -f "$file" ]]; then
            fail "File does not exist: $file"
        fi
    }
    
    # Basic directory existence assertion
    #
    # Verifies that a directory exists. Fails the test if directory doesn't exist.
    #
    # Arguments:
    #   $1: Path to directory to check
    #
    # Returns:
    #   0: Directory exists
    #   1: Directory doesn't exist (fails test)
    assert_dir_exist() {
        local dir="$1"
        if [[ ! -d "$dir" ]]; then
            fail "Directory does not exist: $dir"
        fi
    }
    
    # Basic directory non-existence assertion
    #
    # Verifies that a directory does NOT exist. Fails the test if directory exists.
    #
    # Arguments:
    #   $1: Path to directory to check
    #
    # Returns:
    #   0: Directory doesn't exist
    #   1: Directory exists (fails test)
    assert_dir_not_exist() {
        local dir="$1"
        if [[ -d "$dir" ]]; then
            fail "Directory should not exist: $dir"
        fi
    }
    
    # Basic file non-existence assertion
    #
    # Verifies that a file does NOT exist. Fails the test if file exists.
    #
    # Arguments:
    #   $1: Path to file to check
    #
    # Returns:
    #   0: File doesn't exist
    #   1: File exists (fails test)
    assert_file_not_exist() {
        local file="$1"
        if [[ -f "$file" ]]; then
            fail "File should not exist: $file"
        fi
    }
    
    # Basic file contains assertion
    #
    # Verifies that a file contains a specific pattern (fixed string match).
    # Fails the test if pattern is not found or file doesn't exist.
    #
    # Arguments:
    #   $1: Path to file to check
    #   $2: Pattern to search for (fixed string, not regex)
    #
    # Returns:
    #   0: Pattern found in file
    #   1: Pattern not found or file doesn't exist (fails test)
    assert_file_contains() {
        local file="$1"
        local pattern="$2"
        if [[ ! -f "$file" ]]; then
            fail "File does not exist: $file"
        fi
        if ! grep -Fq -- "$pattern" "$file"; then
            fail "File does not contain pattern: $pattern"
        fi
    }
    
fi

# Always define refute_file_contains (needed even if bats-file is loaded)
# bats-file may provide it, but we ensure it's available with consistent behavior
if ! type refute_file_contains >/dev/null 2>&1; then
    # Refute file contains assertion
    #
    # Verifies that a file does NOT contain a specific pattern.
    # Succeeds if file doesn't exist (empty file doesn't contain pattern).
    # Fails the test if pattern is found.
    #
    # Arguments:
    #   $1: Path to file to check
    #   $2: Pattern to search for (fixed string, not regex)
    #
    # Returns:
    #   0: Pattern not found (or file doesn't exist)
    #   1: Pattern found (fails test)
    refute_file_contains() {
        local file="$1"
        local pattern="$2"
        if [[ -f "$file" ]] && grep -Fq -- "$pattern" "$file"; then
            fail "File should not contain pattern: $pattern"
        fi
    }
fi

# Create test install.sh setup with lib directory
#
# Creates a test directory structure with install.sh and the required lib directory.
# This ensures install.sh can find lib/common.sh when sourced.
#
# Arguments:
#   $1: Path to original install.sh script
#   $2: Path where test install.sh should be created (directory will be created)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created test install.sh script
#
# Side effects:
#   Creates test directory structure with install.sh and lib/ directory
create_test_install_setup() {
	local original_install="$1"
	local test_install_dir="$2"
	local project_root
	project_root=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
	
	# Create test source directory
	mkdir -p "$test_install_dir"
	
	# Copy install.sh
	cp "$original_install" "${test_install_dir}/install.sh"
	chmod +x "${test_install_dir}/install.sh"
	
	# Copy lib directory
	cp -r "${project_root}/lib" "${test_install_dir}/lib"
	
	echo "${test_install_dir}/install.sh"
}

# Create a test version of vpn-monitor.sh with custom paths
#
# Creates a modified copy of vpn-monitor.sh with test-specific paths.
# Modifies CONFIG_FILE, STATE_DIR, LOG_FILE, and LOCKFILE variables using sed.
# This allows tests to run the actual script with test directories instead of /data/.
#
# Arguments:
#   $1: Path to original vpn-monitor.sh script
#   $2: Path where test script should be created
#   $3: Optional custom CONFIG_FILE path
#   $4: Optional custom STATE_DIR path
#   $5: Optional custom LOG_FILE path
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created test script
#
# Side effects:
#   Creates a modified copy of the original script with test paths
create_test_vpn_monitor_script() {
    local original_script="$1"
    local test_script="$2"
    local config_file="${3:-}"
    local state_dir="${4:-}"
    local log_file="${5:-}"
    
    # Get the project root directory (parent of tests directory)
    local project_root
    project_root=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
    
    # Copy the original script
    cp "$original_script" "$test_script"
    chmod +x "$test_script"
    
    # Modify the script to use test paths
    # Need to escape special characters for sed
    if [[ -n "$config_file" ]]; then
        # Escape forward slashes and other special chars
        local escaped_config
        escaped_config=$(echo "$config_file" | sed 's/[[\.*^$()+?{|]/\\&/g')
        sed -i "s|^CONFIG_FILE=.*|CONFIG_FILE=\"${escaped_config}\"|" "$test_script"
    fi
    if [[ -n "$state_dir" ]]; then
        local escaped_state
        escaped_state=$(echo "$state_dir" | sed 's/[[\.*^$()+?{|]/\\&/g')
        sed -i "s|^STATE_DIR=.*|STATE_DIR=\"${escaped_state}\"|" "$test_script"
        # Also update LOCKFILE which depends on STATE_DIR
        sed -i "s|^LOCKFILE=.*|LOCKFILE=\"${escaped_state}/vpn-monitor.lock\"|" "$test_script"
    fi
    if [[ -n "$log_file" ]]; then
        local escaped_log
        escaped_log=$(echo "$log_file" | sed 's/[[\.*^$()+?{|]/\\&/g')
        sed -i "s|^LOG_FILE=.*|LOG_FILE=\"${escaped_log}\"|" "$test_script"
    fi
    
    # Fix module source paths to use absolute paths from project root
    # This ensures modules can be found even when script is copied to test directory
    local escaped_project_root
    escaped_project_root=$(echo "$project_root" | sed 's/[[\.*^$()+?{|]/\\&/g')
    sed -i "s|source \"\${SCRIPT_DIR}/lib/|source \"${escaped_project_root}/lib/|g" "$test_script"
    
    echo "$test_script"
}

# Assert file exists and is executable
#
# Verifies that a file exists and has executable permissions.
# Fails the test if file doesn't exist or is not executable.
#
# Arguments:
#   $1: Path to file to check
#
# Returns:
#   0: File exists and is executable
#   1: File doesn't exist or is not executable (fails test)
assert_file_executable() {
    local file="$1"
    assert_file_exist "$file"
    if [[ ! -x "$file" ]]; then
        fail "File is not executable: $file"
    fi
}

# Assert cron entry exists
#
# Verifies that a cron entry matching the pattern exists in the crontab.
# Fails the test if pattern is not found.
#
# Arguments:
#   $1: Pattern to search for in crontab (partial match)
#
# Returns:
#   0: Cron entry found
#   1: Cron entry not found (fails test)
assert_cron_entry_exists() {
    local pattern="$1"
    run crontab -l 2>/dev/null
    assert_success
    assert_output --partial "$pattern"
}

# Assert cron entry does not exist
#
# Verifies that a cron entry matching the pattern does NOT exist in the crontab.
# Fails the test if pattern is found.
#
# Arguments:
#   $1: Pattern to search for in crontab (regex)
#
# Returns:
#   0: Cron entry not found
#   1: Cron entry found (fails test)
assert_cron_entry_not_exists() {
    local pattern="$1"
    run crontab -l 2>/dev/null
    if [[ $status -eq 0 ]]; then
        refute_output --regexp "$pattern"
    fi
}

# Create a test cron entry
#
# Adds a test cron entry to the current user's crontab.
# Used to set up test environment with cron entries.
#
# Arguments:
#   $1: Cron schedule (default: "*/1 * * * *")
#   $2: Script path (default: "/data/vpn-monitor/vpn-monitor.sh")
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Adds cron entry to current user's crontab
create_test_cron_entry() {
    local schedule="${1:-*/1 * * * *}"
    local script_path="${2:-/data/vpn-monitor/vpn-monitor.sh}"
    local cron_entry="${schedule} ${script_path} >> /tmp/test-cron.log 2>&1"
    (crontab -l 2>/dev/null || true; echo "$cron_entry") | crontab -
}

# Get script directory (for sourcing scripts)
#
# Returns the absolute path of the directory containing a script file.
# Useful for determining script locations in tests.
#
# Arguments:
#   $1: Path to script file
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the absolute directory path
get_script_dir() {
    local script_path="$1"
    echo "$(cd "$(dirname "$script_path")" && pwd)"
}

# Run script with captured output
#
# Executes a script in the test directory and captures its output.
# Changes to test directory before running to ensure relative paths work.
#
# Arguments:
#   $1: Path to script to run
#   $2+: Additional arguments to pass to script
#
# Returns:
#   Exit code of the script
#
# Side effects:
#   Changes working directory to TEST_DIR
#   Sets 'output' and 'status' variables (bats convention)
run_script() {
    local script="$1"
    shift
    local args=("$@")
    
    # Change to test directory
    cd "$TEST_DIR" || return 1
    
    # Run script with arguments
    run bash "$script" "${args[@]}"
}

# Assert log file contains pattern
#
# Verifies that a log file contains a specific pattern (fixed string match).
# Fails the test if pattern is not found or file doesn't exist.
#
# Arguments:
#   $1: Path to log file
#   $2: Pattern to search for (fixed string, not regex)
#
# Returns:
#   0: Pattern found in log file
#   1: Pattern not found or file doesn't exist (fails test)
assert_log_contains() {
    local log_file="$1"
    local pattern="$2"
    
    if [[ ! -f "$log_file" ]]; then
        fail "Log file does not exist: $log_file"
    fi
    
    run grep -Fq -- "$pattern" "$log_file"
    assert_success "Log file should contain: $pattern"
}

# Assert log file does not contain pattern
#
# Verifies that a log file does NOT contain a specific pattern.
# Succeeds if file doesn't exist (empty file doesn't contain pattern).
# Fails the test if pattern is found.
#
# Arguments:
#   $1: Path to log file
#   $2: Pattern to search for (fixed string, not regex)
#
# Returns:
#   0: Pattern not found (or file doesn't exist)
#   1: Pattern found (fails test)
assert_log_not_contains() {
    local log_file="$1"
    local pattern="$2"
    
    if [[ ! -f "$log_file" ]]; then
        return 0  # File doesn't exist, so pattern doesn't exist
    fi
    
    run grep -Fq -- "$pattern" "$log_file"
    assert_failure "Log file should not contain: $pattern"
}

# Create mock ip command output
#
# Creates a mock 'ip' command that returns fake xfrm state output.
# Used to simulate VPN tunnel states in tests without requiring actual IPsec.
#
# Arguments:
#   $1: Peer IP address to include in mock output
#   $2: Byte counter value (default: 1000)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR
mock_ip_xfrm_state() {
    local peer_ip="$1"
    local bytes="${2:-1000}"
    
    # Create a mock ip command
    local mock_ip="${TEST_DIR}/mock_ip"
    cat > "$mock_ip" << EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    echo "src 192.168.1.1 dst ${peer_ip}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    replay-window 0"
    echo "    auth-trunc hmac(sha256) 0x1234567890abcdef 96"
    echo "    enc cbc(aes) 0x1234567890abcdef"
    echo "    lifetime current: ${bytes} bytes, 10 packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime soft: 2880s, 0 bytes, 0 packets"
    echo "    current use: 1"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
fi
EOF
    chmod +x "$mock_ip"
    echo "$mock_ip"
}

# Create mock swanctl command
#
# Creates a mock 'swanctl' command that returns fake SA list output.
# Used to simulate strongSwan SA states in tests.
#
# Arguments:
#   $1: Peer IP address to include in mock output
#   $2: Status ("up" or "down", default: "up")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR
mock_swanctl() {
    local peer_ip="$1"
    local status="${2:-up}"
    
    local mock_swanctl="${TEST_DIR}/mock_swanctl"
    cat > "$mock_swanctl" << EOF
#!/bin/bash
if [[ "\$1" == "--list-sas" ]]; then
    if [[ "$status" == "up" ]]; then
        echo "test-conn: IKEv2, established, ${peer_ip}"
        echo "test-conn: ESP, established, ${peer_ip}"
    fi
fi
EOF
    chmod +x "$mock_swanctl"
    echo "$mock_swanctl"
}

# Create mock ping command
#
# Creates a mock 'ping' command that simulates successful or failed ping.
# Used to test ping connectivity checks without requiring network access.
#
# Arguments:
#   $1: Target IP address to ping
#   $2: Success flag ("1" for success, "0" for failure, default: "1")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR
mock_ping() {
    local target_ip="$1"
    local success="${2:-1}"
    
    local mock_ping="${TEST_DIR}/mock_ping"
    cat > "$mock_ping" << EOF
#!/bin/bash
# Mock ping command
if [[ "$success" == "1" ]]; then
    echo "PING ${target_ip} (${target_ip}) 56(84) bytes of data."
    echo "64 bytes from ${target_ip}: icmp_seq=1 ttl=64 time=0.123 ms"
    echo "64 bytes from ${target_ip}: icmp_seq=2 ttl=64 time=0.124 ms"
    echo "64 bytes from ${target_ip}: icmp_seq=3 ttl=64 time=0.125 ms"
    echo ""
    echo "--- ${target_ip} ping statistics ---"
    echo "3 packets transmitted, 3 received, 0% packet loss"
    exit 0
else
    echo "PING ${target_ip} (${target_ip}) 56(84) bytes of data."
    echo ""
    echo "--- ${target_ip} ping statistics ---"
    echo "3 packets transmitted, 0 received, 100% packet loss"
    exit 1
fi
EOF
    chmod +x "$mock_ping"
    echo "$mock_ping"
}

# Create mock ipsec command
#
# Creates a mock 'ipsec' command that simulates IPsec service operations.
# Supports 'restart' and 'status' subcommands for testing.
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR
mock_ipsec() {
    local mock_ipsec="${TEST_DIR}/mock_ipsec"
    cat > "$mock_ipsec" << 'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "Restarting IPsec..."
    echo "Stopping IPsec..."
    echo "Starting IPsec..."
    exit 0
fi
if [[ "$1" == "status" ]]; then
    echo "IPsec connections:"
    echo "  test-conn: ESTABLISHED"
fi
EOF
    chmod +x "$mock_ipsec"
    echo "$mock_ipsec"
}

# Add mock commands to PATH
#
# Prepends TEST_DIR to PATH so mock commands are found before real system commands.
# Must be called after creating mock commands and before running scripts that use them.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Modifies PATH environment variable
add_mock_to_path() {
    export PATH="${TEST_DIR}:${PATH}"
}

# Remove mock commands from PATH
#
# Removes TEST_DIR from PATH to restore original command search order.
# Should be called after tests complete to clean up PATH modifications.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Modifies PATH environment variable
remove_mock_from_path() {
    export PATH=$(echo "$PATH" | sed "s|${TEST_DIR}:||g")
}

# Assert state file exists and contains value
#
# Verifies that a state file exists and contains the expected value.
# Used to check failure counters, restart counts, and other state files.
#
# Arguments:
#   $1: Path to state file
#   $2: Expected value (exact match)
#
# Returns:
#   0: File exists and contains expected value
#   1: File doesn't exist or contains different value (fails test)
assert_state_file() {
    local state_file="$1"
    local expected_value="$2"
    
    assert_file_exist "$state_file"
    run cat "$state_file"
    assert_success
    assert_output "$expected_value"
}

# Wait for file to appear (with timeout)
#
# Polls for a file to appear, waiting up to the specified timeout.
# Useful for testing asynchronous operations that create files.
#
# Arguments:
#   $1: Path to file to wait for
#   $2: Timeout in seconds (default: 5)
#
# Returns:
#   0: File appeared within timeout
#   1: Timeout exceeded, file not found
wait_for_file() {
    local file="$1"
    local timeout="${2:-5}"
    local start_time
    local elapsed_time
    local sleep_interval=0.1
    
    # Get start time in seconds since epoch
    start_time=$(date +%s 2>/dev/null || echo "0")
    
    # If date command failed, use iteration-based fallback
    if [[ "$start_time" == "0" ]]; then
        # Fallback: use iteration counting (less accurate but works without date)
        local max_iterations=$((timeout * 10))  # timeout * (1 / sleep_interval)
        local iterations=0
        while [[ $iterations -lt $max_iterations ]]; do
            if [[ -f "$file" ]]; then
                return 0
            fi
            sleep "$sleep_interval"
            iterations=$((iterations + 1))
        done
        return 1
    fi
    
    # Normal path: use time-based checking
    while true; do
        if [[ -f "$file" ]]; then
            return 0
        fi
        
        # Calculate elapsed time
        elapsed_time=$(($(date +%s) - start_time))
        if [[ $elapsed_time -ge $timeout ]]; then
            return 1
        fi
        
        sleep "$sleep_interval"
    done
}

