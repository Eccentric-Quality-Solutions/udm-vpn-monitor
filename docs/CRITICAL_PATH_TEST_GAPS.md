# Critical Path Test Coverage Gaps

This document identifies critical execution paths in the VPN monitor codebase and lists additional tests that should be added to ensure comprehensive coverage of these paths.

## Critical Paths Overview

The VPN monitor follows these main execution paths:

1. **Main Execution Flow** (`vpn-monitor.sh`)
   - Lockfile acquisition → Config loading → State initialization → Cooldown check → Network partition check → Peer monitoring → Recovery escalation

2. **Detection Flow** (`lib/detection.sh`)
   - VPN status check (xfrm → ipsec fallback) → Byte counter validation → SA rekey detection → Ping checks → Failure type detection

3. **Recovery Flow** (`lib/recovery.sh`)
   - Tier escalation → Recovery strategy selection → xfrm recovery → ipsec reload/restart → Rate limiting → Cooldown management

4. **State Management Flow** (`lib/state.sh`)
   - Per-peer state tracking → Failure counters → Cooldown tracking → Rate limiting → State file corruption recovery

5. **Configuration Flow** (`lib/config.sh`)
   - Config loading → Schema validation → Default application → Safe parsing

## Missing Critical Path Tests

### 1. Main Execution Flow (`vpn-monitor.sh`)

#### 1.1 Network Partition Detection
**Critical Path**: `process_peer_ips()` → `check_network_partition()` → Skip VPN checks

**Missing Tests**:
- [ ] Network partition detected - VPN checks skipped for all peers
- [ ] Network partition state transitions (healthy → partitioned → healthy)
- [ ] Network partition check disabled (`ENABLE_NETWORK_PARTITION_CHECK=0`) - VPN checks proceed normally
- [ ] Network partition check fails (DNS/timeout) - Should default to healthy or partitioned?
- [ ] Network partition state file corrupted - Should recover gracefully
- [ ] Network partition check during cooldown - Should still check partition before skipping VPN checks

**Why Critical**: Network partition detection prevents false VPN failure detection when the local network is down. This is a critical safety mechanism that prevents unnecessary recovery actions.

#### 1.2 Command-Line Argument Validation
**Critical Path**: Early argument parsing → `validate_args()` → `parse_args()`

**Missing Tests**:
- [ ] Multiple `--fake` flags - Should handle gracefully
- [ ] `--fake` combined with `--help` - Should show help and exit (handled early)
- [ ] Invalid file path arguments - Should validate and reject
- [ ] Unknown arguments that look like file paths - Should validate file existence
- [ ] Argument validation failure during config loading - Should exit cleanly

**Why Critical**: Argument validation happens early and affects all subsequent execution. Invalid arguments could cause unexpected behavior or security issues.

#### 1.3 Early Exit Paths
**Critical Path**: `--help`/`--version` → Early exit before directory creation

**Missing Tests**:
- [ ] `--help` works when directories don't exist (critical for first-run)
- [ ] `--version` works when directories don't exist
- [ ] Early exit paths don't create state files or directories
- [ ] Early exit paths don't require config file to exist

**Why Critical**: Help/version flags must work even when the system is not fully configured, allowing users to understand the script before installation.

#### 1.4 Log File Initialization
**Critical Path**: Early log file write test → Config loading → `recalculate_log_paths()`

**Missing Tests**:
- [ ] Log file write test fails (permissions) - Should exit with clear error
- [ ] Log file path changes after config load (`LOG_FILE` override) - Should use new path
- [ ] Log directory changes after config load (`LOGS_DIR` override) - Should create new directory
- [ ] Log file initialization succeeds but subsequent writes fail - Should handle gracefully

**Why Critical**: Logging is essential for troubleshooting. If logging fails early, the script should fail fast with a clear error message.

### 2. Detection Flow (`lib/detection.sh`)

#### 2.1 Network Partition Detection Functions
**Critical Path**: `check_network_partition()` → `check_default_route()` / `check_dns_resolution()` / `check_interface_state()`

