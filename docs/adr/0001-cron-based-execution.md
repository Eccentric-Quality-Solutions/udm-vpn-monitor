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
- Core monitor avoids daemon lifecycle management; optional wrapper ([ADR-0032](0032-sub-minute-execution-via-wrapper.md)) and keepalive ([ADR-0009](0009-vpn-keepalive-daemon.md)) add separate long-running processes when enabled

## Decision
We will use cron-based execution with periodic runs (default: every 1 minute) instead of a long-running **monitor daemon**. The core monitor (`vpn-monitor.sh`) runs, exits, and is invoked again on schedule — each execution is independent.

Optional sub-minute checks use a separate wrapper process ([ADR-0032](0032-sub-minute-execution-via-wrapper.md)); that does not change the monitor's run-and-exit model. The optional keepalive daemon ([ADR-0009](0009-vpn-keepalive-daemon.md)) is also separate from the monitor cron path.

## Consequences

### Positive
- **Resilience**: Survives system restarts automatically via cron
- **Simplicity**: No daemon lifecycle management, signal handling, or process monitoring required
- **Error Recovery**: If script crashes, cron automatically restarts it on next schedule
- **Resource Efficiency**: Script runs only when needed, no idle process overhead (wrapper and keepalive are optional separate processes)
- **Easier Debugging**: Each execution is independent, easier to trace and debug
- **UDM Compatibility**: Cron jobs are more likely to survive UniFi OS upgrades

### Negative
- **Check Frequency**: Limited to cron schedule granularity (minimum 1 minute intervals) when cron invokes `vpn-monitor.sh` directly; optional sub-minute checks via wrapper (see ADR-0032) trade pure run-and-exit simplicity for a long-running scheduling loop
- **No Continuous Monitoring**: Brief failures between cron runs may be missed when wrapper is disabled; mitigated when `ENABLE_MONITOR_WRAPPER=1` (ADR-0032)
- **Cron Dependency**: Relies on cron service being available and configured correctly
- **Potential Cron Wipe**: Cron jobs may be removed during UniFi OS upgrades (mitigated by installation script)

## Implementation Details
- Default cron schedule: `*/1 * * * *` (every 1 minute)
- Configurable via `CRON_SCHEDULE` configuration variable
- Lockfile protection prevents concurrent executions if cron runs overlap
- Installation script sets up cron job automatically
- Uninstallation script removes cron job cleanly
- **Sub-minute checks (optional, default on):** When `ENABLE_MONITOR_WRAPPER=1`, cron runs `vpn-monitor-wrapper.sh` instead of `vpn-monitor.sh` directly. The wrapper loops with `MONITOR_INTERVAL` (default 20s). `vpn-monitor.sh` remains run-and-exit per invocation. See ADR-0032.

## Related ADRs
- ADR-0002: Lockfile Protection Mechanism
- ADR-0009: VPN Keepalive Daemon (Optional) — separate optional long-running process
- ADR-0032: Sub-Minute Execution via Wrapper Script

## References
- ARCHITECTURE.md: "Key Design Decisions #1: Cron-Based Execution"
- README.md: "Cron-Based: More resilient than long-running processes on UDM"

