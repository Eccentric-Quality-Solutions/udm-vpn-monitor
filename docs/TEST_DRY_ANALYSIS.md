# Test DRY Analysis - New Tests Review

**Date**: 2026-01-02  
**Purpose**: Identify code duplication in recently created test files and recommend DRY improvements  
**Scope**: Tests created in recent commits (test_recovery_*.sh, test_detection_*.sh, etc.)

---

## Executive Summary

After reviewing the recently created test files, several patterns of duplication have been identified. While many helper functions already exist in `test_helper.bash`, there are opportunities to extract additional common patterns into reusable functions.

**Key Findings**:
- **High Priority**: Mock command creation patterns, state file setup patterns
- **Medium Priority**: Config file creation patterns, log assertion patterns
- **Low Priority**: Test structure patterns (acceptable duplication for test clarity)

---

## 1. Mock IP Command Creation Pattern

### Problem
The pattern for creating a mock `ip` command that handles `xfrm state` (VPN down scenario) is repeated across many tests:

**Locations**:
- `test_recovery_tier2.sh:105-112` (lines 105-112)
- `test_recovery_tier2.sh:170-177` (lines 170-177)
- `test_recovery_tier2.sh:236-243` (lines 236-243)
- `test_recovery_tier3.sh:125-132` (lines 125-132)
- `test_recovery_tier3.sh:191-198` (lines 191-198)
- `test_recovery_tier3.sh:316-323` (lines 316-323)
- `test_recovery_tier3.sh:385-392` (lines 385-392)
- `test_recovery_tier3.sh:472-480` (lines 472-480)
- `test_recovery_rate_limiting.sh:233-241` (lines 233-241)
- `test_recovery_network_partition.sh:33-60` (lines 33-60)
- `test_recovery_partial_failures.sh:224-234` (lines 224-234)
- And many more...

**Example Pattern**:
```bash
local mock_ip="${TEST_DIR}/ip"
cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0  # Return empty output (no SA found - VPN down)
fi
EOF
chmod +x "$mock_ip"
```

### Suggested Solution
Create a helper function in `test_helper.bash`:

```bash
# Create a mock ip command for VPN down scenario
#
# Creates a mock ip command that returns empty output for xfrm state queries,
# simulating a VPN down scenario (no SAs found).
#
# Arguments:
#   $1: Optional path to mock ip file (default: ${TEST_DIR}/ip)
#   $2: Optional additional ip command handlers (heredoc content)
#
# Side effects:
#   - Creates executable mock ip script at specified path
#   - Adds mock to PATH via add_mock_to_path (if called separately)
#
# Example:
#   mock_ip_vpn_down
#   add_mock_to_path
#
#   # Or with custom path:
#   mock_ip_vpn_down "${TEST_DIR}/custom_ip"
#
mock_ip_vpn_down() {
    local mock_ip="${1:-${TEST_DIR}/ip}"
    local additional_handlers="${2:-}"
    
    cat >"$mock_ip" <<EOF
#!/bin/bash
# Handle xfrm state - return empty (VPN down, no SA)
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    exit 0  # Return empty output (no SA found - VPN down)
fi
${additional_handlers}
# Handle other ip commands
exec /usr/bin/ip "\$@"
EOF
    chmod +x "$mock_ip"
}
```

**Usage**:
```bash
# Replace:
local mock_ip="${TEST_DIR}/ip"
cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
chmod +x "$mock_ip"

# With:
mock_ip_vpn_down
add_mock_to_path
```

### Impact
- **Files affected**: ~15+ test files
- **Lines reduced**: ~8-10 lines per occurrence
- **Maintenance**: Single point of change for VPN down mock pattern
- **Consistency**: Standardized mock behavior

### Priority: **HIGH**

---

## 2. Mock IPsec Command Creation Pattern

### Problem
The pattern for creating a mock `ipsec` command that handles `reload` and `restart` is repeated:

**Locations**:
- `test_recovery_tier2.sh:30-38` (lines 30-38)
- `test_recovery_tier2.sh:323-333` (lines 323-333)
- `test_recovery_tier3.sh:28-36` (lines 28-36)
- `test_recovery_rate_limiting.sh:94-101` (lines 94-101)
- `test_recovery_rate_limiting.sh:157-164` (lines 157-164)
- `test_recovery_rate_limiting.sh:244-251` (lines 244-251)
- `test_recovery_rate_limiting.sh:311-318` (lines 311-318)
- `test_recovery_rate_limiting.sh:366-373` (lines 366-373)
- And many more...

**Example Pattern**:
```bash
local mock_ipsec="${TEST_DIR}/ipsec"
cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
chmod +x "$mock_ipsec"
```

**Note**: There's already a `mock_ipsec_reload_restart()` function, but many tests create custom ipsec mocks for specific scenarios.

### Suggested Solution
Enhance `mock_ipsec_reload_restart()` or create additional helpers:

```bash
# Create a mock ipsec command with customizable behavior
#
# Creates a mock ipsec command that handles reload and restart commands
# with configurable success/failure behavior.
#
# Arguments:
#   $1: reload_success (0=fail, 1=succeed, default: 1)
#   $2: restart_success (0=fail, 1=succeed, default: 1)
#   $3: Optional custom handler script (heredoc content)
#
# Side effects:
#   - Creates executable mock ipsec script at ${TEST_DIR}/ipsec
#
# Example:
#   mock_ipsec_simple 1 1  # Both succeed
#   mock_ipsec_simple 0 1  # Reload fails, restart succeeds
#
mock_ipsec_simple() {
    local reload_success="${1:-1}"
    local restart_success="${2:-1}"
    local custom_handler="${3:-}"
    local mock_ipsec="${TEST_DIR}/ipsec"
    
    cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "reload" ]]; then
    exit $((1 - reload_success))  # 0 if reload_success=1, 1 if reload_success=0
elif [[ "\$1" == "restart" ]]; then
    exit $((1 - restart_success))  # 0 if restart_success=1, 1 if restart_success=0
fi
${custom_handler}
exec /usr/bin/ipsec "\$@"
EOF
    chmod +x "$mock_ipsec"
}
```

### Impact
- **Files affected**: ~10+ test files
- **Lines reduced**: ~6-8 lines per occurrence
- **Maintenance**: Standardized ipsec mock creation

### Priority: **HIGH**

---

## 3. State File Setup Pattern

### Problem
The pattern for setting up failure counters and other state files is repeated:

**Locations**:
- `test_recovery_tier2.sh:94-102` (lines 94-102)
- `test_recovery_tier2.sh:159-167` (lines 159-167)
- `test_recovery_tier2.sh:225-233` (lines 225-233)
- `test_recovery_tier3.sh:116-122` (lines 116-122)
- `test_recovery_tier3.sh:182-188` (lines 182-188)
- `test_recovery_tier3.sh:302-309` (lines 302-309)
- `test_recovery_tier3.sh:377-382` (lines 377-382)
- `test_recovery_tier3.sh:460-465` (lines 460-465)
- And many more...

**Example Pattern**:
```bash
export STATE_DIR="$state_dir"
export LOGS_DIR="${TEST_DIR}/logs"
source_function "get_peer_state_file_path"
local failure_counter
failure_counter=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")

# Set failure count to Tier 2 threshold
echo "3" >"$failure_counter"
```

### Suggested Solution
Create a helper function:

```bash
# Set up peer state file with a value
#
# Sets up a peer state file (e.g., failure_count, last_bytes) with a specified value.
# Handles all the boilerplate of exporting STATE_DIR, sourcing functions, etc.
#
# Arguments:
#   $1: Location name (e.g., "TEST")
#   $2: Peer IP address (e.g., "192.168.1.1")
#   $3: State file type (e.g., "failure_count", "last_bytes")
#   $4: Value to set
#   $5: Optional STATE_DIR (default: ${TEST_DIR})
#   $6: Optional LOGS_DIR (default: ${TEST_DIR}/logs)
#
# Side effects:
#   - Exports STATE_DIR and LOGS_DIR
#   - Sources get_peer_state_file_path function
#   - Creates state file with specified value
#
# Example:
#   setup_peer_state "TEST" "192.168.1.1" "failure_count" "3"
#
setup_peer_state() {
    local location_name="$1"
    local peer_ip="$2"
    local state_type="$3"
    local value="$4"
    local state_dir="${5:-${TEST_DIR}}"
    local logs_dir="${6:-${TEST_DIR}/logs}"
    
    export STATE_DIR="$state_dir"
    export LOGS_DIR="$logs_dir"
    source_function "get_peer_state_file_path"
    
    local state_file
    state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "$state_type")
    
    echo "$value" >"$state_file"
}
```

**Usage**:
```bash
# Replace:
export STATE_DIR="$state_dir"
export LOGS_DIR="${TEST_DIR}/logs"
source_function "get_peer_state_file_path"
local failure_counter
failure_counter=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")
echo "3" >"$failure_counter"

# With:
setup_peer_state "TEST" "192.168.1.1" "failure_count" "3" "$state_dir"
```

### Impact
- **Files affected**: ~20+ test files
- **Lines reduced**: ~6-8 lines per occurrence
- **Maintenance**: Single point of change for state file setup
- **Consistency**: Standardized state file creation

### Priority: **HIGH**

---

## 4. Config File Creation Pattern

### Problem
While `setup_test_location_config()` exists, many tests still manually create config files with similar structures:

**Locations**:
- `test_recovery_tier2.sh:79-88` (lines 79-88)
- `test_recovery_tier2.sh:365-373` (lines 365-373)
- `test_recovery_tier3.sh:98-108` (lines 98-108)
- `test_recovery_tier3.sh:166-174` (lines 166-174)
- `test_recovery_tier3.sh:287-294` (lines 287-294)
- `test_recovery_tier3.sh:361-369` (lines 361-369)
- `test_recovery_tier3.sh:441-451` (lines 441-451)
- `test_recovery_rate_limiting.sh:61-68` (lines 61-68)
- And many more...

**Example Pattern**:
```bash
local config_file="${TEST_DIR}/vpn-monitor.conf"
cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
EOF
```

### Suggested Solution
These should use `setup_test_location_config()` instead. However, some tests need more control. Consider:

1. **Update existing tests** to use `setup_test_location_config()` where possible
2. **Create a helper** for common tier threshold patterns:

```bash
# Set up config with tier thresholds
#
# Creates a config file with common tier threshold settings.
# Wrapper around setup_test_location_config() for common patterns.
#
# Arguments:
#   $1: Config file path
#   $2: Peer external IP
#   $3: Peer internal IP (optional, defaults to external IP)
#   $4: Tier 1 threshold (default: 1)
#   $5: Tier 2 threshold (default: 3)
#   $6: Tier 3 threshold (default: 5)
#   $7+: Additional config overrides
#
# Example:
#   setup_tier_config "${TEST_DIR}/vpn-monitor.conf" "192.168.1.1" "192.168.1.1" 1 3 5 'ENABLE_XFRM_RECOVERY=0'
#
setup_tier_config() {
    local config_file="$1"
    local peer_external="$2"
    local peer_internal="${3:-$peer_external}"
    local tier1="${4:-1}"
    local tier2="${5:-3}"
    local tier3="${6:-5}"
    shift 6 || shift $#
    
    setup_test_location_config "$config_file" \
        "LOCATION_TEST_EXTERNAL=\"$peer_external\"" \
        "LOCATION_TEST_INTERNAL=\"$peer_internal\"" \
        "TIER1_THRESHOLD=$tier1" \
        "TIER2_THRESHOLD=$tier2" \
        "TIER3_THRESHOLD=$tier3" \
        "$@"
}
```

### Impact
- **Files affected**: ~15+ test files
- **Lines reduced**: ~8-10 lines per occurrence
- **Maintenance**: Standardized config creation