**Missing Tests**:
- [ ] `check_default_route()` - Default route missing
- [ ] `check_default_route()` - Default route exists
- [ ] `check_dns_resolution()` - DNS resolution succeeds
- [ ] `check_dns_resolution()` - DNS resolution fails (timeout)
- [ ] `check_dns_resolution()` - DNS server unreachable
- [ ] `check_interface_state()` - All interfaces UP
- [ ] `check_interface_state()` - One interface DOWN
- [ ] `check_interface_state()` - Interface doesn't exist
- [ ] `check_network_partition()` - All checks pass (network healthy)
- [ ] `check_network_partition()` - One check fails (network partitioned)
- [ ] `check_network_partition()` - Custom DNS server/hostname/interfaces

**Why Critical**: Network partition detection prevents false VPN failure detection. These functions are the foundation of partition detection.

#### 2.2 SA Rekey Detection
**Critical Path**: `check_byte_counters()` → `detect_sa_rekey()` → Reset baseline

**Missing Tests**:
- [ ] SA rekey detected - SPI changes, baseline reset to 0
- [ ] SA rekey detected - Byte counter baseline reset allows new baseline
- [ ] SA rekey detected - Idle state cleared on rekey
- [ ] SA rekey not detected - SPI unchanged
- [ ] SA rekey detection - First check (no stored SPI) - Should store SPI
- [ ] SA rekey detection - SPI file corrupted - Should recover gracefully
- [ ] SA rekey detection - Multiple rekeys in sequence

**Why Critical**: SA rekey events reset byte counter baselines. Without proper detection, rekeys could cause false failure detection.

#### 2.3 Failure Type Detection
**Critical Path**: `check_vpn_status()` → `detect_failure_type()` → Store failure type

**Missing Tests**:
- [ ] Failure type "tunnel_down" - No Phase 2 SA found
- [ ] Failure type "routing_issue" - Phase 2 SA exists but bytes not increasing
- [ ] Failure type "routing_issue" - Phase 2 SA exists but ping fails
- [ ] Failure type "rekey" - SPI changed (not a failure, but logged)
- [ ] Failure type "unknown" - Unable to determine type
- [ ] Failure type stored in state file for recovery actions
- [ ] Failure type cleared on VPN recovery
- [ ] Failure type detection when xfrm unavailable

**Why Critical**: Failure type detection enables recovery actions to use failure-specific strategies. This is important for targeted recovery.

#### 2.4 Idle Tunnel Detection
**Critical Path**: `check_byte_counters()` → Bytes not increasing → Ping check → Idle detection

**Missing Tests**:
- [ ] Idle tunnel detected - Bytes not increasing but ping succeeds
- [ ] Idle tunnel detected - Idle state stored in state file
- [ ] Idle tunnel - Keepalive suggestion logged when keepalive disabled
- [ ] Idle tunnel - Keepalive daemon check when keepalive enabled
- [ ] Idle tunnel - Traffic resumes, idle state cleared
- [ ] Idle tunnel - Ping check disabled, idle not detected

**Why Critical**: Idle tunnel detection prevents false failure detection for tunnels that are healthy but not passing traffic.

### 3. Recovery Flow (`lib/recovery.sh`)

#### 3.1 Recovery Strategy Selection
**Critical Path**: `surgical_cleanup()` / `full_restart()` → `select_recovery_strategy()`

**Missing Tests**:
- [ ] Strategy selection - xfrm recovery selected when peer IP provided and enabled
- [ ] Strategy selection - ipsec_reload selected for Tier 2 when xfrm unavailable
- [ ] Strategy selection - ipsec_restart selected for Tier 3 when xfrm unavailable
- [ ] Strategy selection - No strategy available (no ip/ipsec commands)
- [ ] Strategy selection - Invalid tier (not 2 or 3) - Should error
- [ ] Strategy selection - xfrm recovery disabled (`ENABLE_XFRM_RECOVERY=0`) - Should use ipsec

**Why Critical**: Recovery strategy selection determines which recovery method is used. Incorrect selection could lead to ineffective recovery or unnecessary disruption.

#### 3.2 xfrm Recovery Verification
**Critical Path**: `attempt_xfrm_recovery()` → Delete SAs → Wait for re-establishment → Verify

**Missing Tests**:
- [ ] xfrm recovery - SA re-establishment verification succeeds
- [ ] xfrm recovery - SA re-establishment timeout - Should warn but continue
- [ ] xfrm recovery - Byte counter verification after re-establishment
- [ ] xfrm recovery - Multiple SAs deleted and re-established
- [ ] xfrm recovery - SA count verification after re-establishment
- [ ] xfrm recovery - Verification timeout exceeded - Should log warning
- [ ] xfrm recovery - Exponential backoff during verification wait

