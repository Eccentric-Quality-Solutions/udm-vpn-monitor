## ADDED Requirements

### Requirement: Control-plane acceptance checklist exists

The project SHALL provide a documented controller-side acceptance checklist that defines how an operator proves deploy, observe-only posture, pause/start, config pull/push, log centralization, and fleet status using existing `scripts/manage/` tools (without requiring a long-lived management server).

#### Scenario: Checklist covers required control operations

- **GIVEN** an operator preparing a stage-1 fleet
- **WHEN** they follow the control-plane acceptance checklist
- **THEN** the document SHALL include steps for: fleet deploy, verify `observe-only`, pause and start (or resume), config pull and push with validation, log pull via centralize-logs, and status/registry consistency
- **THEN** each step SHALL name the script (and essential flags) to run

_Verified by: documentation review; optional helper script dry-run if implemented_

### Requirement: Acceptance assumes safe default observe-only

The acceptance checklist SHALL assume that a fresh deploy leaves agents in `observe-only` and SHALL include an explicit verification that remote status reports `observe-only` before treating the control plane as proven.

#### Scenario: Post-deploy mode verification

- **GIVEN** a successful fleet deploy of a package that defaults to observe-only
- **WHEN** the operator reaches the post-deploy verification step
- **THEN** the checklist SHALL require confirming `observe-only` (via `status-udms.sh` and/or `control-remote-udm.sh … status`) on each target host

_Verified by: documentation review_

### Requirement: Keepalive note in acceptance docs

The acceptance checklist SHALL note that observe-only does not stop or disable `vpn-keepalive`, and that operators may disable keepalive in config separately if stage-1 observation must not inject keepalive traffic.

#### Scenario: Keepalive independence documented

- **WHEN** an operator reads the control-plane acceptance checklist
- **THEN** the document SHALL state that observe-only suppresses recovery only and leaves keepalive unchanged unless config is edited

_Verified by: documentation review_

### Requirement: Enable recovery is an explicit later step

The acceptance checklist SHALL treat enabling recovery (`start` / remote `start`) as a separate, post-validation step (e.g. canary then expand), not as part of proving the control plane itself.

#### Scenario: Recovery enablement gated

- **GIVEN** the control-plane acceptance criteria are met
- **WHEN** the operator wants agents to perform recovery
- **THEN** the checklist SHALL direct use of `start` (local or via `control-remote-udm.sh`) on a defined canary or fleet subset
- **THEN** proving the control plane SHALL NOT require recovery to have run successfully

_Verified by: documentation review_
