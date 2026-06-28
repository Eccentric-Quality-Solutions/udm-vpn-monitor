## 1. Operating-mode library

- [x] 1.1 Create `lib/control/operating_mode.sh` with read/write/get-default functions for `state/operating_mode` (atomic writes, key=value format)
- [x] 1.2 Add pause time parsing (`--until` epoch, relative `+30m`/`+2h`/`+1d`, local datetime) with past-time validation
- [x] 1.3 Add `check_operating_mode()` with auto-resume when `paused_until` has passed
- [x] 1.4 Create `lib/control/cron_control.sh` extracting cron add/remove helpers reusable by install and control scripts
- [x] 1.5 Add `lib/control.sh` aggregate entry sourcing control modules

## 2. Local control script

- [x] 2.1 Create `vpn-monitor-control.sh` with subcommands: `start`, `stop`, `pause`, `observe-only`, `status`, `--help`
- [x] 2.2 Implement `start`: set running, restore cron, start keepalive when enabled
- [x] 2.3 Implement `stop`: set stopped, remove cron, stop wrapper (PID file), stop keepalive
- [x] 2.4 Implement `pause` and `observe-only` with optional `--reason`; log transitions via `log_message`
- [x] 2.5 Implement `status` with human-readable paused-until and cron/keepalive state

## 3. Monitor pipeline integration

- [x] 3.1 Call `check_operating_mode()` early in `vpn-monitor.sh` `main()` — exit 0 for active pause/stopped paths
- [x] 3.2 Export/set flag for observe-only mode; guard recovery orchestration to skip all tier actions when set
- [x] 3.3 Ensure `vpn-monitor-wrapper.sh` respects operating mode (skip spawning monitor when paused/stopped)
- [x] 3.4 Update `docs/reference/STATE_SYSTEM.md` with `operating_mode` file documentation

## 4. Install and package

- [x] 4.1 Update `install.sh` to copy `vpn-monitor-control.sh` and initialize default `state/operating_mode` if missing
- [x] 4.2 Update `uninstall.sh` to remove operating_mode state
- [x] 4.3 Update `scripts/prepare_install_package.sh` to include new scripts and lib/control modules

## 5. Remote control CLI

- [x] 5.1 Create `scripts/manage/control-remote-udm.sh` with `--host`, `--config`, `--user`, `--port` options
- [x] 5.2 Reuse SSH ControlMaster patterns from `deploy-to-udm.sh` (source or shared helper)
- [x] 5.3 Add batch mode with per-host summary and non-zero exit on any failure
- [x] 5.4 Add `scripts/manage/control-udms.conf.example` documenting host-list format

## 6. Tests

- [x] 6.1 Create `tests/test_operating_mode.sh` covering all modes, pause expiry, past-time rejection, and logging
- [x] 6.2 Create `tests/test_remote_control.sh` with mocked SSH for single-host and batch commands
- [x] 6.3 Update `tests/test_main.sh` for observe-only and pause early-exit paths
- [x] 6.4 Update `tests/test_install.sh` for control script installation
- [x] 6.5 Run `TEST_TIMEOUT=120 bats tests/test_operating_mode.sh tests/test_remote_control.sh tests/test_main.sh tests/test_install.sh`
- [x] 6.6 Run `shellcheck --severity=error` on new/changed shell scripts; `shfmt -d` on same files

## 7. Documentation

- [x] 7.1 Add operating modes and remote control section to `README.md`
- [x] 7.2 Add developer notes to `DEVELOPER.md` and code-to-test mapping in `docs/testing/RELEVANT_TESTS.md`
