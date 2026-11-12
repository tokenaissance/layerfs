# D1 — the `namespaces` backend has no network namespace: a guest reaches the host worker control port

Status: **defect analysis + a bounded prototype of the network-namespace part**
(prototype Commit `12fd0ddb`; this document is a later docs Commit on
`agent-d1-net`).
It reproduces D1 from `core/docs/issues/545/ACCEPTANCE-V2.md` on the same real
`ssh` machine, and it changes only the helper's exec stage
(`connect/crates/layerfs-sandbox/src/bin/layerfs-sandbox-helper/exec.rs`).
The prototype is **typechecked, never executed**: no test, no acceptance run and
no exploit is claimed. It lands on Branch `agent-d1-net` (forked from
`main@62b1b982f7e1`); `main` is untouched.

| Field | Value |
|---|---|
| Finding | D1 in `core/docs/issues/545/ACCEPTANCE-V2.md` (branch `agent-accept545`, head `1275f0bf`; file snapshot `agent-accept545@75f0bfa45a94`): "The `namespaces` backend has no network namespace; the guest can reach host services (highest impact)" |
| Machine | `aluminium` — `platform: ssh`, `backend: namespaces`, `100.117.34.99`, root `/layerfs/data`, kernel `6.14.0-29-generic` |
| Sandbox | `d1net` — `runtime: namespaces`, `backend: namespaces`, `route: fuse`, image `sha256:265bfe946bf7e916b93f8d500bef0e642687e36cd7661843eb8fcfdf999dfb32` |
| Store | `dell` (sqlite, on `aluminium`) |
| Client binary | `layerfs 2.0.0`, `sha256 b79ff7b5169dd4b73a212b68b9c5274d0dcdc6f55ff12dfb38ed12a84cb1d743` — the same binary ACCEPTANCE-V2 measured |
| Guest time of these checks | 2026-11-06, `Fri Nov  6 04:19:35 UTC 2026` |
| Guest identity | Debian 12 userland on the Dell kernel; `uid=501`, `gid=20(dialout)`, `CapEff=0`, `NoNewPrivs=1` |

One other agent's Sandbox shared the machine during the run (`e2e551` was
created 77 s after `d1net`), so the cross-Sandbox part of §1.3 is a fact of this
run, not a theory.

## 1. Reproduction and failure mode

### 1.1 The namespace set the helper creates (read before probing)

The whole defect is visible in one line each (line numbers of the branch base,
before the §4 patch):

- `init.rs:26` — the outer init stage creates **mount, PID and IPC** only:
  `unshare(CloneFlags::CLONE_NEWNS | CloneFlags::CLONE_NEWPID | CloneFlags::CLONE_NEWIPC)`.
- `exec.rs:71-93` — a command's helper opens `mnt`, `pid_for_children` (or
  `pid`) and `ipc` and enters them; no network namespace is opened, created or
  entered.
- `host.rs:16-71` — the runtime's host prerequisites are root, user namespaces
  blocked, cgroup v2, `/dev/fuse`, and an overlay-capable runtime root. None of
  them concerns the network.
- `provider.rs:4-5` — the backend's stated premise: "The VM that holds this
  kernel is the boundary; the namespaces keep Sandboxes on one Store out of each
  other." On an `ssh` machine the premise does not hold: the host that runs the
  kernel also runs the Store, the worker and every Sandbox.

### 1.2 Probes run inside the `d1net` Sandbox

Each is one `layerfs workspace exec` (the harness wrapper adds nothing but
`CARGO_HOME`). Output abridged where marked.

```text
$ readlink /proc/self/ns/net
net:[4026531840]
```

`4026531840` is the inode the kernel gives its **initial** network namespace.
`/proc/1/ns/net` and `/proc/2/ns/net` (the helper init stage and the daemon, both
root) are not readable by uid 501 (`rc=1`), so the guest cannot compare against
a host process directly. The socket table below is the decisive evidence.

```text
$ command -v ip; command -v ss; command -v nc
ip-absent
ss-absent
nc-absent
```

