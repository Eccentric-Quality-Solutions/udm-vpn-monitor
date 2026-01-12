# ADR-0026: Detection Reliability Safeguard

## Status
Accepted

## Context
The VPN monitoring system relies on detection tools (`ip` and `ipsec` commands) to determine VPN tunnel status. When these tools are unavailable, the system cannot reliably determine if a VPN tunnel is actually down or if the detection failure is due to missing tools.

Without a safeguard:
- Recovery actions (Tier 2/3) could be triggered based on unreliable detection
- False recovery actions could disrupt working VPN connections
- System could restart VPNs unnecessarily when detection tools are missing
- Recovery escalation could occur even when the VPN is actually functioning

## Decision
We will implement a detection reliability safeguard that prevents recovery escalation when detection is unreliable. The safeguard checks if both `ip` and `ipsec` commands are unavailable when failure type is "unknown", and if so, skips recovery escalation (Tier 2/3) while still logging failures for monitoring.

## Consequences

### Positive
- **Prevents False Recovery Actions**: Avoids disrupting working VPN connections when detection tools are unavailable
- **Safety First**: Prioritizes system stability over automated recovery when detection is unreliable
- **Maintains Monitoring**: Failures are still logged for monitoring and troubleshooting
- **Clear Error Messages**: Logs explicit error messages explaining why recovery was skipped
- **Tier 1 Still Works**: Basic logging (Tier 1) continues to function for monitoring

### Negative
- **Delayed Recovery**: Recovery actions may be delayed if detection tools become unavailable during actual VPN failures
- **Manual Intervention Required**: When detection tools are unavailable, manual intervention may be needed to verify VPN status
- **Dependency on Detection Tools**: System effectiveness depends on availability of detection tools

## Implementation Details
- **Location**: Implemented in `lib/recovery.sh` in the `handle_vpn_failure()` function
- **Trigger Condition**: When failure type is "unknown" and both `ip` and `ipsec` commands are unavailable
- **Behavior**: 
  - Checks availability of both `ip` and `ipsec` commands using `check_command_available()`
  - If both are unavailable, logs error message and skips recovery escalation
  - Still logs Tier 1 failures for monitoring purposes
  - Returns early to prevent Tier 2/3 recovery actions
- **Command Availability Checking**: Uses `check_command_available()` function which handles PATH restrictions in cron/systemd environments
- **Test Coverage**: Comprehensive test suite in `tests/test_recovery_detection_reliability.sh` verifies safeguard behavior

## Related ADRs
- ADR-0003: Tiered Recovery System (recovery escalation mechanism)
- ADR-0006: Multi-Method Detection with Fallback (detection methods)
- ADR-0027: Enhanced Command Availability Checking (command availability mechanism)

## References
- ARCHITECTURE.md: "Key Design Decisions #3: Tiered Recovery" section (safety safeguard documentation)
- lib/recovery.sh:1482-1506 (implementation)
- tests/test_recovery_detection_reliability.sh (test suite)
- CHANGELOG.md: "Detection Reliability Safeguard" entry
