## 1. Move tree and fix script internals

- [x] 1.1 `git mv scripts/manage manage` (preserve history; ensure `scripts/manage` is gone)
- [x] 1.2 In every `manage/*.sh` (and sourced libs if needed): set `REPO_ROOT` to `"$(cd "${SCRIPT_DIR}/.." && pwd)"` instead of `../..`
- [x] 1.3 Update `# shellcheck source=` directives from `scripts/manage/...` to `manage/...`
- [x] 1.4 Update usage/`--help`/error strings that print `scripts/manage/` paths to `manage/`

## 2. Packaging and tests

- [x] 2.1 Update `scripts/prepare_install_package.sh` file list: `scripts/manage/...` → `manage/...` (include `manage/lib/` if listed elsewhere or discovered missing)
- [x] 2.2 Update `tests/test_prepare_install_package.sh` expected paths for manage scripts
- [x] 2.3 Update BATS/helpers that hardcode `scripts/manage/` (at least deploy, remote control, uninstall, fleet status, pull/push config tests per `docs/testing/RELEVANT_TESTS.md`)
- [x] 2.4 Ripgrep for remaining `scripts/manage` outside `openspec/changes/archive/` and `openspec/changes/promote-manage-to-top-level/`; fix or intentionally skip

## 3. Specs and operator docs

- [x] 3.1 Apply delta path updates into main specs: `openspec/specs/{remote-control,fleet-status,remote-uninstall,remote-config-pull-push}/spec.md`
- [x] 3.2 Update operator paths in README, `docs/scripts/CONTROL_PLANE_ACCEPTANCE.md`, `docs/scripts/CENTRALIZE_LOGS.md`, `docs/research/SERVER_APP_RECOMMENDATIONS.md` (active cites only)
- [x] 3.3 Update `docs/testing/RELEVANT_TESTS.md` mapping row from `scripts/manage/` to `manage/`
- [x] 3.4 Add CHANGELOG **BREAKING** entry: fleet tools moved to top-level `manage/`

## 4. Verify

- [x] 4.1 Run `TEST_TIMEOUT=120 bats tests/test_prepare_install_package.sh tests/test_deploy_to_udm.sh tests/test_deploy_to_udms.sh tests/test_remote_control.sh tests/test_remote_uninstall.sh tests/test_fleet_status.sh tests/test_pull_config_from_udms.sh tests/test_push_config_to_udms.sh`
- [x] 4.2 Run `shellcheck --severity=error` and `shfmt -d` on `manage/**/*.sh` (and any touched packaging scripts)
- [x] 4.3 Confirm no live references to `scripts/manage` remain in code/tests/active docs (archive excluded)
