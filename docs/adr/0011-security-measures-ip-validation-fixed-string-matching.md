# ADR-0011: Security Measures (IP Validation, Fixed-String Matching)

## Status
Accepted

## Context
The monitoring script processes user-provided IP addresses and uses them in shell commands:
- Peer IPs come from configuration files
- IPs are used in shell commands (grep, ip xfrm state, etc.)
- Malicious or malformed IPs could lead to:
  - Command injection attacks
  - Regex injection attacks
  - Unexpected command execution
  - System compromise

Without security measures:
- Command injection via malicious IP addresses
- Regex injection via specially crafted IPs
- Arbitrary code execution
- System security vulnerabilities

## Decision
We will implement multiple security measures:
1. **IP Address Validation**: Robust validation function supporting IPv4, IPv6, and IPv4-mapped IPv6
2. **Fixed-String Matching**: Use `grep -F` instead of regex for IP matching
3. **Input Sanitization**: Sanitize IPs before use in filenames and commands
4. **Command Parameterization**: Use proper parameterization in shell commands

## Consequences

### Positive
- **Prevents Injection Attacks**: IP validation prevents command injection
- **Prevents Regex Injection**: Fixed-string matching prevents regex injection
- **Defense in Depth**: Multiple security layers
- **Safe Filenames**: IP sanitization ensures safe filenames
- **Secure by Default**: Security measures applied automatically

### Negative
- **Validation Overhead**: IP validation adds processing time (minimal)
- **Code Complexity**: Additional validation code required

## Implementation Details
- **IP Validation**: `validate_ip_address()` function in `lib/common.sh`
  - Supports IPv4 (dotted decimal)
  - Supports IPv6 (colon-separated hex)
  - Supports IPv4-mapped IPv6
  - Rejects invalid formats
- **Fixed-String Matching**: Uses `grep -F` for IP matching in detection
- **IP Sanitization**: Dots and colons replaced with underscores for filenames
- **Command Parameterization**: IPs passed as quoted parameters in shell commands
- **Validation Points**: IPs validated at configuration load time and before use in commands

## Related ADRs
- ADR-0010: Configuration Schema Validation
- ADR-0004: Per-Peer State Tracking

## References
- ARCHITECTURE.md: "Security Considerations" section
- ARCHITECTURAL_REVIEW.md: "Security" section
- CHANGELOG.md: "Security: Added proper IP address validation" entry
- lib/common.sh: `validate_ip_address()` implementation

