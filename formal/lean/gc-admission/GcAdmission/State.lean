/-
  GcAdmission/State.lean

  The Level-2 model of the LayerFS GC admission / liveness design.
  Everything here is pure, computable and Mathlib-free: the only imports are
  the Lean 4 standard library.

  Modelling note.  The plan's §5.3 uses `Finset` for the enumerated
  collections and a plain `audit : OpId → Option Intent` field.  Lean 4 core
  (and `Std`) does not ship `Finset`, and the task forbids Mathlib, so the
  enumerated collections are `List`s with deduplicated updates.  The audit
  set is *derived* from the live intent map as its `done` rows, which is the
  structural form of the SQLite compact's `Copy::Done`: the done rows are
  exactly the retained rows.  This keeps the eight invariant statements of
  §7 verbatim while making the retention property provable.
-/
import Std

namespace GcAdmission

abbrev OpId      := Nat
abbrev BranchId  := Nat
abbrev ProjectId := Nat
abbrev MachineId := String
abbrev SandboxId := String
abbrev HomeId    := String
abbrev BootId    := String
abbrev Fence     := String
abbrev Ms        := Nat

/-! ## 5.1 Ordered token and place relation -/

/-- A place token `p1:<label>:<ms>:<nonce>`.  The label is part of the token
but not of the within-kind order: admission compares a worker token with a
worker token and a Sandbox token with a Sandbox token, never across kinds. -/
structure Ordered where
  label : String
  ms    : Nat
  nonce : String
  deriving DecidableEq, Repr

/-- Tokens are ordered only within one label. -/
def Ordered.sameLabel (a b : Ordered) : Prop := a.label = b.label

/-- `a` is strictly older than `b` (same-label tokens). -/
def Ordered.lt (a b : Ordered) : Prop :=
  a.ms < b.ms ∨ (a.ms = b.ms ∧ a.nonce < b.nonce)

instance : LT Ordered := ⟨Ordered.lt⟩

instance (a b : Ordered) : Decidable (a < b) := by
  change Decidable (a.ms < b.ms ∨ (a.ms = b.ms ∧ a.nonce < b.nonce))
  infer_instance

/-- Asymmetry of the within-label order; used by the ordered-rule proofs. -/
theorem Ordered.lt_asymm {a b : Ordered} (h : a < b) : ¬ b < a := by
  intro hba
  rcases h with h | ⟨hms, hn⟩ <;> rcases hba with h' | ⟨h'ms, h'n⟩
  · omega
  · omega
  · omega
  · exact String.lt_asymm hn h'n

/-- Transitivity of the within-label order. -/
theorem Ordered.lt_trans {a b c : Ordered} (h₁ : a < b) (h₂ : b < c) : a < c := by
  rcases h₁ with h₁ | ⟨h₁, h₁'⟩ <;> rcases h₂ with h₂ | ⟨h₂, h₂'⟩
  · exact Or.inl (by omega)
  · exact Or.inl (by omega)
  · exact Or.inl (by omega)
  · exact Or.inr ⟨by omega, String.lt_trans h₁' h₂'⟩

/-- Irreflexivity of the within-label order. -/
theorem Ordered.lt_irrefl (a : Ordered) : ¬ a < a := by
  intro h
  rcases h with h | ⟨_, h⟩
  · omega
  · exact String.lt_irrefl _ h

/-- The recorded/current relation, mirroring `contract::authority::PlaceOrder`. -/
inductive PlaceOrder
  | equal
  | recordedOlder   -- recorded < current: the current place is newer
  | recordedNewer   -- recorded > current: a restore/rollback
  | unordered       -- at least one value predates `p1:` and the two differ
  deriving DecidableEq, Repr

/-- A place value as admission can see it. `legacy` is any value that does not
parse; it compares equal only to itself and never proves death. -/
inductive PlaceValue
  | missing
  | ordered (o : Ordered)
  | legacy  (raw : String)
  deriving DecidableEq, Repr

/-- Cross-label is no proof: the design never compares a worker token with
a Sandbox token, and widening the model to do so would be unsound. -/
def comparePlace : PlaceValue → PlaceValue → PlaceOrder
  | .ordered a, .ordered b =>
      if a.label ≠ b.label then .unordered
      else if a < b then .recordedOlder
      else if b < a then .recordedNewer
      else .equal
  | .legacy a, .legacy b => if a = b then .equal else .unordered
  | _, _ => .unordered

