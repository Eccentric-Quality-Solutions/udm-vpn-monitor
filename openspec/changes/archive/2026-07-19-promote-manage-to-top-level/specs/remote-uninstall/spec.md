## MODIFIED Requirements

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
