# ADR-0004: Per-Peer State Tracking

## Status
Accepted

## Context
Many UDM deployments have multiple Site-to-Site VPN connections to different remote sites. These VPNs:
- Operate independently
- May fail independently
- Should be monitored and recovered independently
- Have different traffic patterns and failure characteristics

A shared failure counter would:
- Cause recovery actions for one VPN to affect monitoring of others
- Prevent independent recovery actions per VPN
- Mix failure patterns from different VPNs
- Make troubleshooting difficult

## Decision
We will track state independently for each configured peer IP, including:
- Per-peer failure counters (`failure_counter_<peer_ip>`)
- Per-peer byte counters (`last_bytes_<peer_ip>`)
- Independent recovery actions per peer
- Separate state files with sanitized IP addresses in filenames

## Consequences

### Positive
- **Independent Monitoring**: Each VPN is monitored separately
- **Independent Recovery**: Recovery actions can target specific failing VPNs
- **Accurate Detection**: Byte counter tracking per peer ensures accurate traffic flow detection
- **Better Troubleshooting**: Per-peer logging and state files make diagnosis easier
- **Multi-Tunnel Support**: Enables monitoring of multiple VPN peers without interference

### Negative
- **File System Overhead**: Multiple state files (one per peer)
- **Code Complexity**: Requires peer IP handling throughout the codebase
- **Filename Sanitization**: Need to sanitize IP addresses for safe filenames (dots/colons → underscores)

## Implementation Details
- **Failure Counters**: Stored in `logs/failure_counter_<sanitized_ip>` (e.g., `failure_counter_192_168_1_1`)
- **Byte Counters**: Stored in `last_bytes_<sanitized_ip>` (e.g., `last_bytes_192_168_1_1`)
- **IP Sanitization**: Dots and colons replaced with underscores (IPv4: `192.168.1.1` → `192_168_1_1`, IPv6: `2001:db8::1` → `2001_db8__1`)
- **Independent Tracking**: Each peer's failure count and byte counters tracked separately
- **Recovery Actions**: Triggered independently based on each peer's failure count
- **State Reset**: Each peer's failure counter resets independently when that peer's VPN check succeeds

## Related ADRs
- ADR-0003: Tiered Recovery System
- ADR-0006: Multi-Method Detection with Fallback
- ADR-0012: Atomic File Operations

## References
- ARCHITECTURE.md: "Key Design Decisions #4: Per-Peer State Tracking"
- ARCHITECTURE.md: "File Structure" section
- README.md: "Per-Peer Tracking" section
- lib/state.sh: Implementation details

