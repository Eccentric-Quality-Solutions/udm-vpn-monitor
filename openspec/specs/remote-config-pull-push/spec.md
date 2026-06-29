# Remote Config Pull/Push

Controller-side pull and push of live `vpn-monitor.conf` across a UDM fleet via SCP over SSH, with timestamped backups, remote validation, and a pull-edit-push workflow.

## Requirements

### Requirement: Pull script copies live config from UDMs to controller working tree

The system SHALL provide `scripts/manage/pull-config-from-udms.sh` that reads a fleet config file and for each listed host copies live `/data/vpn-monitor/vpn-monitor.conf` to a controller working path via SCP over SSH.

#### Scenario: Successful pull for installed host

- **GIVEN** a controller with SSH access to a UDM with VPN Monitor installed and a live config at `/data/vpn-monitor/vpn-monitor.conf`
- **WHEN** `pull-config-from-udms.sh --config FILE` runs for that host
- **THEN** the controller SHALL write the remote file to `configs/<host>/vpn-monitor.conf` under the config directory (default `${REPO_ROOT}/configs/`)
- **THEN** the write SHALL be atomic (temporary file then rename)
- **THEN** the controller SHALL report success for that host

_Verified by: `tests/test_pull_config_from_udms.sh` (mocked SCP/SSH)_

#### Scenario: Host not installed or no remote config

- **GIVEN** a reachable UDM without VPN Monitor config at the expected path
- **WHEN** pull runs for that host
- **THEN** the controller SHALL report `not_installed` or `no_remote_config` and SHALL NOT create a misleading local file
- **THEN** processing SHALL continue for remaining hosts

_Verified by: `tests/test_pull_config_from_udms.sh`_

#### Scenario: Host unreachable

- **GIVEN** a fleet config listing a host that cannot be reached over SSH
- **WHEN** pull runs
- **THEN** the controller SHALL report that host as unreachable or error
- **THEN** exit status SHALL be non-zero if any host failed

_Verified by: `tests/test_pull_config_from_udms.sh`_

### Requirement: Pull uses standard fleet config and SSH transport

The pull script SHALL read hosts using the same `host [bind_ip]` format as other manage scripts and reuse ControlMaster SSH patterns from `scripts/manage/lib/ssh_control.sh`.

#### Scenario: Default and explicit fleet config

- **GIVEN** no `--config` flag is passed
- **WHEN** `pull-config-from-udms.sh` runs
- **THEN** it SHALL attempt `deploy-udms.conf` then fallback to `control-udms.conf`
- **WHEN** `--config FILE` is passed
- **THEN** it SHALL read hosts from `FILE` only

_Verified by: `tests/test_pull_config_from_udms.sh`_

#### Scenario: Dry-run mode

- **WHEN** `--dry-run` is passed
- **THEN** the script SHALL print planned SCP sources and local destinations without transferring files
- **THEN** exit status SHALL be 0

_Verified by: `tests/test_pull_config_from_udms.sh`_

### Requirement: Push script installs local config with backup and validation

The system SHALL provide `scripts/manage/push-config-to-udms.sh` that pushes a local config file to `/data/vpn-monitor/vpn-monitor.conf` on one or more UDMs with timestamped backup, atomic install, and remote validation.

#### Scenario: Successful push with backups

- **GIVEN** a local config file at `configs/<host>/vpn-monitor.conf` (or `--file PATH`)
- **AND** a reachable UDM with an existing live config
- **WHEN** `push-config-to-udms.sh` runs for that host
- **THEN** the controller SHALL copy the current remote config to a timestamped backup on the UDM under `/data/vpn-monitor/backups/`
- **THEN** the controller SHALL copy the current remote config to `configs/backups/<host>/vpn-monitor.conf.<timestamp>` when the remote file exists
- **THEN** the controller SHALL upload the new config atomically and run `/data/vpn-monitor/check-config.sh` before committing
- **THEN** on validation success the live config SHALL be updated
- **THEN** the controller SHALL report success for that host

_Verified by: `tests/test_push_config_to_udms.sh` (mocked SCP/SSH)_

#### Scenario: Validation failure leaves live config unchanged

- **GIVEN** a push where remote `check-config.sh` fails on the staged config
- **WHEN** push runs for that host
- **THEN** the previous live config on the UDM SHALL remain unchanged
- **THEN** the controller SHALL report failure for that host
- **THEN** exit status SHALL be non-zero

_Verified by: `tests/test_push_config_to_udms.sh`_

#### Scenario: Missing local file

- **GIVEN** no local config file for a fleet host
- **WHEN** batch push runs for that host
- **THEN** the controller SHALL report skip or error for that host and SHALL NOT modify the remote UDM

_Verified by: `tests/test_push_config_to_udms.sh`_

#### Scenario: Dry-run mode

- **WHEN** `--dry-run` is passed
- **THEN** the script SHALL print planned backup paths, upload target, and validation command without modifying remote or local backup trees
- **THEN** exit status SHALL be 0

_Verified by: `tests/test_push_config_to_udms.sh`_

### Requirement: Push uses standard fleet config and SSH transport

The push script SHALL read hosts using the same `host [bind_ip]` format and SSH options as the pull script and other manage tools.

#### Scenario: Single host mode

- **WHEN** `--host HOST` is passed with optional `--file PATH`
- **THEN** push SHALL target only that host using the specified or default local file path

_Verified by: `tests/test_push_config_to_udms.sh`_

#### Scenario: Per-host bind IP from config

- **GIVEN** a config line `192.168.1.100 10.0.0.5`
- **WHEN** push runs for that host
- **THEN** SSH/SCP SHALL use `BindAddress=10.0.0.5` for that host only

_Verified by: `tests/test_push_config_to_udms.sh`_

### Requirement: Config workflow documentation and repository hygiene

Documentation SHALL describe the pull-edit-push workflow and SHALL prevent accidental commit of pulled configs.

#### Scenario: Gaps document updated

- **WHEN** the change is implemented
- **THEN** `docs/scripts/CENTRAL_MANAGEMENT_GAPS.md` §1 SHALL list pull/push scripts as implemented
- **THEN** `diff-config-udms.sh` SHALL NOT remain a suggested addition

_Verified by: manual review_

#### Scenario: Config directory gitignored

- **WHEN** the change is implemented
- **THEN** `${REPO_ROOT}/configs/` SHALL be listed in `.gitignore` (except optional non-secret example files if any)

_Verified by: manual review_
