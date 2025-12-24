# ADR-0009: VPN Keepalive Daemon (Optional)

## Status
Accepted

## Context
VPN tunnels may be idle for extended periods:
- No traffic flowing through tunnel
- Byte counters not increasing
- Tunnel appears "down" but is actually healthy
- Network devices may timeout idle connections

Without keepalive:
- Idle VPNs trigger false positives
- Healthy tunnels detected as failed
- Unnecessary recovery actions triggered
- Byte counter detection fails for idle tunnels

## Decision
We will implement an optional VPN keepalive daemon that:
- Runs as a separate systemd service
- Sends periodic ping traffic through VPN tunnels
- Prevents idle timeout and keeps tunnels active
- Works independently from the monitoring script

## Consequences

### Positive
- **Prevents False Positives**: Keeps idle tunnels active
- **Maintains Byte Counters**: Ensures byte counters continue incrementing
- **Optional**: Users can enable/disable based on their needs
- **Independent Operation**: Separate from monitoring script, doesn't affect monitoring logic
- **Automatic Restart**: When managed via systemd, automatically restarts on failure

### Negative
- **Additional Component**: Requires separate daemon process
- **Resource Usage**: Continuous background process (minimal)
- **Configuration**: Requires additional configuration and service management
- **Complexity**: Additional component to maintain and troubleshoot

## Implementation Details
- **Service File**: `vpn-keepalive.service` (systemd unit)
- **Script**: `vpn-keepalive.sh` (daemon implementation)
- **Configuration**: Uses same `vpn-monitor.conf` configuration
- **Operation**:
  - Runs continuously as background daemon
  - Sends pings at configured intervals (default: 30 seconds)
  - Uses internal IP addresses (from `INTERNAL_PEER_IPS`) when available
  - Falls back to external IPs if internal IPs not configured
- **Management**: Controlled via systemd (`systemctl enable/start/stop vpn-keepalive`)
- **Logging**: Minimal logging (only logs failures, not successful pings)

## Related ADRs
- ADR-0006: Multi-Method Detection with Fallback
- ADR-0001: Cron-Based Execution Instead of Daemon

## References
- ARCHITECTURE.md: "Key Design Decisions #10: VPN Keepalive Daemon"
- ARCHITECTURE.md: "VPN Keepalive Daemon" section
- README.md: "Keepalive Daemon" section
- vpn-keepalive.sh: Implementation details

