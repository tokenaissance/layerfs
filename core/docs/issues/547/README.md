# #547 slice 1: daemon control-slot regression coverage

> **Status:** Slice 1 of [#547](https://github.com/Ephemeral-AI-Lab/layerfs/issues/547).
> Tests only: it restores coverage [#543](https://github.com/Ephemeral-AI-Lab/layerfs/pull/543)
> deleted and does not change daemon behavior. Stacked on #540/#543
> (`fix/540-daemon-slots`) and merged after #543.

## What slice 1 restores

#543 moved every inline `#[cfg(test)]` module out of product `src/`. The bridge
admission tests and the doctor capacity warnings were rehomed against public
calls, but the daemon's slot-custody tests could not be: they read `Slots`,
`RetainedFailures` and the control pool's admission classification, all
`pub(super)` or `pub(crate)`. This slice restores that coverage in three
integration test files and exposes exactly the values they read, behind two
hidden modules:

- `layerfs-daemon::application::internals` re-exports `Slots`, `SlotTicket`,
  `SlotClass`, `AdmissionClass`, `Finished`, `SlotCounts`, `RESERVED_SLOTS`,
  `RetainedFailure`, `RetainedFailures`, `RetainedSnapshot`, `LIMIT` and `TTL`.
  The documented `application` exports stay `Application`, `ApplicationError`
  and `ConnectionFailure`.
- `layerfs-control::daemon::internal` re-exports only the classification,
  `not_admitted` and `NotAdmitted`. The two refusal *message* builders
  (`notice_refusal`, `admission_refusal`) are `pub(crate)` again: their wording
  is not a contract, and the typed admission reason that should replace them is
  S6 work.

Every re-export is `#[doc(hidden)]`, and each hidden module is `#[doc(hidden)]`
too. That keeps the surface out of rustdoc; it is not access control. There is
no feature gate: a test is never compiled out, and the product-boundary guard
still rejects `#[cfg(test)]` in product `src/`.

The one behavior change is `Slots::abandon`: the pure release a worker performs
when its guard is dropped without an explicit `finish`. `SlotGuard::drop` now
calls it instead of building the failure itself, so the drop path's state
machine is reachable from a test. No socket, Store or thread behavior changed.

## Tests

| File | Layer | Asserts |
| --- | --- | --- |
| `engine/crates/layerfs-daemon/tests/daemon_slots.rs` | real process | Starts the package's own `layerfs-daemon` binary with a protected config (NFS route, no Store installed) and talks Noise over TCP as a client. 12 clients send a record the daemon receives but cannot decode; each failure is logged and retained, each slot is released, and a fresh client reaches Hello. The pool reads `pool_running == 1` and `pool_vacant == 7` with the capacity query holding the only slot; `retained.limit == 64`, `recorded == 12`, `dropped == 0`. With 8 idle holders and a raw connection parked in the reserved slot, the next caller gets the fixed 24-byte `LAYERFS-CAPACITY` body, not a bare EOF (its reason is `Starting`: no Store is installed). 16 threads × 4 deaths neither deadlock nor leak, and the ring stays `count + dropped == recorded`. |
| `engine/crates/layerfs-daemon/tests/slot_state.rs` | pure state | `Slots` and `RetainedFailures` without a socket: pool admission never takes the reserved slot and vice versa; `finish` frees the slot even for a retained failure; a dropped guard's `Slots::abandon` frees the slot and records the abandonment once; a decoded request whose reply was never sent is retained with `request` named and `reply_sent: false`; stale or duplicate finishes change nothing and cannot free a newer worker; the 65th record evicts the oldest and increments `dropped`; TTL prunes; a textual cause is bounded and cut on a character boundary; a record names slot, class, generation, owner, received bytes, request, reply state and cause. |
| `api/crates/layerfs-control/tests/pool_admission.rs` | pure classification | EOF before Hello is a no-vacant-slot admission failure with an unknown retained count; a reset is a failed connection; stale-daemon and timeout refusals are not admission refusals. |

## Results

On this branch (macOS aarch64; the daemon test files are gated to Linux or
macOS):

```text
$ cargo test -p layerfs-daemon --test daemon_slots --test slot_state
running 3 tests
test result: ok. 3 passed; 0 failed
running 11 tests
test result: ok. 11 passed; 0 failed

$ cargo test -p layerfs-control --test pool_admission
running 3 tests
test result: ok. 3 passed; 0 failed
```

## Base proof (pre-#543, `d2c3f2c97`)

`d2c3f2c97` predates both #540's fix and #543's restructure, so the restored
suite cannot compile there: the slot types it names (`Slots`, `SlotTicket`,
`RetainedFailures`, `CapacityModel`) do not exist yet. The base half of the
proof is therefore the failing behavior alone, committed beside this file as
[`pre543_repro.rs`](pre543_repro.rs). It uses only the public `DaemonSetup`
encoding, the `layerfs-daemon` binary and the authenticated duplex client, and
it is not built with this branch.

```text
git worktree add /tmp/layerfs-547-base d2c3f2c97
cp <this branch>/core/docs/issues/547/pre543_repro.rs \
   /tmp/layerfs-547-base/engine/crates/layerfs-daemon/tests/
cd /tmp/layerfs-547-base
cargo test -p layerfs-daemon --test pre543_repro
```

Nine clients send a record the base daemon receives but cannot decode, then
close; the tenth opens the authenticated handshake. Every failed slot stays
`Retained` on the base, so the tenth is refused before Hello:

```text
thread 'tenth_client_is_refused_after_nine_deaths' panicked at
engine/crates/layerfs-daemon/tests/pre543_repro.rs:166:6:
called `Result::unwrap()` on an `Err` value: Io(Kind(UnexpectedEof))
test result: FAILED. 0 passed; 1 failed
```

Line 166 is the copied file's line; the run above is a clean worktree at
`d2c3f2c97`, macOS aarch64, 2026-11-05.

On this branch `daemon_slots.rs::undecodable_records_do_not_consume_control_slots`
runs twelve such deaths and then reaches Hello on the same daemon; the pool
reads 1 running / 7 vacant and twelve retained records.

## Coverage caveats

- **`SlotGuard::Drop` is covered at the state-machine level, not end to end.**
  `SlotGuard::drop` now ends through `Slots::abandon`, and
  `abandoning_a_slot_releases_it_and_records_the_drop_once` asserts that this
  frees the slot, records the `dropped before completion` cause exactly once,
  and treats a second drop as stale. The wiring from a real dropped guard to
  that call still has no external test: a worker panic is caught and finished
  explicitly, and a thread spawn failure cannot be provoked from outside the
  daemon.
- **The decoded-request reply-lost path is covered as a record, not over a
  socket.** `decoded_request_without_a_reply_is_retained` builds the same
  `ConnectionFailure` (`ApplicationError::Control` around the original
  `Served`) that `connection()` builds when `answer_call` fails after a decoded
  call, and asserts retention with `request: Some("end-session")` and
  `reply_sent: false`. The socket-level send failure itself is not reproduced:
  it cannot be forced deterministically from outside. The real-process deaths
  fail at `InitialRecord::decode` and show `request: None`, so they are *not*
  this path.
- **Three `Dial` tests are not restored.** `garbage_before_hello_is_not_a_notice`,
  `a_daemon_that_closes_before_hello_refuses_precisely` and
  `a_capacity_notice_is_classified_before_hello` drove `Dial::open`/
  `open_waiting` end to end. Only the pure classification they proved is back;
  the `Dial` retry/wait path is `pub(crate)` and still has no external test.
- **`NoPoolSlot` is never emitted in a real-process test.** The accept loop
  picks `NoPoolSlot` only when the daemon is `ControlReady`; the suite starts a
  daemon with no installed Store, so its notice test reads `Starting`. The
  `NoPoolSlot` wire encoding is covered by
  `engine/crates/layerfs-bridge/tests/admission.rs`; the daemon emitting it,
  and the client mapping a decoded notice to `Capacity`, have no test. The
  latter lost its test when the refusal message builders went private (see
  above).
- **"8 vacant" is never observed at once.** The real-process suite reads
  capacity over its own connection, so it sees `pool_running == 1` and
  `pool_vacant == 7`. "The pool is whole" is asserted as
  `pool_vacant + pool_running == 8`, not as an 8-vacant reading.
- **The two hidden modules are public surface.** `#[doc(hidden)]` is the price
  of testing the slot state machine from outside `src/`. A dedicated
  test-support crate was considered and not added in this slice, and no
  feature gate hides the surface (a feature would silently skip the tests when
  CI does not pass it).

## Diagrams

- [`test-topology.png`](test-topology.png) — the real process, the three test
  files and what each layer asserts.
- [`regression-sequence.png`](regression-sequence.png) — the 12 deaths, the
  retained ring, the fresh client, the capacity notice, the storm, and the
  pre-#543 red path.

Both are hand-built Excalidraw scenes in the `layerfs` collection (workspace
`9Zq6XgRe98z`), Comic Shanns throughout, title 38 px and body 26 px:

| Scene | Id | Canvas | PNG sha256 |
| --- | --- | --- | --- |
| `SandboxComputePlane — #547 test topology` | `2wz3wJaCLXD` | 1234 × 1016 | `8a8fe4faf4fa56f0fa923e1fbb81970e0eb9f84abf158c7a2a1324138a1f1ddc` |
| `SandboxComputePlane — #547 regression sequence` | `101C2dsHwIv` | 1218 × 1016 | `13b0a0b78be7619b583103374f3b94323b50608a84ca92e946568aad2fb2f27d` |

The `.excalidraw` sources sit beside the PNGs. Two screenshots of each scene
render are byte-identical.

## Links

- [#540](https://github.com/Ephemeral-AI-Lab/layerfs/issues/540) — control-slot
  custody and the capacity notice.
- [#543](https://github.com/Ephemeral-AI-Lab/layerfs/pull/543) — the move of
  tests out of product source; this slice follows it.
- [#547](https://github.com/Ephemeral-AI-Lab/layerfs/issues/547) — restore the
  daemon slot regression coverage.
