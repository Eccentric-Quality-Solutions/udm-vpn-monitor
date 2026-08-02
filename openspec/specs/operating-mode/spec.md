# Operating Mode

Control whether VPN Monitor runs, is paused during maintenance, or logs without taking recovery action. State is persisted in `state/operating_mode` and enforced by `vpn-monitor.sh` and `vpn-monitor-wrapper.sh`.

## Requirements

### Requirement: Operating mode state persistence

The system SHALL persist the current monitor operating mode in `${STATE_DIR}/operating_mode` using atomic write-to-tmp-then-mv semantics.

The file SHALL contain at minimum `mode` with one of: `running`, `stopped`, `paused`, `observe-only`.

When `mode=paused`, the file SHALL also contain `paused_until` as Unix epoch seconds (`0` means indefinite pause).

#### Scenario: Default mode on missing state file

- **GIVEN** no `operating_mode` state file exists
- **WHEN** the operating mode is read
- **THEN** the effective mode SHALL be `observe-only`

#### Scenario: Atomic write on mode change

- **GIVEN** the control script sets a new operating mode
- **WHEN** the state file is written
- **THEN** the write SHALL use a `.tmp` file and `mv` to the final path
- **THEN** a partial write SHALL NOT leave a corrupt `operating_mode` file

_Verified by: `tests/test_operating_mode.sh`_

### Requirement: Fresh install initializes observe-only

When the install path initializes operating mode and no `operating_mode` state file exists, the system SHALL create the file with `mode=observe-only`.

When an `operating_mode` file already exists, install or upgrade SHALL NOT overwrite the existing mode.

#### Scenario: First install creates observe-only

- **GIVEN** a new installation with no prior `state/operating_mode`
- **WHEN** install completes operating-mode initialization
- **THEN** `state/operating_mode` SHALL contain `mode=observe-only`
- **THEN** subsequent monitor runs SHALL detect and log without executing recovery until `start` is used

#### Scenario: Upgrade preserves existing mode

- **GIVEN** an existing installation with `mode=running`
- **WHEN** install or upgrade re-runs operating-mode initialization
- **THEN** `mode` SHALL remain `running`

_Verified by: `tests/test_operating_mode.sh`, `tests/test_install.sh`_

### Requirement: Start command restores normal operation

The system SHALL provide `vpn-monitor-control.sh start` which sets mode to `running`, restores the cron entry per install configuration, and starts the keepalive service when enabled in config.

#### Scenario: Start from stopped

- **GIVEN** operating mode is `stopped` and cron entry is absent
- **WHEN** `vpn-monitor-control.sh start` is executed
- **THEN** mode SHALL become `running`
- **THEN** cron entry for vpn-monitor SHALL be restored
- **THEN** subsequent cron-triggered runs SHALL execute full detection and recovery

_Verified by: `tests/test_operating_mode.sh`, `tests/test_install.sh` (cron helpers)_

### Requirement: Stop command halts monitor execution

The system SHALL provide `vpn-monitor-control.sh stop` which sets mode to `stopped`, removes the vpn-monitor cron entry, stops the monitor wrapper if running, and stops the keepalive service if running.

#### Scenario: Stop prevents monitor runs

- **GIVEN** operating mode is `running` with cron enabled
- **WHEN** `vpn-monitor-control.sh stop` is executed
- **THEN** mode SHALL become `stopped`
- **THEN** no vpn-monitor cron entry SHALL remain
- **THEN** `vpn-monitor.sh` SHALL NOT be invoked by cron until `start` is run

_Verified by: `tests/test_operating_mode.sh`_

### Requirement: Pause command suppresses execution until end time or indefinitely

The system SHALL provide `vpn-monitor-control.sh pause` which sets mode to `paused` and ensures cron is enabled.

When `--until <time>` is supplied, the system SHALL set `paused_until` to the parsed future epoch. While paused and current time is before `paused_until`, `vpn-monitor.sh` SHALL exit immediately without performing detection or recovery.

