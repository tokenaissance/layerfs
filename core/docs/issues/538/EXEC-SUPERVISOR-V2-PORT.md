# Exec supervisor (#538) — port to `layerfs_v2_0_0`: analysis and blockers

**Status:** no port. The supervisor work does not apply to `layerfs_v2_0_0`
(`d2c3f2c97`) as a cherry-pick or as a mechanical adaptation; it needs a v2
design. This branch (`feat/exec-supervisor-v2`, from `d2c3f2c97`) carries only
this record. No upstream branch was pushed and no pull request was opened.

- Source work: `feat/exec-supervisor-skeleton`, PR #542 (draft, base `main`),
  commits `a20f5ae81` (skeleton), `df60ad8ef` (modular doc), `cab2199e4`
  (presence/registry decisions), on #499 (`8545a284f`, `6554e7fdb`,
  `386f1b227`).
- The v2 tree already has a mount-namespace exec seam, and it is a different
  one, so #499 is not a prerequisite here; it is superseded.

## What v2 already has

v2 does not run commands through the daemon; it runs them through the Sandbox
runtime owner, and a namespace Sandbox's helper already joins the Sandbox's
namespaces:

| Concern | v2 location |
| --- | --- |
| Command API (`workspace.exec`) | `api/crates/layerfs-control/src/sandbox/exec.rs` — "the daemon is not involved" |
| Launcher (owns stdio, exit) | `api/crates/layerfs-control/src/sandbox/runtime.rs` `run` -> `layerfs_sandbox::Sandbox::run` |
| Namespace backend's one command | `connect/crates/layerfs-sandbox/src/backend/namespaces/exec.rs` |
| Helper that enters the namespaces | `connect/crates/layerfs-sandbox/src/bin/layerfs-sandbox-helper/exec.rs` (`exec --init <pid> --cgroup <dir> --uid --gid --cwd -- …`) |
| Namespace owner | the helper's own `init` stage (`init`/`init-inner`), not the daemon |

The helper opens `/proc/<init>/ns/{mnt,pid_for_children,ipc}`, `setns`es into
all three, and spawns the command. The namespace owner is the helper's init
process, which the launcher can inspect. That is why v2 needs no
`SCM_RIGHTS` handoff: #499's rationale — the daemon is `set_dumpable(false)`
(`engine/crates/layerfs-daemon/src/application/config.rs`), so root in the
Sandbox cannot open `/proc/<daemon>/ns/mnt` — does not apply when the
namespace owner is not the daemon.

v2's rules state the same boundary: `engine/AGENTS.md` §"Filesystem access and
execution ownership" says "the daemon has no exec/supervisor, launcher mode,
per-Exec cgroups, command registration or custom Exec stream/status/
cancellation protocol", and
`engine/crates/layerfs-daemon/src/application/mod.rs` is documented as
"Production direct-Store daemon startup/control, with no command supervisor".

## Why the commits do not apply

Cherry-picking on `d2c3f2c97`:

| Commit | Result |
| --- | --- |
| `8545a284f` (#499 ns-exec) | 9 content conflicts, 7 modify/delete conflicts: `engine/crates/layerfs-api/**` is `api/crates/layerfs-control/**` in v2, `engine/crates/layerfs-node/**` is `api/crates/layerfs-node/**`, `engine/crates/layerfs-sandbox/**` is `connect/crates/layerfs-sandbox/**`; `api/crates/layerfs-control/src/sandbox/exec.rs` still exists but is now the launcher call, not a daemon route |
| `6554e7fdb` (SCM_RIGHTS handoff) | inapplicable: no daemon namespace owner and no `/proc` dumpability problem; the v2 helper opens the handles itself |
| `386f1b227` (fmt/clippy/guard) | inapplicable except as style on already-ported files |
| `a20f5ae81` (skeleton) | modifies/deletes `engine/crates/layerfs-daemon/src/application/ns_fd.rs` (absent in v2), and conflicts in the daemon `Cargo.toml`, `cli.rs` and `mod.rs`; it adds daemon-side `ns_exec_control`/`ns_exec_supervisor` and a `layerfs-daemon` binary mode |
| `df60ad8ef`, `cab2199e4` (docs) | apply, but describe a daemon-owned supervisor that v2 forbids |

So a cherry-pick would either resurrect the #499 daemon seam that v2 removed,
or land a supervisor stage the daemon may not own.

## Why it is more than a path/API move

The skeleton's process model does not map onto v2's namespace backend:

1. **PID namespace.** `setns(CLONE_NEWPID)` applies only to processes created
   afterwards, so v2's helper enters `pid_for_children` and then *spawns* the
   command. #538's child `exec`s in place, so it can only join the mount
   namespace. A v2 supervisor would need a forked command, which changes the
   session model: `Started { pid, pgid }`, `Signal { signo }`,
   `group_alive` and the `PDEATHSIG` chain would report the launcher process,
   not the command, or need new plumbing to learn the command's pid.
2. **One command, not a session.** v2 `exec` is synchronous ("one command to
   its end"), with `spool` output and a single exit code. No v2 route keeps a
   session alive after the command returns, so a control socket has no caller,
   and #538's P1–P3 (daemon session registry, presence, reconnect/background)
   are refused by the v2 ownership rule above.
3. **Ownership.** In v2 the launcher (`layerfs-control` -> `Sandbox::run`)
   owns stdio, exit status and cancellation; the daemon owns only the
   filesystem. #538's control socket is a second status/cancellation channel
   and its lifecycle decisions were written for daemon ownership.

## Recommendation

- Keep #542 on `main` for the 1.x line: it is coherent with #499 and should
  not be closed as superseded by a v2 port that does not exist. #543 and the
  v2 branch head are untouched.
- Do not port #499 to v2: v2's helper seam supersedes it.
- For 2.0, treat an exec session as a *launcher* feature, not a daemon one.
  A v2 design would add a `supervise` stage to
  `layerfs-sandbox-helper` that (a) opens `/proc/<init>/ns/*` itself, (b)
  spawns a child that enters mount/IPC and `pid_for_children`, then spawns
  the command as its own group, (c) owns the control socket and reports the
  launcher's pid/pgid, and (d) declares explicitly that the session ends with
  the command. That is a redesign of the session/identity contract, and it
  should be a new issue rather than a port of #538.
