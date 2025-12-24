# ADR-0001: Cron-Based Execution Instead of Daemon

## Status
Accepted

## Context
The UDM VPN Monitor needs to run continuously to monitor VPN tunnel health. On UniFi Dream Machine systems, there are two primary approaches for running background processes:
1. Long-running daemon process (systemd service)
2. Cron-based periodic execution

The UDM OS environment has specific constraints:
- System restarts may occur during UniFi OS upgrades
- Long-running processes may be killed or interrupted
- Cron jobs are more resilient to system changes
- Cron provides simpler error handling (process exits, cron restarts it)
- No need for process management, signal handling, or daemon lifecycle management

## Decision
We will use cron-based execution with periodic runs (default: every 1 minute) instead of a long-running daemon process.

## Consequences

### Positive
- **Resilience**: Survives system restarts automatically via cron
- **Simplicity**: No daemon lifecycle management, signal handling, or process monitoring required
- **Error Recovery**: If script crashes, cron automatically restarts it on next schedule
- **Resource Efficiency**: Script runs only when needed, no idle process overhead
- **Easier Debugging**: Each execution is independent, easier to trace and debug
- **UDM Compatibility**: Cron jobs are more likely to survive UniFi OS upgrades

### Negative
- **Check Frequency**: Limited to cron schedule granularity (minimum 1 minute intervals)
- **No Continuous Monitoring**: Brief failures between cron runs may be missed
- **Cron Dependency**: Relies on cron service being available and configured correctly
- **Potential Cron Wipe**: Cron jobs may be removed during UniFi OS upgrades (mitigated by installation script)

## Implementation Details
- Default cron schedule: `*/1 * * * *` (every 1 minute)
- Configurable via `CRON_SCHEDULE` configuration variable
- Lockfile protection prevents concurrent executions if cron runs overlap
- Installation script sets up cron job automatically
- Uninstallation script removes cron job cleanly

## Related ADRs
- ADR-0002: Lockfile Protection Mechanism

## References
- ARCHITECTURE.md: "Key Design Decisions #1: Cron-Based Execution"
- README.md: "Cron-Based: More resilient than long-running processes on UDM"

