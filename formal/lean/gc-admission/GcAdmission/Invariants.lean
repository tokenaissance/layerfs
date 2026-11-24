import GcAdmission.Transitions

/-!
  GcAdmission/Invariants.lean

  The eight invariants of §7, verbatim, plus the helper predicates they use.
  `Inv` is a structure (still a `Prop`) so the preservation proofs can name
  each conjunct.
-/
namespace GcAdmission

/-- An intent holds Branch `b` when it names `b`, when it is Store-scoped,
or when it is Project-scoped for the project that owns `b`.  The real
`gc_intent_all_branch` query returns all three, so a live Store/Project row
blocks a Branch removal just as a live Branch row does. -/
def HoldsBranch (s : State) (b : BranchId) (i : Intent) : Prop :=
  i.branch = some b ∨
  (i.branch = none ∧ i.project = none) ∨
  (i.branch = none ∧ ∃ p, i.project = some p ∧
      (s.branchProject b = none ∨ s.branchProject b = some p))

def MountedOn (s : State) (b : BranchId) : Prop :=
  ∃ op i, s.store.intents op = some i ∧
          HoldsBranch s b i ∧ i.state ≠ .done

def AnyMounted (s : State) : Prop :=
  ∃ op i, s.store.intents op = some i ∧ i.state ≠ .done

/-- The rows an adoption/compact guard uses: a non-done intent that is not
dead-certain.  A dead-certain row may be removed automatically; a live or
explicitly uncertain one may not. -/
def LiveHeldOn (s : State) (b : BranchId) : Prop :=
  ∃ op i, s.store.intents op = some i ∧ HoldsBranch s b i ∧
          i.state ≠ .done ∧ (¬ Dead s i ∨ i.uncertain = true)

def AnyLiveHeld (s : State) : Prop :=
  ∃ op i, s.store.intents op = some i ∧ i.state ≠ .done ∧
          (¬ Dead s i ∨ i.uncertain = true)

def OperatorDone (i : Intent) : Prop :=
  i.state = .done ∧ i.doneBy = some .operator ∧ i.action ≠ some .preview

/-- Every place witness that says `dead` names an ordered cause: a newer
machine incarnation, a newer Sandbox generation, or a retired generation at or
after the recorded one. -/
def OrderedDeath (w : Witness) : Prop :=
  w.kind = .place → w.verdict = .dead →
    ∃ p, w.place = some p ∧
      ((∃ r c, w.recorded.machine = some r ∧ p.machine = some c ∧
                comparePlace r c = .recordedOlder) ∨
       (∃ r c, w.recorded.sandbox = some r ∧ p.sandbox = some c ∧
                comparePlace r c = .recordedOlder) ∨
       (∃ r t, w.recorded.sandbox = some r ∧ p.retired = some t ∧
                (comparePlace r t = .recordedOlder ∨ comparePlace r t = .equal)))

/-- The exact sequential `compareMachine` → `compareSandbox` → lease
decomposition of `placeVerdict`. -/
def OrderedRule (w : Witness) : Prop :=
  w.kind = .place →
  match w.place with
  | none => True
  | some p =>
      match compareMachine w.recorded.machine p.machine with
      | some .dead      => w.verdict = .dead
      | some .uncertain => w.verdict = .uncertain
      | some .live      => w.verdict = .live
      | none =>
          match compareSandbox w.recorded.sandbox p.sandbox p.retired with
          | some .dead      => w.verdict = .dead
          | some .uncertain => w.verdict = .uncertain
          | some .live      => w.verdict = .live
          | none =>
              match w.recorded.leaseExpires with
              | some e => (e ≤ w.now → w.verdict = .uncertain) ∧
                          (w.now < e → w.verdict = .live)
              | none   => w.verdict = .live

/-- 1. A live mount is never reclaimed. -/
def Inv1 (s : State) : Prop :=
  (∀ op i, s.store.intents op = some i → i.state ≠ .done →
      ∀ b, i.branch = some b → s.store.branches b = some .live) ∧
  (∀ b, s.store.branches b = some .removed → ¬ MountedOn s b) ∧
  (s.store.compacted = true → ¬ AnyMounted s)

/-- 2. Release only on an explicitly uncertain (settled) row; settle only
marks an existing non-done row uncertain.  Every done release and every
uncertain row carries an admission witness. -/
def Inv2 (s : State) : Prop :=
  (∀ op i, s.store.intents op = some i → OperatorDone i →
    ∃ w, i.witness = some w ∧ WitnessConsistent w ∧
      (w.verdict = .dead ∨ w.verdict = .uncertain ∨ i.settled = true)) ∧
  (∀ op i, s.store.intents op = some i → i.state = .uncertain →
    ∃ w, i.witness = some w ∧ WitnessConsistent w)

