# GC admission / liveness — Lean 4 model

A Level-2, Mathlib-free Lean 4 model of the LayerFS GC admission/liveness
design (ordered place tokens, the bounded cross-home `PlaceView`, the
`gc_intent` done-row/audit path, the compact barrier, fence checks and the
operator escape).  It is a *design model*: the Rust/DB transaction, the
filesystem home protocol and concurrency are refinements, not proved here.

## Build

```sh
export ELAN_HOME=/path/to/elan
export PATH="$ELAN_HOME/bin:$PATH"
lake build
```

`lean-toolchain` pins `leanprover/lean4:v4.36.0`.  There is no Mathlib, no
`lake exe cache get`, and no network step after the toolchain install.

## Policy

No `sorry`, no `admit`, no `axiom`, no `native_decide`.  `GcAdmission/Axioms.lean`
prints the axiom receipt for the main theorem; the allowed axioms are only
`propext`, `Classical.choice` and `Quot.sound`.  `#guard`s are elaborated by
`lake build`, so a false example fails the build.

## Module map

| Module | Contents |
| --- | --- |
| `GcAdmission/State.lean` | `Ordered`/`PlaceOrder`/`PlaceValue`/`comparePlace`/`parseToken`; `Liveness`, `RecordedPlace`, `PlaceRecord`, `Witness`, `Intent`, `Machine`/`Home`, `Store`, `State`; the G1 `PlaceView`/`PlaceField`/`Merged` merge; `placeOf`/`verdict`/`witnessFor` |
| `GcAdmission/Transitions.lean` | `Op` (15 transitions), executable guards, `step`, `settlePlace`, `reconcileDead` |
| `GcAdmission/Invariants.lean` | `HoldsBranch`, `MountedOn`, `LiveHeldOn`, `OrderedDeath`, `OrderedRule`, the eight `Inv1`–`Inv8_no_automatic_release` and `Inv`; the §8 hypotheses H2–H8 |
| `GcAdmission/Proofs.lean` | pure ordered lemmas, per-transition preservation, `step_preserves`, the §9.4 corollaries |
| `GcAdmission/Examples.lean` | executable `#guard` examples |
| `GcAdmission/Axioms.lean` | `#print axioms step_preserves` receipt |

Dependency order: `State → Transitions → Invariants → Proofs → Examples →
GcAdmission`.

## Model notes

* **Lists instead of `Finset`.** Lean 4 core/`Std` does not ship `Finset` and
  the task forbids Mathlib, so the enumerated collections are `List`s with
  deduplicated updates.  Every invariant statement is unchanged.
* **Audit is derived.** `Store.audit` is the `done` projection of the live
  intent map.  That is the structural form of SQLite's `Copy::Done`: compact
  keeps exactly the done rows, so a retained done row cannot be lost by a
  compact.  The alternative (an independent mutable audit field) needs a
  ninth invariant that the eight do not state, so the derived form keeps the
  §7 statements exact.
* **Finite intent support.** `Store.entries` lists the visible intent keys;
  `Store.intents` is `none` outside it.  This is what lets the universal
  guards (`every non-done holder is dead-certain`) be executable `Bool`s.
* **Same-label order.** `comparePlace` refuses to order tokens of different
  labels (`.unordered`, no proof), matching H2's side condition; the Rust
  comparator ignores the label but admission never compares across kinds.
* **Own-place fallback.** `placeOf` falls back to the intent's own recorded
  place before the owner evidence, so a placed row whose home this admission
  cannot read is never owner-killed.  This is deliberately more conservative
  than the p4 code for that one case (see plan §14).

## Invariant / transition matrix

`✔ guard` = the transition may change the invariant's subject and needs the
guard; `–` = unchanged by construction.

| Transition | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `sandboxCreate` | – | – | – | – | – | – | – | – |
| `sandboxMount` | ✔ guard | – | ✔ | ✔ | ✔ | – | – | – |
| `sandboxUnmount` | – | – | – | – | – | – | – | – |
| `sandboxClose` | – | – | – | – | – | – | – | – |
| `sandboxForceRemove` | – | – | – | – | – | – | – | – |
| `machineStart` | – | – | – | – | – | – | – | – |
| `machineRestore` | – | – | – | – | – | – | – | – |
| `admissionRecheck` | – | ✔ | ✔ | ✔ | – | – | – | – |
| `leaseRenew` | – | – | – | – | – | ✔ guard | – | – |
| `branchRemove` | ✔ guard | – | – | – | – | – | – | – |
| `storeCompact` | ✔ guard | – | – | – | ✔ | – | ✔ | – |
| `operatorPreview` | – | – | ✔ | ✔ | – | – | ✔ | ✔ |
| `operatorSettle` | – | ✔ | ✔ | ✔ | – | – | – | – |
| `operatorRelease` | – | ✔ | ✔ | ✔ | – | ✔ guard | ✔ | ✔ |
| `operatorArchive` | – | – | – | – | – | – | ✔ | – |

## What each invariant says

1. A live mount is never reclaimed: a Branch-scoped non-done row sits on a
   live Branch, a removed Branch has no non-done holder, and a compacted
   Store has no non-done row.
2. A retained operator done row and every uncertain row carries a consistent
   admission witness.
3. Missing, restored or unordered place evidence is never `Dead` (the
   `OrderedDeath` cause is explicit).
4. The ordered rule: newer ⇒ Dead, older ⇒ Uncertain, equal ⇒ Live unless
   the tombstone or the lease says otherwise.
5. A live/uncertain intent blocks `store.compact`.
6. A stale fence can neither release nor renew a row.
7. A retained done row survives `store.compact` (`Copy::Done`), and a pruned
   row was exported first.
8. No automatic release: every done row has an operator principal.

## Limits

* Level 2 proves the **design**, not the database: H1 (one atomic
  transaction), H4 (one bounded read), H7 (the unique owner key) and the
  SQLite/PG details are obligations of the implementation.
* H2 (ordered-token monotonicity) is an implementation obligation of the
  mint; a clock rollback can only lose reclamation, never cause a false
  death, because an older current value is `Uncertain`.
* H3 (tombstone/incarnation retention) and H8 (`machines.<m>.home` is
  seeded, with no public writer) bound the cross-home result.
* Concurrency, crash recovery, the JSONL audit durability and the 4096-place
  cap (H6) are operational/Level-3 concerns; the cap can only remove proof.
* The G1/G2/G4 conformance record is the plan's §14; the code read is the p4
  tree `87890d785c` (`place_view.rs`, `store.rs`, `service.rs`,
  `history/admission.rs`, `sql/sqlite/gc.sql`, `compact/build.rs`).
