# OpenSpec

This directory holds [OpenSpec](https://openspec.dev/) specs and change proposals for UDM VPN Monitor.

OpenSpec is spec-driven development for AI-assisted workflows: propose a change, review the plan, implement, then archive so specs become living documentation. Specs grow incrementally — you do not document the whole codebase upfront.

## Prerequisites

OpenSpec CLI (development machine only; not required on UDM):

```bash
npm install -g @fission-ai/openspec@latest
```

Verify: `openspec doctor`

## Workflow (Cursor)

Restart Cursor after init so slash commands are available.

| Command | Purpose |
|---------|---------|
| `/opsx:explore` | Investigate an area before committing to a change |
| `/opsx:propose <name>` | Create proposal, design, specs, and tasks |
| `/opsx:apply` | Implement tasks from the active change |
| `/opsx:sync` | Sync delta specs to main specs (optional) |
| `/opsx:archive` | Merge specs and archive the completed change |

Example:

```text
/opsx:explore
/opsx:propose improve-idle-detection
/opsx:apply
/opsx:archive
```

## Directory layout

```
openspec/
├── config.yaml    # Project context and artifact rules (injected into AI prompts)
├── specs/         # Source of truth — current system behavior by domain
│   └── <domain>/
│       └── spec.md
└── changes/       # Active proposals (one folder per change)
    └── <change-name>/
        ├── proposal.md
        ├── design.md
        ├── tasks.md
        └── specs/   # Delta specs (ADDED/MODIFIED/REMOVED)
```

Archived changes move to `openspec/changes/archive/`.

## CLI reference

```bash
openspec list                  # Active changes
openspec show <change-name>    # Change details
openspec validate <change>     # Validate spec formatting
openspec update                # Refresh Cursor commands/skills after profile change
```

## Relationship to other docs

| Artifact | Role |
|----------|------|
| `docs/adr/` | Permanent architecture decisions |
| `openspec/specs/` | Behavioral requirements (what the system does) |
| `openspec/changes/` | In-flight work with deltas |
| `docs/reference/CODE_PATTERNS.md` | How to implement (patterns, not requirements) |

See [DEVELOPER.md](../DEVELOPER.md#spec-driven-development-openspec) for the full developer guide.
