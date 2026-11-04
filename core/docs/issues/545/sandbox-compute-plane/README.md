# SandboxComputePlane — diagrams for issue #545 (v3)

Four Excalidraw scenes for **#545 · Sandbox compute plane**, updated to the
four-axis model:

| Axis | Layer |
| --- | --- |
| Abstraction | Machine → Sandbox → Backend |
| Isolation | process / container / VM / remote |
| Scheduling | Worker + long-lived Sandbox |
| Semantic boundary | Store / Commit / Branch + Workspace |

A Sandbox is an abstraction, not an isolation strength. `serverless` is
scheduling, not isolation. `process` is a Backend, not a separate top-level.
Every text element and every shape label uses **Comic Shanns**
(`fontFamily: 8`); body text is 26 px and titles are 38 px.

| Scene | Excalidraw id | What it shows |
| --- | --- | --- |
| `SandboxComputePlane — Architecture: machines, backends, stores` | `1ccYgtDgv9j` | Two-column architecture: caller / `layerfs-control` / one home (`machine/`, `store/`, `backup/`, no `platform/`) beside machines and workers; Sandbox → Backend → Guest with four backend cards and isolation badges (`native [process]`, `docker [container]`, `VM [VM]`, `ssh [remote]`); store routing keeps SQLite on the Store kernel, PostgreSQL in the caller, and one VM machine holding many Stores. The bottom **Four axes** strip separates abstraction, isolation, scheduling and semantic boundary, with a red note: *serverless is not isolation · process = backend · semantics do not change with backend*. |
| `SandboxComputePlane — Lifecycle: create, exec, receipt, idle close` | `78G41Fbx0rs` | A dashed boundary separates **Agent runtime** (outside the compute plane: step / serverless / queue) from the **Compute plane**: first call → `machine.start` → worker ready → `sandbox.create` → mount Workspace → exec Bash call → **exec receipt** → idle close. A side panel states that `exec_async` / `exec_wait` / `exec_status` are launcher-owned, not the daemon; another states there is no serverless backend. Failure is `Unknown` + log, `Unresolved` via `get` / `close`, with no retry or replay. |
| `SandboxComputePlane — Observability: B8/B10/B9` | `73d51mJ58mV` | Four read-only cards. `machine list/get` now includes `isolation` and `scheduling`; `sandbox list/get` now includes `backend` and `isolation`; `doctor` checks backend isolation capability (`capability, not "is Docker"`) instead of testing for Docker; worker health covers lease, heartbeat and restart. The bottom band records bounded queries, no start side effects and data-not-error handling. |
| `SandboxComputePlane — Isolation & Semantics Matrix` | `75beQrV0BBW` | A six-column table — backend, isolation, kernel, guest no home, Workspace semantics, Commit semantics — across `native/namespaces`, `docker`, `VM` and `ssh`. Isolation strength and kernel sharing differ; guest-never-reads-home and LayerFS semantics are `yes` / `same` on every row. Closing line: *Isolation changes the strength. Semantics stay the same.* |

## Rendering

All scenes were rendered twice at `maxWidth: 1920`; the two PNGs of each scene
are byte-identical. The `.excalidraw` files are the full
`get_scene_content` documents (live elements only).

| Scene | PNG | Scene canvas | PNG size |
| --- | --- | --- | --- |
| Architecture | 1256 × 1057 | 1215.6 × 1016.5 | 325,525 B |
| Lifecycle | 1220 × 919 | 1180 × 878.5 | 246,282 B |
| Observability | 1166 × 1040 | 1126 × 1000 | 182,726 B |
| Isolation & Semantics Matrix | 1242 × 703 | 1202 × 662.5 | 127,993 B |

These are documentation assets for the issue; no code or runtime behavior is
defined here.