(The image has no networking tools, which is why every probe uses `/proc` and
`bash`'s `/dev/tcp`.)

```text
$ cat /proc/net/dev
Inter-|   Receive ... |  Transmit ...
    lo:  907121    3842 ...
  eno3:       0       0 ...
  eno4:       0       0 ...
  eno1: 5392687   23121 ...
  eno2:       0       0 ...
tailscale0:     965       6 ...
docker0:       0       0 ...
```

The guest sees the **host's** interfaces — the Dell's four NICs, its Tailscale
interface and its Docker bridge — not the single `lo` of a private namespace.

```text
$ cat /proc/net/route
Iface  Destination Gateway  Flags RefCnt Use Metric Mask     MTU ...
eno1   00000000    011FA8C0 0003  0      0   100    00000000 ...
docker0 000011AC   00000000 0001  0      0   0      0000FFFF ...
eno1   001FA8C0    00000000 0001  0      0   100    00FFFFFF ...
```

The guest also reads the host's default route (`192.168.31.1`, little-endian
`011FA8C0`) and its Docker bridge route.

```text
$ grep -E '^(Uid|Gid|CapEff|NoNewPrivs):' /proc/self/status
Uid:	501	501	501	501
Gid:	20	20	20	20
CapEff:	0000000000000000
NoNewPrivs:	1
```

No capability, so the guest can neither create a network namespace of its own
(also `user.max_user_namespaces=0`, ACCEPTANCE-V2 C26) nor open a raw socket to
sniff this shared stack.

```text
$ cat /proc/net/tcp      (local_address column, port as hex; abridged)
0100007F:B3CD 00000000:0000 0A  uid 0     <- 127.0.0.1:46029  consistent with Sandbox e2e551's daemon control port (one forward targets it)
0100007F:8D63 00000000:0000 0A  uid 0     <- 127.0.0.1:36195  this Sandbox's daemon control port
63227564:856B 00000000:0000 0A  uid 0     <- 100.117.34.99:34155
3600007F:0035 00000000:0000 0A  uid 991   <- 127.0.0.54:53  systemd-resolved
3500007F:0035 00000000:0000 0A  uid 991   <- 127.0.0.53:53  systemd-resolved
00000000:0016 00000000:0000 0A  uid 0     <- 0.0.0.0:22     sshd
0100007F:0277 00000000:0000 0A  uid 0     <- 127.0.0.1:631   (a host service; not attributed)
0100007F:1B9E 00000000:0000 0A  uid 0     <- 127.0.0.1:7070  the machine worker control port
```

Every host listener, including the LayerFS worker (`7070`), both Sandboxes'
daemon control ports (`36195`, `46029`), the host sshd and the resolver, is
listed in the guest's own `/proc/net/tcp`.

```text
$ timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/7070'; echo "worker7070_connect_rc=$?"
worker7070_connect_rc=0
```

A bounded TCP **connect** to the host worker control port succeeds. No byte is
written to the socket (the connection is opened and the shell exits). Same probe,
same result, for `127.0.0.1:22` (`sshd22_connect_rc=0`) and for this Sandbox's own
daemon control port `127.0.0.1:36195` (`p36195_connect_rc=0`). The other
Sandbox's daemon port `46029` was left alone: the same code path applies, but
probing another agent's Sandbox was not necessary.

The decisive observation is that both ends of the connection appear in the table
the guest reads, in one TCP stack:

```text
0100007F:1B9E 0100007F:C764 01  uid 0     <- the worker's accepted side
0100007F:C764 0100007F:1B9E 01  inode 16827  <- the guest's connecting side
```

The accepted end is owned by uid 0 (the worker). The connecting end is the
guest's. There is no name-space boundary between them.

Host-side context (client `ps`, same session): `ssh -L` forwards carry both
LayerFS services from the Dell's loopback to the client:

```text
-L 127.0.0.1:59366:127.0.0.1:7070    the machine worker (spec.rs:11 WORKER_PORT = 7070)
-L 127.0.0.1:59460:127.0.0.1:36195   this Sandbox's daemon control port
-L 127.0.0.1:60176:127.0.0.1:46029   a second Sandbox's daemon control port (e2e551, created during the run)
```

