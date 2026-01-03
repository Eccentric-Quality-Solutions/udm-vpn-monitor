# Audit: Missing Dependencies and Recovery Actions

**Date:** 2026-01-03  
**Purpose:** Audit codebase for paths where missing dependencies or resources could trigger inappropriate recovery actions (e.g., restarting VPNs when detection tools are unavailable)

## Summary

After comprehensive audit, **the codebase is safe** - recovery actions are properly guarded by availability checks. The recent fix for ipsec unavailability is working correctly.

**Important:** Both `ip` and `ipsec` commands use the same robust checking mechanism (`check_command_available()`) with multiple fallback layers, ensuring consistent behavior regardless of PATH restrictions or command location.

## Recent Fix (Verified)

The fix at `lib/recovery.sh:1482-1506` prevents escalation when:
- Failure type is "unknown" 
- Both `ip` and `ipsec` commands are unavailable

This correctly prevents false recovery actions when detection is unreliable.

## Command Availability Checking

### Unified Checking Function
Both `ip` and `ipsec` (and all other commands) use the same `check_command_available()` function (`lib/common.sh:808-858`), which provides multiple fallback mechanisms:

1. **Primary:** `command -v` (POSIX compliant, checks PATH)
2. **Fallback 1:** Checks common system directories directly (`/usr/sbin`, `/usr/bin`, `/sbin`, `/bin`)
   - Handles cron/systemd environments where PATH may be restricted
   - Common issue on UDM OS where PATH doesn't include `/usr/sbin`
3. **Fallback 2:** Attempts to execute command with `--help` or `--version` flags
   - Handles cases where command exists but `command -v` doesn't find it
   - Handles functions, aliases, or commands in non-standard locations
   - Uses timeout to prevent hanging

**Result:** Both `ip` and `ipsec` get the same robust checking with all fallbacks. There's no difference in how they're checked.

### Usage Pattern
```bash
# Both use the same function:
if check_command_available "ip"; then
    _RECOVERY_IP_AVAILABLE=1
fi

if check_command_available "ipsec"; then
    _RECOVERY_IPSEC_AVAILABLE=1
fi
```

## Safe Paths Verified

### 1. Recovery Strategy Selection
- **Location:** `lib/recovery.sh:895-961` (`select_recovery_strategy()`)
- **Protection:** Checks command availability (`_check_recovery_command_availability()`) before selecting strategies
- **Result:** If commands unavailable, returns error, no recovery executed

### 2. Recovery Execution
- **Locations:** 
  - `lib/recovery.sh:1001-1107` (`surgical_cleanup()`)
  - `lib/recovery.sh:1156-1250` (`full_restart()`)
- **Protection:** Both functions call `select_recovery_strategy()` first
- **Result:** If strategy selection fails, functions return/exit without executing recovery

### 3. IPsec Command Execution
- **Locations:**
  - `lib/recovery.sh:1045` (`ipsec reload` in surgical_cleanup)
  - `lib/recovery.sh:1051` (`ipsec restart` in surgical_cleanup)
  - `lib/recovery.sh:1207` (`ipsec restart` in full_restart)
- **Protection:** Only executed after `select_recovery_strategy()` succeeds, which verifies ipsec availability
- **Result:** Safe - ipsec commands only execute when ipsec is confirmed available

### 4. Verification Functions
- **Location:** `lib/recovery.sh:172-260` (`verify_ipsec_connections_active()`)
- **Protection:** Checks `check_command_or_warn "ipsec"` at line 202 before using ipsec
- **Result:** Safe - returns error if ipsec unavailable

### 5. Detection Functions
- **Locations:**
  - `lib/detection.sh:1626-1645` (`check_ipsec_phase2()`)
  - `lib/detection.sh:1330-1352` (`check_ipsec_status()`)
  - `lib/detection.sh:506-515` (`get_xfrm_state_for_peer()`)
- **Protection:** All check command availability before use
- **Result:** Safe - return errors instead of false failures

### 6. Ping Checks
- **Location:** `lib/detection.sh:732-870` (`check_ping_connectivity()`)
- **Protection:** Checks `check_command_or_warn "ping"` at line 745 before using ping
- **Result:** Safe - returns error if ping unavailable

### 7. State File Access
- **Locations:** 
  - `lib/state.sh:454-458` (`get_failure_count()`)
  - `lib/state.sh:822-850` (`check_rate_limit()`)
  - `lib/state.sh:878-920` (`record_restart()`)
- **Protection:** All use `file_exists_and_readable()` before accessing files
- **Result:** Safe - handles missing files gracefully

## Edge Cases Analyzed

### Case 1: Only ipsec Unavailable (ip Available)
**Scenario:** `ip` available, `ipsec` unavailable, failure_type="unknown"

**Flow:**
1. Check at line 1498: Allows escalation (ip is available)
2. Tier 2/3 recovery attempted
3. `select_recovery_strategy()` called
4. Strategy selection fails (ipsec required for ipsec_reload/restart)
5. Recovery function returns error, no recovery executed

**Result:** ✅ Safe - no recovery executed despite escalation being allowed

### Case 2: Only ip Unavailable (ipsec Available)
**Scenario:** `ipsec` available, `ip` unavailable, failure_type="unknown"

**Flow:**
1. Check at line 1498: Allows escalation (ipsec is available)
2. Tier 2/3 recovery attempted
3. `select_recovery_strategy()` called
4. Strategy selection succeeds (ipsec_reload/restart available)
5. Recovery executes using ipsec commands

**Result:** ✅ Safe - ipsec commands are available and checked

### Case 3: Both Commands Unavailable
**Scenario:** Both `ip` and `ipsec` unavailable, failure_type="unknown"

**Flow:**
1. Check at line 1498: Prevents escalation
2. Returns early at line 1504
3. No recovery attempted

**Result:** ✅ Safe - escalation prevented by recent fix

## Potential Improvement (Low Priority)

**Location:** `lib/recovery.sh:1485-1506`

**Current Behavior:** Only prevents escalation when BOTH ip AND ipsec are unavailable

**Suggested Improvement:** Also check if recovery strategies are available before allowing escalation. This would make the intent clearer and prevent unnecessary strategy selection attempts.

**Impact:** Low - current behavior is safe (strategy selection will fail anyway), but improvement would make code clearer

**Example:**
```bash
# After checking command availability, also verify recovery is possible
if [[ "$failure_type" == "unknown" ]]; then
    # ... existing checks ...
    
    # Additional check: Verify recovery strategies are available
    if ! select_recovery_strategy "$external_peer_ip" 2 >/dev/null 2>&1; then
        handle_error "ERROR" "Detection unreliable and no recovery strategies available - skipping recovery escalation"
        return 0
    fi
fi
```

**Note:** This is optional - current code is safe as-is.

## Conclusion

✅ **Codebase is safe** - all recovery paths properly check dependencies before executing actions.

✅ **Recent fix is working correctly** - prevents escalation when detection is unreliable.

✅ **No critical issues found** - all command executions are properly guarded.

✅ **State file access is safe** - all functions check file existence before access.

The codebase follows defense-in-depth principles with multiple layers of protection against inappropriate recovery actions.