/-- The current place is newer than the recorded one (the death direction). -/
def newer (recorded current : PlaceValue) : Prop :=
  comparePlace recorded current = .recordedOlder

/-- The current place is older than the recorded one (a restore: uncertain). -/
def older (recorded current : PlaceValue) : Prop :=
  comparePlace recorded current = .recordedNewer

/-- The two values name the same place. -/
def equal (recorded current : PlaceValue) : Prop :=
  comparePlace recorded current = .equal

def unordered (recorded current : PlaceValue) : Prop :=
  comparePlace recorded current = .unordered

/-- Parse the real `p1:<label>:<ms>:<nonce>` shape into the ordered model.
Anything else is absent evidence, never death. -/
def parseToken (raw : String) : Option Ordered :=
  match raw.splitOn ":" with
  | ["p1", label, ms, nonce] =>
      match ms.toNat? with
      | some ms => if nonce.isEmpty then none else some ⟨label, ms, nonce⟩
      | none    => none
  | _ => none

/-- The pure ordered lemma used by the `omega` proofs. -/
theorem newer_iff_lt {a b : Ordered} (hlabel : a.label = b.label) :
    newer (.ordered a) (.ordered b) ↔ a < b := by
  by_cases h : a < b
  · simp [newer, comparePlace, hlabel, h]
  · have hne : comparePlace (.ordered a) (.ordered b) ≠ .recordedOlder := by
      simp [comparePlace, hlabel, h]
      split <;> simp
    simp [newer, hne, h]

/-- The restore direction: an older current value is `recordedNewer`. -/
theorem older_iff_gt {a b : Ordered} (hlabel : a.label = b.label) :
    older (.ordered a) (.ordered b) ↔ b < a := by
  by_cases hba : b < a
  · have hnot : ¬ a < b := fun hab => Ordered.lt_asymm hab hba
    simp [older, comparePlace, hlabel, hnot, hba]
  · have hne : comparePlace (.ordered a) (.ordered b) ≠ .recordedNewer := by
      simp [comparePlace, hlabel, hba]
      split <;> simp
    simp [older, hne, hba]

/-- The comparePlace cases used by the main proof. -/
theorem comparePlace_eq_refl_ordered {a : Ordered} :
    comparePlace (.ordered a) (.ordered a) = .equal := by
  simp [comparePlace, Ordered.lt_irrefl]

theorem comparePlace_ordered_older {a b : Ordered} (hlabel : a.label = b.label)
    (h : a < b) : comparePlace (.ordered a) (.ordered b) = .recordedOlder := by
  simp [comparePlace, hlabel, h]

theorem comparePlace_ordered_newer {a b : Ordered} (hlabel : a.label = b.label)
    (h : b < a) : comparePlace (.ordered a) (.ordered b) = .recordedNewer := by
  have hnot : ¬ a < b := fun hab => Ordered.lt_asymm hab h
  simp [comparePlace, hlabel, hnot, h]

theorem comparePlace_ordered_equal {a b : Ordered} (hlabel : a.label = b.label)
    (h : a = b) : comparePlace (.ordered a) (.ordered b) = .equal := by
  subst h
  exact comparePlace_eq_refl_ordered

theorem comparePlace_legacy_refl {a : String} :
    comparePlace (.legacy a) (.legacy a) = .equal := by
  unfold comparePlace; simp

/-! ## 5.2 Liveness, evidence, and the verdict -/

inductive Liveness
  | live
  | uncertain
  | dead
  deriving DecidableEq, Repr

inductive RowState
  | live
  | uncertain
  | done
  deriving DecidableEq, Repr

inductive Principal
  | owner        -- the owner's own graceful unmount/close
  | operator     -- the explicit first-class repair
  | reconcile    -- the worker-start automatic reconcile
  deriving DecidableEq, Repr

inductive Action
  | preview | settle | release | archive | reconcile | adopt | close | unmount
  deriving DecidableEq, Repr

/-- The owner evidence the intent itself carries; the fallback for a private or
place-null row. Missing/another-namespace evidence is never death. -/
inductive OwnerEvidence
  | sameBootLive
  | oldBoot
  | otherNamespace
  | none
  deriving DecidableEq, Repr

