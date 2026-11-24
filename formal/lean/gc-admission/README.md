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

## Main theorem and receipt

```lean
theorem step_preserves (op : Op) (s : State) (h : Inv s) : Inv (step op s)
```

`GcAdmission/Axioms.lean` prints the axiom closure:

```
'GcAdmission.step_preserves' depends on axioms: [propext, Classical.choice, Quot.sound]
```

There is no `sorryAx` and no user axiom.  `GcAdmission/Axioms.lean` is the
CI receipt; `tools/check_lean_axioms.py` accepts exactly the three standard
axioms above.

## Corollary / example map

| §9.4 corollary | Statement in this model | Example |
| --- | --- | --- |
| `no_reclaim_live` | a successful `branchRemove` leaves no `LiveHeldOn` | mount on a removed Branch is refused |
| `compact_barrier` | a successful `storeCompact` leaves no `AnyLiveHeld` | a live intent blocks compact |
| `reconcile_only_dead` | a row the worker-start reconcile deletes satisfies `reconcileDead` | (covered by `Inv8`/`Inv5` guards) |
| `done_is_operator` | every done row has `doneBy = some .operator` | preview retains an operator done row |
| `cross_home_conservative` | `placeOf = none` ⇒ the verdict is the owner fallback | owner-evidence witness |
| `conservative_no_death` | `placeOf = none` ⇒ `¬ PlaceDead` | missing place is live |
| `unordered_never_dead` | a machine `some .uncertain` never yields `Dead` | (pure authority) |
| `restore_is_uncertain` | a machine `some .uncertain` is `Uncertain` | restore case |
| `ordered_rule` | `compareMachine` dead/uncertain/none decomposes `placeVerdict` | ordered compare cases |
| `stale_fence_release_is_identity` | a stale release token is the identity | stale fence example |
| `stale_fence_renew_is_identity` | a stale renew token is the identity | (same guard) |
| `done_survives_compact` | pre-`audit` rows survive `storeCompact` (`Copy::Done`) | archive exports the done row |
| `archive_export_only` | a pruned row is in `exported` | G2 archive example |
| `preview_is_done` | preview adds a `done` row (G4) | G4 preview example |

Two type corrections to the illustrative §9.4 statements are recorded here.
`comparePlace` takes `PlaceValue`, not `Option PlaceValue`, so `ordered_rule`
and `unordered_never_dead`/`restore_is_uncertain` are stated at the
`compareMachine` level (`some .dead`/`some .uncertain`), which is the exact
sequential rule `placeVerdict` implements.  `preview_is_done`'s freshness is
`s.store.intents row = none` (a function, not a set membership).
