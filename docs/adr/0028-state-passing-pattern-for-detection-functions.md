# ADR-0028: State Passing Pattern for Detection Functions

## Status
Accepted

## Context
The VPN detection system requires checking Security Association (SA) existence at multiple points in the detection flow:
- `check_xfrm_status()` checks SA existence to determine tunnel status
- `check_ping_if_enabled()` needs SA existence state for accurate logging
- `detect_failure_type()` needs SA existence state to classify failure types

**Original Problem:**
- Each function was independently checking SA existence, leading to:
  - **Duplicate system calls**: `ip xfrm state` executed 3 times per VPN check cycle
  - **Performance overhead**: 66-75% more system calls than necessary
  - **Inconsistent state**: Temporal inconsistencies when SA state changes between checks
  - **Contradictory log messages**: Functions inferred SA state from `vpn_ok` return code, leading to incorrect assumptions (e.g., `vpn_ok=0` could mean "no SA" OR "SA exists but validation failed")

**Alternative Approaches Considered:**
1. **Re-checking at each function** (original approach) - Simple but inefficient and error-prone
2. **Centralized caching** - Adds complexity, risk of stale data, bash associative array compatibility concerns
3. **State passing via parameters** (chosen) - Explicit data flow, eliminates duplicates, maintains consistency

## Decision
We will implement a state passing pattern where expensive system state checks (like SA existence) are performed once at the source and passed explicitly to downstream functions via function parameters. This eliminates duplicate checks, improves performance, and ensures consistent state across the detection flow.

**Pattern:**
- Source function (e.g., `check_xfrm_status()`) performs the system check and exposes state via optional output variable parameter
- Downstream functions (e.g., `check_ping_optional()`, `detect_failure_type()`) receive state as explicit parameters
- Functions maintain backward compatibility by accepting optional parameters with fallback to checking if not provided

## Consequences

### Positive
- **Performance Improvement**: Reduces system calls by 66-75% (from 3 SA checks to 1 per cycle)
- **Consistent State**: All functions use the same state snapshot, eliminating temporal inconsistencies
- **Explicit Data Flow**: State passing makes data dependencies clear and traceable
- **Accurate Logging**: Functions use actual SA state rather than inferring from return codes
- **Separation of Concerns**: Functions focus on their primary responsibility (e.g., ping checks) rather than also checking SA state
- **DRY Principle**: State is captured once and reused, following Don't Repeat Yourself
- **Backward Compatibility**: Optional parameters allow gradual adoption without breaking existing code

### Negative
- **Function Signature Changes**: Functions need additional optional parameters (maintained backward compatible)
- **Parameter Passing Overhead**: Slightly more complex function calls (minimal impact)
- **State Management**: Callers must capture and pass state explicitly (improves clarity)

## Implementation Details

### Pattern Implementation

**Source Function (State Provider):**
```bash
check_xfrm_status() {
  local peer_ip="$1"
  local sa_exists_var="${5:-}"  # Optional output variable for SA existence state

  # Perform system check
  local xfrm_output=$(get_xfrm_state_for_peer "$peer_ip")

  if [[ -z "$xfrm_output" ]]; then
    # No SA exists - set output variable if provided
    if [[ -n "$sa_exists_var" ]]; then
      printf -v "$sa_exists_var" "%s" "0"
    fi
    return 1
  fi

  # SA exists - set output variable if provided
  if [[ -n "$sa_exists_var" ]]; then
    printf -v "$sa_exists_var" "%s" "1"
  fi

  # ... rest of validation logic ...
  return $exit_code
}
```

**Caller Function (State Capturer and Passer):**
```bash
check_vpn_status() {
  local sa_exists=""

  # Capture SA existence state from xfrm check
  if check_xfrm_primary "$external_peer_ip" "$first_internal_ip" "$location_name" "xfrm_diagnostic" "sa_exists"; then
    vpn_ok=1
  else
    # xfrm check failed, but sa_exists may still be set (SA exists but validation failed)
    # ... fallback logic ...
  fi

  # Pass known state downstream
  check_ping_optional "$vpn_ok" "$external_peer_ip" "$internal_peer_ips" "$location_name" "$sa_exists"
  determine_vpn_status "$vpn_ok" "$external_peer_ip" "$first_internal_ip" "$peer_sanitized" "$location_name" "$sa_exists"
}
```

**Downstream Function (State Consumer):**
```bash
check_ping_optional() {
  local vpn_ok="$1"
  local external_peer_ip="$2"
  local internal_peer_ips="$3"
  local location_name="$4"
  local sa_exists="${5:-}"  # Optional SA existence state

  # Use provided SA existence state if available, otherwise check SA existence
  # This optimization eliminates duplicate SA checks by reusing state from check_xfrm_status()
  if [[ -z "$sa_exists" ]]; then
    # Fallback: check SA existence if not provided (for backward compatibility)
    sa_exists=0
    if check_ipsec_phase2 "$external_peer_ip" 2>/dev/null; then
      sa_exists=1
    fi
  fi

  # Use sa_exists for accurate logging
  check_ping_if_enabled "$sa_exists" "$ping_ip" "$local_ip" "$location_name"
}
```

### Key Implementation Points

- **Output Variable Pattern**: Uses `printf -v "$var_name"` to set output variables (bash idiom for output parameters)
- **Optional Parameters**: All state parameters are optional with fallback behavior for backward compatibility
- **Single Source of Truth**: State is captured once at the source (`check_xfrm_status()`) and passed explicitly
- **Performance**: Reduces from 3 `ip xfrm state` calls to 1 per VPN check cycle
- **Consistency**: All functions use the same state snapshot, eliminating race conditions

### Data Flow

```
check_vpn_status()
  ├─> check_xfrm_primary() -> check_xfrm_status()
  │     └─> Returns: 0 (no SA OR SA exists but validation failed)
  │                1 (SA exists and validated)
  │     └─> Sets sa_exists_var: 0 (no SA) or 1 (SA exists)
  │
  ├─> check_ping_optional(..., sa_exists)
  │     └─> Uses provided sa_exists (no duplicate check!)
  │     └─> check_ping_if_enabled(sa_exists, ...)
  │
  └─> determine_vpn_status(..., sa_exists)
        └─> detect_failure_type(..., sa_exists)
              └─> Uses provided sa_exists (no duplicate check!)
```

### Performance Impact

- **Before**: 3 `ip xfrm state` calls per VPN check cycle
- **After**: 1 `ip xfrm state` call per VPN check cycle
- **Reduction**: 66-75% fewer system calls
- **Scalability**: Impact increases with number of VPNs monitored (each VPN check cycle benefits)

## Related ADRs
- ADR-0006: Multi-Method Detection with Fallback (detection flow architecture)
- ADR-0019: Byte Counter Detection Method (SA state checking context)
- ADR-0014: Ping Check as Supplementary Diagnostic (ping check function that uses SA state)

## References
- analyze/ARCHITECTURE_REVIEW_SA_CHECK.md: Comprehensive architecture review of this refactoring
- lib/detection/xfrm_detection.sh: `check_xfrm_status()` function (state provider)
- lib/detection/failure_analysis.sh: `check_vpn_status()` function (state capturer and passer)
- lib/detection/ping_detection.sh: `check_ping_optional()` function (state consumer)
- lib/detection/failure_analysis.sh: `detect_failure_type()` function (state consumer)
- tests/test_detection_ping_optional.sh: Test coverage for state passing pattern
- CHANGELOG.md: "SA State Passing Optimization" entry
- CODE_REVIEW_detection_split.md: Detection module split (2026-01-15) - state passing pattern preserved across module boundaries