**Why Critical**: xfrm recovery verification ensures recovery actually worked. Without verification, recovery actions could appear successful when they're not.

#### 3.3 Recovery Fallback Logic
**Critical Path**: `surgical_cleanup()` → xfrm recovery fails → Fallback to ipsec reload

**Missing Tests**:
- [ ] xfrm recovery fails - Falls back to ipsec reload
- [ ] ipsec reload fails - Falls back to ipsec restart (Tier 2)
- [ ] Recovery fallback - Logs appropriate messages for each fallback
- [ ] Recovery fallback - Verification runs after fallback recovery

**Why Critical**: Fallback logic ensures recovery actions have multiple options. This is critical for reliability when preferred methods fail.

#### 3.4 Rate Limiting Edge Cases
**Critical Path**: `full_restart()` → `check_rate_limit()` → Block or allow

**Missing Tests**:
- [ ] Rate limit - Exactly at limit (should block)
- [ ] Rate limit - One below limit (should allow)
- [ ] Rate limit - Old entries cleaned up before check
- [ ] Rate limit - File contains invalid timestamps - Should recover gracefully
- [ ] Rate limit - File contains future timestamps - Should handle gracefully
- [ ] Rate limit - File is empty - Should allow restart

**Why Critical**: Rate limiting prevents restart loops. Edge cases could allow excessive restarts or block legitimate recovery.

### 4. State Management Flow (`lib/state.sh`)

#### 4.1 Per-Peer State Abstraction Layer
**Critical Path**: `get_peer_state()` / `set_peer_state()` → File path resolution → Atomic writes

**Missing Tests**:
- [ ] Per-peer state - Unknown key type - Should use default path
- [ ] Per-peer state - Atomic write failure - Should handle gracefully
- [ ] Per-peer state - File path resolution for all key types (failure_count, last_bytes, spi, idle_detected)
- [ ] Per-peer state - IPv6 peer IPs - Sanitization and file paths
- [ ] Per-peer state - Concurrent access (multiple peers) - Should not interfere

**Why Critical**: Per-peer state abstraction is used throughout the codebase. Bugs here could affect all peer monitoring.

#### 4.2 State File Corruption Recovery
**Critical Path**: `validate_state()` → `recover_corrupted_state_file()` → Backup and reset

**Missing Tests**:
- [ ] State file corruption - Backup created before recovery
- [ ] State file corruption - Multiple file types corrupted simultaneously
- [ ] State file corruption - Backup file creation fails - Should still recover
- [ ] State file corruption - Recovery with empty default (file removal)
- [ ] State file corruption - Recovery with non-empty default (file reset)
- [ ] State file corruption - Per-peer files corrupted (failure_count, last_bytes, spi)

**Why Critical**: State file corruption recovery prevents script failures from corrupted files. This is essential for long-running systems.

#### 4.3 Network Partition State Management
**Critical Path**: `get_network_partition_state()` / `set_network_partition_state()`

**Missing Tests**:
- [ ] Network partition state - Get state when file doesn't exist (should return 0)
- [ ] Network partition state - Set state to 0 (healthy)
- [ ] Network partition state - Set state to 1 (partitioned)
- [ ] Network partition state - Invalid value (not 0 or 1) - Should reject
- [ ] Network partition state - File corrupted - Should recover to 0
- [ ] Network partition state - Atomic write ensures consistency

**Why Critical**: Network partition state affects whether VPN checks are performed. Incorrect state could cause missed failures or false positives.

### 5. Configuration Flow (`lib/config.sh`)

#### 5.1 Safe Config Parsing Security
**Critical Path**: `load_config()` → `safe_parse_config_file()` → Variable assignment

**Missing Tests**:
- [ ] Safe parsing - Command injection via backticks - Should reject
- [ ] Safe parsing - Command substitution via `$()` - Should reject
- [ ] Safe parsing - `eval` in config - Should reject
- [ ] Safe parsing - `source` in config - Should reject
- [ ] Safe parsing - Variable not in schema whitelist - Should reject
- [ ] Safe parsing - Multiple dangerous patterns in one line - Should reject
- [ ] Safe parsing - Dangerous pattern in comment - Should allow (comments ignored)
- [ ] Safe parsing - Valid variable assignment with quotes - Should allow
- [ ] Safe parsing - Valid variable assignment without quotes - Should allow

