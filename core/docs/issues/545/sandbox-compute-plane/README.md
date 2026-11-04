# SandboxComputePlane — diagrams for issue #545

Three Excalidraw scenes for **#545 · Sandbox compute plane: machines, backends,
observability and lifecycle**, following the model of #533. Every text element
and every shape/arrow label uses **Comic Shanns** (`fontFamily: 8`).

| Scene | Excalidraw id | What it shows |
| --- | --- | --- |
| `SandboxComputePlane — Architecture: machines, backends, stores` | `1ccYgtDgv9j` | Caller → `layerfs-control`; one home (`machine/`, `store/`, `backup/`, no `platform/`); `native`/`docker` one each, VM kinds many, `ssh` host; worker on loopback with a secret, lease and health; Sandbox bound to one project and one machine; Backend as `machine/` host layer plus `backend/` guest layer; guest never reads the home. The store-routing band keeps SQLite on the Store kernel, PostgreSQL in the caller, and one VM machine holding many Stores. The observability band previews `machine list/get`, `sandbox list/get`, `doctor` and worker health. |
| `SandboxComputePlane — Lifecycle: create, exec, idle, close` | `78G41Fbx0rs` | Swimlanes for caller, control plane, machine + worker, sandbox + guest across five stages: first call, create, mount, exec, idle/close. It covers `machine.start`, `sandbox.create`, record writes under `machine/<machine>/sandbox/<name>/`, mount, launcher-owned exec (the daemon is not an exec supervisor), idle TTL and scratch cleanup. The failure band records `Unknown` with a log, and `Unresolved` reconciled through `sandbox get` / `sandbox close`; no retry, replay or busy handler. |
| `SandboxComputePlane — Observability: B8/B10/B9` | `73d51mJ58mV` | B8 read-only machine/sandbox inspect (state, project, machine, backend, image, capacity, mounted Workspaces, running command, recently closed); B10 doctor checks (docker engine/socket, machine kind/VM provider, sandbox image, mount driver, free disk, worker state/lease) as warnings only; B9 worker health (pid/starttime/lease, heartbeat, restart → reconnect or `Unresolved`, no hanging call). The bounds band adds 2s/5s queries, no hold on all 8 control slots, no side effects, precise `Unavailable`/`Capacity`, plus B5 idle close and B6 scratch cleanup. |

The PNGs are rendered at `maxWidth: 1920`; each scene rendered twice with the
same bytes. The `.excalidraw` files are the full `get_scene_content` JSON.

These are documentation assets for the issue; no code or runtime behavior is
defined here.
