## ADDED Requirements

### Requirement: Remote control via SSH

The system SHALL provide `scripts/manage/control-remote-udm.sh` that executes `vpn-monitor-control.sh` on a target UDM over SSH using ControlMaster connection reuse consistent with `deploy-to-udm.sh`.

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

### Requirement: Batch remote control

The system SHALL support batch operation via `--config FILE` reading one host per line using the same format as `deploy-udms.conf.example`.

#### Scenario: Batch pause across multiple hosts

- **GIVEN** a config file listing three UDM hosts
- **WHEN** `control-remote-udm.sh --config FILE pause --until +1h` is executed
- **THEN** each host SHALL receive the pause command
- **THEN** the controller SHALL print a per-host success or failure summary

_Verified by: `tests/test_remote_control.sh`_

#### Scenario: Continue batch on single host failure

- **GIVEN** a batch config where one host is unreachable
- **WHEN** batch remote control is executed
- **THEN** the controller SHALL continue processing remaining hosts
- **THEN** exit status SHALL be non-zero if any host failed

_Verified by: `tests/test_remote_control.sh`_

### Requirement: Remote pause passes time argument

The remote control script SHALL forward `--until` and optional `--reason` arguments to the on-UDM control script unchanged.

#### Scenario: Remote pause with relative duration

- **GIVEN** SSH access to target UDM
- **WHEN** `control-remote-udm.sh --host <target> pause --until +30m` is executed
- **THEN** target mode SHALL become `paused` with `paused_until` approximately 30 minutes ahead

_Verified by: `tests/test_remote_control.sh`, `tests/test_operating_mode.sh`_

### Requirement: Remote control from UDM or server

The remote control script SHALL run on any Linux host with bash, ssh, and optional sshpass — including a UDM acting as controller — without requiring additional UDM-specific daemons on the target beyond the installed VPN Monitor.

#### Scenario: Controller uses standard SSH options

- **GIVEN** the remote control script establishes an SSH session
- **WHEN** connecting to the target
- **THEN** it SHALL use ControlMaster/ControlPersist patterns from `docs/reference/CODE_PATTERNS.md`
- **THEN** it SHALL NOT depend on python3, jq, or node

_Verified by: `tests/test_remote_control.sh`; shellcheck on script_

### Requirement: Remote control install path

Remote commands SHALL invoke the control script at `${INSTALL_DIR}/vpn-monitor-control.sh` (default `/data/vpn-monitor/vpn-monitor-control.sh`).

#### Scenario: Missing control script on target

- **GIVEN** target UDM does not have VPN Monitor installed
- **WHEN** remote control is attempted
- **THEN** the controller SHALL report a clear error indicating the control script was not found
- **THEN** exit status SHALL be non-zero

_Verified by: `tests/test_remote_control.sh`_