/-- 3. Missing / restored / unordered place evidence is never Dead. -/
def Inv3 (s : State) : Prop :=
  ∀ op i w, s.store.intents op = some i → i.witness = some w →
    WitnessConsistent w → OrderedDeath w

/-- 4. The ordered rule: newer ⇒ Dead, older ⇒ Uncertain, equal ⇒ Live
(unless the tombstone or the lease says otherwise). -/
def Inv4 (s : State) : Prop :=
  ∀ op i w, s.store.intents op = some i → i.witness = some w →
    WitnessConsistent w → OrderedRule w

/-- 5. The Store-wide compact barrier. -/
def Inv5 (s : State) : Prop :=
  s.store.compacted = true → ¬ AnyMounted s

/-- 6. Fence: a recorded release token is the row's fence. -/
def Inv6 (s : State) : Prop :=
  ∀ op i, s.store.intents op = some i →
    ∀ f, i.releasedWith = some f → i.recorded.fence = some f

/-- 7. A retained done row survives `store.compact` (`Copy::Done`). -/
def Inv7 (s : State) : Prop :=
  (∀ op i, s.store.intents op = some i → i.state = .done →
      s.store.audit op = some i ∨ op ∈ s.store.exported) ∧
  (∀ op i, s.store.audit op = some i → i.state = .done) ∧
  (s.store.compacted = true →
      ∀ op i, s.store.audit op = some i → s.store.intents op = some i)

/-- 8. No automatic release: every done row was created by an operator
action (settle/release, or audit-only preview). -/
def Inv8_no_automatic_release (s : State) : Prop :=
  ∀ op i, s.store.intents op = some i → i.state = .done →
    i.doneBy = some .operator

/-- The conjunction of the eight invariants. -/
structure Inv (s : State) : Prop where
  inv1 : Inv1 s
  inv2 : Inv2 s
  inv3 : Inv3 s
  inv4 : Inv4 s
  inv5 : Inv5 s
  inv6 : Inv6 s
  inv7 : Inv7 s
  inv8 : Inv8_no_automatic_release s

/-! ## §8 hypotheses (definitions only; obligations, not axioms) -/

def H2_mint_monotone (s : State) (m : MachineId) (inc : Ordered) : Prop :=
  ∀ cur, homeIncarnation s m = some (.ordered cur) →
    cur.label = inc.label → cur < inc

def H2_restore (s : State) (m : MachineId) (inc : Ordered) : Prop :=
  ∀ cur, homeIncarnation s m = some (.ordered cur) →
    cur.label = inc.label → inc < cur

def H3_retention (s s' : State) : Prop :=
  (∀ m sb g, tombstone s m sb = some g → ∃ g', tombstone s' m sb = some g') ∧
  (∀ m inc, homeIncarnation s m = some inc →
      ∃ inc', homeIncarnation s' m = some inc')

def placeOfUsing (v : PlaceView) (i : Intent) : Option PlaceRecord :=
  v.record i.machine i.sandbox

def H4_transaction (Impl : State → State → Prop) : Prop :=
  ∀ s s', Impl s s' → ∃ op, s' = step op s

def H4_read_once (Read : State → PlaceView) : Prop :=
  (∀ s, Read s = viewOf s) ∧
  (∀ s i, placeOfUsing (Read s) i = placeOf s i)

def H5_merge_sound (s : State) : Prop :=
  ∀ m v, (viewOf s).machineOf m = some v →
    ∃ h, h ∈ reachableHomes s ∧ homeIncarnationIn s h m = some v

def H5_newest (s : State) : Prop :=
  ∀ m v, (viewOf s).machineOf m = some (.ordered v) →
    ∀ h, h ∈ reachableHomes s → ∀ v',
      homeIncarnationIn s h m = some (.ordered v') → v' < v ∨ v' = v

def PlaceNewer (recorded current : PlaceValue) : Prop :=
  comparePlace recorded current = .recordedOlder

def H6_bounded (s : State) : Prop :=
  (viewOf s).placeCount ≤ 4096

def Intent.scopeKey (i : Intent) : Option (ProjectId ⊕ BranchId) :=
  match i.branch, i.project with
  | some b, _     => some (Sum.inr b)
  | none, some p  => some (Sum.inl p)
  | none, none    => none            -- Store scope

def H7_key_unique (s : State) : Prop :=
  ∀ op i op' i', s.store.intents op = some i → s.store.intents op' = some i' →
    i.state ≠ .done → i'.state ≠ .done →
    i.ownerBoot ≠ none → i.ownerBoot = i'.ownerBoot →
    i.scopeKey = i'.scopeKey → op = op'

def H8_home_seeded (s : State) (seeded : List (MachineId × HomeId)) : Prop :=
  ∀ m h, (storeMachine s m).home = some h → (m, h) ∈ seeded

end GcAdmission
