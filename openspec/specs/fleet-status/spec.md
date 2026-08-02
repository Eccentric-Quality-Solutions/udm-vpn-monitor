# Fleet Status

SSH-based live inventory of VPN Monitor installation state across a fleet of UDMs from a controller, including version, operating mode, cron presence, and deploy-registry drift.

## Requirements

### Requirement: Fleet status script reports live inventory per UDM

The system SHALL provide `manage/status-udms.sh` that reads a fleet config file and for each listed host reports live installation state gathered over SSH together with the local deploy-registry row (if any).

#### Scenario: Per-host report includes required fields

- **GIVEN** a controller with SSH access to a target UDM with VPN Monitor installed at `/data/vpn-monitor/`
- **WHEN** `status-udms.sh --config FILE` is executed and the target is reachable
- **THEN** the controller SHALL report for that host: live `SCRIPT_VERSION` from `/data/vpn-monitor/vpn-monitor.sh`, operating mode, cron presence (yes/no or enabled/disabled), and deploy-registry version/timestamp when a registry row exists
- **THEN** the controller SHALL NOT modify anything on the target or in the deploy registry

_Verified by: `tests/test_fleet_status.sh` (mocked SSH)_

#### Scenario: Host not installed

- **GIVEN** a target UDM reachable over SSH but `/data/vpn-monitor/vpn-monitor.sh` is absent
- **WHEN** fleet status is collected for that host
- **THEN** the controller SHALL report the host as not installed (empty or explicit `not installed` version field)
- **THEN** operating mode and cron fields SHALL reflect absence of installation where applicable
- **THEN** processing SHALL continue for remaining hosts

_Verified by: `tests/test_fleet_status.sh`_

#### Scenario: Host unreachable

- **GIVEN** a fleet config listing a host that cannot be reached over SSH
- **WHEN** fleet status is collected
- **THEN** the controller SHALL report that host as unreachable or error
- **THEN** processing SHALL continue for remaining hosts
- **THEN** exit status SHALL be non-zero if any host failed

_Verified by: `tests/test_fleet_status.sh`_

### Requirement: Fleet status uses standard fleet config and SSH transport

The fleet status script SHALL read hosts using the same `host [bind_ip]` format as `deploy-udms.conf.example` and reuse ControlMaster SSH patterns from other `manage/` tools.

#### Scenario: Default and explicit config files

- **GIVEN** no `--config` flag is passed
- **WHEN** `status-udms.sh` runs
- **THEN** it SHALL attempt to read `deploy-udms.conf` from the repo root, falling back to `control-udms.conf` when the deploy config is missing
- **WHEN** `--config FILE` is passed
- **THEN** it SHALL read hosts from `FILE` only

_Verified by: `tests/test_fleet_status.sh`_

#### Scenario: Per-host bind IP from config

- **GIVEN** a config line `192.168.1.100 10.0.0.5`
- **WHEN** fleet status runs for that host
- **THEN** SSH SHALL use `BindAddress=10.0.0.5` for that host only
- **THEN** subsequent hosts without a bind IP SHALL NOT inherit the previous host's bind IP

_Verified by: `tests/test_fleet_status.sh`_

#### Scenario: Standard SSH options

- **GIVEN** the fleet status script establishes SSH to a target
- **WHEN** connecting
- **THEN** it SHALL use ControlMaster/ControlPersist patterns consistent with `control-remote-udm.sh`
- **THEN** it SHALL support `--bind-ip`, `--username`, `--port`, `--timeout`, and `--dry-run` consistent with other manage scripts
- **THEN** it SHALL NOT depend on python3, jq, or node

_Verified by: `tests/test_fleet_status.sh`; shellcheck on scripts_

### Requirement: Registry drift is visible in output

The fleet status script SHALL compare live `SCRIPT_VERSION` with the deploy-registry version for each host and surface mismatches in the report.

#### Scenario: Registry matches live version

- **GIVEN** live `SCRIPT_VERSION` on the UDM equals the version recorded in `logs/deploy-registry` for that host
- **WHEN** fleet status is reported
- **THEN** the output SHALL indicate registry alignment (e.g. `match` or equivalent neutral marker)

_Verified by: `tests/test_fleet_status.sh`_

#### Scenario: Registry drift detected

- **GIVEN** live `SCRIPT_VERSION` differs from the deploy-registry version, or the host has no registry entry but is installed
- **WHEN** fleet status is reported
- **THEN** the output SHALL indicate registry drift or missing registry entry distinctly from a match
- **THEN** live version SHALL remain the authoritative field for installed state

_Verified by: `tests/test_fleet_status.sh`_

#### Scenario: No registry file

- **GIVEN** `logs/deploy-registry` does not exist
- **WHEN** fleet status runs
- **THEN** registry columns SHALL be empty or marked absent
- **THEN** live SSH queries SHALL still proceed for all hosts

_Verified by: `tests/test_fleet_status.sh`_

### Requirement: Fleet summary after per-host rows

The fleet status script SHALL print a concise summary after all per-host rows.

#### Scenario: Summary counts hosts by outcome

- **GIVEN** a fleet config with multiple hosts of mixed reachability and install state
- **WHEN** `status-udms.sh` completes
- **THEN** it SHALL print counts such as reachable, installed, not installed, unreachable, and registry drift (exact labels documented in `--help`)
- **THEN** per-host detail SHALL appear before the summary

_Verified by: `tests/test_fleet_status.sh`_

#### Scenario: Dry-run shows remote commands without SSH

- **GIVEN** `--dry-run` is passed
- **WHEN** `status-udms.sh` runs
- **THEN** it SHALL print the remote inspection command(s) per host without executing SSH
- **THEN** exit status SHALL be zero when config parsing succeeds

_Verified by: `tests/test_fleet_status.sh`_
