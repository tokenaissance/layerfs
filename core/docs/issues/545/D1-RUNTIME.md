# D1 — runtime verification of the per-command network namespace on `aluminium`

Status: **prototype built, installed, run and measured on the real `ssh` machine**,
then restored. This file is the runtime evidence D1-NETWORK-NS.md §4 said was
missing ("not built, not executed, not tested"). Branch `agent-d1-run`
(forked from `agent-d1-net@121d711c`, which is `main@62b1b982` plus the prototype
`12fd0ddb`). `main` untouched; no GitHub issue updated.

| Field | Value |
|---|---|
| Machine | `aluminium`, `platform: ssh`, `backend: namespaces`, `100.117.34.99`, kernel `6.14.0-29-generic` |
| Client | `layerfs 2.0.0`, debug, `LAYERFS_HOME=/tmp/layerfs-cloud-home` |
| Bundle on the machine | `/layerfs/bundle`, `.sealed = 79ad8ef4…` (unchanged before and after) |
| Prototype helper | `/tmp/d1-target/debug/layerfs-sandbox-helper`, 9 950 632 bytes, `sha256 863c74353c73755b31376c3d629a0ca24206e1f2519e406d5d61f663d8bc99d8` |
| Original helper (restored) | `sha256 5a74b615094403a1ab2c3ff6b60e6a735b1ffaa1b3a0203905c444168fcfb029` |
| Backup | `/root/d1helper-backup/layerfs-sandbox-helper.orig` (`cp -a`, same sha256) |
| Sandboxes used | `d1run` (patched helper), `d1ctl` (control, original helper); both closed |

## 1. Build and deploy

The branch tree was materialised on the machine from its own Workspace: the
workspace FUSE mount lives only in the Sandbox's mount namespace, so the host
sees it at `/proc/<sandbox pid>/root/layerfs/data/machine/native/run/<sandbox>/workspaces/<n>`.
`tar` from there to `/tmp/d1-src` (236 MB, 7 313 files) is the exact branch
source, not a local copy.

```console
$ cd /tmp/d1-src && CARGO_TARGET_DIR=/tmp/d1-target \
    cargo build --locked --offline -p layerfs-sandbox --bin layerfs-sandbox-helper
   Compiling layerfs-sandbox v2.0.0 (/tmp/d1-src/connect/crates/layerfs-sandbox)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 11.28s
```

The build needed two client-side caches first: the machine's sparse-index
fetches stalled (`Updating crates.io index`, one socket in `do_select`) and
`--offline` then failed on `libproc` and `autocfg`. Copying the client's
`~/.cargo/registry/index/index.crates.io-*/.cache` and
`~/.cargo/registry/cache/index.crates.io-*` into the machine's `/root/.cargo`
made `--locked --offline` build deterministically. The machine's rustc is
1.87.0; the helper links only `libgcc_s`/`libc`.

Install and restart, only after the binary's own checks passed
(`noargs_rc=125`, `badargs_rc=125`, `ldd` clean):

```console
# install -m 0755 -o 501 -g root /tmp/d1-target/debug/layerfs-sandbox-helper \
    /layerfs/bundle/layerfs-sandbox-helper
# sha256sum /layerfs/bundle/layerfs-sandbox-helper   -> 863c7435…
$ layerfs machine stop aluminium && layerfs machine start aluminium
```

`machine start` does **not** overwrite the bundle: `setup/worker.rs::install`
re-copies only when `/layerfs/bundle/.sealed` differs from the client bundle
hash, and both stayed `79ad8ef4…`. The worker restarted with the patched helper;
the next `sandbox create` copied it into that Sandbox's own `bin/`
(`paths.rs::HELPER`, 9 950 632 bytes, same sha256) — a running Sandbox keeps the
helper it was created with, which is why the restore is safe.

## 2. Measurements

Each `layerfs workspace exec` is one command, run by the helper's `exec` stage.

### 2.1 With the prototype helper (`d1run`)

```console
$ readlink /proc/self/ns/net
net:[4026533559]                      # not the initial namespace
$ readlink /proc/self/ns/mnt /proc/self/ns/pid /proc/self/ns/ipc
mnt:[4026533555] pid:[4026533557] ipc:[4026533556]
$ cat /proc/net/dev
Inter-|   Receive ... |  Transmit ...
    lo:       0       0    0    0 ...   # only lo, down, zero counters
$ cat /proc/net/route
Iface  Destination Gateway ...        # header only, no route
$ cat /proc/net/tcp
  sl  local_address rem_address   st tx_queue ...   # header only, no socket
$ timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/7070'; echo $?
bash: connect: Network is unreachable
bash: line 1: /dev/tcp/127.0.0.1/7070: Network is unreachable
1
```