So the two control surfaces under discussion are, by design, loopback TCP
services on the machine: the worker's (`7070`) and one per Sandbox daemon
(`setup/forward.rs::daemon`, `#535 G4`).

`lo` byte counters before and after the connects (`921661` → `921989`) are
consistent with shared loopback but are not offered as proof: the host's own
loopback traffic moves those counters too. The socket-pair evidence above is the
proof.

### 1.3 Failure mode

The Sandbox's untrusted execution context — every `workspace exec` command — has
the **host's network identity**: the Dell's interfaces, routes, Tailscale address
and loopback. Consequences, separated by what is observed and what is inferred:

1. **Observed:** any host-local TCP service is reachable, including the LayerFS
   worker control port, the host sshd, the resolver, the CUPS port, and every
   Sandbox daemon control port on the machine. The `namespaces` backend is not a
   network-security boundary on an `ssh` machine.
2. **Observed:** a second tenant's control surface is visible from inside the
   first tenant's Sandbox (`127.0.0.1:46029`, consistent with `e2e551`'s daemon,
   in `d1net`'s socket table). One Sandbox can attempt another's daemon control
   port for the same reason it can reach `7070`.
3. **Read from code, not exercised:** both control surfaces authenticate. The
   worker's first frame is a secret read from a `0600` root file
   (`setup/worker.rs::hello`, `/layerfs/state/secret`, mode `0700` directory); the
   daemon's control transport takes `setup.private_key` and `setup.control_peer`
   (`engine/crates/layerfs-daemon/src/application/connection.rs:117`). The guest
   uid 501 cannot read either (the Sandbox's `config/` is `0700 root`; ACCEPTANCE-V2
   C22 shows `Permission denied`; `/layerfs/state` does not exist in the guest at
   all — verified again in this run). So what this run demonstrates is
   **reachability without defence in depth**, not an authentication bypass.
4. **Inferred, unverified:** a listener the guest creates on host loopback would
   race any loopback port the client's `ssh -L` forward targets while the
   legitimate listener is down, and would receive the worker's secret in the
   hello frame. The guest also holds the same stack as every unauthenticated host
   service (the resolver at `:53`). No bind and no such race was attempted here.
5. **Why documentation is not enough (see option (c)):** the backend's premise is
   a VM boundary; `aluminium` is not a VM. The Store is a directory on the same
   host, and ACCEPTANCE-V2 D2 shows the Store directory is bind-mounted into the
   guest, with POSIX mode as its only protection. The network boundary is the
   missing layer that would keep a future Store-mode or capability regression
   from being reachable across this host.

## 2. Options

All three sit in **Frameworks & Drivers** / adapter code: nothing in Entities or
Use Cases says which namespaces a Sandbox command has. The options differ in how
far the change leaks into the persisted record and the client transport.

### (a) `CLONE_NEWNET` + veth pair with port forwarding

Create a veth pair per Sandbox: the host side lives in the host namespace, the
guest side is moved into the Sandbox's new network namespace. Give the pair an
address (`/30` or `/32` per Sandbox), make the daemon bind the guest side (or
proxy its control port into the namespace), and point the client's `ssh -L`
target at the host side. Egress requires NAT on the host (`iptables`/`nft`), or
is cut.

Not adapter-local:

- `Sandbox::endpoint()` returns `SocketAddr::from((Ipv4Addr::LOCALHOST, port))`
  (`namespaces/sandbox.rs:203-217`), and `LocalRecord.port` is a `u16`
  (`types/`), persisted in the Store and bound by the Node SDK. A veth address is
  not `127.0.0.1`, so the record and the wire contract change.
- The client's `ssh -L` target becomes the host-side veth address, and the
  machine adapter (`connect/crates/layerfs-machine`) changes with it.
