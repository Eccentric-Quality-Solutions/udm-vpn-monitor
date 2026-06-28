# IP XFRM Guide (UDM VPN Monitor)

Reference for using `ip xfrm` on **UniFi Dream Machine (UDM OS 4.3+)** with VPN Monitor: reading SA byte counters, targeted deletion for Tier 2 recovery, and debugging when tunnels misbehave.

**Scope:** Monitoring plus **targeted per-peer deletes** during recovery. UniFi creates SAs and policies via the controller — VPN Monitor does not add them. We **delete specific SAs and policies** for a failing peer; we never **`flush`** (which removes everything).

For generic `ip xfrm` add/update/flush syntax, see [IP_XFRM_IPROUTE2_REFERENCE.md](IP_XFRM_IPROUTE2_REFERENCE.md).

## Table of Contents

1. [Overview](#overview)
2. [Quick Reference](#quick-reference)
3. [Understanding XFRM on UDM](#understanding-xfrm-on-udm)
4. [Monitoring Operations](#monitoring-operations)
5. [Recovery Operations](#recovery-operations)
6. [Output Format Reference](#output-format-reference)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)
9. [References](#references)
10. [Appendix: Topics Not Covered Here](#appendix-topics-not-covered-here)

## Overview

VPN Monitor uses `ip xfrm state` as its **primary detection method** — byte counters in `lifetime current:` tell us whether traffic is actually flowing through a tunnel. At Tier 2 recovery (`ENABLE_XFRM_RECOVERY=1`, default), it **deletes specific SAs** (and optionally policies) for the failing peer only; UniFi recreates them.

**Commands VPN Monitor actually uses:**

| Operation | Command | Notes |
|-----------|---------|-------|
| Read SAs | `ip xfrm state` / `ip -s xfrm state` | Detection, byte counters |
| Read policies | `ip xfrm policy` | Debug / pre-delete inspection |
| Delete SA | `ip xfrm state delete src … dst … proto … spi … [mark … mask …]` | Tier 2 recovery; per-SA, both directions |
| Query SA | `ip xfrm state get …` | Pre-delete diagnostics |
| Delete policy | `ip xfrm policy delete dst <peer> dir <in\|out\|fwd>` | Post-SA cleanup; scoped to failing peer |
| Fallback | `ipsec status` | When xfrm hangs; no byte counters |
| **Never** | `ip xfrm state flush` / `ip xfrm policy flush` | Removes **all** SAs/policies — not used by VPN Monitor |

**UDM-specific constraints:**
- Requires root (SSH as root on UDM)
- `ip` lives in `/usr/sbin` — cron jobs need full paths or `get_command_path()` (see [ISSUES_AND_TECH_DECISIONS.md](../ISSUES_AND_TECH_DECISIONS.md))
- `swanctl` is **not available** on UDM; use `ipsec status` as the daemon-level fallback
- `ip xfrm state` can **hang** under load — always wrap with `timeout` (VPN Monitor uses `XFRM_STATE_TIMEOUT=5`)
- Never run `ip xfrm state flush` or `ip xfrm policy flush` on a production UDM

## Quick Reference

### Most Common Commands

```bash
# List all Security Associations (SAs)
ip xfrm state show

# List all Security Policies (read-only debugging)
ip xfrm policy show

# Monitor XFRM events in real-time
ip xfrm monitor

# UniFi IPsec daemon status (fallback when xfrm hangs or is inconclusive)
ipsec status
```

### Critical Gotchas

1. **Mark format difference:**
   - **In output:** `mark 0x1/0xffffffff` (combined format)
   - **In delete/get commands:** `mark 0x1 mask 0xffffffff` (separate parameters)
   - Recovery deletion fails silently if mark is omitted or wrong format is used

2. **Exit code behavior:**
   - `ip xfrm state` returns exit code 0 even when no SAs exist (empty output)
   - Check for error messages in output to detect actual failures

3. **Byte counters:**
   - On UDM OS 4.3+, `lifetime current:` bytes appear in normal `ip xfrm state show` output
   - VPN Monitor tries `ip -s xfrm state` first, then falls back — defensive, not required for counters

4. **Multi-line output:**
   - `lifetime current:` section spans multiple lines
   - Bytes appear on the line **after** `lifetime current:`
   - Use context lines to capture the complete section — VPN Monitor uses `grep -A 10` (`XFRM_OUTPUT_CONTEXT_LINES=10`) because `lifetime config:` can be long on UDM

5. **Always use timeout:**
   - Wrap xfrm commands: `timeout 5 ip xfrm state show`
   - Exit code 124 = timed out; fall back to `ipsec status`

### Common Patterns

```bash
# Check if SA exists for peer
ip xfrm state show | grep -q "dst 10.0.0.2" && echo "SA exists"

# Extract byte counter (UDM format)
ip xfrm state show | grep -A 10 "lifetime current:" | grep -E "[0-9]+\(bytes\)"

# Delete SA with mark (parse from output first) — Tier 2 recovery
mark_info=$(ip xfrm state show | grep "mark" | head -1)
if [[ "$mark_info" =~ mark[[:space:]]+(0x[0-9a-fA-F]+)/(0x[0-9a-fA-F]+) ]]; then
    ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 \
        mark "${BASH_REMATCH[1]}" mask "${BASH_REMATCH[2]}"
fi

# Delete policy for a peer (recovery cleanup — scoped to one dst + dir)
ip xfrm policy delete dst 10.0.0.2 dir fwd
```

## Understanding XFRM on UDM

XFRM is the Linux kernel IPsec framework. On UDM you interact with two components:

### Security Associations (SAs)

Define **how** traffic is encrypted and carry **byte/packet counters**. VPN Monitor reads these for detection and deletes specific SAs during Tier 2 recovery.

### Security Policies (SPs)

Define **which traffic** goes through IPsec. UniFi creates and manages these. VPN Monitor may **delete policies for the failing peer** after SA deletion (`ip xfrm policy delete dst … dir …`); failures are non-fatal. Useful for debugging template mismatches (`ip xfrm policy show`).

**What VPN Monitor cares about:**
- `lifetime current:` byte counters → is traffic flowing?
- SA existence for peer tunnel endpoints → is Phase 2 up?
- Mark selectors on SAs → required for correct recovery deletion
- `ipsec status` fallback → SA existence only (no byte counters; can show "established" on broken tunnels)

## Monitoring Operations

### Checking VPN Status

**List all SAs:**

```bash
ip xfrm state show
```

**Filter by peer IP (forward SAs):**

```bash
ip xfrm state show | grep -A 20 "dst 10.0.0.2"
```

**Filter by peer IP (reverse SAs):**

```bash
ip xfrm state show | grep -A 20 "^src 10.0.0.2"
```

**Get all SAs for a peer (both directions):**

```bash
# Using fixed-string matching for safety (validated IP)
ip xfrm state show | grep -F "dst 10.0.0.2" -A 20
ip xfrm state show | grep -E "^src 10.0.0.2" -A 20
```

**Check if SA exists (robust method):**

```bash
output=$(timeout 5 ip xfrm state show 2>&1)
if echo "$output" | grep -qE "(error|Error|ERROR|failed|Failed|FAILED)"; then
    echo "Command failed"
elif echo "$output" | grep -q "dst 10.0.0.2"; then
    echo "SA exists"
else
    echo "No SA found"
fi
```

### Monitoring XFRM Events

```bash
ip xfrm monitor
```

Displays real-time SA additions, deletions, updates, and policy changes. Press `Ctrl+C` to stop.

### Checking Policies (Debug Only)

```bash
ip xfrm policy show
ip xfrm policy show | grep -c "^src"
```

### Extract Byte Counter for a Peer

```bash
ip xfrm state show | grep -A 10 "dst 10.0.0.2" | grep "lifetime current:" -A 2 | grep -E "[0-9]+\(bytes\)"
```

Validate the extracted value is numeric before using it:

```bash
bytes=$(ip xfrm state show | grep -A 10 "lifetime current:" | grep -oE "[0-9]+\(bytes\)" | grep -oE "^[0-9]+" | head -1)
[[ -n "$bytes" && "$bytes" =~ ^[0-9]+$ ]] && echo "Byte counter: $bytes"
```

### Rekey and Multiple SAs

SAs are **unidirectional** — a tunnel has separate forward and reverse SAs. During **rekey**, UniFi may briefly install a **new SA alongside the old one** (different SPI, same peer endpoints). You can see two SA blocks for the same `src`/`dst` pair.

**Implications for monitoring and recovery:**
- Check **both** `dst <peer>` and `^src <peer>` when looking for a tunnel
- Do not assume one grep hit is the whole story — count SAs: `ip xfrm state show | grep -c "dst 10.0.0.2"`
- Recovery must **delete every matching SA** (each unique `src`+`dst`+`proto`+`spi`+`mark`), not just the first block
- VPN Monitor tracks SPI in state files and treats SPI change as rekey (resets byte baseline — not a failure)

**Watch for rekey on UDM:**

```bash
# List SPIs for a peer (may show old + new during rekey)
ip xfrm state show | grep -E "(^src|proto.*spi)" | grep -B1 -A0 "10.0.0.2"

# Monitor SA add/delete during rekey
ip xfrm monitor
```

See `detect_sa_rekey()` and `deduplicate_sa_blocks()` in `lib/detection/xfrm_detection.sh`.

### IPv6 Peer Filtering

If tunnel endpoints use IPv6, validate the address before embedding it in grep patterns (prevents injection and format surprises). Prefer fixed-string matching after validation:

```bash
peer_ip="2001:db8::1"
# validate_ip_address "$peer_ip"  # from lib/detection/network_validation.sh
ip xfrm state show | grep -F "dst $peer_ip" -A 10
ip xfrm state show | grep -F "^src $peer_ip" -A 10
```

IPv6 may appear compressed or expanded in output; `-F` matching against the configured peer IP is safest after validation.

## Recovery Operations

Tier 2 xfrm recovery (`lib/recovery/xfrm_recovery.sh`) runs when byte counters stall or the tunnel is stuck. It does **not** flush — it deletes only SAs and policies matching the **failing peer**.

### Recovery flow

1. **Query** — `ip xfrm state` for all SAs matching the peer (forward and reverse; may be multiple SPIs during rekey)
2. **Parse** — extract `src`, `dst`, `proto`, `spi`, and `mark` from **each** SA block
3. **Delete SAs** — `ip xfrm state delete` for each parsed SA (include `mark` / `mask` if present)
4. **Delete policies** — `ip xfrm policy delete dst <external_peer_ip> dir <dir>` for each direction found (`fwd`, `out`, `in`)
5. **Verify** — re-check xfrm state and/or `ipsec status`; UniFi typically recreates SAs within seconds

### Delete a specific SA

Required selectors: `src`, `dst`, `proto`, `spi`. If the SA has a mark, add `mark <value> mask <mask>` (separate parameters — not `mark value/mask`).

```bash
ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100

# With mark (common on UniFi-created SAs):
ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 mark 0x1 mask 0xffffffff
```

**Mark format difference:**
- **In output:** `mark 0x1/0xffffffff`
- **In delete/get commands:** `mark 0x1 mask 0xffffffff`

**Parse mark from output before delete:**

```bash
mark_line=$(ip xfrm state show | grep -A 5 "dst 10.0.0.2" | grep "mark" | head -1)
if [[ "$mark_line" =~ mark[[:space:]]+(0x[0-9a-fA-F]+)/(0x[0-9a-fA-F]+) ]]; then
    mark_value="${BASH_REMATCH[1]}"
    mark_mask="${BASH_REMATCH[2]}"
    ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 \
        mark "$mark_value" mask "$mark_mask"
fi
```

**Pre-delete diagnostic:**

```bash
ip xfrm state get src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 mark 0x1 mask 0xffffffff
```

Deletion fails silently if mark is omitted or wrong format is used.

### Delete policies for a peer

Scoped to one external peer IP and one direction. VPN Monitor parses directions from existing policy output, or tries `fwd`, `out`, `in` if none are found. Policy delete failures are **non-fatal**.

```bash
ip xfrm policy delete dst 10.0.0.2 dir fwd
ip xfrm policy delete dst 10.0.0.2 dir out
ip xfrm policy delete dst 10.0.0.2 dir in
```

Policies are recreated when UniFi re-establishes the tunnel.

### Delete vs flush

| Command | Scope | VPN Monitor |
|---------|-------|-------------|
| `ip xfrm state delete …` | One SA (by selectors) | **Yes** — Tier 2 recovery |
| `ip xfrm policy delete dst … dir …` | One policy | **Yes** — post-SA cleanup |
| `ip xfrm state flush` | **All** SAs | **No** — breaks every tunnel |
| `ip xfrm policy flush` | **All** policies | **No** — breaks every tunnel |

Tier 3 fallback uses `ipsec restart` (global), not xfrm flush. Tier 2 `ipsec reload` is disabled by default (`ENABLE_TIER2_IPSEC_RELOAD=0`) because it affects all connections.

## Output Format Reference

### State (SA) Output Format

**UDM OS 4.3+ format (`ip xfrm state show`):**

```
src 10.0.0.1 dst 10.0.0.2
    proto esp spi 0x00000100 reqid 1 mode tunnel
    replay-window 0
    mark 0x1/0xffffffff
    auth-trunc hmac(sha256) 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef 96
    enc cbc(aes) 0xabcdef1234567890abcdef1234567890
    anti-replay context: seq 0x0, oseq 0x0, bitmap 0x00000000
    lifetime config:
       limit: soft (INF)(bytes), hard (INF)(bytes)
       limit: soft (INF)(packets), hard (INF)(packets)
       add 2026-01-03 12:19:25 use 2026-01-03 12:19:34
    lifetime current:
      39492(bytes), 609(packets)
      add 2026-01-03 12:19:25 use 2026-01-03 12:19:34
    stats:
      replay-window 0 replay 0 failed 0
```

**Key fields for monitoring:**
- `src` / `dst` - Tunnel endpoint IPs (match against peer)
- `proto` / `spi` - Required for SA deletion during recovery
- `mark` - Required for delete/get if present (see [Recovery Operations](#recovery-operations))
- `lifetime current:` - **Byte/packet counters** (primary detection signal)
- `stats:` - Per-SA replay and integrity failure counts

### Policy Output Format

```
src 192.168.1.0/24 dst 192.168.2.0/24
    dir out priority 0 ptype main
    tmpl src 10.0.0.1 dst 10.0.0.2
        proto esp reqid 1 mode tunnel
    mark 0x1/0xffffffff
```

Useful when debugging policy/template/reqid mismatches, or before policy delete during recovery.

### Parsing Tips

**Extract byte counter (UDM format):**

```
lifetime current:
  39492(bytes), 609(packets)
  add 2026-01-03 12:19:25 use 2026-01-03 12:19:34
```

```bash
ip xfrm state show | grep -A 5 "lifetime current:" | grep -E "[0-9]+\(bytes\)"
```

Use `-A 10` when filtering by peer first — matches VPN Monitor's `XFRM_OUTPUT_CONTEXT_LINES` default.

**Extract SPI:**

```bash
ip xfrm state show | grep -i "spi" | head -1 | sed -n 's/.*[[:space:]]spi[[:space:]]*\(0x[0-9a-fA-F]\+\|[0-9]\+\)[[:space:]].*/\1/p'
```

**Extract mark (if present):**

```bash
ip xfrm state show | grep "mark" | head -1 | sed -n 's/.*mark[[:space:]]*\(0x[0-9a-fA-F]\+\)\/\(0x[0-9a-fA-F]\+\)/\1 \2/p'
```

## Troubleshooting

### Common Issues

**1. SA deletion fails silently**

Check for a mark selector. Include `mark <value> mask <mask>` as separate parameters (see [Recovery Operations](#recovery-operations)).

**2. No SAs found but VPN should be active**

```bash
ip xfrm state show
ip xfrm policy show
ipsec status
```

Possible causes: IKE still negotiating, wrong tunnel endpoint IP, mark/reqid mismatch.

**3. Byte counters not incrementing**

```bash
timeout 5 ip xfrm state show | grep -A 5 "lifetime current:"
watch -n 1 'timeout 5 ip xfrm state show | grep -A 5 "lifetime current:"'
```

Possible causes: no traffic, policy mismatch, SA not in use, SA expired.

**4. Policy not matching traffic**

```bash
ip xfrm policy show
ip xfrm policy show | grep -A 10 "dst 192.168.2.0/24"
ip xfrm policy show | grep "reqid"
ip xfrm state show | grep "reqid"
```

**5. xfrm commands hanging or timing out**

On UDM, `ip xfrm state` can block 12–13+ seconds under netlink/XFRM lock contention.

**Solution:** Always use timeout (VPN Monitor: `XFRM_STATE_TIMEOUT=5`):

```bash
if command -v timeout >/dev/null 2>&1; then
    output=$(timeout 5 ip xfrm state show 2>&1)
    exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
        echo "WARNING: ip xfrm state timed out — fall back to ipsec status"
    fi
fi
```

**When xfrm is unavailable:**
- Detection falls back to `ipsec status` (confirms SA existence only, not traffic flow)
- Byte counter tracking is lost (cannot detect idle/stuck connections)
- Do **not** trust `ipsec status` when xfrm reports an SA exists but bytes/ping indicate failure (see CHANGELOG v0.8.0)

**Investigation when timeouts occur:**

```bash
uptime
dmesg | grep -i "soft lockup\|xfrm\|netlink"
cat /proc/net/xfrm_stat
ip xfrm monitor
```

**Timeout frequency (operational guidance):**
- **Normal:** 0–1 timeouts per hour under steady load
- **Investigate:** >5 timeouts per hour — check CPU load, concurrent IPsec activity, kernel messages
- **Tune:** If timeouts occur but manual runs complete in 6–10 seconds, consider raising `XFRM_STATE_TIMEOUT` to 8–10 seconds in config (default is 5)
- Log correlation: frequent timeouts often coincide with ping failures — both share kernel/network stack pressure

### Diagnostic Commands

**Check XFRM drop/error counters:**

```bash
cat /proc/net/xfrm_stat
```

These are **kernel packet drop and error counters** (not lookup statistics). Useful counters when debugging "tunnel up but traffic dead":

| Counter | Meaning |
|---------|---------|
| `XfrmInNoStates` | Inbound ESP/AH packet, no matching SA (wrong SPI, address, or protocol) |
| `XfrmInTmplMismatch` | SA decoded OK but policy template does not match |
| `XfrmInStateProtoError` | Authentication or encryption checksum failure |
| `XfrmOutNoStates` | Outbound packet, no matching SA for encryption |
| `XfrmOutStateSeqError` | Outbound sequence number overflow |

Rising counts indicate packets being **dropped** — configuration mismatch, expired SA, or key problems.

**Check system logs:**

```bash
dmesg | grep xfrm
```

**Verify command availability (especially from cron):**

```bash
which ip
/usr/sbin/ip -V
```

## Best Practices

### 1. Always Wrap with Timeout

```bash
timeout 5 ip xfrm state show
```

### 2. Parse Output with Context Lines

On UDM, bytes appear on the line after `lifetime current:`. Use enough context to skip past `lifetime config:`:

```bash
ip xfrm state show | grep -A 10 "lifetime current:" | grep -E "[0-9]+\(bytes\)" | head -1
```

When filtering by peer first, use `-A 10` (VPN Monitor default) rather than `-A 5`.

### 3. Include Mark on Delete

Parse mark from output; use separate `mark` and `mask` parameters. See [Recovery Operations](#recovery-operations).

### 4. Check Both Directions and All SPIs

SAs are unidirectional. Check both `dst <peer>` and `^src <peer>`. During rekey, delete **every** SA block for the peer — see [Rekey and Multiple SAs](#rekey-and-multiple-sas).

### 5. Validate IPv6 Before Grep

Use `grep -F` with a validated IPv6 address; see [IPv6 Peer Filtering](#ipv6-peer-filtering).

### 6. Delete vs Flush

Use **targeted** `state delete` and `policy delete` for one peer during recovery. Never `flush` — that removes all tunnels. See [Delete vs flush](#delete-vs-flush).

### 7. Use `ipsec status` as Fallback Only

On UDM: `ipsec status` (not `swanctl`). It confirms SA existence but not traffic flow. VPN Monitor skips this fallback when xfrm shows an SA but bytes/ping indicate failure.

### 8. Use `ip xfrm monitor` for Lifecycle Debugging

Watch SA add/delete timing during recovery or rekey events.

## References

### Project Documentation

- [IP_XFRM_IPROUTE2_REFERENCE.md](IP_XFRM_IPROUTE2_REFERENCE.md) — Generic iproute2 syntax (add/update/flush)
- [IPSEC_GUIDE.md](IPSEC_GUIDE.md) — UDM IPsec overview
- [ISSUES_AND_TECH_DECISIONS.md](../ISSUES_AND_TECH_DECISIONS.md) — UDM platform constraints

### Official Documentation

- **ip-xfrm man page:** `man ip-xfrm` or [man7.org](https://man7.org/linux/man-pages/man8/ip-xfrm.8.html)
- **Linux Kernel XFRM proc documentation:** [docs.kernel.org](https://docs.kernel.org/networking/xfrm/xfrm_proc.html)

### Related UDM Commands

- `ipsec status` — UniFi IPsec daemon status (fallback detection)
- `cat /proc/net/xfrm_stat` — Kernel XFRM drop/error counters

## Appendix: Topics Not Covered Here

Items removed or shortened when this guide was split for UDM VPN Monitor scope. Most write operations live in [IP_XFRM_IPROUTE2_REFERENCE.md](IP_XFRM_IPROUTE2_REFERENCE.md). Use this index if you need to look something up later.

### Moved to iproute2 reference

| Topic | Brief description |
|-------|-------------------|
| General `ip` syntax | `ip [OPTIONS] OBJECT {COMMAND}`; non-xfrm objects (`link`, `addr`, `route`, `rule`, `tunnel`) |
| `ip -4` / `ip -6` / `-f family` | Restrict xfrm queries to IPv4 or IPv6 |
| `ip xfrm policy add` / `update` | Create or modify security policies manually |
| `ip xfrm policy deleteall` / `count` / `set` / `setdefault` / `getdefault` | Bulk policy ops and SPD hash-table tuning |
| `ip xfrm policy flush` | Remove **all** policies (dangerous on UDM) |
| `ip xfrm state add` / `update` / `allocspi` | Create or modify SAs manually; SPI allocation |
| `ip xfrm state deleteall` / `count` | Bulk delete or count SAs |
| `ip xfrm state flush` | Remove **all** SAs (dangerous on UDM) |
| Crypto on `state add` | `auth`, `enc`, `auth-trunc`, `aead` examples (AES-CBC, GCM, HMAC-SHA256, etc.) |
| `limit byte-soft` / `time-soft` / … | SA lifetime limits on add (not `lifetime soft bytes`) |
| `replay-window` on add | Configure anti-replay window size when creating an SA |
| Policy `priority` / template `reqid` on add | Policy ordering and SA template matching at config time |
| Mark on `state add` | `mark 0x1/0xffffffff` when creating an SA (vs delete/get separate params) |
| `action allow` / `block` | Policy actions (`ipsec` is not a valid action — use `tmpl` for IPsec) |

### Abbreviated or omitted (not UDM daily ops)

| Topic | Brief description | Where to look |
|-------|-------------------|---------------|
| Elaborate `-s` fallback script | Full try/fallback loop with output validation for `ip -s xfrm state` | VPN Monitor uses this in `execute_xfrm_state_command()` — see `lib/detection/xfrm_detection.sh` |
| Awk one-liner for all SA selectors | Parse `src`, `dst`, `proto`, `spi`, `mark` from full dump in one pass | `parse_xfrm_sas()` / state machine in `lib/recovery/xfrm_recovery.sh`; examples in [CODE_REVIEW_LESSONS_LEARNED.md](CODE_REVIEW_LESSONS_LEARNED.md) |
| Awk dedupe by `src+dst+spi` | Collapse duplicate SA blocks when combining forward/reverse grep | `deduplicate_sa_blocks()` in `lib/detection/xfrm_detection.sh` |
| `-s` flag semantics | Global `ip -s`; on `policy count` shows hash buckets; byte counters appear in normal `state show` on UDM | [ip-xfrm(8)](https://man7.org/linux/man-pages/man8/ip-xfrm.8.html) |
| `ip xfrm policy show -d` | Global `ip -d` details flag on policy listing | `man ip`; rarely needed on UDM |
| `ip xfrm monitor` filters | Limit events: `acquire`, `expire`, `SA`, `policy`, `aevent`, `report` | `man ip-xfrm` |
| Extended timeout diagnostics | `top`, `vmstat`, `ss -s`, `netstat -s`, `journalctl -k` during xfrm hangs | Generic Linux perf/network debugging |
| StrongSwan / Libreswan CLI | `strongswan statusall`, `swanctl` | Not on UDM; use `ipsec status` |
| UniFi vs generic daemon notes | Manual delete triggers IKE rekey; daemons recreate SAs | Covered briefly in [Recovery Operations](#recovery-operations); UniFi-specific |
| Policy tie-breaking | Same priority → newest policy wins | [IP_XFRM_IPROUTE2_REFERENCE.md](IP_XFRM_IPROUTE2_REFERENCE.md) (Policy Priorities) |
| Output field glossary (full) | `auth-trunc`, `ptype`, `sel`, `output-mark`, `level required`/`use` on templates | [IP_XFRM_IPROUTE2_REFERENCE.md](IP_XFRM_IPROUTE2_REFERENCE.md); [Cilium XFRM guide](https://docs.cilium.io/en/stable/reference-guides/xfrm/) for field-by-field output |
| RFC / iproute2 wiki links | RFC 4301/4302/4303, IKEv2 (RFC 7296), Linux Foundation iproute2 docs | [IP_XFRM_IPROUTE2_REFERENCE.md](IP_XFRM_IPROUTE2_REFERENCE.md) References |

---

**Last Updated:** 2026-06-28  
**Tested On:** UDM OS 4.3+  
**Scope:** UDM VPN Monitor — monitoring, targeted SA/policy delete for recovery (not flush)