def ownerVerdict : OwnerEvidence → Liveness
  | .sameBootLive   => .live
  | .oldBoot        => .dead
  | .otherNamespace => .live
  | .none           => .live

/-- The four `gc_intent` authority columns, as the intent records them. -/
structure RecordedPlace where
  machine      : Option PlaceValue
  sandbox      : Option PlaceValue
  leaseExpires : Option Ms
  fence        : Option Fence
  deriving DecidableEq, Repr

/-- The current values one admission compares against (the bounded view's
answer for one machine/sandbox). -/
structure PlaceRecord where
  machine : Option PlaceValue
  sandbox : Option PlaceValue
  retired : Option PlaceValue   -- the machine tombstone's generation
  deriving DecidableEq, Repr

/-- Whether a witness is a place decision or the owner fallback. -/
inductive WitnessKind
  | place
  | owner
  deriving DecidableEq, Repr

/-- The snapshot admission decided; stored on the row so a retained done row
is auditable after the home moved on.  A place witness carries the bounded
`PlaceRecord`; an owner witness carries the `OwnerEvidence` fallback. -/
structure Witness where
  kind          : WitnessKind
  now           : Ms
  recorded      : RecordedPlace
  place         : Option PlaceRecord
  ownerEvidence : OwnerEvidence
  verdict       : Liveness
  deriving DecidableEq, Repr

/-- Machine-incarnation comparison: the machine wins before the Sandbox. -/
def compareMachine (recorded current : Option PlaceValue) : Option Liveness :=
  match recorded, current with
  | some r, some c =>
      match comparePlace r c with
      | .recordedOlder => some .dead
      | .recordedNewer => some .uncertain
      | .unordered     => some .uncertain
      | .equal         => none
  | _, _ => none

/-- Sandbox generation comparison, including the retained tombstone. -/
def compareSandbox (recorded current retired : Option PlaceValue) :
    Option Liveness :=
  match recorded with
  | none => none
  | some r =>
      match current with
      | some c =>
          match comparePlace r c with
          | .recordedOlder => some .dead
          | .recordedNewer => some .uncertain
          | .unordered     => some .uncertain
          | .equal =>
              match retired with
              | some t =>
                  match comparePlace r t with
                  | .equal          => some .dead
                  | .recordedOlder  => some .dead
                  | .recordedNewer  => none          -- an earlier Sandbox
                  | .unordered      => some .uncertain
              | none => none
      | none =>
          match retired with
          | some t =>
              match comparePlace r t with
              | .equal         => some .dead
              | .recordedOlder => some .dead
              | .recordedNewer => some .uncertain     -- a restore
              | .unordered     => some .uncertain
          | none => none

/-- The hand translation of `PlaceAuthority::liveness`.  The order is exact:
machine incarnation first, then the Sandbox generation (record first, then the
tombstone), then the lease. -/
def placeVerdict (now : Ms) (recorded : RecordedPlace)
    (place : PlaceRecord) : Liveness :=
  match compareMachine recorded.machine place.machine with
  | some v => v
  | none =>
      match compareSandbox recorded.sandbox place.sandbox place.retired with
      | some v => v
      | none =>
          match recorded.leaseExpires with
          | some e => if e ≤ now then .uncertain else .live
          | none   => .live

/-- The verdict the row's stored `Witness` must agree with. -/
def WitnessConsistent (w : Witness) : Prop :=
  match w.kind with
  | .place =>
      ∃ p, w.place = some p ∧ w.verdict = placeVerdict w.now w.recorded p
  | .owner =>
      w.place = none ∧ w.verdict = ownerVerdict w.ownerEvidence

/-! ## 5.3 State -/

structure Intent where
  op             : OpId
  state          : RowState
  branch         : Option BranchId
  project        : Option ProjectId
  machine        : Option MachineId
  sandbox        : Option SandboxId
  ownerBoot      : Option BootId
  ownerEvidence  : OwnerEvidence
  recorded       : RecordedPlace
  evidence       : String
  doneBy         : Option Principal
  uncertain      : Bool          -- the DB `uncertain` column: true marks the
                                 -- row unresolved and blocks any automatic
                                 -- adoption or compact deletion
  settled        : Bool          -- an explicit operator settle marked the row;
                                 -- retained on the done row for the audit
  action         : Option Action
  witness        : Option Witness
  releasedWith   : Option Fence
  deriving DecidableEq, Repr

