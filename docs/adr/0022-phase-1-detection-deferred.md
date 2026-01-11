# ADR-0022: Phase 1 Detection Deferred

## Status
Accepted

## Context

IPsec VPN tunnels operate in two phases:
- **Phase 1 (IKE)**: Establishes the control channel for key exchange and authentication
- **Phase 2 (ESP/AH)**: Establishes the data channel for encrypted traffic

When a VPN tunnel fails, the failure can occur at either phase:
- **Phase 1 failure**: IKE SA is down, preventing Phase 2 negotiation
- **Phase 2 failure**: IKE SA is up, but ESP/AH SA negotiation failed or SA was deleted

The current detection system can reliably detect Phase 2 (ESP/AH) Security Associations (SAs) using `ip xfrm state`, but cannot distinguish between Phase 1 failures and Phase 2 negotiation failures when Phase 2 SAs don't exist.

**Current Capability**:
- Phase 2 detection: Can reliably detect Phase 2 (ESP/AH) SAs via `ip xfrm state`
- Phase 1 inference: If Phase 2 SA exists, Phase 1 must be up (Phase 2 requires Phase 1)
- Phase 1 ambiguity: If Phase 2 SA doesn't exist, cannot distinguish Phase 1 down vs Phase 2 negotiation failure

**UDM OS Constraints**:
- UDM OS uses strongSwan but does not provide `swanctl` utility (the standard tool for querying Phase 1 state)
- The `ipsec status` command is available but its reliability for Phase 1 state detection when Phase 2 is down is unknown
- Would require empirical testing to determine if `ipsec status` parsing is reliable across UDM OS versions

## Decision

We will **not implement Phase 1 detection at this time**. Instead, we will treat all tunnel-down scenarios uniformly, relying on the existing recovery fallback mechanism to handle both Phase 1 and Phase 2 failures appropriately.

**Rationale**:
1. **Recovery effectiveness**: The current recovery system already handles both failure types correctly:
   - xfrm recovery (Phase 2 SA deletion) works when Phase 1 is up but Phase 2 failed
   - When xfrm recovery times out (indicating Phase 1 may be down), the system falls back to `ipsec reload`/`ipsec restart`, which fixes Phase 1 failures
2. **Minimal practical impact**: The only impact is a bounded delay (up to 30 seconds) when Phase 1 is down, as xfrm recovery attempts before falling back to more aggressive recovery
3. **Investigation required**: Implementing Phase 1 detection would require:
   - Empirical testing of `ipsec status` output reliability when Phase 1 is up but Phase 2 is down
   - Verification across multiple UDM OS versions
   - Parsing implementation and comprehensive testing
4. **Low priority**: Phase 1 failures are less common than Phase 2 issues, and the current system already recovers correctly

## Consequences

### Positive
- **Simpler implementation**: No need for Phase 1 state parsing or additional detection logic
- **Proven recovery path**: Current recovery mechanism is battle-tested and handles all failure scenarios
- **No investigation overhead**: Avoids time spent testing `ipsec status` parsing reliability
- **Consistent behavior**: All tunnel-down scenarios handled uniformly, reducing complexity

### Negative
- **Recovery delay**: When Phase 1 is down, xfrm recovery attempts first (up to 30 seconds timeout) before falling back to `ipsec reload`/`ipsec restart`
- **Less targeted recovery**: Cannot optimize recovery strategy based on failure phase (e.g., skip xfrm recovery when Phase 1 is known to be down)
- **Diagnostic limitation**: Cannot distinguish Phase 1 vs Phase 2 failures in logs and monitoring

### Impact Assessment

**Practical Impact**: **Low to Minimal**

- Recovery works correctly in all scenarios (fallback ensures success)
- Delay is bounded and acceptable (30 seconds maximum)
- Phase 1 failures are less common than Phase 2 issues
- Current uniform treatment is acceptable given fallback mechanism

## Future Consideration

Phase 1 detection **could be implemented in the future** if:
1. **Investigation proves feasibility**: Testing confirms `ipsec status` reliably shows Phase 1 state when Phase 2 is down
2. **Parsing reliability verified**: Confirmed to work consistently across UDM OS versions
3. **Benefit justifies effort**: The delay reduction becomes a priority or diagnostic value is needed

**Potential Implementation Approach**:
1. Test `ipsec status` output when Phase 1 is up but Phase 2 is down
2. Verify parsing reliability across UDM OS versions
3. Implement Phase 1 state detection using `ipsec status` parsing (similar to existing `discover_connection_name()` function)
4. Update recovery strategy selection to skip xfrm recovery when Phase 1 is known to be down
5. Add Phase 1 state to failure type detection for better diagnostics

**Alternative Approaches**:
- If `ipsec status` parsing proves unreliable, would require `swanctl` or equivalent Phase 1 state query mechanism (not available on UDM OS)
- Could investigate other strongSwan state query mechanisms if available on UDM OS

## Implementation Details

**Current Behavior**:
- When Phase 2 SA doesn't exist, failure type is detected as "tunnel_down"
- Recovery attempts xfrm-based recovery first (Tier 2/Tier 3)
- If xfrm recovery times out (30 seconds), falls back to `ipsec reload`/`ipsec restart`
- Fallback recovery fixes both Phase 1 and Phase 2 failures

**Recovery Flow**:
1. Tier 2/Tier 3: Attempt xfrm recovery (deletes Phase 2 SAs, waits for re-establishment)
2. If xfrm recovery succeeds: Phase 2 was the issue, recovery complete
3. If xfrm recovery times out: Phase 1 likely down, fallback to `ipsec reload`/`ipsec restart`
4. Fallback recovery: Fixes Phase 1 failures and re-establishes both phases

**Code References**:
- `lib/detection/failure_analysis.sh`: `detect_failure_type()` - detects "tunnel_down" but cannot distinguish Phase 1 vs Phase 2
- `lib/recovery.sh`: `attempt_xfrm_recovery()` - attempts Phase 2 SA deletion, times out after 30 seconds
- `lib/recovery.sh`: `surgical_cleanup()` / `full_restart()` - fallback to `ipsec reload`/`ipsec restart` when xfrm fails

## Related ADRs
- ADR-0003: Tiered Recovery System (recovery fallback mechanism)
- ADR-0006: Multi-Method Detection with Fallback (detection approach)
- ADR-0019: Byte Counter Detection Method (Phase 2 detection)

## References
- ARCHITECTURAL_REVIEW.md: "Phase 1 vs Phase 2 Failure Distinction" (section 6.2)
- ARCHITECTURE.md: Detection Method Flow
- UDM-Linux-Tools.md: Available tools on UDM OS
- lib/detection/failure_analysis.sh: `detect_failure_type()` implementation
- lib/recovery.sh: Recovery strategy selection and fallback logic

