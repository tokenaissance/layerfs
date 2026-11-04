# SandboxComputePlane — diagrams for issue #545 (v5)

Five Excalidraw scenes for **#545 · Sandbox compute plane**: the four-axis
model plus the provider / storage placement derived from
`compute-backend-providers-and-storage.md` and
`pi-durable-cloudflare-compute.md`.

| Axis | Layer |
| --- | --- |
| Abstraction | Machine → Sandbox → Backend |
| Isolation | process / container / VM / remote |
| Scheduling | Worker + long-lived Sandbox |
| Semantic boundary | Store / Commit / Branch + Workspace |

A Sandbox is an abstraction, not an isolation strength. `serverless` is
scheduling, not isolation. `process` is a Backend, not a separate top-level.
A **provider is a constructor, not a kind**: `Machine.kind` stays the
isolation class, `Machine.provider` is the implementation, and capability
flags decide Family 1 (our worker can run in the guest) versus Family 2
(SDK `remote-exec` only).

Three revision points from the cs-infra review are drawn here:

- **default isolation**: `sandbox.create` defaults to `docker`, `process` is
  opt-in, and a requested class that is not available is refused with
  `Unavailable` instead of downgraded; the Sandbox record keeps
  `requested_isolation` and `effective_isolation`;
- **close is a CAS protocol**: an active exec holds a lease deadline, close
  moves `Ready → Draining` by CAS on `generation`, and the outcome is
  `Closed` or `Lost` — never a blind kill;
- **the storage-placement guard is 2.0.0**: `StoragePlacement` refusal, no
  live remote SQLite and no object storage as a live Store belong to this
  version, while the provider adapters are future work.

Every text element and every shape label uses **Comic Shanns**
(`fontFamily: 8`); body text is 26 px and titles are 38 px. The Architecture
scene also carries one 18 px note badge (`provider = constructor, not kind`)
in the `MACHINES + WORKERS` header; every other text is 26 px or 38 px.

| Scene | Excalidraw id | What it shows |
| --- | --- | --- |
| `SandboxComputePlane — Architecture: machines, backends, stores` | `1ccYgtDgv9j` | Two-column architecture: caller / `layerfs-control` / one home (`machine/`, `store/`, `backup/`, no `platform/`) beside machines and workers; Sandbox → Backend → Guest with four backend cards and isolation badges (`native [process]`, `docker [container]`, `VM [VM]`, `ssh [remote]`), a `sandbox record: requested / effective` line for the isolation fields, and a **DEFAULT ISOLATION** badge (`docker default`, `opt-in only`, `mismatch → Unavailable`); store routing keeps SQLite on the Store kernel, PostgreSQL in the caller, and one VM machine holding many Stores. The bottom **Four axes** strip separates abstraction, isolation, scheduling and semantic boundary, with a red note: *serverless is not isolation · process = backend · semantics do not change*. A small header note says *provider = constructor, not kind*. |
| `SandboxComputePlane — Lifecycle: create, exec, idle, close` | `78G41Fbx0rs` | A dashed boundary separates **Agent runtime** (outside the compute plane: step / serverless / queue) from the **Compute plane**: first call → `machine.start` → worker ready → `sandbox.create` → mount Workspace → exec Bash call → **exec receipt**, then the **close protocol**: `exec lease` (an active exec holds a deadline) → `Draining` (CAS on generation, no new exec) → `check lease` (generation stale?) → `close / abort` (no blind kill) → `Closed | Lost` (lease expiry → `Lost`). A side panel states that `exec_async` / `exec_wait` / `exec_status` are launcher-owned, not the daemon; another states there is no serverless backend. Failure is `Unknown` + log, `Unresolved` via `get` / `close`, with no retry or replay. |
| `SandboxComputePlane — Observability: B8/B10/B9` | `73d51mJ58mV` | Four read-only cards. `machine list/get` now includes `isolation` and `scheduling`; `sandbox list/get` now includes `backend` and `isolation`; `doctor` checks backend isolation capability (`capability, not "is Docker"`) instead of testing for Docker; worker health covers lease, heartbeat and restart. The bottom band records bounded queries, no start side effects and data-not-error handling. |
| `SandboxComputePlane — Isolation & Semantics Matrix` | `75beQrV0BBW` | A six-column table — backend, isolation, kernel, guest no home, Workspace semantics, Commit semantics — across `native/namespaces`, `docker`, `VM` and `ssh`. Isolation strength and kernel sharing differ; guest-never-reads-home and LayerFS semantics are `yes` / `same` on every row. Closing line: *Isolation changes the strength. Semantics stay the same.* |
| `SandboxComputePlane — Provider & Storage Placement` | `1mGJ8A18D9h` | Top band splits **2.0.0 GUARD** (`StoragePlacement`, no live remote SQLite, no S3 live Store) from **FUTURE ADAPTERS** (Fly, E2B, Cloudflare, Modal, Daytona, K8s, Fargate, ssh). Left: provider constructor → `Machine.kind` (isolation) + `Machine.provider` (implementation) + capability flags, then Family 1 (`worker/mount`) vs Family 2 (`remote-exec`). Centre: provider matrix for Fly, E2B, Cloudflare, Modal, Daytona, K8s, Fargate and ssh/VM with family, worker, mount, local SQLite and live PostgreSQL. Bottom left: storage placement — PostgreSQL live, Family 1 machine-local SQLite live, SQLite snapshot handoff, R2/S3 backup only, and a red **no live remote SQLite / no S3 as a live Store** bar. Bottom right: pi-durable borrow strip — intent before side effect, durable timer shape without DO, manifest snapshot, cancel by id with `TimedOut ≠ Cancelled`, identity in one place. |

## Rendering

All scenes were rendered twice at `maxWidth: 1250`; the two PNGs of each scene
are byte-identical. The `.excalidraw` files are the full `get_scene_content`
documents for the live scene elements.

| Scene | PNG | Canvas | PNG size | PNG sha256 (first 12) |
| --- | --- | --- | --- | --- |
| Architecture | 1243 × 1060 | 1202.7 × 1019.5 | 345,722 B | `46af45a2df71` |
| Lifecycle | 1220 × 983 | 1180 × 943 | 293,371 B | `a025208625f4` |
| Observability | 1166 × 1040 | 1126 × 1000 | 182,726 B | — |
| Isolation & Semantics Matrix | 1242 × 703 | 1202 × 662.5 | 127,993 B | — |
| Provider & Storage Placement | 1240 × 1057 | 1200 × 1017.3 | 332,600 B | `f85d8e0a0bf4` |

These are documentation assets for the issue; no code or runtime behavior is
defined here.
