## ADDED Requirements

### Requirement: Operating mode state persistence

The system SHALL persist the current monitor operating mode in `${STATE_DIR}/operating_mode` using atomic write-to-tmp-then-mv semantics.

The file SHALL contain at minimum `mode` with one of: `running`, `stopped`, `paused`, `observe-only`.

When `mode=paused`, the file SHALL also contain `paused_until` as Unix epoch seconds.

#### Scenario: Default mode on missing state file

- **GIVEN** no `operating_mode` state file exists
- **WHEN** the operating mode is read
- **THEN** the effective mode SHALL be `running`

#### Scenario: Atomic write on mode change

- **GIVEN** the control script sets a new operating mode
- **WHEN** the state file is written
- **THEN** the write SHALL use a `.tmp` file and `mv` to the final path
- **THEN** a partial write SHALL NOT leave a corrupt `operating_mode` file

_Verified by: `tests/test_operating_mode.sh`_

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

### Requirement: Pause command suppresses execution until end time

The system SHALL provide `vpn-monitor-control.sh pause --until <time>` which sets mode to `paused` with a future `paused_until` timestamp and ensures cron is enabled.

While paused and current time is before `paused_until`, `vpn-monitor.sh` SHALL exit immediately without performing detection or recovery.

#### Scenario: Active pause skips execution

- **GIVEN** mode is `paused` and `paused_until` is 10 minutes in the future
- **WHEN** `vpn-monitor.sh` is invoked
- **THEN** it SHALL exit 0 without running detection or recovery
- **THEN** it SHALL log that the monitor is paused until the configured time

_Verified by: `tests/test_operating_mode.sh`, `tests/test_main.sh`_

#### Scenario: Pause auto-resumes after expiry

- **GIVEN** mode is `paused` and `paused_until` is in the past
- **WHEN** `vpn-monitor.sh` is invoked
- **THEN** mode SHALL transition to `running`
- **THEN** full detection and recovery SHALL proceed

_Verified by: `tests/test_operating_mode.sh`_

#### Scenario: Reject pause with past time

- **GIVEN** operator supplies `--until` with a timestamp in the past
- **WHEN** `vpn-monitor-control.sh pause` is executed
- **THEN** the command SHALL fail with a validation error
- **THEN** operating mode SHALL remain unchanged

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
