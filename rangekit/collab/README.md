# rangekit.collab

A governed case bus for several agent or human sessions working one event together: the Case Lead dispatches tasks, workers acknowledge and report through immutable runtime events, and Race mode publishes answers as soon as they are found.

The full protocol (roles, task contract, Race mode, handoffs) is in [`.collab/README.md`](../../.collab/README.md). Role cards live in `.collab/roles/` and the case skeleton in `.collab/cases/C00_Template/`.

## Where data lives

| Path | Tracked | Content |
|---|---|---|
| `.collab/README.md`, `roles/`, `cases/C00_Template/` | yes | Protocol, role cards, templates |
| `.collab/cases/<CaseID>/` | no (git-ignored) | One event's tasks, findings and questions |
| `.collab/runtime/` | no (git-ignored) | Events, inboxes, watcher state, Race answers, MCP gate log |

Case data is event data: copy or archive it outside the repository after the event.

## Modules

| Module | Purpose |
|---|---|
| `python -m rangekit.collab.bus` | Create tasks, ACK / START / DONE / ERROR / QUESTION / REPLY events, inbox, status, `doctor`, and `mcp` calls |
| `python -m rangekit.collab.watch --session <Name>` | Watch one session's assigned tasks and events |
| `python -m rangekit.collab.host_watch` | Watch several sessions on one host and optionally run a worker command per handoff |
| `python -m rangekit.collab.race` | Race mode: `preflight`, `open`, `lane`, `answer`, `board`, `review-queue`, `metrics`, `close` |
| `rangekit.collab.protocol` | Shared task contract, paths and atomic writes |
| `rangekit.collab.mcp_calls` | Drive the MCP servers registered in [`rangekit/mcp/`](../mcp/README.md) as collab tool calls, behind the authorization gate |

```bash
python -m rangekit.collab.bus doctor                 # check templates, ignores and runtime state
python -m rangekit.collab.race preflight --case C01 --lead-session Lead --image <sample.E01>
python -m rangekit.collab.bus mcp list               # registered MCP servers and runtime readiness
```

`race preflight` runs `python -m rangekit.dfir.query preflight` before the clock starts (install the `dfir` extra first).

## Origin

Ported from `security/tools/` and `.collab/` in [sec-compendium](https://github.com/Youchenjiang/sec-compendium). MCP data moved from `.agent/mcp/` to `rangekit/mcp/`; credentials are read from the git-ignored `.env` instead of `secrets.env`.