When `--until` is omitted, the system SHALL set `paused_until=0` (indefinite). While indefinitely paused, `vpn-monitor.sh` SHALL exit immediately without auto-resuming until an explicit mode change (`start`, `observe-only`, or `stop`).

#### Scenario: Active timed pause skips execution

- **GIVEN** mode is `paused` and `paused_until` is 10 minutes in the future
- **WHEN** `vpn-monitor.sh` is invoked
- **THEN** it SHALL exit 0 without running detection or recovery
- **THEN** it SHALL log that the monitor is paused until the configured time

_Verified by: `tests/test_operating_mode.sh`, `tests/test_main.sh`_

#### Scenario: Indefinite pause skips execution

- **GIVEN** mode is `paused` and `paused_until` is `0`
- **WHEN** `vpn-monitor.sh` is invoked
- **THEN** it SHALL exit without running detection or recovery
- **THEN** mode SHALL remain `paused`

#### Scenario: Pause auto-resumes after timed expiry

- **GIVEN** mode is `paused` and `paused_until` is in the past and greater than zero
- **WHEN** `vpn-monitor.sh` is invoked
- **THEN** mode SHALL transition to `running`
- **THEN** full detection and recovery SHALL proceed

_Verified by: `tests/test_operating_mode.sh`_

#### Scenario: Reject timed pause with past time

- **GIVEN** operator supplies `--until` with a timestamp in the past
- **WHEN** `vpn-monitor-control.sh pause` is executed
- **THEN** the command SHALL fail with a validation error
- **THEN** operating mode SHALL remain unchanged

_Verified by: `tests/test_operating_mode.sh`_

### Requirement: Pause may be indefinite or timed

The system SHALL accept `vpn-monitor-control.sh pause` without `--until`, setting `paused_until=0` (indefinite). Indefinite pause SHALL NOT auto-resume; operators SHALL clear it with `start`, `observe-only`, or `stop`.

When `--until` is supplied with a valid future time, timed pause behavior (including auto-resume to `running` after expiry) SHALL remain available.

#### Scenario: Indefinite pause without --until

- **GIVEN** an installed monitor
- **WHEN** `vpn-monitor-control.sh pause` is executed without `--until`
- **THEN** mode SHALL become `paused` with `paused_until=0`
- **THEN** subsequent monitor invocations SHALL skip detection until mode is changed explicitly

_Verified by: `tests/test_operating_mode.sh`_

### Requirement: Observe-only mode logs without recovery

The system SHALL provide `vpn-monitor-control.sh observe-only` which sets mode to `observe-only` and ensures cron is enabled.

In observe-only mode, `vpn-monitor.sh` SHALL run detection and logging but SHALL NOT execute any recovery action at any tier.

#### Scenario: Observe-only suppresses recovery

- **GIVEN** mode is `observe-only` and a location has failures exceeding Tier 2 threshold
- **WHEN** `vpn-monitor.sh` completes a monitoring cycle
- **THEN** failures SHALL be logged
- **THEN** no xfrm recovery, ipsec reload, or ipsec restart SHALL be invoked

_Verified by: `tests/test_operating_mode.sh`, `tests/test_recovery_orchestration_determine_action.sh`_

### Requirement: Status command reports current mode

The system SHALL provide `vpn-monitor-control.sh status` which prints the current mode, paused-until time when applicable, and whether cron and keepalive are active.

#### Scenario: Status output for paused mode

- **GIVEN** mode is `paused` with a known `paused_until`
- **WHEN** `vpn-monitor-control.sh status` is executed
- **THEN** output SHALL include mode `paused` and a human-readable end time

_Verified by: `tests/test_operating_mode.sh`_

### Requirement: Mode transitions are logged

The system SHALL log operating mode changes at INFO level to `vpn-monitor.log` with context `SYSTEM`, including previous mode, new mode, and operator identity when available.

#### Scenario: Stop logs transition

- **GIVEN** mode is `running`
- **WHEN** `vpn-monitor-control.sh stop` is executed
- **THEN** `vpn-monitor.log` SHALL contain an INFO entry recording the transition to `stopped`

_Verified by: `tests/test_operating_mode.sh`_
