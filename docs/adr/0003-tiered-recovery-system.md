# ADR-0003: Tiered Recovery System

## Status
Accepted

## Context
VPN tunnel failures can have different severities and causes:
- Transient network issues that resolve themselves
- Routing problems requiring SA cleanup
- Complete tunnel failures requiring full restart

A single recovery action (e.g., always restarting) would be:
- Too disruptive for minor issues
- Potentially causing unnecessary downtime
- Affecting all VPN tunnels even when only one fails
- Risking restart loops if the underlying issue persists

## Decision
We will implement a three-tier recovery system that escalates based on consecutive failure count (defaults: `TIER1_THRESHOLD=1`, `TIER2_THRESHOLD=2`, `TIER3_THRESHOLD=3`):
1. **Tier 1 (Logging)**: Log failures for monitoring (threshold: 1+ failures)
2. **Tier 2 (Surgical Cleanup)**: Per-connection recovery via xfrm (default); optional `ipsec reload` fallback only when `ENABLE_TIER2_IPSEC_RELOAD=1` (default **0** — disabled because reload affects all tunnels)
3. **Tier 3 (Full Restart)**: Per-connection xfrm recovery (default) or `ipsec restart` (fallback) when xfrm disabled or fails (threshold: 3+ failures)

## Consequences

### Positive
- **Gradual Escalation**: Prevents unnecessary disruption for transient issues
- **Targeted Recovery**: Default xfrm-based recovery affects only the failing tunnel
- **Fallback Safety**: Tier 3 falls back to `ipsec restart` when xfrm recovery fails; Tier 2 avoids global reload by default until Tier 3 threshold
- **Configurable Thresholds**: Users can adjust escalation thresholds based on their needs
- **Per-Peer Independence**: Each VPN peer has independent failure tracking

### Negative
- **Complexity**: Requires tracking failure counts and tier logic
- **Recovery Delay**: Multiple failures required before recovery actions
- **Fallback Impact**: When xfrm recovery fails at Tier 3, `ipsec restart` fallback affects all tunnels; Tier 2 avoids global reload by default (`ENABLE_TIER2_IPSEC_RELOAD=0`)

## Implementation Details
- **Tier 1**: Logs failure with context (peer IP, failure type, failure count)
- **Tier 2 Default**: Uses `ip xfrm state delete` for per-connection recovery (enabled by default, `ENABLE_XFRM_RECOVERY=1`)
- **Tier 2 Fallback**: Uses `ipsec reload` (affects all connections) if xfrm disabled or fails. Configurable via `ENABLE_TIER2_IPSEC_RELOAD` (default 0); when 0, ipsec reload is not used at Tier 2.
- **Tier 3 Default**: Attempts xfrm-based per-connection recovery first (enabled by default, `ENABLE_XFRM_RECOVERY=1`)
- **Tier 3 Fallback**: Uses `ipsec restart` (affects all tunnels) if xfrm disabled or fails
- **Rate Limiting**: Tier 3 actions are rate-limited to prevent restart loops
- **Cooldown Period**: After Tier 3 actions, system enters cooldown to allow stabilization
- **Module**: Implemented in `lib/recovery/` (orchestration in `recovery_orchestration.sh`; `surgical_cleanup()` and `full_restart()`)

## Change History
- **v0.8.0 (2026-02-14)**: Default thresholds changed from 3/5 to 2/3 for Tier 2/Tier 3. See CHANGELOG.md v0.8.0.
- **v0.8.3 (2026-02-25)**: Tier 2 `ipsec reload` disabled by default (`ENABLE_TIER2_IPSEC_RELOAD=0`; opt-in via `=1`). See CHANGELOG.md v0.8.3.

## Related ADRs
- ADR-0004: Per-Peer State Tracking
- ADR-0008: Rate Limiting and Cooldown Periods
- ADR-0006: Multi-Method Detection with Fallback

## References
- ARCHITECTURE.md: "Key Design Decisions #3: Tiered Recovery"
- ARCHITECTURE.md: "Recovery Tier Flow" diagram
- lib/recovery.sh: Implementation details

