# ADR-0027: Enhanced Command Availability Checking

## Status
Accepted

## Context
Scripts executed by cron or systemd on UDM OS (and many Linux systems) often have restricted PATH environments that don't include `/usr/sbin` or other system directories. This causes `command -v` to fail even when binaries exist in standard system locations.

Without enhanced checking:
- Commands like `ip`, `ipsec`, `ping` may not be found even though they exist
- Detection and recovery mechanisms could fail unnecessarily
- System could incorrectly assume commands are unavailable
- Fallback mechanisms might not work correctly

## Decision
We will implement an enhanced command availability checking function (`check_command_available()`) that provides multiple fallback mechanisms:
1. Primary: Use `command -v` (POSIX compliant, checks PATH)
2. Fallback 1: Check common system directories directly (`/usr/sbin`, `/usr/bin`, `/sbin`, `/bin`)
3. Fallback 2: Attempt to execute command with `--help` or `--version` flags

This ensures commands are found even in restricted PATH environments common in cron/systemd contexts.

## Consequences

### Positive
- **Robust Command Detection**: Commands are found even in restricted PATH environments
- **Cron/Systemd Compatibility**: Works correctly in cron and systemd execution contexts
- **UDM OS Compatibility**: Handles UDM OS PATH restrictions properly
- **Multiple Fallback Layers**: Three-tier fallback ensures maximum compatibility
- **Consistent Behavior**: All command checks use the same robust mechanism

### Negative
- **Additional Complexity**: More complex than simple `command -v` check
- **Potential Performance Impact**: Multiple fallback checks may be slower (minimal in practice)
- **Fallback 2 Risk**: Executing commands with `--help`/`--version` could theoretically have side effects (mitigated with timeout and output redirection)

## Implementation Details
- **Location**: Implemented in `lib/common.sh` as `check_command_available()` function
- **Primary Method**: Uses `command -v` (POSIX compliant, checks PATH)
- **Fallback 1**: Checks common system directories directly:
  - `/usr/sbin`
  - `/usr/bin`
  - `/sbin`
  - `/bin`
- **Fallback 2**: Attempts to execute command with `--help` or `--version` flags:
  - Uses `timeout` if available to prevent hanging
  - Redirects output to avoid side effects
  - Exit code 127 means "command not found", any other exit code means command exists
- **Usage Pattern**: All binary command checks in code that runs via cron/systemd should use this function
- **Exception**: Direct `command -v` is acceptable for checking function availability (functions are in same shell context)

## Related ADRs
- ADR-0001: Cron-Based Execution Instead of Daemon (execution context)
- ADR-0006: Multi-Method Detection with Fallback (uses command availability checking)
- ADR-0026: Detection Reliability Safeguard (uses command availability checking)

## References
- lib/common.sh:808-858 (implementation)
- docs/CODE_PATTERNS.md: "Command Availability Patterns" section (usage guidelines)
- docs/AUDIT_MISSING_DEPENDENCIES.md (audit documentation)
- docs/ROUTE_ISSUE_INVESTIGATION.md (investigation that identified the need)
- CHANGELOG.md: "Enhanced Command Availability Checking" entry