/-- The Store record's `machines.<m>` entry: G1's optional home path. -/
structure StoreMachine where
  home : Option HomeId
  deriving DecidableEq, Repr

structure Sandbox where
  machine    : MachineId
  generation : Option PlaceValue
  retired    : Option PlaceValue
  deriving DecidableEq, Repr

/-- One machine's home record: its ordered incarnation, its current
Sandbox records, the machine-level retired Sandboxes, and whether this
admission can read it.  The `retired` list is the model of
`machine/<machine>/sandbox-retired/<name>.json`; it survives the Sandbox
record's deletion. -/
structure Machine where
  machine     : MachineId
  incarnation : Option PlaceValue
  sandboxes   : List (SandboxId × Sandbox)
  retired     : List (SandboxId × PlaceValue)
  reachable   : Bool
  deriving DecidableEq, Repr

/-- One machine home in the G1 merge (the `Home` alias of `Machine`). -/
abbrev Home := Machine

inductive BranchState
  | live
  | removed
  deriving DecidableEq, Repr

/-- The Store record.  `entries` is the finite support of `intentMap`: an
intent key is only visible when it is listed.  That is what lets the
transition guards (which quantify over every live intent) be executable
without an unbounded function scan. -/
structure Store where
  branches  : BranchId → Option BranchState
  intentMap : OpId → Option Intent
  entries   : List OpId
  exported  : List OpId
  machines  : List (MachineId × StoreMachine)
  compacted : Bool

/-- The live intent map.  Keys outside `entries` are absent. -/
def Store.intents (s : Store) (op : OpId) : Option Intent :=
  if op ∈ s.entries then s.intentMap op else none

/-- The audit/retained done set: the done rows of the live map (`Copy::Done`). -/
def Store.audit (s : Store) : OpId → Option Intent :=
  fun op => (s.intents op).filter (fun i => i.state == .done)

/-- The empty Store. -/
def Store.empty : Store :=
  { branches := fun _ => none
  , intentMap := fun _ => none
  , entries := []
  , exported := []
  , machines := []
  , compacted := false }

structure State where
  store        : Store
  homes        : List (HomeId × Home)
  callerHome   : HomeId
  branchProject : BranchId → Option ProjectId   -- static project ownership
  now          : Ms

/-- The lookups H3/H5 use.  A missing home, a machine without a record and a
missing tombstone are all `none` (no proof, never death). -/
def Home.incarnationIn (h : Home) (m : MachineId) : Option PlaceValue :=
  if h.machine = m then h.incarnation else none

def homeIncarnationIn (s : State) (h : HomeId) (m : MachineId) : Option PlaceValue :=
  (s.homes.find? (fun p => p.1 = h)).bind (fun p => p.2.incarnationIn m)

def homeIncarnation (s : State) (m : MachineId) : Option PlaceValue :=
  (s.homes.find? (fun p => p.2.machine = m)).bind (fun p => p.2.incarnation)

def tombstone (s : State) (m : MachineId) (sb : SandboxId) : Option PlaceValue :=
  (s.homes.find? (fun p => p.2.machine = m)).bind fun p =>
    (p.2.retired.find? (fun t => t.1 = sb)).map (·.2)

def State.homeFor (s : State) (m : MachineId) : Option Home :=
  (s.homes.find? (fun p => p.2.machine = m)).map (·.2)

def storeMachine (s : State) (m : MachineId) : StoreMachine :=
  match s.store.machines.find? (fun p => p.1 = m) with
  | some (_, entry) => entry
  | none            => { home := none }

/-! ## 5.4 Building the bounded cross-home view (G1) -/

/-- The bounded view one admission compares. -/
structure PlaceView where
  machines  : List (MachineId × PlaceValue)
  sandboxes : List (MachineId × SandboxId × Option PlaceValue × Option PlaceValue)
  deriving DecidableEq, Repr

/-- One machine's current value in the view; `none` is no proof. -/
def PlaceView.machineOf (v : PlaceView) (m : MachineId) : Option PlaceValue :=
  (v.machines.find? (fun p => p.1 = m)).map (·.2)

