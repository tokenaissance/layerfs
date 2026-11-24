import GcAdmission.State

/-!
  GcAdmission/Transitions.lean

  The 15 transitions of §6.  Guards are executable `Bool` predicates over the
  finite support `Store.entries`; a refused guard returns the state unchanged.
  Keeping the guards computable is what makes the `#guard` regression net in
  `Examples.lean` evaluate real transitions.
-/

namespace GcAdmission

/-! ### Store update helpers -/

/-- Insert (or replace) one intent, keeping the finite support in sync. -/
def Store.addIntent (s : Store) (op : OpId) (i : Intent) : Store :=
  { s with
    entries := op :: s.entries.filter (fun x => x ≠ op)
    intentMap := fun x => if x = op then some i else s.intentMap x }

/-- Remove one intent from the visible map. -/
def Store.removeIntent (s : Store) (op : OpId) : Store :=
  { s with entries := s.entries.filter (fun x => x ≠ op) }

/-- Remove every intent satisfying a predicate.  The map is left alone; an
entry removed from `entries` is no longer visible through `Store.intents`. -/
def Store.removeWhere (s : Store) (p : OpId → Intent → Bool) : Store :=
  { s with
    entries := s.entries.filter (fun op =>
      match s.intents op with
      | some i => !p op i
      | none => true) }

/-- Update one intent in place. -/
def Store.updateIntent (s : Store) (op : OpId) (f : Intent → Intent) : Store :=
  { s with
    intentMap := fun x => if x = op then (s.intentMap x).map f else s.intentMap x }

/-! ### Bool guards -/

def fenceOk (i : Intent) (f : Option Fence) : Bool :=
  match f with
  | none => true
  | some x => i.recorded.fence == some x

