# IP XFRM iproute2 Reference

Generic `ip xfrm` command reference for the Linux `iproute2` suite. This documents kernel-level IPsec policy and SA management syntax.

**UDM operators:** UniFi Dream Machine manages IPsec via the UniFi controller — you normally do not run these commands on a UDM. For monitoring, parsing, and recovery on UDM OS 4.3+, see [IP_XFRM_GUIDE.md](IP_XFRM_GUIDE.md).

## Table of Contents

1. [Overview](#overview)
2. [The IP Command](#the-ip-command)
3. [Understanding XFRM](#understanding-xfrm)
4. [Security Policies (SPs)](#security-policies-sps)
5. [Security Associations (SAs)](#security-associations-sas)
6. [Advanced Features](#advanced-features)
7. [References](#references)

## Overview

The `ip` command is part of the `iproute2` suite. The `xfrm` (transform) subcommand manages IPsec configurations through the Linux kernel's XFRM framework.

**Key Points:**
- Requires root privileges to execute
- Part of the `iproute2` package (standard on UDM OS 4.3+)
- Directly interfaces with the Linux kernel's XFRM subsystem
- Used by IPsec daemons under the hood
- Provides low-level control over IPsec policies and states

On UDM, `show` and `list` are aliases (iproute2 accepts both).

## The IP Command

### General Syntax

```bash
ip [ OPTIONS ] OBJECT { COMMAND | help }
```

**Common Objects:**
- `link` - Network interfaces
- `addr` - IP addresses
- `route` - Routing tables
- `xfrm` - IPsec transform framework (our focus)
- `tunnel` - Tunnels
- `rule` - Routing rules

**Common Options:**
- `-s`, `-stats`, `-statistics` - Show statistics (on some subcommands, e.g. `ip xfrm policy count`)
- `-d`, `-details` - Show detailed information
- `-f`, `-family` - Specify address family (inet, inet6)
- `-4` - IPv4 only
- `-6` - IPv6 only

### Getting Help

```bash
ip help                    # General help
ip xfrm help              # XFRM-specific help
ip xfrm state help        # State command help
ip xfrm policy help       # Policy command help
```

## Understanding XFRM

XFRM (Transform) is a framework within the Linux kernel that handles packet transformation, primarily for IPsec operations. It manages two critical components:

### Security Policies (SPs)

Security Policies define **which traffic** should be protected by IPsec. They specify:
- Source and destination addresses/networks
- Protocols and ports
- Direction (inbound, outbound, forward)
- Action on match (`allow` or `block`)
- Template matching for SA selection (IPsec encryption is applied via `tmpl`, not a separate action)

### Security Associations (SAs)

Security Associations define **how** traffic is secured. They specify:
- Cryptographic algorithms (encryption, authentication)
- Keys for encryption and authentication
- Security Parameter Index (SPI) - unique identifier
- Mode (transport or tunnel)
- Lifetime and byte/packet counters
- Optional selectors (mark, reqid, etc.)

**Relationship:**
- Policies select traffic that needs protection
- SAs provide the cryptographic parameters for that protection
- Multiple policies can reference the same SA
- SAs are typically established via IKE (Internet Key Exchange) protocols

## Security Policies (SPs)

### Basic Syntax

```bash
ip xfrm policy { add | update | delete | get | flush | list | show | deleteall | count | set | setdefault | getdefault } [ OPTIONS ]
```

### Adding a Policy

```bash
ip xfrm policy add src <SRC> dst <DST> dir <DIR> [ OPTIONS ]
```

**Required Parameters:**
- `src <SRC>` - Source address/network (e.g., `192.168.1.0/24` or `192.168.1.1`)
- `dst <DST>` - Destination address/network
- `dir <DIR>` - Direction: `in`, `out`, or `fwd`

**Common Options:**
- `tmpl src <TUNNEL_SRC> dst <TUNNEL_DST> proto <PROTO> mode <MODE>` - Template for SA matching
  - `proto esp` or `proto ah` - Protocol (ESP or AH)
  - `mode tunnel` or `mode transport` - IPsec mode
- `priority <PRIORITY>` - Policy priority (lower number = higher priority; if equal, newest policy wins)
- `action <ACTION>` - Action: `allow` (default) or `block`
- `sel <SELECTOR>` - Additional selectors (protocol, ports, etc.)

**Example - Outbound Policy:**

```bash
ip xfrm policy add \
    src 192.168.1.0/24 \
    dst 192.168.2.0/24 \
    dir out \
    tmpl src 10.0.0.1 dst 10.0.0.2 proto esp mode tunnel
```

**Example - Inbound Policy:**

```bash
ip xfrm policy add \
    src 192.168.2.0/24 \
    dst 192.168.1.0/24 \
    dir in \
    tmpl src 10.0.0.2 dst 10.0.0.1 proto esp mode tunnel
```

### Listing Policies

```bash
ip xfrm policy list        # List all policies
ip xfrm policy show        # Same as list
ip xfrm policy show src 192.168.1.0/24  # Filter by source
ip xfrm policy show dst 192.168.2.0/24  # Filter by destination
```

### Deleting a Policy

```bash
ip xfrm policy delete src <SRC> dst <DST> dir <DIR>
# Or simplified form (when matching by destination and direction only):
ip xfrm policy delete dst <DST> dir <DIR>
```

**Examples:**

```bash
# Full form (matches specific source and destination)
ip xfrm policy delete src 192.168.1.0/24 dst 192.168.2.0/24 dir out

# Simplified form (matches any source for the destination and direction)
ip xfrm policy delete dst 192.168.2.0/24 dir out
```

**Note:** The simplified form (`dst` and `dir` only) is useful when you want to delete all policies matching a destination and direction, regardless of source. The full form is more specific and only deletes policies matching all specified selectors.

### Flushing Policies

```bash
ip xfrm policy flush       # Delete all policies
```

**Warning:** This removes ALL policies. Use with extreme caution in production.

## Security Associations (SAs)

### Basic Syntax

```bash
ip xfrm state { add | update | delete | get | flush | list | show | deleteall | count | allocspi } [ OPTIONS ]
```

### Adding a State (SA)

```bash
ip xfrm state add src <SRC> dst <DST> proto <PROTO> spi <SPI> [ OPTIONS ]
```

**Required Parameters:**
- `src <SRC>` - Source IP address
- `dst <DST>` - Destination IP address
- `proto <PROTO>` - Protocol: `esp` or `ah`
- `spi <SPI>` - Security Parameter Index (hex format: `0x12345678` or decimal)

**Common Options:**
- `mode <MODE>` - `tunnel` or `transport`
- `auth <ALGO> <KEY>` - Authentication algorithm and key
  - Examples: `hmac(sha1)`, `hmac(sha256)`, `hmac(sha512)`
- `enc <ALGO> <KEY>` - Encryption algorithm and key
  - Examples: `cbc(aes)`, `ctr(aes)`, `gcm(aes)`
- `aead <ALGO> <KEY> <ICV_LEN>` - Authenticated encryption (combined auth+enc)
  - Example: `aead 'rfc4106(gcm(aes))' <KEY> 128`
- `mark <VALUE>/<MASK>` or `mark <VALUE> mask <MASK>` - Mark selector (for policy matching)
- `reqid <ID>` - Request ID (links SA to policy template)
- `replay-window <SIZE>` - Anti-replay window size
- `limit <TYPE> <VALUE>` - Lifetime limits (repeat `limit` for each type)
  - Types: `byte-soft`, `byte-hard`, `packet-soft`, `packet-hard`, `time-soft`, `time-hard`, `time-use-soft`, `time-use-hard`

**Example - ESP with Separate Auth and Enc:**

```bash
ip xfrm state add \
    src 10.0.0.1 \
    dst 10.0.0.2 \
    proto esp \
    spi 0x100 \
    mode tunnel \
    auth hmac(sha256) 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef \
    enc cbc(aes) 0xabcdef1234567890abcdef1234567890
```

**Example - ESP with AEAD (GCM):**

```bash
ip xfrm state add \
    src 10.0.0.1 \
    dst 10.0.0.2 \
    proto esp \
    spi 0x100 \
    mode tunnel \
    aead 'rfc4106(gcm(aes))' 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef 128
```

**Example - With Mark Selector:**

```bash
ip xfrm state add \
    src 10.0.0.1 \
    dst 10.0.0.2 \
    proto esp \
    spi 0x100 \
    mode tunnel \
    mark 0x1/0xffffffff \
    auth hmac(sha256) <KEY> \
    enc cbc(aes) <KEY>
```

### Listing States

```bash
ip xfrm state list         # List all SAs
ip xfrm state show         # Same as list
ip xfrm state show src 10.0.0.1  # Filter by source
ip xfrm state show dst 10.0.0.2  # Filter by destination
```

**Exit Code Behavior:** `ip xfrm state` returns exit code 0 even when no SAs exist (just empty output). To detect actual command errors, check for error messages in the output:

```bash
output=$(ip xfrm state 2>&1)
if echo "$output" | grep -qE "(error|Error|ERROR|failed|Failed|FAILED|No such|Permission denied)"; then
    echo "Command failed"
fi
```

### Getting a Specific State

```bash
ip xfrm state get src <SRC> dst <DST> proto <PROTO> spi <SPI> [ mark <VALUE> mask <MASK> ]
```

**Example:**

```bash
ip xfrm state get src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100
```

**Note:** If the SA has a mark selector, you must include it in the get command using **separate `mark` and `mask` parameters**:

```bash
ip xfrm state get src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 mark 0x1 mask 0xffffffff
```

**Important:** The mark format in `ip xfrm` output shows as `mark 0x<value>/0x<mask>`, but when using it in commands (`get`, `delete`), you must use separate parameters: `mark <value> mask <mask>`, not `mark <value>/<mask>`.

### Deleting a State

```bash
ip xfrm state delete src <SRC> dst <DST> proto <PROTO> spi <SPI> [ mark <VALUE> mask <MASK> ]
```

**Example:**

```bash
ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100
```

**Important:** If the SA was created with a mark selector, you **must** include it in the delete command using **separate `mark` and `mask` parameters**, otherwise deletion will fail silently or return an error:

```bash
# Correct format: separate mark and mask parameters
ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 mark 0x1 mask 0xffffffff

# ❌ WRONG: Combined format will fail
ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 mark 0x1/0xffffffff
```

### Flushing States

```bash
ip xfrm state flush        # Delete all SAs
```

**Warning:** This removes ALL SAs. This will break all active IPsec connections. Use with extreme caution.

## Advanced Features

### Mark Selectors

Marks are 32-bit values used to tag packets and SAs for policy matching.

**Adding mark to SA:**

```bash
ip xfrm state add \
    src 10.0.0.1 dst 10.0.0.2 \
    proto esp spi 0x100 \
    mark 0x1/0xffffffff \
    mode tunnel \
    auth hmac(sha256) <KEY> \
    enc cbc(aes) <KEY>
```

**Format difference for get/delete:**
- **In output:** `mark 0x1/0xffffffff` (combined format)
- **In commands:** `mark 0x1 mask 0xffffffff` (separate parameters)

### Request IDs (reqid)

Request IDs link policies to SAs. When a policy template specifies a `reqid`, only SAs with matching `reqid` values will be used.

**Setting reqid on SA:**

```bash
ip xfrm state add \
    src 10.0.0.1 dst 10.0.0.2 \
    proto esp spi 0x100 \
    reqid 1 \
    mode tunnel \
    auth hmac(sha256) <KEY> \
    enc cbc(aes) <KEY>
```

**Matching policy template:**

```bash
ip xfrm policy add \
    src 192.168.1.0/24 dst 192.168.2.0/24 \
    dir out \
    tmpl src 10.0.0.1 dst 10.0.0.2 proto esp reqid 1 mode tunnel
```

### Policy Priorities

Policies are evaluated in priority order (lower number = higher priority). When multiple policies match at the same priority, the newest policy wins.

**Setting priority:**

```bash
ip xfrm policy add \
    src 192.168.1.0/24 dst 192.168.2.0/24 \
    dir out \
    priority 100 \
    tmpl src 10.0.0.1 dst 10.0.0.2 proto esp mode tunnel
```

### Lifetime Management

SAs have configurable lifetimes based on bytes, packets, or time.

**Setting byte limit:**

```bash
ip xfrm state add \
    src 10.0.0.1 dst 10.0.0.2 \
    proto esp spi 0x100 \
    mode tunnel \
    limit byte-soft 1000000 \
    limit byte-hard 2000000 \
    auth hmac(sha256) <KEY> \
    enc cbc(aes) <KEY>
```

**Setting time limit:**

```bash
ip xfrm state add \
    src 10.0.0.1 dst 10.0.0.2 \
    proto esp spi 0x100 \
    mode tunnel \
    limit time-soft 3600 \
    limit time-hard 7200 \
    auth hmac(sha256) <KEY> \
    enc cbc(aes) <KEY>
```

When soft limits are reached, the SA is marked for rekeying. When hard limits are reached, the SA expires and is removed.

### Anti-Replay Protection

Anti-replay protection prevents replay attacks by tracking sequence numbers.

**Setting replay window:**

```bash
ip xfrm state add \
    src 10.0.0.1 dst 10.0.0.2 \
    proto esp spi 0x100 \
    mode tunnel \
    replay-window 32 \
    auth hmac(sha256) <KEY> \
    enc cbc(aes) <KEY>
```

The replay window size determines how many out-of-order packets are accepted.

## References

### Official Documentation

- **ip-xfrm man page:** `man ip-xfrm` or [man7.org](https://man7.org/linux/man-pages/man8/ip-xfrm.8.html)
- **iproute2 documentation:** [wiki.linuxfoundation.org](https://wiki.linuxfoundation.org/networking/iproute2)
- **Linux Kernel XFRM proc documentation:** [docs.kernel.org](https://docs.kernel.org/networking/xfrm/xfrm_proc.html)

### Additional Resources

- **IPsec Protocol:** RFC 4301 (Security Architecture), RFC 4303 (ESP), RFC 4302 (AH)
- **IKE Protocol:** RFC 7296 (IKEv2)

---

**Last Updated:** 2026-06-28  
**Scope:** Generic Linux iproute2 syntax (not UDM-specific operations)
