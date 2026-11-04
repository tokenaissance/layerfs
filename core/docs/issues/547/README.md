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
integration test files and exposes exactly the values they read:

- `layerfs-daemon::application` re-exports `Slots`, `SlotTicket`, `SlotClass`,
  `AdmissionClass`, `Finished`, `SlotCounts`, `RESERVED_SLOTS`,
  `RetainedFailure`, `RetainedFailures`, `RetainedSnapshot`, `LIMIT` and `TTL`;
- `layerfs-control::daemon::internal` re-exports `NotAdmitted`,
  `not_admitted`, `notice_refusal` and `admission_refusal`.

Every re-export is `#[doc(hidden)]`: the test surface is reachable, but it is
not part of the documented API. The only product edits are these visibility
changes; no behavior changed.

## Tests

| File | Layer | Asserts |
| --- | --- | --- |
| `engine/crates/layerfs-daemon/tests/daemon_slots.rs` | real process | Starts the package's own `layerfs-daemon` binary with a protected config (NFS route, no Store installed) and talks Noise over TCP as a client. 12 clients die after a decoded request: each failure is logged and retained, each slot is released, and a fresh client reaches Hello. The pool reads `pool_running == 1` and `pool_vacant == 7` with the capacity query holding the only slot; `retained.limit == 64`, `recorded == 12`, `dropped == 0`. With 8 idle holders and a raw connection parked in the reserved slot, the next caller gets the fixed 24-byte `LAYERFS-CAPACITY` body, not a bare EOF. 16 threads × 4 deaths neither deadlock nor leak, and the ring stays `count + dropped == recorded`. |
| `engine/crates/layerfs-daemon/tests/slot_state.rs` | pure state | `Slots` and `RetainedFailures` without a socket: pool admission never takes the reserved slot and vice versa; `finish` frees the slot even for a retained failure; stale or duplicate finishes change nothing and cannot free a newer worker; the 65th record evicts the oldest and increments `dropped`; TTL prunes; a textual cause is bounded and cut on a character boundary; a record names slot, class, generation, owner, received bytes, request, reply state and cause. |
| `api/crates/layerfs-control/tests/pool_admission.rs` | pure classification | EOF before Hello is `Capacity` with an unknown retained count and `resource: daemon_control_slot`; a reset is `Unavailable`; a decoded notice maps to `Capacity` with the exact retained/pool/reserved counts; a starting daemon is `Unavailable`; stale-daemon and timeout refusals are not admission refusals. |

## Results

On `7d594d78e` (macOS aarch64; the daemon test files are gated to Linux or macOS):

```text
$ cargo test -p layerfs-daemon --test daemon_slots --test slot_state
running 3 tests
test retained_failures_do_not_consume_control_slots ... ok
test no_vacant_slot_writes_the_capacity_notice ... ok
test concurrent_failures_do_not_deadlock_or_leak ... ok
test result: ok. 3 passed; 0 failed; finished in 4.21s

running 9 tests
test result: ok. 9 passed; 0 failed; finished in 0.00s

$ cargo test -p layerfs-control --test pool_admission
running 5 tests
test result: ok. 5 passed; 0 failed; finished in 0.00s
```

## Base proof (pre-#543, `d2c3f2c97`)

`d2c3f2c97` predates both #540's fix and #543's restructure, so the restored
suite cannot compile there: the slot types it names do not exist yet. The
proof is the same harness reduced to the failing behavior: nine clients die
after a decoded request, then a tenth opens the Noise handshake. On that base
all nine slots stay retained and the tenth connection is closed before Hello:

```text
thread 'tenth_client_is_refused_after_nine_deaths' panicked at
engine/crates/layerfs-daemon/tests/pre543_repro.rs:138:6:
called `Result::unwrap()` on an `Err` value: Io(Kind(UnexpectedEof))
test result: FAILED. 0 passed; 1 failed
```

On `7d594d78e` the same sequence admits the tenth client, and
`retained_failures_do_not_consume_control_slots` asserts the released slots
and the 12 retained records.

## Coverage caveats

- **`SlotGuard::Drop` has no direct test.** #543 deleted
  `dropping_the_guard_releases_the_slot_and_records_once`; this slice restores
  the explicit `finish` path only. Release on unwind, panic and spawn failure
  still relies on that `Drop` arm without a regression test.
- **Three `Dial` tests are not restored.** `garbage_before_hello_is_not_a_notice`,
  `a_daemon_that_closes_before_hello_refuses_precisely` and
  `a_capacity_notice_is_classified_before_hello` drove `Dial::open`/
  `open_waiting` end to end. The pure classification they proved is back in
  `pool_admission.rs`, but the `Dial` retry/wait path is `pub(crate)` and still
  has no external test.
- **"8 vacant" is never observed at once.** The real-process suite reads
  capacity over its own connection, so it sees `pool_running == 1` and
  `pool_vacant == 7`. "The pool is whole" is asserted as
  `pool_vacant + pool_running == 8`, not as an 8-vacant reading.
- **The re-exports are hidden API.** `#[doc(hidden)]` on the product types is
  the price of testing them from outside `src/`. It is deliberately invisible
  in docs, but it is still public surface; a dedicated test-support crate was
  considered and not added in this slice.

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