/-- An intent holds Branch `b` when it names `b`, when it is Store-scoped, or
when it is Project-scoped for the project that owns `b` (the boolean form of
§7's `HoldsBranch`). -/
def holdsBranchB (s : State) (b : BranchId) (i : Intent) : Bool :=
  (i.branch == some b) ||
  (i.branch == none && i.project == none) ||
  (i.branch == none &&
    (match i.project with
     | some p => (match s.branchProject b with
                  | none => true
                  | some q => p == q)
     | none => false))

/-- Every visible non-done intent is dead-certain (Dead and not uncertain). -/
def allDeadCertainB (s : State) : Bool :=
  s.store.entries.all (fun op =>
    match s.store.intents op with
    | none => true
    | some i => i.state == .done || (verdict s i == .dead && !i.uncertain))

/-- Every visible non-done holder of `b` is dead-certain. -/
def allDeadCertainOnB (s : State) (b : BranchId) : Bool :=
  s.store.entries.all (fun op =>
    match s.store.intents op with
    | none => true
    | some i =>
        !holdsBranchB s b i || i.state == .done ||
          (verdict s i == .dead && !i.uncertain))

def mountOk (s : State) (i : Intent) : Bool :=
  i.state == .live &&
  (s.store.intents i.op).isNone &&
  (match i.branch with
   | some b => s.store.branches b == some .live
   | none => false)

def sandboxCreateOk (s : State) (m : MachineId) (sb : SandboxId)
    (gen : Ordered) : Bool :=
  match s.homeFor m with
  | none => false
  | some h =>
      (h.sandboxes.find? (fun p => p.1 = sb)).isNone &&
      (h.retired.filter (fun p => p.1 = sb)).all (fun p =>
        match p.2 with
        | .ordered g => decide (g < gen)
        | _ => true)

def sandboxCloseOk (s : State) (m : MachineId) (sb : SandboxId)
    (gen : Ordered) : Bool :=
  match s.homeFor m with
  | none => false
  | some h =>
      match (h.sandboxes.find? (fun p => p.1 = sb)).bind (fun p => p.2.generation) with
      | some (.ordered g) => g == gen
      | _ => false

def machineStartOk (s : State) (m : MachineId) (inc : Ordered) : Bool :=
  match s.homeFor m with
  | none => false
  | some h =>
      match h.incarnation with
      | none => true
      | some (.ordered cur) => cur.label == inc.label && decide (cur < inc)
      | some _ => true

def machineRestoreOk (s : State) (m : MachineId) (inc : Ordered) : Bool :=
  match s.homeFor m with
  | none => false
  | some h =>
      match h.incarnation with
      | some (.ordered cur) => cur.label == inc.label && decide (inc < cur)
      | _ => false

def sandboxUnmountOk (s : State) (op : OpId) : Bool :=
  match s.store.intents op with
  | none => false
  | some i => i.state != .done && i.doneBy == none

def leaseRenewOk (s : State) (op : OpId) (f : Option Fence) : Bool :=
  match s.store.intents op with
  | none => false
  | some i => i.state != .done && fenceOk i f

def operatorSettleOk (s : State) (op : OpId) : Bool :=
  match s.store.intents op with
  | none => false
  | some i => i.state != .done

def operatorReleaseOk (s : State) (op : OpId) (f : Option Fence) : Bool :=
  match s.store.intents op with
  | none => false
  | some i => i.state == .uncertain && fenceOk i f

def previewOk (s : State) (row : OpId) : Bool :=
  (s.store.intents row).isNone &&
  (s.store.audit row).isNone &&
  !(row ∈ s.store.exported)

def archiveOk (s : State) (rows : List OpId) : Bool :=
  rows.all (fun op =>
    match s.store.audit op with
    | some i => i.state == .done
    | none => false)

/-! ### Reconcile at worker start -/

/-- The place record the worker-start reconcile compares against: the new
incarnation, plus the Sandbox/retired values the bounded view already has. -/
def reconcileRecord (s : State) (i : Intent) (inc : Ordered) : PlaceRecord :=
  { machine := some (.ordered inc)
  , sandbox := (placeOf s i).bind (·.sandbox)
  , retired := (placeOf s i).bind (·.retired) }

def reconcileDead (s : State) (m : MachineId) (inc : Ordered)
    (i : Intent) : Prop :=
  i.machine = some m ∧ i.state ≠ .done ∧ i.uncertain = false ∧
    (placeVerdict s.now i.recorded (reconcileRecord s i inc) = .dead ∨
     (i.recorded.machine = none ∧ i.recorded.sandbox = none ∧
      ownerVerdict i.ownerEvidence = .dead))

def reconcileDeadB (s : State) (m : MachineId) (inc : Ordered)
    (i : Intent) : Bool :=
  (i.machine == some m) && (i.state != .done) && (!i.uncertain) &&
  ((placeVerdict s.now i.recorded (reconcileRecord s i inc) == .dead) ||
   (i.recorded.machine == none && i.recorded.sandbox == none &&
    ownerVerdict i.ownerEvidence == .dead))

/-! ### Transition effects -/

/-- Update the home record of machine `m`, if it exists. -/
def State.mapHome (s : State) (m : MachineId) (f : Home → Home) : State :=
  { s with homes := s.homes.map (fun p => if p.2.machine = m then (p.1, f p.2) else p) }

def doSandboxCreate (s : State) (m : MachineId) (sb : SandboxId)
    (gen : Ordered) : State :=
  if sandboxCreateOk s m sb gen then
    s.mapHome m (fun h =>
      { h with
        sandboxes :=
          ((sb, { machine := m, generation := some (.ordered gen), retired := none }) ::
            h.sandboxes.filter (fun p => p.1 ≠ sb)) })
  else s

/-- The explicit `settlePlace` sub-step: release every existing non-done intent
at the admitting machine that is dead-certain (`Dead`, not `PlaceDead`; the
real `settle_place` also accepts the owner-evidence death of a place-null
row).  It never touches a live or uncertain row. -/
def settlePlace (s : State) (intent : Intent) : State :=
  { s with store := s.store.removeWhere (fun _ i =>
      (i.machine == intent.machine) && (i.state != .done) &&
      (!i.uncertain) && (verdict s i == .dead)) }

def doSandboxMount (s : State) (i : Intent) : State :=
  if mountOk s i then
    let s1 := settlePlace s i
    let i1 := { i with witness := some (witnessFor s i) }
    { s1 with store :=
        { (s1.store.addIntent i.op i1) with compacted := false } }
  else s

def doSandboxUnmount (s : State) (op : OpId) : State :=
  if sandboxUnmountOk s op then
    { s with store := s.store.removeIntent op }
  else s

def doSandboxClose (s : State) (m : MachineId) (sb : SandboxId)
    (gen : Ordered) : State :=
  if sandboxCloseOk s m sb gen then
    s.mapHome m (fun h =>
      { h with
        retired := ((sb, .ordered gen) :: h.retired.filter (fun p => p.1 ≠ sb))
        sandboxes := h.sandboxes.filter (fun p => p.1 ≠ sb) })
  else s

def doMachineStart (s : State) (m : MachineId) (inc : Ordered) : State :=
  if machineStartOk s m inc then
    let s1 := s.mapHome m (fun h => { h with incarnation := some (.ordered inc) })
    { s1 with store :=
        s1.store.removeWhere (fun _ i => reconcileDeadB s m inc i) }
  else s

def doMachineRestore (s : State) (m : MachineId) (inc : Ordered) : State :=
  if machineRestoreOk s m inc then
    s.mapHome m (fun h => { h with incarnation := some (.ordered inc) })
  else s

def doAdmissionRecheck (s : State) (op : OpId) : State :=
  match s.store.intents op with
  | none => s
  | some _ =>
      { s with store := s.store.updateIntent op (fun i =>
          { i with witness := some (witnessFor s i) }) }

def doLeaseRenew (s : State) (op : OpId) (f : Option Fence) (e : Ms) : State :=
  if leaseRenewOk s op f then
    { s with store := s.store.updateIntent op (fun i =>
        { i with recorded :=
            { i.recorded with
              leaseExpires :=
                match i.recorded.leaseExpires with
                | none => some e
                | some old => some (max old e) } }) }
  else s

def doBranchRemove (s : State) (b : BranchId) : State :=
  if allDeadCertainOnB s b then
    { s with store :=
        { (s.store.removeWhere (fun _ i => holdsBranchB s b i)) with
          branches := fun x => if x = b then some .removed else s.store.branches x } }
  else s

def doStoreCompact (s : State) : State :=
  if allDeadCertainB s then
    { s with store :=
        { (s.store.removeWhere (fun _ i => i.state != .done)) with
          compacted := true } }
  else s

def previewIntent (s : State) (branch : BranchId) (row : OpId)
    (label : String) : Intent :=
  { op := row
  , state := .done
  , branch := some branch
  , project := s.branchProject branch
  , machine := none
  , sandbox := none
  , ownerBoot := none
  , ownerEvidence := .none
  , recorded := { machine := none, sandbox := none, leaseExpires := none, fence := none }
  , evidence := label
  , doneBy := some .operator
  , uncertain := false
  , settled := false
  , action := some .preview
  , witness := some (auditWitness s)
  , releasedWith := none }

def doOperatorPreview (s : State) (branch : BranchId) (row : OpId)
    (label : String) : State :=
  if previewOk s row then
    { s with store := s.store.addIntent row (previewIntent s branch row label) }
  else s

def doOperatorSettle (s : State) (op : OpId) (label : String) : State :=
  match s.store.intents op with
  | none => s
  | some i =>
      if i.state != .done then
        { s with store := s.store.updateIntent op (fun i =>
            { i with state := .uncertain, uncertain := true, settled := true,
                     witness := some (witnessFor s i) }) }
      else s

def doOperatorRelease (s : State) (op : OpId) (label : String)
    (f : Option Fence) : State :=
  if operatorReleaseOk s op f then
    { s with store := s.store.updateIntent op (fun i =>
        { i with state := .done, uncertain := false, settled := true,
                 doneBy := some .operator, action := some .release,
                 releasedWith := f, ownerBoot := none, evidence := label }) }
  else s

def doOperatorArchive (s : State) (rows : List OpId) (prune : Bool) : State :=
  if archiveOk s rows then
    let s1 := { s with store := { s.store with exported := rows ++ s.store.exported } }
    if prune then
      { s1 with store := rows.foldl (fun st op => st.removeIntent op) s1.store }
    else s1
  else s

/-! ### `Op` and `step` -/

inductive Op where
  | sandboxCreate      (machine : MachineId) (sandbox : SandboxId) (gen : Ordered)
  | sandboxMount       (intent : Intent)
  | sandboxUnmount     (op : OpId)
  | sandboxClose       (machine : MachineId) (sandbox : SandboxId) (gen : Ordered)
  | sandboxForceRemove (machine : MachineId) (sandbox : SandboxId) (gen : Ordered)
  | machineStart       (machine : MachineId) (inc : Ordered)
  | machineRestore     (machine : MachineId) (inc : Ordered)
  | admissionRecheck   (op : OpId)
  | leaseRenew         (op : OpId) (fence : Option Fence) (expires : Ms)
  | branchRemove       (branch : BranchId)
  | storeCompact
  | operatorPreview    (branch : BranchId) (row : OpId) (operator : String)
  | operatorSettle     (op : OpId) (operator : String)
  | operatorRelease    (op : OpId) (operator : String) (fence : Option Fence)
  | operatorArchive    (rows : List OpId) (prune : Bool)
  deriving Repr

/-- One atomic model transition.  A refused guard is the identity. -/
def step : Op → State → State
  | .sandboxCreate m sb gen, s      => doSandboxCreate s m sb gen
  | .sandboxMount i, s              => doSandboxMount s i
  | .sandboxUnmount op, s           => doSandboxUnmount s op
  | .sandboxClose m sb gen, s       => doSandboxClose s m sb gen
  | .sandboxForceRemove m sb gen, s => doSandboxClose s m sb gen
  | .machineStart m inc, s          => doMachineStart s m inc
  | .machineRestore m inc, s        => doMachineRestore s m inc
  | .admissionRecheck op, s         => doAdmissionRecheck s op
  | .leaseRenew op f e, s           => doLeaseRenew s op f e
  | .branchRemove b, s              => doBranchRemove s b
  | .storeCompact, s                => doStoreCompact s
  | .operatorPreview b row label, s => doOperatorPreview s b row label
  | .operatorSettle op label, s     => doOperatorSettle s op label
  | .operatorRelease op label f, s  => doOperatorRelease s op label f
  | .operatorArchive rows prune, s  => doOperatorArchive s rows prune

end GcAdmission
