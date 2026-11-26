# sec-range-kit

[閱讀繁體中文版](README.zh-TW.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.10+-blue.svg)](https://www.python.org/downloads/)

> A shared, reusable toolkit for cyber range exercises and DFIR competitions. It is the sister project of [sec-compendium](https://github.com/Youchenjiang/sec-compendium):
>
> - **sec-compendium**: 📚 teaching material (courses, study groups, playbooks, exams)
> - **sec-range-kit**: 🛠️ battle-tested tooling you clone and use on game day

## Status

Initial scaffold. Tooling is being migrated from sec-compendium, starting with the HITCON 2026 range toolchain.

## Planned layout

```text
sec-range-kit/
├── rangekit/        # Python package (pip install -e ".[dfir]")
│   ├── common/      # Shared path safety checks
│   ├── dfir/        # Evidence parsers and query helpers (E01, ESE, AD1, auditd)
│   ├── vm/          # Analysis VM operations (vmrun guest ops, setup and collection scripts)
│   ├── collab/      # Multi-session collaboration bus for team play
│   └── mcp/         # MCP bridges and the server registry
├── skills/      # Agent skills (with upstream source and license manifest)
├── playbooks/   # Reusable game-day templates (role split SOP, daily decision cards)
├── docs/        # ADRs and per-event retrospectives
├── tools/       # Repository governance (commit lint, PR tool, release checks)
└── tests/
```

## How the kit evolves

The kit improves with every event instead of being copied per event.

1. **Before an event**: clone the repo and branch `event/<year>-<name>` from `main` (e.g. `event/2026-hitcon`). Event branches push without a PR body; commit lint and tests still run.
2. **During the event**: work freely on the event branch. Case data, evidence and notes stay **outside** the repository; point the tools at them with environment variables (see `.env.example` once tools land).
3. **After the event**: open PRs that bring only reusable improvements back to `main` (bug fixes, new tools, better templates). Event-only hacks stay on the branch.
4. **Release**: tag `main` after the merge, e.g. `v2026-hitcon`, and add a retrospective under `docs/retros/`.

Teachable lessons from an event go to sec-compendium as course material.

## Ground rules

- No hardcoded hosts, accounts or absolute paths; everything machine-specific comes from environment variables or a git-ignored config file.
- No event evidence, participant data or credentials in the repository.
- Imported third-party skills keep their upstream license and commit in the source manifest.

## Development

```bash
python scripts/install-hooks.py            # commit-msg and pre-push hooks
python -m unittest discover -s tests       # run the test suite
```

Commits follow Conventional Commits; see [AGENTS.md](AGENTS.md) for the full rules and allowed scopes.

## License

[MIT](LICENSE). Imported skills keep their own upstream licenses.