Same non-zero result, same reason, for `127.0.0.1:22`, `127.0.0.1:44513` (this
Sandbox's daemon control port, read from its `record.json`), and
`100.117.34.99:22`. No packet was sent; the failure is local (`ENETUNREACH`).

### 2.2 Namespaces are per command, not per Sandbox

Sequential commands show the same inode number (`4026533559`) because the
kernel frees the previous namespace's id when its last process exits. Two
*concurrent* commands disprove a shared namespace:

```console
exec A (sleep 6): net:[4026533559]
exec B (during A): net:[4026534875]
```

Two different network namespaces alive at once: the `unshare(CLONE_NEWNET)` is
per exec stage, exactly as `12fd0ddb` intends. A Sandbox-wide namespace would
show one inode in both.

### 2.3 Host and control (original helper restored, `d1ctl`)

```console
# on the machine:
host /proc/self/ns/net         net:[4026531840]
worker /proc/<worker>/ns/net   net:[4026531840]
daemon /proc/<daemon>/ns/net   net:[4026531840]
```

The daemon stays in the host network namespace (decision D1-D1: unchanged,
still reachable only by its own loopback/forward path).

```console
$ readlink /proc/self/ns/net
net:[4026531840]                      # the initial namespace
$ cat /proc/net/dev
    lo: ... eno1: ... eno2: ... eno3: ... eno4: ... tailscale0: ...
$ timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/7070'; echo $?
0
```

The same probe with the original helper returns the host's initial namespace,
all four Dell NICs, the Tailscale interface, and a **successful** connect to the
worker control port. The difference between §2.1 and §2.3 is the helper and
nothing else.

## 3. Lifecycle under the new helper

All of these ran in `d1run`, with the patched helper:

| Step | Result |
|---|---|
| `sandbox create` (helper `init`/`init-inner`, daemon start) | ok, daemon on `127.0.0.1:44513` |
| `workspace mount` | ok, `workspaces/1` |
| `workspace exec` (readlink, cat, ls, grep in the tree) | ok, `exit:0` |
| write `d1-runtime-probe.txt` in the Workspace | ok, 44 bytes, `501:dialout` |
| `workspace exec '…; exit 7'` | `exit:7` — a command's code is not the helper's failure (which is `SIGKILL`, never an exit code) |
| `workspace commit -m …` | ok, head `12d43411` |
| second commit (probe file removed) | ok, head `12ffc253` |
| `workspace unmount` / `workspace mount` again | ok, new namespace 2 on the new head `ffc2539d` |
| `workspace exec` on the re-mounted Workspace | ok, netns `4026533559` |
| `workspace unmount`, `sandbox close` | ok |
| after close | `/layerfs/data/sandbox` empty, no helper/daemon process, no `lfs-*` cgroup, `machine/native/run/` holds only `images/`, worker alive |

So the FUSE Workspace path, the command's `uid:gid`/cwd, commit, mount/unmount
and teardown are undisturbed. No orphan process or cgroup was found after either
Sandbox (patched or control).

## 4. The home-permission finding

Measured, immediately after `machine start` on a machine whose data root was
already correct:

```console
# stat -c '%a %n' /layerfs/data /layerfs/data/store /layerfs/data/sandbox /layerfs/data/machine /layerfs/data/log
701 /layerfs/data
755 /layerfs/data/store        <- wrong
755 /layerfs/data/sandbox      <- wrong
701 /layerfs/data/machine
700 /layerfs/data/log
```

`setup/worker.rs::PREPARE` (the script every `machine start`/`connect` runs in
the guest) is the cause:

```rust
mkdir -p "$1/store" "$1/sandbox" /layerfs/state
chmod 755 "$1" "$1/store" "$1/sandbox"      # <- 0755 on all three
```

`worker::serve` then sets the root to `0701` (`machine/worker/server.rs:47-51`),
and `traversable` sets the home→run-root ancestors to `0701`; nothing re-tightens
`store` and `sandbox` (the store/sandbox code sets `0700` only where it
creates/opens those folders). This is the verified "not 0755" defect.

### 4.1 `common/home/records.rs` is not the cause

Checked and measured, not assumed:

- a **fresh home** (`LAYERFS_HOME=/tmp/d1home-probe layerfs project list`) comes
  out `0700` for `home`, `machine/`, `machine/native/`, `machine/docker/`; the
  `layerfs.json`/`record.json` files are `0600`;
- `private_dir` creates each missing level with `mode(0o700)` (std applies the
  mode to every level it creates), and leaves an existing folder alone — which
  is required, because `lock::open` calls `private_dir(home)` on every call and
  a chmod to `0700` there would undo the `0701` that `traversable` needs for a
  namespaces command to traverse;
- `traversable` only adds `o+x`; `machine/native/run` is `0755` by design
  (`route.rs`, "^the runtime requires" it), and
  `api/crates/layerfs-control/tests/local_root_modes.rs` asserts exactly
  `0701` for the home's ancestors and `0755` for an already-passable run root.

So no change in `records.rs` is warranted; a change there would be in the wrong
layer and would either be a no-op on the real defect or break traversal.

### 4.2 The change applied (commit `12fb7fe2`)

```rust
chmod 701 "$1"
chmod 700 "$1/store" "$1/sandbox"
```

Verified live by running the patched body on `aluminium` with `$1=/layerfs/data`,
starting from `755/755/755`:

```console
before: 755 /layerfs/data  755 /layerfs/data/store  755 /layerfs/data/sandbox
after:  701 /layerfs/data  700 /layerfs/data/store  700 /layerfs/data/sandbox
```

and the full lifecycle in §3 ran in a Sandbox whose data root had exactly these
modes, so `0701/0700/0700` does not starve a namespaces command of traversal.

**Limit of this verification:** the fix changes the *client* crate
(`layerfs-machine`), which is compiled into the client `layerfs` binary. The
client was **not rebuilt** in this run, so the patch is source-verified and its
mode values are runtime-verified, but the shipped client still writes `0755`
until it is rebuilt and its bundle re-sealed. Until then the manual mitigation
is `chmod 701 /layerfs/data; chmod 700 /layerfs/data/store /layerfs/data/sandbox`
after every `machine start`.

Focused test: the repo's home-layout tests (`local_root_modes.rs`, `doctor.rs`)
cover the control crate, not this machine-setup script; the script is private
to `setup/worker.rs` and the machine tests use a standin guest, so no focused
test was added here — the exact shell line and the measured modes above are the
record.

## 5. What remains

1. **Rebuild the client** with `12fb7fe2` and re-run `machine start` on a fresh
   machine to see `0701/0700/0700` without the manual chmod; re-seal the bundle
   (`bundle.json`/`.sealed`) in the same step.
2. **Land or reject slice 1.** On this evidence `exec` commands have *no*
   network at all — loopback included (`ENETUNREACH` for `127.0.0.1`). That
   answers test 2 of D1-NETWORK-NS.md §4 and test 4 (a bind-using command
   fails, but by `ENETUNREACH` on every address, not by a refused bind). The
   product decision D1-D2 ("do commands get egress?") is now concrete: with
   this patch they get none.
3. **Decisions D1-D1/D1-D2/D1-D3** in D1-NETWORK-NS.md §4 are still open; this
   run only confirms that keeping the daemon on the host namespace costs nothing
   in the exec path (D1-D1) and that the per-command choice (D1-D3) is what the
   prototype actually implements.
4. **`PROVIDERS.md`** must say: mount/PID/IPC for the Sandbox; an empty network
   namespace per command; the daemon on the host loopback, which is the control
   path the client forwards.
5. **D2 interplay unchanged:** the Store directory is still bind-mounted into
   the guest; this run does not touch it.

## Appendix — exact run

```console
cd /Users/reina/Project/subagent-harness && source harness-v2.env
python3 subagent_harness_v2.py spawn d1run --branch agent-d1-run --base agent-d1-net --sandbox d1run
# (the mount step can race a macOS ephemeral port in the detached ssh -L; retry)
python3 subagent_harness_v2.py exec d1run 'readlink /proc/self/ns/net; cat /proc/net/dev'
# install /layerfs/bundle/layerfs-sandbox-helper = 863c7435…, machine stop/start,
# sandbox create d1run, workspace mount, probes in §2/§3,
# restore backup (5a74b615…), machine stop/start, control probes in §2.3,
# close both Sandboxes.
```
