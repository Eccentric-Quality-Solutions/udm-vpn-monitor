## MODIFIED Requirements

### Requirement: Remote control via SSH

The system SHALL provide `manage/control-remote-udm.sh` that executes `vpn-monitor-control.sh` on a target UDM over SSH using ControlMaster connection reuse consistent with `deploy-to-udm.sh`.

#### Scenario: Remote stop on single host

- **GIVEN** a controller with SSH access to target UDM at `/data/vpn-monitor/`
- **WHEN** `control-remote-udm.sh --host <target> stop` is executed
- **THEN** the controller SHALL SSH to the target and run `vpn-monitor-control.sh stop`
- **THEN** the target operating mode SHALL become `stopped`

_Verified by: `tests/test_remote_control.sh` (mocked SSH)_

#### Scenario: Remote status on single host

- **GIVEN** a controller with SSH access to target UDM
- **WHEN** `control-remote-udm.sh --host <target> status` is executed
- **THEN** the controller SHALL print the target's operating mode status to stdout

_Verified by: `tests/test_remote_control.sh`_