### Priority: **MEDIUM** (helper exists, just needs adoption)

---

## 5. Log Assertion Patterns

### Problem
Similar patterns for asserting log file contents with multiple alternatives:

**Locations**:
- `test_recovery_tier2.sh:129-135` (lines 129-135)
- `test_recovery_tier2.sh:193-195` (lines 193-195)
- `test_recovery_tier2.sh:260-262` (lines 260-262)
- `test_recovery_tier3.sh:68` (line 68)
- `test_recovery_network_partition.sh:79` (line 79)
- And many more...

**Example Pattern**:
```bash
# Verify that reload was attempted and failed (check for either pattern)
if ! grep -q "ipsec reload failed" "$log_file" && ! grep -q "reload failed" "$log_file"; then
    fail "Expected log to contain 'ipsec reload failed' or 'reload failed'"
fi
```

### Suggested Solution
Create helper functions for flexible log assertions:

```bash
# Assert log file contains one of multiple patterns
#
# Checks if log file contains at least one of the specified patterns.
# Useful for asserting log messages that may vary slightly.
#
# Arguments:
#   $1: Log file path
#   $2+: Patterns to search for (at least one must match)
#
# Returns:
#   0: At least one pattern found
#   1: No patterns found
#
# Example:
#   assert_log_contains_any "$log_file" "ipsec reload failed" "reload failed"
#
assert_log_contains_any() {
    local log_file="$1"
    shift
    
    local pattern
    for pattern in "$@"; do
        if grep -q "$pattern" "$log_file" 2>/dev/null; then
            return 0
        fi
    done
    
    fail "Expected log to contain one of: $*"
    return 1
}
```

**Usage**:
```bash
# Replace:
if ! grep -q "ipsec reload failed" "$log_file" && ! grep -q "reload failed" "$log_file"; then
    fail "Expected log to contain 'ipsec reload failed' or 'reload failed'"
fi

# With:
assert_log_contains_any "$log_file" "ipsec reload failed" "reload failed"
```

### Impact
- **Files affected**: ~20+ test files
- **Lines reduced**: ~3-4 lines per occurrence
- **Readability**: More concise and clear assertions

### Priority: **MEDIUM**

---

## 6. Test Script Creation Pattern

### Problem
The pattern for creating test scripts is consistent but verbose:

**Locations**: Almost every test file

**Example Pattern**:
```bash
mkdir -p "${TEST_DIR}/logs"
local log_file="${TEST_DIR}/logs/vpn-monitor.log"
local state_dir="${TEST_DIR}"

local test_script
test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")
```

### Suggested Solution
Create a wrapper function that handles common defaults:

```bash
# Create test script with common defaults
#
# Creates a test script with default paths for logs and state directories.
# Wrapper around create_test_vpn_monitor_script() for common patterns.
#
# Arguments:
#   $1: Config file path (optional)
#   $2: State directory (optional, default: ${TEST_DIR})
#   $3: Log file path (optional, default: ${TEST_DIR}/logs/vpn-monitor.log)
#
# Returns:
#   Path to created test script
#
# Example:
#   test_script=$(create_test_script "$config_file")
#
create_test_script() {
    local config_file="${1:-}"
    local state_dir="${2:-${TEST_DIR}}"
    local log_file="${3:-${TEST_DIR}/logs/vpn-monitor.log}"
    
    mkdir -p "$(dirname "$log_file")"
    
    create_test_vpn_monitor_script \
        "$VPN_MONITOR_SCRIPT" \
        "${TEST_DIR}/vpn-monitor.sh" \
        "$config_file" \
        "$state_dir" \
        "$log_file"
}
```

### Impact
- **Files affected**: ~30+ test files
- **Lines reduced**: ~2-3 lines per occurrence
- **Consistency**: Standardized test script creation

### Priority: **LOW** (minor improvement, but helpful)

---

## 7. Mock Command State Tracking Pattern

### Problem
Some tests use file-based state tracking for mocks (e.g., counting calls):

