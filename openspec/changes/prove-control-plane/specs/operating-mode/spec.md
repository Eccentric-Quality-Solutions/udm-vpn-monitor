## MODIFIED Requirements

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

## ADDED Requirements

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

## ADDED Requirements

### Requirement: Pause may be indefinite or timed

The system SHALL accept `vpn-monitor-control.sh pause` without `--until`, setting `paused_until=0` (indefinite). Indefinite pause SHALL NOT auto-resume; operators SHALL clear it with `start`, `observe-only`, or `stop`.

When `--until` is supplied with a valid future time, timed pause behavior (including auto-resume to `running` after expiry) SHALL remain available.

#### Scenario: Indefinite pause without --until

- **GIVEN** an installed monitor
- **WHEN** `vpn-monitor-control.sh pause` is executed without `--until`
- **THEN** mode SHALL become `paused` with `paused_until=0`
- **THEN** subsequent monitor invocations SHALL skip detection until mode is changed explicitly

_Verified by: `tests/test_operating_mode.sh`_
