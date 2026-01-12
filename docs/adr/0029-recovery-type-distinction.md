# ADR-0029: Recovery Type Distinction

## Status
Accepted

## Context
The VPN monitoring system tracks VPN failures and recoveries, but initially did not distinguish between recoveries that occurred with system intervention versus recoveries that occurred naturally without intervention. This distinction is important for:

- **Evaluating Intervention Effectiveness**: Understanding whether recovery actions (Tier 2/3) are actually needed or if VPNs recover naturally
- **System Stability Assessment**: Identifying if VPNs are stable (self-heal frequently) or unstable (require frequent intervention)
- **Pattern Analysis**: Enabling analysis of recovery patterns over time to identify trends and optimization opportunities
- **Operational Insights**: Helping operators understand if failures are transient (self-heal) or persistent (require intervention)

Without recovery type distinction:
- All recoveries were treated the same in log analysis
- No way to evaluate if recovery actions are effective
- No visibility into VPN stability patterns
- Cannot distinguish between natural recovery and intervention-triggered recovery

## Decision
We will implement recovery type distinction in the log analysis system that classifies recoveries into two categories:

1. **App-Managed Recoveries** (with intervention):
   - Recoveries where the system took action (Tier 2 or Tier 3 recovery actions)
   - Identified by log messages containing "recovery method" or "VPN restored" terminology
   - Indicates that recovery actions (xfrm recovery, ipsec reload, or ipsec restart) were attempted

2. **Self-Healed Recoveries** (no intervention):
   - Recoveries that occurred naturally without system intervention
   - Identified by log messages containing "VPN recovered" without "recovery method"
   - Indicates natural recovery (e.g., SA rekey, network recovery, transient issues)

**Classification Method**:
- Pattern-based classification using log message analysis
- Uses specific log message patterns to distinguish recovery types
- Relies on recovery method tracking stored in state files during recovery actions
- Log messages include recovery method information when intervention occurred

## Consequences

### Positive
- **Intervention Evaluation**: Enables evaluation of recovery action effectiveness
- **System Stability Assessment**: Provides visibility into VPN stability patterns
- **Pattern Analysis**: Enables analysis of recovery patterns over time
- **Operational Insights**: Helps distinguish between transient and persistent failures
- **Metrics Enhancement**: Separate statistics for app-managed vs self-healed recoveries
- **CSV Export**: Recovery type labels in CSV export for spreadsheet analysis
- **Report Generation**: Recovery type breakdown in text reports and event timelines
- **No Code Changes Required**: Classification is done in log analysis script, no changes to recovery logic needed

### Negative
- **Pattern Dependency**: Classification relies on log message patterns, which could break if log format changes
- **Analysis-Only**: Distinction is only in log analysis, not in real-time monitoring
- **Pattern Matching Complexity**: Multiple pattern checks required for accurate classification
- **Edge Cases**: Some edge cases (e.g., recovery without failure count) require special handling

## Implementation Details

### Log Message Patterns

**App-Managed Recovery Patterns**:
- `"VPN restored for LOCATION (IP) after N failures (recovery method: METHOD)"` - Explicit recovery method
- `"VPN restored for LOCATION (IP) (recovery method: METHOD)"` - Recovery method without failure count
- `"VPN restored for LOCATION (IP) after N failures"` - "restored" terminology indicates intervention
- `"VPN restored for LOCATION (IP)"` - "restored" terminology indicates intervention

**Self-Healed Recovery Patterns**:
- `"VPN recovered for LOCATION (IP) after N failures"` - "recovered" without recovery method
- `"VPN recovered for LOCATION (IP)"` - "recovered" without recovery method or failure count

### Classification Logic

The classification logic in `analyze-logs.sh` uses a hierarchical pattern matching approach:

1. **Check for "recovery method"** (most specific) - Always app-managed
2. **Check for "VPN restored"** - Always app-managed (indicates intervention)
3. **Check for "after X failures"** with "VPN recovered" - Self-healed (no intervention)
4. **Default to self-healed** - Edge cases default to self-healed

### Recovery Method Tracking

Recovery methods are tracked in state files during recovery actions:
- **Storage**: `recovery_method` state key in state files
- **Methods**: `"xfrm"`, `"ipsec_reload"`, `"ipsec_restart"`
- **Display**: Formatted for log messages (e.g., `"xfrm"` → `"xfrm-based recovery"`)
- **Location**: Stored in `${STATE_DIR}` directory per location/peer

### Statistics and Metrics

The log analysis script provides separate statistics for each recovery type:
- **Total Recoveries** = App-Managed Recoveries + Self-Healed Recoveries
- **Recovery Success Rate** = (Total Recoveries / Total Failures) × 100%
- **App-Managed Recovery Rate** = (App-Managed Recoveries / Total Failures) × 100%
- **Self-Healed Recovery Rate** = (Self-Healed Recoveries / Total Failures) × 100%

### CSV Export

CSV export includes recovery type labels:
- `RECOVERY_APP_MANAGED` - App-managed recovery events
- `RECOVERY_SELF_HEALED` - Self-healed recovery events

### Report Generation

Text reports include recovery type breakdown:
- Summary statistics with separate counts and rates
- Event timeline with recovery type labels
- Enables evaluation of intervention effectiveness and VPN stability patterns

## Related ADRs
- ADR-0003: Tiered Recovery System (recovery actions that trigger app-managed classification)
- ADR-0004: Per-Peer State Tracking (recovery method state storage)
- ADR-0015: File-Based State Storage (state file storage mechanism)
- ADR-0016: State File Location (/data/vpn-monitor/) (state file location)

## References
- docs/ARCHITECTURE.md: "Recovery Type Distinction" section (lines 565-593)
- analyze-logs.sh: `analyze_logs()` function (lines 396-423) - classification logic
- lib/recovery/recovery_state.sh: Recovery method tracking functions
- tests/test_analyze_logs.sh: Comprehensive test coverage for recovery type distinction
- CHANGELOG.md: Version 0.5.0 - "Recovery Type Distinction in Log Analysis" entry
