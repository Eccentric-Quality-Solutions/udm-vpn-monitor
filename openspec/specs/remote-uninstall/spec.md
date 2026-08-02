# Remote Uninstall

SSH-based remote invocation of on-UDM `uninstall.sh` from a controller machine to one or more target UDMs, without transferring a deployment package.

## Requirements

### Requirement: Remote uninstall via SSH

The system SHALL provide `manage/uninstall-from-udm.sh` that executes the on-UDM `uninstall.sh` on a target UDM over SSH using ControlMaster connection reuse consistent with `deploy-to-udm.sh` and `control-remote-udm.sh`.

#### Scenario: Remote uninstall on single host

- **GIVEN** a controller with SSH access to a target UDM with VPN Monitor installed at `/data/vpn-monitor/`
- **WHEN** `uninstall-from-udm.sh --host <target>` is executed
- **THEN** the controller SHALL SSH to the target and run `/data/vpn-monitor/uninstall.sh --yes` with default uninstall flags matching deploy defaults (`--keep-config`, `--remove-state`, `--remove-logs`)
- **THEN** the target SHALL no longer have cron entries or keepalive service for VPN Monitor
- **THEN** the controller SHALL print uninstall output from the target

_Verified by: `tests/test_remote_uninstall.sh` (mocked SSH)_

#### Scenario: Remote uninstall forwards flag overrides

- **GIVEN** SSH access to target UDM with VPN Monitor installed
- **WHEN** `uninstall-from-udm.sh --host <target> --remove-config --keep-state --keep-logs` is executed
- **THEN** the controller SHALL run `uninstall.sh --yes --remove-config --keep-state --keep-logs` on the target
- **THEN** conflicting flag pairs (e.g. `--keep-config` and `--remove-config`) SHALL be rejected locally before SSH

_Verified by: `tests/test_remote_uninstall.sh`_

#### Scenario: Missing installation on target

- **GIVEN** target UDM does not have `/data/vpn-monitor/uninstall.sh`
- **WHEN** remote uninstall is attempted
- **THEN** the controller SHALL report that no installation was found
- **THEN** exit status SHALL be non-zero

_Verified by: `tests/test_remote_uninstall.sh`_

### Requirement: Batch remote uninstall

The system SHALL provide `manage/uninstall-from-udms.sh` supporting batch operation via `--config FILE` reading one host per line using the same format as `deploy-udms.conf.example` (`host [bind_ip]`).

#### Scenario: Batch uninstall across multiple hosts

- **GIVEN** a config file listing three UDM hosts
- **WHEN** `uninstall-from-udms.sh --config FILE` is executed
- **THEN** each host SHALL receive the remote uninstall command with the same flag set
- **THEN** the controller SHALL print a per-host success or failure summary

_Verified by: `tests/test_remote_uninstall.sh`_

#### Scenario: Continue batch on single host failure

- **GIVEN** a batch config where one host is unreachable
- **WHEN** batch remote uninstall is executed
- **THEN** the controller SHALL continue processing remaining hosts
- **THEN** exit status SHALL be non-zero if any host failed

_Verified by: `tests/test_remote_uninstall.sh`_

### Requirement: Remote uninstall uses standard SSH transport

The remote uninstall scripts SHALL run on any Linux host with bash, ssh, and optional sshpass — including a UDM acting as controller — without requiring additional daemons on the target beyond the installed VPN Monitor.

#### Scenario: Controller uses standard SSH options

- **GIVEN** the remote uninstall script establishes an SSH session
- **WHEN** connecting to the target
- **THEN** it SHALL use ControlMaster/ControlPersist patterns from `docs/reference/CODE_PATTERNS.md`
- **THEN** it SHALL support `--bind-ip`, `--username`, `--port`, and `--timeout` options consistent with other manage scripts
- **THEN** it SHALL NOT depend on python3, jq, or node

_Verified by: `tests/test_remote_uninstall.sh`; shellcheck on scripts_

### Requirement: Remote uninstall does not transfer packages

The remote uninstall scripts SHALL NOT require or transfer a deployment package (zip/tar.gz).

#### Scenario: Uninstall without package file

- **GIVEN** no `udm-vpn-monitor.zip` exists on the controller
- **WHEN** `uninstall-from-udm.sh --host <target>` is executed
- **THEN** uninstall SHALL proceed using only SSH to the target's existing installation
- **THEN** no SCP or package extraction SHALL occur

_Verified by: `tests/test_remote_uninstall.sh`_

### Requirement: Optional deploy registry cleanup

When `--update-registry` is passed, the remote uninstall scripts SHALL remove the target host entry from `logs/deploy-registry` after a successful uninstall.

#### Scenario: Registry entry removed after successful uninstall

- **GIVEN** `logs/deploy-registry` contains an entry for host `192.168.1.100`
- **WHEN** `uninstall-from-udm.sh --host 192.168.1.100 --update-registry` completes successfully
- **THEN** no registry line for `192.168.1.100` SHALL remain

_Verified by: `tests/test_remote_uninstall.sh`_

#### Scenario: Registry unchanged when flag omitted

- **GIVEN** `logs/deploy-registry` contains an entry for the target host
- **WHEN** remote uninstall completes without `--update-registry`
- **THEN** the registry entry SHALL remain unchanged

_Verified by: `tests/test_remote_uninstall.sh`_