/-- The view's answer for one intent's machine/sandbox names; `none` when the
view carries no evidence for any of them (a missing name is no proof). -/
def PlaceView.record (v : PlaceView) (machine : Option MachineId)
    (sandbox : Option SandboxId) : Option PlaceRecord :=
  match machine, sandbox with
  | some m, some sb =>
      let mach := v.machineOf m
      let e := v.sandboxes.find? (fun p => p.1 = m ∧ p.2.1 = sb)
      let gen := e.bind (fun p => p.2.2.1)
      let ret := e.bind (fun p => p.2.2.2)
      if mach.isNone && gen.isNone && ret.isNone then none
      else some { machine := mach, sandbox := gen, retired := ret }
  | some m, none =>
      let mach := v.machineOf m
      if mach.isNone then none
      else some { machine := mach, sandbox := none, retired := none }
  | none, some _ => none
  | none, none => none

/-- The `machines.<m>.home` values the Store record carries. -/
def Store.machineHomes (s : Store) : List HomeId :=
  s.machines.filterMap (fun p => p.2.home)

/-- The homes one admission may read: the caller's home first, then every
recorded home that exists and is reachable. -/
def reachableHomes (s : State) : List HomeId :=
  s.callerHome :: s.store.machineHomes.filter (fun h =>
    match s.homes.find? (fun p => p.1 = h) with
    | some (_, home) => home.reachable
    | none => false)

/-- One place field's merge state.  The real `place_view::Field` is **sticky**:
a conflicting value leaves the field absent for good, and a later home cannot
resurrect it.  A non-sticky fold would make the result depend on home order. -/
structure PlaceField where
  value      : Option PlaceValue
  conflicted : Bool
  deriving DecidableEq, Repr

def PlaceField.empty : PlaceField := { value := none, conflicted := false }

def PlaceField.observe (f : PlaceField) (x : PlaceValue) : PlaceField :=
  if f.conflicted then f
  else match f.value with
  | none => { value := some x, conflicted := false }
  | some current =>
      if current = x then f
      else match comparePlace current x with
      | .equal         => f
      | .recordedOlder => { value := some x, conflicted := false }
      | .recordedNewer => f
      | .unordered     => { value := none, conflicted := true }

/-- The accumulated fields over the homes read so far. -/
structure Merged where
  machines  : List (MachineId × PlaceField)
  sandboxes : List (MachineId × SandboxId × PlaceField × PlaceField)

def Merged.empty : Merged := { machines := [], sandboxes := [] }

def Merged.observeMachine (m : Merged) (k : MachineId) (x : PlaceValue) : Merged :=
  match m.machines.find? (fun p => p.1 = k) with
  | none => { m with machines := ((k, PlaceField.empty.observe x) :: m.machines) }
  | some (_, f) =>
      { m with machines := (m.machines.map (fun p => if p.1 = k then (k, f.observe x) else p)) }

def Merged.observeSandbox (m : Merged) (k : MachineId) (sb : SandboxId)
    (g r : Option PlaceValue) : Merged :=
  match m.sandboxes.find? (fun p => p.1 = k ∧ p.2.1 = sb) with
  | none =>
      let fg := match g with | some x => PlaceField.empty.observe x | none => PlaceField.empty
      let fr := match r with | some x => PlaceField.empty.observe x | none => PlaceField.empty
      { m with sandboxes := ((k, sb, fg, fr) :: m.sandboxes) }
  | some (_, _, fg, fr) =>
      let fg' := match g with | some x => fg.observe x | none => fg
      let fr' := match r with | some x => fr.observe x | none => fr
      { m with sandboxes := (m.sandboxes.map (fun p => if p.1 = k ∧ p.2.1 = sb then (k, sb, fg', fr') else p)) }

/-- Merge one home's places into the accumulated fields; a current record and
a tombstone for the same Sandbox land in the same two fields. -/
def Merged.observeHome (m : Merged) (h : Home) : Merged :=
  let m := match h.incarnation with
    | some v => m.observeMachine h.machine v
    | none => m
  let m := h.sandboxes.foldl (fun m p =>
      m.observeSandbox h.machine p.1 p.2.generation p.2.retired) m
  h.retired.foldl (fun m p => m.observeSandbox h.machine p.1 none (some p.2)) m