- The helper must create the veth and link it (netlink, or `unsafe` ioctls) —
  the helper is `#![deny(unsafe_code)]`, so this is netlink-in-safe-Rust work, or
  a deliberate `allow`.
- Per-Sandbox addressing, conntrack, NAT rules and cleanup enter the sandbox
  lifecycle, and the egress policy becomes a product decision.

Cost: L. It buys command egress if that is wanted; it pays for it in record and
transport changes.

### (b) Loopback-only network namespace with a Unix-socket control transport

Give the Sandbox a network namespace whose only interface is `lo`; the daemon
moves into that namespace and listens on an `AF_UNIX` socket under the Sandbox
directory (`<sandbox>/config/`, `0700 root`), which is bind-mounted at its own
path on both sides and therefore visible to the host-side worker without any
interface. The client's transport becomes an SSH StreamLocal forward (or a
host-side proxy); `DaemonSetup.listen` (an `IpAddr`) becomes a socket address
enum; `LocalRecord.port` becomes a path or address; the daemon, bridge wire and
client SDK all change together.

Cost: L, and it is a **transport change**: it re-decides how the client reaches
the daemon. It is the clean end state if the daemon itself must be inside the
Sandbox boundary, because a Unix socket cannot be reached from a shared network.

### (b′) Per-command network namespace; the daemon's control path untouched

The helper's exec stage creates the command's own network namespace after
entering the Sandbox's mount, PID and IPC namespaces. No interface is moved in,
so the command has no path to any host service; `lo` is down, so it also has no
loopback. The **daemon stays in the host network namespace** (it is started by
the inner init stage before any namespace is created for the command), so:

- the worker keeps `127.0.0.1:<daemon port>` and `endpoint()` needs no change;
- `ssh -L 127.0.0.1:<local>:127.0.0.1:<daemon port>` keeps working;
- `LocalRecord.port`, `SandboxRecord` and the Node binding are unchanged;
- nothing is added: no service, no module, no new public type.

The cost is semantic, and it must be recorded:

- a command gets **no network at all**, including loopback, until a later stage
  brings `lo` up (slice 2 in §4);
- the namespace is per command, not per Sandbox, so two commands cannot reach
  each other's loopback listeners. v2 has no facility to expose a guest port, so
  nothing regresses today, but this is a decision, not an accident;
