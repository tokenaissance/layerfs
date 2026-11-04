# SandboxComputePlane — diagrams for issue #545

Three Excalidraw scenes for **#545 · Sandbox compute plane: machines, backends,
observability and lifecycle**, following the model of #533. Every text element
and every shape/arrow label uses **Comic Shanns** (`fontFamily: 8`).

These are **v2 readability rebuilds**. GitHub renders an issue image at roughly
900 px wide, so the old 1880 px canvases shrank 26 px text to ~12 px. Each scene
is now laid out on a **1126–1202 px canvas** instead of a wide one, with title
38 px, panel labels 26 px and body 26 px (handoffs 24 px) — at ~900 px display
width body text lands at ~19–21 px. Layouts were reflowed, not scaled.

| Scene | Excalidraw id | Size (scene / PNG) | What it shows |
| --- | --- | --- | --- |
| `SandboxComputePlane — Architecture` | `1ccYgtDgv9j` | 1202×1024 / 1242×1064 | A 2-column grid. Top left **CONTROL PLANE**: `caller → layerfs-control → home` (one home: `machine/`, `store/`, `backup/`, no `platform/`, guest never reads it). Top right **MACHINES + WORKERS**: `MACHINE` (native / docker / VM kinds / ssh host) and `WORKER` (one per machine, starts on first call, idle stop; no host server in the data path). Bottom left **SANDBOX → BACKEND → GUEST**: one guest Workspace per Bash call, `machine/` host layer and `backend/` guest layer. Bottom right **STORE ROUTING**: SQLite on the Store kernel, PostgreSQL in the caller, routing by records, one VM machine many Stores. A full-width **OBSERVABILITY** strip previews `machine list/get`, `sandbox list/get`, `doctor` and worker health, bounded 2 s / 5 s and never starting a machine or Sandbox. |
| `SandboxComputePlane — Lifecycle` | `78G41Fbx0rs` | 1116×1020 / 1156×1060 | One vertical sequence with handoff callouts: `first call → machine.start → worker ready → sandbox.create → mount Workspace → exec Bash call → idle close`. Each handoff is annotated (picks a machine, starts the worker, loopback + secret, records the Sandbox, opens one Workspace, runs one Bash call). The failure strip records **no retry, no replay**, the `Unknown` error plus its log path, and `Unresolved` reconciled through `get` / `close`. |
| `SandboxComputePlane — Observability` | `73d51mJ58mV` | 1126×1000 / 1166×1040 | A 2×2 board: `machine list/get` (kind, state, worker, lease, health, one row per machine), `sandbox list/get` (state, project, machine, backend, mounts, one row per Sandbox), `doctor` (warnings only, never starts a machine, exit 0 on warnings) and `worker health` (lease, heartbeat, restart on lost lease, loopback only), each tagged **bounded ≤ 2 s get / ≤ 5 s list**. The bottom band states the read-only guarantee: it does not start a machine or Sandbox, a timeout is a warning, and `Unknown` is data, not a failure. |

The PNGs are rendered at `maxWidth: 1920`; each scene rendered twice with the
same bytes. The `.excalidraw` files are the `get_scene_content` JSON (live
elements).

These are documentation assets for the issue; no code or runtime behavior is
defined here.
