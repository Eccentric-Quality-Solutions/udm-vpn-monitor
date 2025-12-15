# Future Enhancement Recommendations

This document outlines potential improvements and enhancements for the UDM VPN Monitor project. These are suggestions for future development, prioritized by impact and complexity.

## High Priority Enhancements

### 1. Per-Peer Failure Tracking
**Current State**: Failure counter is shared across all peers  
**Enhancement**: Track failures independently per peer IP  
**Benefits**:
- More accurate failure detection for multi-peer setups
- Prevents one failing peer from affecting others
- Better recovery targeting

**Implementation Notes**:
- Create per-peer failure counter files: `failure_counter_<peer_ip>`
- Modify `increment_failure()` and `get_failure_count()` to accept peer IP
- Update tier logic to check per-peer counters

### 2. Notification System
**Current State**: Only logs to file  
**Enhancement**: Add notification mechanisms (email, webhook, syslog)  
**Benefits**:
- Immediate alerts for VPN failures
- Integration with monitoring systems
- Better visibility for operators

**Implementation Notes**:
- Add `NOTIFICATION_METHOD` config option (email/webhook/syslog/none)
- Support SMTP for email notifications
- Support HTTP POST for webhooks (Slack, Discord, PagerDuty)
- Support syslog forwarding
- Rate limit notifications to prevent spam

### 3. Health Check Endpoint
**Current State**: No external status interface  
**Enhancement**: Simple HTTP endpoint for status checks  
**Benefits**:
- Integration with external monitoring (Prometheus, Nagios)
- Health check endpoints for load balancers
- REST API for status queries

**Implementation Notes**:
- Add optional HTTP server (Python/Node.js simple server)
- Endpoints: `/health`, `/status`, `/metrics`
- Return JSON with current status
- Lightweight implementation (netcat-based or simple script)

### 4. Metrics Export
**Current State**: Logs only  
**Enhancement**: Export metrics in Prometheus/InfluxDB format  
**Benefits**:
- Integration with Grafana dashboards
- Historical trend analysis
- Better visualization

**Implementation Notes**:
- Export metrics file: `vpn-monitor.metrics`
- Format: Prometheus text format or InfluxDB line protocol
- Metrics: failure counts, restart counts, ping latency, byte counters
- Optional HTTP endpoint for Prometheus scraping

## Medium Priority Enhancements

### 5. Configurable Recovery Actions
**Current State**: Fixed tiered recovery (log → cleanup → restart)  
**Enhancement**: Allow custom recovery actions per tier  
**Benefits**:
- Flexibility for different network setups
- Custom scripts for specific recovery needs
- Integration with other tools

**Implementation Notes**:
- Add `TIER1_ACTION`, `TIER2_ACTION`, `TIER3_ACTION` config options
- Support: "log", "cleanup", "restart", "script:<path>"
- Allow custom script execution with parameters
- Maintain safety checks (rate limiting, cooldown)

### 6. Advanced Ping Options
**Current State**: Basic ping with count/timeout  
**Enhancement**: More sophisticated connectivity tests  
**Benefits**:
- Better detection of partial failures
- Support for TCP/HTTP checks
- More reliable connectivity verification

**Implementation Notes**:
- Add `PING_TYPE` option (icmp/tcp/http)
- TCP connectivity check: `nc -zv <ip> <port>`
- HTTP check: `curl -f <url>`
- Configurable ports/URLs per peer
- Multiple check types (OR/AND logic)

### 7. Historical Logging and Analysis
**Current State**: Single log file with rotation  
**Enhancement**: Structured logging and analysis tools  
**Benefits**:
- Better troubleshooting
- Pattern detection
- Performance analysis

**Implementation Notes**:
- JSON log format option
- Log rotation with compression
- Analysis script: `analyze-logs.sh`
- Generate reports: failure frequency, recovery success rate
- Export to CSV for spreadsheet analysis

### 8. Per-Tunnel Recovery
**Current State**: 
- Tier 2 (surgical cleanup) attempts per-peer SA deletion but then does `swanctl --reload` (affects all tunnels)
- Tier 3 (full restart) does `ipsec restart` or `swanctl --reload` (affects all tunnels)
- Partial per-peer targeting exists but not true per-tunnel recovery

**Enhancement**: Restart individual tunnels when possible using connection-specific commands  
**Benefits**:
- Less disruption
- More targeted recovery
- Better for multi-tunnel setups
- True per-tunnel isolation

**Implementation Notes**:
- Use `swanctl --reload-conn <connection-name>` instead of `swanctl --reload`
- Map peer IPs to connection names (requires configuration)
- Fallback to full restart if per-tunnel fails
- Configuration: `CONNECTION_NAME_<peer_ip>` mapping
- Update Tier 2 to use `--reload-conn` instead of `--reload`
- Optionally update Tier 3 to attempt per-tunnel restart before full restart

### 9. Watchdog Mode
**Current State**: Cron-based execution  
**Enhancement**: Optional daemon mode with watchdog  
**Benefits**:
- More frequent checks
- Self-monitoring
- Automatic recovery from script failures

**Implementation Notes**:
- Add `MODE` config option (cron/daemon)
- Daemon mode: run in background, check every minute
- Watchdog: monitor script health, restart if hung
- Systemd service file for daemon mode
- Maintain cron mode as default (more reliable on UDM)

### 10. Configuration Validation
**Current State**: Basic validation  
**Enhancement**: Comprehensive config validation  
**Benefits**:
- Catch errors early
- Better error messages
- Prevent misconfiguration