- the daemon process itself remains on the host stack. It is not reachable by the
  guest (the guest's only path to it was the network), but it stays host
  network-namespaced. That is explicit decision D1-D1 below.

This is the option this branch prototypes, because it is the smallest change that
removes the reachability D1 reports while preserving the daemon/worker control
path by construction.

### (c) Shared network and a documented local trust boundary

Rejected. It does not fix a defect; it asks a promise the product cannot keep for
this machine class:

- The only invariant that makes D1 acceptable is "an untrusted Sandbox command
  cannot reach a host control surface". Option (c) says that invariant does not
  hold for the `namespaces` backend. Since `aluminium` is also the Store host and
  the control-plane host, and the Store directory is already mounted into the
  guest (D2), the remaining defence is a shell of documentation around services
  the guest can reach.
- The backend's own premise ("the VM that holds this kernel is the boundary") is
  false for an `ssh` machine: no per-machine VM is created, so "the boundary" is
  the machine's own network.
- An `ssh` machine is a supported placement (`machine platforms` reports it
  `ready`), so documenting the gap would ship a machine class with a weaker
  security property than the docs claim.

Rejecting (c) does not mean hiding the fact: `PROVIDERS.md` must state the
namespace set and which boundary the daemon is inside (§5).

## 3. Clean-architecture / cs-infra verdict

### Layer map (what owns D1)

| Layer | Contents here | D1 relevance |
|---|---|---|
| Entities | Workspace, Branch, Commit, Store, Sandbox identity (`core/crates/layerfs-*`) | untouched |
| Use cases | launch / mount / exec / commit / teardown lifecycle (`api/crates/layerfs-control`, `connect/crates/layerfs-machine`) | untouched |
| Interface adapters | `Runtime`/`Provider` ports, `Sandbox`, `LaunchRequest`, records, and the `namespaces`/docker/ssh adapters (`connect/crates/layerfs-sandbox/src/backend/*`) | the adapter's *contract* (which namespaces the runtime owns) is incomplete: `provider.rs:1-5`, `host.rs`, and the helper's `init.rs`/`exec.rs` |
| Frameworks & Drivers | `layerfs-sandbox-helper` (unshare/setns/cgroup/overlay/pivot), `layerfs-daemon`, Docker, `ssh` | **the defect lives here** |

Dependency direction after the prototype: unchanged.
`helper` (F&D) ← `backend/namespaces` (adapter) ← `Runtime` (port) ← control API
(use case). The prototype adds one call to an already-imported crate (`nix`,
feature `sched`) inside the helper's exec stage; it adds no dependency, no
service and no abstraction, and it changes no type, no record and no use case.

Cross-boundary warning: options (a) and (b) are **not** adapter-local. Both
change the persisted record (`LocalRecord.port: u16`), and (b) changes the
daemon's setup (`DaemonSetup.listen: IpAddr`) and the machine's transport. Those
are Interface-Adapter/wire contracts shared with the Store and the Node SDK, so
they need a decision record, not a patch inside this backend.

### Anti-over-engineering check (Musk's order: question, delete, simplify, accelerate, automate)

- *Question*: does a Sandbox command need any network today? No launch or exec
  option in this tree publishes a guest port or promises command egress; the
  acceptance probes that used the network were checking the host, not using it.
- *Delete*: delete the exposure first — a network namespace costs four lines and
  no new component. Building veth + NAT first would add host networking policy to
  serve a requirement nobody has stated.
- *Simplify*: keep the daemon on the control path it already has. Moving it into
  the namespace (a) or to a Unix socket (b) forces record and transport changes
  for an isolation gain the guest cannot exploit through the daemon's
  key-authenticated listener.
- *Accelerate / automate* only after a decision: lo-up (slice 2) and a sandbox-wide
  namespace (slice 3) are the next lever if loopback or egress is required.

### Verdict

- **Severity: P1.** A security invariant between the untrusted command and the
  host control plane is absent, and there is no defence in depth behind it, on a
  machine class that is `ready`. It is not P0 in this evidence tier: no traffic
  was sent, no authentication was attempted and neither control surface is
  reachable without its key/secret (read from code). It becomes P0 if a handshake
  weakness exists (a secret leak or a worker/daemon authentication bypass) or if
  a second tenant is the threat — and a second tenant was already present on this
  machine during the run, which is why P1 and not "informational".
- **Evidence tier: T1 — runtime-observed reachability.** Direct observation on
  the real v2 binary, the real `ssh` machine and a real Sandbox: shared initial
  network namespace, host interfaces and routes, host listener table, and a
  successful TCP connect to the worker's control port, with both ends of that
  connection in the one table the guest reads. Not T2 (no unauthorised action was
  carried out) and not T0 (more than a code read).
- **Smallest next action:** land (§4 slice 1) the helper's per-command network
  namespace on a branch and verify it on a host with a Linux toolchain, then
  re-run ACCEPTANCE-V2 C31 from a rebuilt bundle and require a non-zero connect
  result; record decisions D1-D1 and D1-D2; add the namespace set to
  `PROVIDERS.md`. Do not start (a) or (b) before those decisions.

## 4. Recommended option and implementation sketch

**Recommendation: (b′) now; decide the daemon's namespace and command egress
later.** It removes D1's reachability with an adapter-local change and leaves the
daemon/worker control path exactly as it is, which is what the task asks for.
(a) and (b) stay open, but only for a stated requirement (command egress, or a
daemon that must be inside the Sandbox boundary), never as a side effect.

### Slice 1 — applied on this branch (Commit `12fd0ddb`; typechecked, not run)

`bin/layerfs-sandbox-helper/exec.rs`: after the helper has opened and entered the
Sandbox's mount, PID and IPC namespaces, and before it drops no-new-privs, it
creates the command's own network namespace. A setup failure takes the existing
`fail` path (raise `SIGKILL`), so it is never read as the command's exit code —
the module's own rule.

```rust
    let namespaces = Namespaces::open(run.init)?;
    namespaces.enter()?;
    // the command's own network namespace, empty: the command inherits
    // no interface of this host, so it reaches no host service -- the
    // worker's control port included. `lo` stays down; a command that
    // needs loopback must be given one by a later stage, never this
    // host's stack.
    if let Err(error) = unshare(CloneFlags::CLONE_NEWNET) {
        // a setup failure must never look like the command's exit code
        fail(&format!("creating the command's network namespace: {error}"));
    }
    set_no_new_privs().map_err(|error| format!("setting no-new-privs: {error}"))?;
```

plus the import (`sched::{setns, unshare, CloneFlags}`) and the module doc. Why
this location:

- the exec stage already runs as root with `CAP_SYS_ADMIN` (the same process that
  joins the cgroup and `setns`es into the Sandbox), so `CLONE_NEWNET` needs no
  new privilege and no new host check;
- `unshare`/`setns` are already the helper's idiom and `nix` is the crate's only
  dependency, so no `unsafe` is needed (the helper is `#![deny(unsafe_code)]`);
- the namespace dies with the last process that holds it — no cleanup, no record,
  no reopen path;
- the daemon and the worker are not touched, so `endpoint()`, `LocalRecord`,
  `SandboxRecord`, the daemon setup and the `ssh -L` transport are unchanged.

### Slice 2 — loopback for commands (not done)

If commands need `localhost` (test runners, a local server, a resolver stub),
bring `lo` up inside the new namespace: an `RTM_NEWLINK` netlink message in the
helper (safe Rust, ~60 lines), because `#![deny(unsafe_code)]` rules out the
`SIOCSIFFLAGS` ioctl unless a deliberate `#[allow(unsafe_code)]` is accepted.
That is a small adapter addition, not a transport change.

### Slice 3 — only if a decision says so

- a Sandbox-wide namespace owned by the inner init stage (PID 1), with the daemon
  re-joined to the host namespace — needs `fork`/`pre_exec` (`unsafe`) or a
  recorded namespace owner, because the daemon is spawned by the same stage that
  would create the namespace;
- or (a) veth + port-forward + egress policy;
- or (b) Unix-socket control + a client transport change.

### Decisions to record (do not implement here)

- **D1-D1 — does the daemon leave the host network namespace?** Proposed for v2:
  **no**. It listens on loopback only, authenticates the control transport with a
  private key from a `0600` file in a `0700` directory, and its port is the target
  of the client's `ssh -L`. Moving it is (b), a transport change, and should be
  driven by a requirement (multi-tenant daemon isolation or a Store mode that
  makes the daemon attacker-reachable), not by this finding.
- **D1-D2 — do command processes get egress?** Proposed: **no** until a feature
  needs it and a policy exists (allow-list/NAT/proxy is a product decision, not an
  adapter default). With slice 1, `exec` is offline; that must be stated where
  Sandboxes are documented.
- **D1-D3 — per-command or per-Sandbox namespace?** Proposed: per-command now;
  promote to per-Sandbox (slice 3) only when cross-exec loopback or a
  Sandbox-wide egress policy is required.

### What was verified about the prototype — and what was not

The patch was applied to a local copy of the Branch base (the crate files
`exec.rs`, `init.rs` and `helper_spec.rs` were byte-identical to
`/tmp/layerfs-v2-clean` before the patch) and typechecked for the Linux target on
the macOS client:

```console
$ rustup target add x86_64-unknown-linux-gnu
$ cargo check -p layerfs-sandbox --bin layerfs-sandbox-helper \
      --target x86_64-unknown-linux-gnu --offline
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 29.07s
```

A negative control (replacing `CLONE_NEWNET` with a non-existent flag) failed as
expected with `error[E0599] ... could not compile`, so the check does cover the
edited bin. That is the whole verification:

- **not built** into a bundle or a shipped binary (`cargo build` for a Linux target
  needs a Linux linker; the client is macOS, the Dell has no toolchain);
- **not executed**: no sandbox was started with the patched helper; no command ran
  under a network namespace; the probe in §1 was made with the unpatched
  acceptance binary;
- **not tested**: `cargo test` was not run — the namespaces lifecycle tests need
  Linux, root, cgroup v2 and `/dev/fuse`. The acceptance image has no `cargo`,
  `git` or `rustc` (ACCEPTANCE-V2 C12), so the guest could not have run them
  either.

Tests that must run before this leaves a prototype branch:

1. `cargo test -p layerfs-sandbox` (or the namespaces lifecycle test) on a Linux
   host with cgroup v2 and `/dev/fuse`: start, mount, exec, commit, stop, delete;
2. from a rebuilt bundle, ACCEPTANCE-V2 C31 re-run: `timeout 3 bash -c
   'exec 3<>/dev/tcp/127.0.0.1/7070'` must be non-zero, `/proc/self/net/dev` must
   show only `lo`, and `/proc/self/ns/net` must not be the initial inode;
3. a command that reads/writes/commits its FUSE Workspace must still work under
   the namespace (this is the path the prototype is meant not to disturb);
4. a command that binds `127.0.0.1` must fail until slice 2, documenting the
   intended slice-1 limitation.

## 5. What remains

Open, in order:

1. **Decisions D1-D1/D1-D2/D1-D3** above — the control transport stays as it is
   until D1-D1 is decided; nothing in this branch changes it.
2. **Slice 2** (`lo` up inside the command namespace) if commands need loopback.
3. **A real verification run** (Slice 1 tests 1-4 in §4) on a host with a Linux
   toolchain; this branch has only a typecheck.
4. **`PROVIDERS.md`** currently lists mount, PID and IPC namespaces and does not
   claim a network namespace (ACCEPTANCE-V2 D1 cites it as consistent with the
   defect). After slice 1 it must say: mount, PID and IPC for the Sandbox;
   an empty network namespace per command; the daemon on the host's loopback,
   which is the control path the client forwards. The same file's image claim
   (ACCEPTANCE-V2 D6) is a separate, already-recorded inconsistency.
5. **D2 interplay**: the Store directory remains bind-mounted into the guest
   (`/layerfs/data/store/dell` at its host path) and is protected only by
   `0700 root` plus the non-root uid. Slice 1 removes the guest's path to host
   network services but not this mount; D2 still needs its own fix.
6. **Not proven, and not claimed:** no exploit, no authentication attempt, no
   bind/hijack attempt, no egress test from the guest (the host's default route
   is visible; ACCEPTANCE-V2 C25 on this machine reached `100.117.34.99:22` from
   the guest, but this run did not repeat it), no multi-machine or Docker
   backend, no test.

## Appendix — exact reproduction

```console
cd /Users/reina/Project/subagent-harness
source harness-v2.env
B="$LAYERFS_V2_BIN"                        # layerfs 2.0.0, sha256 b79ff7b5...

python3 subagent_harness_v2.py spawn d1net --branch agent-d1-net --sandbox d1net
WS=$(python3 -c 'import json;print(json.load(open("/tmp/harness-v2/d1net.json"))["ws"])')

"$B" workspace exec "$WS" 'readlink /proc/self/ns/net; command -v ip; cat /proc/net/dev'
"$B" workspace exec "$WS" 'grep -E "^(Uid|Gid|CapEff|NoNewPrivs):" /proc/self/status'
"$B" workspace exec "$WS" 'cat /proc/net/tcp; cat /proc/net/route'
"$B" workspace exec "$WS" 'b=$(awk "/ lo:/{print \$2}" /proc/net/dev); \
  timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/7070"; echo "worker7070_connect_rc=$?"; \
  a=$(awk "/ lo:/{print \$2}" /proc/net/dev); echo "lo_rx $b -> $a"'
```

The `d1net` Sandbox was unmounted and closed after this run
(`python3 subagent_harness_v2.py finish d1net --close-sandbox --forget`).
