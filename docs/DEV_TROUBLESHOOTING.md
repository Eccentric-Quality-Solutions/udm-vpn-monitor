- If you update the `vpn-keepalive.sh` file you need to restart it using: `systemctl restart vpn-keepalive`.
   - If you get an error, make sure the file is set as executable: `chmod +x vpn-keepalive.sh`

## Code Review Lessons

See `CODE_REVIEW_LESSONS_LEARNED.md` for systematic patterns and lessons learned from code reviews, including:
- Using abstraction layers consistently
- Verifying function signatures match calls
- Removing debug code properly
- Checking for code duplication
- Ensuring test coverage matches code paths

## CONFIG_SCHEMA Not Populating in Tests

### Problem
When sourcing `config.sh` in BATS tests, the `CONFIG_SCHEMA` associative array is not being populated correctly, causing `get_config_schema()` to return "not found" for valid configuration variables like `VPN_NAME`.

### Root Cause
`config.sh` was declaring `CONFIG_SCHEMA` as `declare -A CONFIG_SCHEMA=()` (without `-g` flag) before sourcing `config_schema.sh`. When `config.sh` is sourced from within a function (like BATS test functions), this creates a **local** variable that shadows the global `-gA` one created by `config_schema.sh`. Functions like `get_config_schema` then see the empty local variable instead of the populated global one.

### Fix Applied
Changed `config.sh` line 43 from `declare -A CONFIG_SCHEMA=()` to `declare -gA CONFIG_SCHEMA=()`. This ensures `CONFIG_SCHEMA` is always global, preventing scoping issues when `config.sh` is sourced from within functions.

### Solution Pattern (from working tests)
Other tests that successfully use `safe_parse_config_file` follow this pattern:

1. Source `logging.sh` first (required by `config.sh`)
2. Source `config.sh` (which declares `CONFIG_SCHEMA` as empty)
3. Explicitly source `config_schema.sh` again after `config.sh`

Example from `test_config.sh`:
```bash
# shellcheck source=../lib/config.sh
source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true
# shellcheck source=../lib/config_schema.sh
source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true
```

### Working Pattern (Top Level)
When tested manually at the top level of a shell, this pattern works:
```bash
declare -gA CONFIG_SCHEMA=()
source lib/config_schema.sh  # Populates with 35 keys
source lib/config.sh  # Still has 35 keys - preserved!
```

### Solution
**Fixed in `lib/config.sh`**: Changed `declare -A CONFIG_SCHEMA=()` to `declare -gA CONFIG_SCHEMA=()` to ensure it's always global.

**Test Pattern**: Tests can now use the standard pattern:
```bash
source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true
source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true  # Optional but recommended
```

### Key Lesson
When a test exposes a scoping issue in production code, fix the production code rather than working around it in tests. Using `declare -gA` instead of `declare -A` ensures associative arrays are always global, which is the correct behavior for configuration schemas that need to be accessible from anywhere.

## Testing File Deletion Failures

### Problem
When writing tests for file deletion failures (e.g., `delete_peer_state()`), making a file read-only does not prevent `rm -f` from deleting it. The `rm -f` command can successfully delete read-only files.

### Root Cause
The `rm -f` command removes files regardless of their read-only status. The `-f` flag forces removal even when files are write-protected. To actually prevent deletion in tests, the parent directory must be made read-only (without write permission).

### Solution Pattern
When testing deletion failures, make the **parent directory** read-only instead of the file itself:

```bash
# ❌ This won't work - rm -f can delete read-only files
chmod 444 "$state_file"
run delete_peer_state "" "$peer_ip" "failure_count"
# This will succeed even though file is read-only

# ✅ This works - make directory read-only
local state_dir=$(dirname "$state_file")
chmod 555 "$state_dir"  # Remove write permission from directory
run delete_peer_state "" "$peer_ip" "failure_count"
# This will fail because directory doesn't allow file deletion
```

### Key Lesson
To test file deletion failures, make the parent directory read-only (chmod 555), not the file itself. The `rm -f` command can delete read-only files but cannot delete files from a read-only directory.