**Implementation Notes**:
- Validate all config values on startup
- Check IP format, numeric ranges, file paths
- Validate thresholds make sense (Tier1 < Tier2 < Tier3)
- Test connectivity to ping targets
- Provide clear error messages

## Low Priority / Nice-to-Have Enhancements

### 11. Web UI Dashboard
**Current State**: CLI/logs only  
**Enhancement**: Simple web interface  
**Benefits**:
- Visual status display
- Configuration management
- Historical graphs

**Implementation Notes**:
- Lightweight web server (Python Flask or Node.js)
- Simple HTML/CSS/JavaScript dashboard
- Real-time status updates
- Configuration editor
- Optional: authentication

### 12. SNMP Support
**Current State**: No SNMP  
**Enhancement**: SNMP MIB for monitoring  
**Benefits**:
- Integration with SNMP monitoring tools
- Standard protocol support
- Enterprise monitoring compatibility

**Implementation Notes**:
- Define custom MIB
- Export via `snmpd` extension
- OIDs for: peer status, failure counts, restart counts
- Read-only access

### 13. Multi-Instance Support
**Current State**: Single instance per UDM  
**Enhancement**: Support multiple monitoring instances  
**Benefits**:
- Different configs for different VPN types
- Separate monitoring for different networks
- Testing without affecting production

**Implementation Notes**:
- Instance identifier in config
- Separate state directories
- Separate lockfiles
- Configurable instance names

### 14. Automated Testing
**Current State**: Manual testing  
**Enhancement**: Automated test suite  
**Benefits**:
- Regression prevention
- Easier development
- Better code quality

**Implementation Notes**:
- Unit tests for functions (bash-test or bats)
- Integration tests with mock VPN states
- CI/CD pipeline
- Test coverage reporting

### 15. Documentation Improvements
**Current State**: README and inline comments  
**Enhancement**: Comprehensive documentation  
**Benefits**:
- Easier onboarding
- Better troubleshooting guides
- Architecture documentation

**Implementation Notes**:
- Architecture diagram
- Detailed troubleshooting guide
- Configuration examples for common scenarios
- API documentation (if HTTP endpoint added)
- Video tutorials

### 16. IPv6 Enhancements
**Current State**: Basic IPv6 support  
**Enhancement**: Full IPv6 support and testing  
**Benefits**:
- Future-proofing
- Better IPv6 tunnel support
- Dual-stack environments

**Implementation Notes**:
- Enhanced IPv6 validation
- IPv6-specific ping handling
- IPv6 xfrm state parsing
- Test with IPv6-only tunnels

### 17. Backup and Restore
**Current State**: Manual backup  
**Enhancement**: Automated backup/restore  
**Benefits**:
- Configuration safety
- Easy migration
- Disaster recovery

**Implementation Notes**:
- `backup-config.sh` script
- Export config and state
- `restore-config.sh` script
- Version control integration
- Encrypted backups option

### 18. Performance Monitoring
**Current State**: No performance metrics  
**Enhancement**: Track script performance  
**Benefits**:
- Identify bottlenecks
- Optimize execution time
- Resource usage tracking

**Implementation Notes**:
- Execution time tracking
- Resource usage (CPU, memory)
- Log slow operations
- Performance reports

## Security Enhancements

### 19. Secure Configuration Storage
**Current State**: Plain text config files  
**Enhancement**: Encrypted configuration option  
**Benefits**:
- Protect sensitive information
- Compliance requirements
- Better security posture

**Implementation Notes**:
- Optional encryption for config files
- Key management
- Secure credential storage
- Integration with UDM keychain if available

### 20. Audit Logging
**Current State**: Standard logging  
**Enhancement**: Security audit trail  
**Benefits**:
- Compliance requirements
- Security incident investigation
- Change tracking

**Implementation Notes**:
- Separate audit log
- Log all configuration changes
- Log all recovery actions
- Immutable audit log option
- Integration with syslog

## Integration Enhancements

### 21. UniFi Controller Integration
**Current State**: Standalone tool  
**Enhancement**: Integration with UniFi Controller  
**Benefits**:
- Unified management
- Controller-based configuration
- Better visibility

**Implementation Notes**:
- UniFi API integration
- Controller-based config sync
- Status display in Controller UI
- Requires API access and documentation

### 22. External Monitoring Integration
**Current State**: Standalone  
**Enhancement**: Integrations with common monitoring tools  
**Benefits**:
- Centralized monitoring
- Existing toolchain integration
- Better alerting

**Implementation Notes**:
- Prometheus exporter
- Grafana dashboard templates
- Zabbix template
- Nagios plugin
- Datadog integration

## Implementation Guidelines

### Priority Ranking
1. **High Priority**: Core functionality improvements that significantly enhance reliability or usability
2. **Medium Priority**: Features that add value but aren't critical
3. **Low Priority**: Nice-to-have features that improve user experience

### Development Principles
- **Maintainability**: Keep code simple and well-documented
- **Reliability**: Don't break existing functionality
- **UDM Compatibility**: Ensure all features work on UDM systems
- **Backward Compatibility**: Maintain config file compatibility
- **Testing**: Test thoroughly before release

### Contribution Guidelines
- Open issues for discussion before major changes
- Maintain code style and documentation standards
- Add tests for new features
- Update README and documentation
- Consider impact on existing deployments

## Notes

- These enhancements are suggestions, not requirements
- Prioritize based on user needs and feedback
- Some enhancements may conflict with UDM constraints
- Consider maintenance burden when adding features
- Keep the tool simple and focused on its core purpose

## Feedback

If you have ideas for enhancements or want to prioritize certain features, please open an issue or submit a pull request.

