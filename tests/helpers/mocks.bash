#!/usr/bin/env bash
#
# Standardized Mock Creation Patterns
#
# This module provides standardized patterns for creating mock commands in tests.
# It consolidates common mock creation patterns to reduce duplication and ensure
# consistency across test files.
#
# Usage:
#   load test_helper
#   load helpers/mocks
#
#   # Create a mock command that fails
#   mock_command_failure "mycommand" 1 "Error message"
#   add_mock_to_path
#
#   # Create a mock command with custom behavior
#   create_mock_command "mycommand" <<'EOF'
#   #!/bin/bash
#   echo "custom output"
#   exit 0
#   EOF
#   add_mock_to_path

# Create mock command that fails with specific exit code and error message
#
# Creates a mock command script that exits with the specified exit code and
# optionally prints an error message to stderr. This is useful for testing
# error handling scenarios.
#
# Arguments:
#   $1: Command name to mock
#   $2: Exit code (default: 1)
#   $3: Error message to print to stderr (optional)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock command
#
# Side effects:
#   - Creates executable mock command script in TEST_DIR
#
# Example:
#   # Create a mock that fails with exit code 1
#   mock_command_failure "mycommand"
#   add_mock_to_path
#
#   # Create a mock that fails with exit code 2 and error message
#   mock_command_failure "mycommand" 2 "Connection refused"
#   add_mock_to_path
mock_command_failure() {
	local command_name="$1"
	local exit_code="${2:-1}"
	local error_message="${3:-}"
	local mock_command="${TEST_DIR}/${command_name}"
	cat >"$mock_command" <<EOF
#!/bin/bash
${error_message:+echo "$error_message" >&2}
exit $exit_code
EOF
	chmod +x "$mock_command"
	echo "$mock_command"
}

# Create a mock command with custom script content
#
# Creates a mock command script with the provided content. This provides a
# flexible way to create mocks with complex behavior.
#
# Arguments:
#   $1: Command name to mock
#   $2: Script content (can be provided via heredoc or as a string)
#   $3: Optional path to mock file (default: ${TEST_DIR}/${command_name})
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock command
#
# Side effects:
#   - Creates executable mock command script
#
# Example:
#   # Using heredoc
#   create_mock_command "mycommand" <<'EOF'
#   #!/bin/bash
#   if [[ "$1" == "test" ]]; then
#       echo "test mode"
#   else
#       echo "normal mode"
#   fi
#   exit 0
#   EOF
#   add_mock_to_path
#
#   # Using string
#   create_mock_command "mycommand" '#!/bin/bash
#   echo "output"
#   exit 0'
#   add_mock_to_path
create_mock_command() {
	local command_name="$1"
	local script_content="$2"
	local mock_path="${3:-${TEST_DIR}/${command_name}}"

	cat >"$mock_path" <<EOF
$script_content
EOF
	chmod +x "$mock_path"
	echo "$mock_path"
}

# Create a mock command that passes through to the real command
#
# Creates a mock command that executes the real command with the same name.
# Useful when you want to mock some commands but pass through others.
#
# Arguments:
#   $1: Command name to mock
#   $2: Optional path to real command (default: /usr/bin/${command_name})
#   $3: Optional path to mock file (default: ${TEST_DIR}/${command_name})
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock command
#
# Side effects:
#   - Creates executable mock command script that calls real command
#
# Example:
#   # Pass through to real command
#   create_mock_pass_through "date"
#   add_mock_to_path
#
#   # Pass through with custom path
#   create_mock_pass_through "date" "/bin/date"
#   add_mock_to_path
create_mock_pass_through() {
	local command_name="$1"
	local real_command="${2:-/usr/bin/${command_name}}"
	local mock_path="${3:-${TEST_DIR}/${command_name}}"

	cat >"$mock_path" <<EOF
#!/bin/bash
exec "$real_command" "\$@"
EOF
	chmod +x "$mock_path"
	echo "$mock_path"
}