/-- The final view: keep every surviving (non-conflicted) value. -/
def Merged.view (m : Merged) : PlaceView :=
  { machines := m.machines.filterMap (fun p => p.2.value.map (fun v => (p.1, v)))
  , sandboxes := m.sandboxes.filterMap (fun p =>
      match p.2.2.1.value, p.2.2.2.value with
      | none, none => none
      | g, r => some (p.1, p.2.1, g, r)) }

/-- The merged view of one home's places.  A current record contributes its
generation and the `Sandbox.retired` field it carries; a machine tombstone
contributes a retired-only entry, so a Sandbox whose record was deleted is
still visible to admission. -/
def Home.view (h : Home) : PlaceView :=
  { machines := (h.incarnation.map (fun v => [(h.machine, v)])).getD []
  , sandboxes :=
      (h.sandboxes.filterMap (fun p =>
        p.2.generation.map (fun g => (h.machine, p.1, some g, p.2.retired))))
      ++ (h.retired.map (fun p => (h.machine, p.1, none, some p.2))) }

/-- The bounded cross-home view.  Truncation can only remove a value (no
proof). -/
def viewOf (s : State) : PlaceView :=
  ((reachableHomes s).foldl (fun m h =>
      match s.homes.find? (fun p => p.1 = h) with
      | some (_, home) => m.observeHome home
      | none => m) Merged.empty).view

/-- The cap counts *places*, not map entries. -/
def PlaceView.placeCount (v : PlaceView) : Nat :=
  v.machines.length +
    v.sandboxes.foldl (fun n p =>
      n + (match p.2.2.1 with | some _ => 1 | none => 0)
        + (match p.2.2.2 with | some _ => 1 | none => 0)) 0

/-! ## 5.5 The admission verdict -/

/-- The current place one admission compares against.  The bounded view wins;
when it carries nothing for this intent, the intent's own recorded place is the
fallback, so a placed row whose home this caller cannot read is Live, not
owner-killed.  Only a truly place-null intent gets the owner fallback. -/
def placeOf (s : State) (i : Intent) : Option PlaceRecord :=
  match (viewOf s).record i.machine i.sandbox with
  | some p => some p
  | none =>
      match i.recorded.machine, i.recorded.sandbox with
      | none, none => none
      | m, sb => some { machine := m, sandbox := sb, retired := none }

def verdict (s : State) (i : Intent) : Liveness :=
  match placeOf s i with
  | some p => placeVerdict s.now i.recorded p
  | none   => ownerVerdict i.ownerEvidence

def Dead (s : State) (i : Intent) : Prop := verdict s i = .dead
def Uncertain (s : State) (i : Intent) : Prop := verdict s i = .uncertain
def Live (s : State) (i : Intent) : Prop := verdict s i = .live

/-- Death from the place authority alone (the automatic path). -/
def PlaceDead (s : State) (i : Intent) : Prop :=
  match placeOf s i with
  | some p => placeVerdict s.now i.recorded p = .dead
  | none   => False

/-- Death from the caller's own namespace/boot evidence (the fallback). -/
def OwnerDead (s : State) (i : Intent) : Prop :=
  placeOf s i = none ∧ ownerVerdict i.ownerEvidence = .dead

/-- The witness of a direct audit row (preview) that names no place and no
owner evidence; its verdict is the owner fallback `.live`, so it is
consistent but never proves death. -/
def auditWitness (s : State) : Witness :=
  { kind := .owner
  , now := s.now
  , recorded := { machine := none, sandbox := none,
                  leaseExpires := none, fence := none }
  , place := none
  , ownerEvidence := .none
  , verdict := .live }

/-- The snapshot a mount/admission stores. -/
def witnessFor (s : State) (i : Intent) : Witness :=
  match placeOf s i with
  | some p =>
      { kind := .place, now := s.now, recorded := i.recorded,
        place := some p, ownerEvidence := i.ownerEvidence,
        verdict := placeVerdict s.now i.recorded p }
  | none =>
      { kind := .owner, now := s.now, recorded := i.recorded,
        place := none, ownerEvidence := i.ownerEvidence,
        verdict := ownerVerdict i.ownerEvidence }

end GcAdmission