**Why Critical**: Safe config parsing prevents arbitrary code execution. This is a critical security feature.

#### 5.2 Config Schema Default Application
**Critical Path**: `load_config()` → `apply_schema_defaults()` → Set defaults

**Missing Tests**:
- [ ] Schema defaults - All variables get defaults before config file parsing
- [ ] Schema defaults - Config file values override defaults
- [ ] Schema defaults - Required variables without defaults - Should remain empty until validation
- [ ] Schema defaults - Optional variables without defaults - Should remain empty
- [ ] Schema defaults - Default application order (before config parsing)

**Why Critical**: Default application ensures variables have values before they're used. This prevents undefined variable errors.

#### 5.3 Config Validation Order Dependencies
**Critical Path**: `validate_config()` → `validate_config_schema()` → Relative validation

**Missing Tests**:
- [ ] Relative validation - TIER2_THRESHOLD >= TIER1_THRESHOLD (TIER1 validated first)
- [ ] Relative validation - TIER2_THRESHOLD >= TIER1_THRESHOLD (TIER2 validated first)
- [ ] Relative validation - TIER3_THRESHOLD >= TIER2_THRESHOLD (TIER2 validated first)
- [ ] Relative validation - Referenced variable doesn't exist - Should use default
- [ ] Relative validation - Multiple relative validations in sequence

**Why Critical**: Relative validation order dependencies could cause validation failures if order is wrong. This is a known complexity that needs testing.

### 6. Integration Paths

#### 6.1 End-to-End Recovery Scenarios
**Critical Path**: Full monitoring cycle → Failure detection → Recovery → Verification

**Missing Tests**:
- [ ] End-to-end - VPN fails → Tier 1 → Tier 2 → Tier 3 → Recovery → Success
- [ ] End-to-end - VPN fails → Tier 1 → Recovers before Tier 2 → Counter reset
- [ ] End-to-end - Multiple peers fail → Independent recovery per peer
- [ ] End-to-end - Recovery succeeds but VPN still fails on next check
- [ ] End-to-end - Recovery fails → Failure counter continues incrementing
- [ ] End-to-end - Rate limit reached → Recovery blocked → Next check allows recovery

**Why Critical**: End-to-end tests verify the complete system works together. Unit tests don't catch integration issues.

#### 6.2 Error Recovery Paths
**Critical Path**: Error occurs → Error handling → Continue or exit

**Missing Tests**:
- [ ] Error recovery - Config file unreadable → Should exit with error
- [ ] Error recovery - State directory unwritable → Should exit with error
- [ ] Error recovery - Log file unwritable → Should exit with error (early test)
- [ ] Error recovery - Lockfile acquisition fails → Should exit gracefully
- [ ] Error recovery - State file corruption → Should recover and continue
- [ ] Error recovery - Recovery action fails → Should log and continue monitoring

**Why Critical**: Error recovery paths determine system resilience. Poor error handling could cause script failures or silent errors.

## Test Priority Recommendations

### High Priority (Critical Paths)
1. Network partition detection (prevents false failures)
2. Safe config parsing security (prevents code injection)
3. Recovery strategy selection (determines recovery method)
4. State file corruption recovery (prevents script failures)
5. End-to-end recovery scenarios (verifies system integration)

### Medium Priority (Important Paths)
1. SA rekey detection (prevents false failures)
2. Failure type detection (enables targeted recovery)
3. Recovery verification (ensures recovery worked)
4. Rate limiting edge cases (prevents restart loops)
5. Config validation order dependencies (prevents validation bugs)

### Lower Priority (Edge Cases)
1. Idle tunnel detection (nice-to-have feature)
2. Command-line argument validation (early exit paths)
3. Log file initialization edge cases (rare failure scenarios)
4. Per-peer state abstraction edge cases (well-tested but complex)

## Notes

- Many of these paths have partial test coverage but are missing edge cases or integration scenarios
- Some paths (like network partition detection) are critical but have minimal test coverage
- Security-related paths (safe config parsing) should be prioritized even if they seem edge-casey
- Integration tests are particularly important for verifying the system works end-to-end

## Related Documentation

- See `ARCHITECTURE.md` for system architecture and execution flow diagrams
- See `docs/BATS_GUIDE.md` for testing guidelines and best practices
- See existing test files in `tests/` directory for examples of test patterns