# Create a mock command that returns specific output
#
# Creates a mock command that prints the specified output and exits successfully.
# Useful for mocking commands that return data.
#
# Arguments:
#   $1: Command name to mock
#   $2: Output to print (can be multiline)
#   $3: Optional path to mock file (default: ${TEST_DIR}/${command_name})
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock command
#
# Side effects:
#   - Creates executable mock command script
#
# Example:
#   # Simple output
#   create_mock_output "mycommand" "output text"
#   add_mock_to_path
#
#   # Multiline output
#   create_mock_output "mycommand" "line 1
#   line 2
#   line 3"
#   add_mock_to_path
create_mock_output() {
	local command_name="$1"
	local output="$2"
	local mock_path="${3:-${TEST_DIR}/${command_name}}"

	cat >"$mock_path" <<EOF
#!/bin/bash
cat <<'OUTPUT_EOF'
$output
OUTPUT_EOF
EOF
	chmod +x "$mock_path"
	echo "$mock_path"
}

# Create a mock command that tracks calls
#
# Creates a mock command that tracks each call in a state file, allowing tests
# to verify how many times a command was called and with what arguments.
#
# Arguments:
#   $1: Command name to mock
#   $2: Optional path to call tracking file (default: ${TEST_DIR}/${command_name}_calls)
#   $3: Optional path to mock file (default: ${TEST_DIR}/${command_name})
#   $4: Optional script content to execute (default: exit 0)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock command
#
# Side effects:
#   - Creates executable mock command script
#   - Creates call tracking file
#
# Example:
#   # Track calls with default behavior
#   create_mock_with_tracking "mycommand"
#   add_mock_to_path
#   mycommand arg1 arg2
#   # Check calls: cat ${TEST_DIR}/mycommand_calls
#
#   # Track calls with custom behavior
#   create_mock_with_tracking "mycommand" "" "" 'echo "custom output"'
#   add_mock_to_path
create_mock_with_tracking() {
	local command_name="$1"
	local tracking_file="${2:-${TEST_DIR}/${command_name}_calls}"
	local mock_path="${3:-${TEST_DIR}/${command_name}}"
	local script_content="${4:-exit 0}"

	cat >"$mock_path" <<EOF
#!/bin/bash
# Track this call
echo "\$(date +%s) \$(basename "\$0") \$*" >> "$tracking_file"
# Execute custom script content
$script_content
EOF
	chmod +x "$mock_path"
	echo "$mock_path"
}

# Get call count for a tracked mock command
#
# Returns the number of times a tracked mock command was called.
#
# Arguments:
#   $1: Command name
#   $2: Optional path to call tracking file (default: ${TEST_DIR}/${command_name}_calls)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the number of calls (0 if file doesn't exist)
#
# Example:
#   create_mock_with_tracking "mycommand"
#   add_mock_to_path
#   mycommand
#   mycommand
#   local count
#   count=$(get_mock_call_count "mycommand")
#   assert_equal "$count" 2
get_mock_call_count() {
	local command_name="$1"
	local tracking_file="${2:-${TEST_DIR}/${command_name}_calls}"

	if [[ -f "$tracking_file" ]]; then
		wc -l <"$tracking_file" | tr -d ' '
	else
		echo "0"
	fi
}

# Clear call tracking for a mock command
#
# Removes the call tracking file for a mock command, resetting the call count.
#
# Arguments:
#   $1: Command name
#   $2: Optional path to call tracking file (default: ${TEST_DIR}/${command_name}_calls)
#
# Returns:
#   0: Always succeeds
#
# Example:
#   create_mock_with_tracking "mycommand"
#   add_mock_to_path
#   mycommand
#   clear_mock_tracking "mycommand"
#   # Call count is now 0
clear_mock_tracking() {
	local command_name="$1"
	local tracking_file="${2:-${TEST_DIR}/${command_name}_calls}"

	rm -f "$tracking_file"
}