**Locations**:
- `test_recovery_network_partition.sh:96-117` (lines 96-117)
- `test_recovery_network_partition.sh:183-247` (lines 183-247)
- `test_recovery_partial_failures.sh:180-196` (lines 180-196)
- And more...

**Example Pattern**:
```bash
local partition_check_state_file="${TEST_DIR}/partition_check_state"
echo "0" >"$partition_check_state_file"
local mock_ip="${TEST_DIR}/ip"
cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "route" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "default" ]]; then
    partition_check_count=\$(cat "$partition_check_state_file" 2>/dev/null || echo "0")
    partition_check_count=\$((partition_check_count + 1))
    echo "\$partition_check_count" >"$partition_check_state_file"
    if [[ \$partition_check_count -eq 1 ]]; then
        exit 0
    else
        exit 1
    fi
fi
EOF
```

### Suggested Solution
Create a helper for stateful mocks:

```bash
# Create a stateful mock command
#
# Creates a mock command that tracks state across calls using a counter file.
# Useful for simulating commands that behave differently on subsequent calls.
#
# Arguments:
#   $1: Mock command path
#   $2: Command name (for error messages)
#   $3: Handler script (heredoc) - can use \$CALL_COUNT variable
#
# Side effects:
#   - Creates executable mock script
#   - Creates state file for tracking call count
#
# Example:
#   create_stateful_mock "${TEST_DIR}/ip" "ip" <<'EOF'
#   if [[ \$CALL_COUNT -eq 1 ]]; then
#       exit 0
#   else
#       exit 1
#   fi
#   EOF
#
create_stateful_mock() {
    local mock_path="$1"
    local cmd_name="$2"
    local handler_script="$3"
    local state_file="${TEST_DIR}/.${cmd_name}_call_count"
    
    cat >"$mock_path" <<EOF
#!/bin/bash
CALL_COUNT=\$(cat "$state_file" 2>/dev/null || echo "0")
CALL_COUNT=\$((CALL_COUNT + 1))
echo "\$CALL_COUNT" >"$state_file"
export CALL_COUNT
$handler_script
EOF
    chmod +x "$mock_path"
}
```

### Impact
- **Files affected**: ~5-10 test files
- **Lines reduced**: ~5-8 lines per occurrence
- **Complexity**: Simplifies stateful mock creation

### Priority: **LOW** (only affects a few tests, but would be helpful)

---

## Summary and Recommendations

### High Priority (Implement First)
1. **Mock IP Command Creation** - `mock_ip_vpn_down()` helper
2. **Mock IPsec Command Creation** - Enhance `mock_ipsec_reload_restart()` or create `mock_ipsec_simple()`
3. **State File Setup** - `setup_peer_state()` helper

### Medium Priority
4. **Config File Creation** - Encourage use of `setup_test_location_config()` and create `setup_tier_config()` wrapper
5. **Log Assertions** - `assert_log_contains_any()` helper

### Low Priority
6. **Test Script Creation** - `create_test_script()` wrapper
7. **Stateful Mocks** - `create_stateful_mock()` helper

### Implementation Strategy

1. **Start with High Priority items** - These have the most impact
2. **Update tests incrementally** - Don't try to update all tests at once
3. **Add tests for new helpers** - Ensure helpers work correctly
4. **Update documentation** - Document new helpers in `TEST_PATTERNS.md`

### Benefits

- **Reduced maintenance burden** - Changes to common patterns only need to be made in one place
- **Improved consistency** - All tests use the same patterns
- **Better readability** - Helper function names make test intent clearer
- **Faster test development** - Less boilerplate code to write
- **Fewer bugs** - Centralized logic reduces chance of inconsistencies

---

## Notes

- Some duplication is acceptable in tests for clarity (e.g., test structure)
- Focus on extracting patterns that appear 5+ times
- Maintain backward compatibility with existing helper functions
- Consider test readability - don't over-abstract if it makes tests harder to understand

---

**Document Version**: 1.0  
**Last Updated**: 2026-01-02  
**Reviewer**: AI Code Review
