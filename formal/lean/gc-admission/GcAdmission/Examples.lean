import GcAdmission.Proofs

/-!
  GcAdmission/Examples.lean

  Executable regression net.  `#guard` elaborates a `Bool` at build time, so a
  false example breaks `lake build`.  24 closed computations: the pure ordered
  authority, the verdict cases, and one example for every invariant plus the
  G1/G2/G4 behaviours (matrix in README.md).
-/
namespace GcAdmission

def w10 : Ordered := ⟨"worker", 10, "aa"⟩
def w20 : Ordered := ⟨"worker", 20, "aa"⟩
def s10 : Ordered := ⟨"sandbox", 10, "aa"⟩
def s20 : Ordered := ⟨"sandbox", 20, "aa"⟩

def rp (m sb : Option PlaceValue) (e : Option Ms) : RecordedPlace :=
  { machine := m, sandbox := sb, leaseExpires := e, fence := none }

def pp (m sb r : Option PlaceValue) : PlaceRecord :=
  { machine := m, sandbox := sb, retired := r }

/-! ### Ordered compare and parse (8) -/

#guard comparePlace (.ordered w10) (.ordered w20) = .recordedOlder
#guard comparePlace (.ordered w20) (.ordered w10) = .recordedNewer
#guard comparePlace (.ordered w10) (.ordered w10) = .equal
#guard comparePlace (.ordered w10) (.ordered s10) = .unordered
#guard comparePlace (.legacy "worker:7") (.legacy "worker:8") = .unordered
#guard parseToken "p1:worker:0000000000000010:aa" = some w10
#guard parseToken "worker:10" = none
#guard parseToken "p1:worker:0000000000000010:" = none

/-! ### Place verdict (9) -/

#guard placeVerdict 1000 (rp (some (.ordered w10)) none none)
  (pp (some (.ordered w20)) none none) = .dead
#guard placeVerdict 1000 (rp (some (.ordered w20)) none none)
  (pp (some (.ordered w10)) none none) = .uncertain
#guard placeVerdict 1000 (rp (some (.ordered w10)) none none)
  (pp (some (.ordered w10)) none none) = .live
#guard placeVerdict 1000 (rp none none (some 500)) (pp none none none) = .uncertain
#guard placeVerdict 1000 (rp none none (some 2000)) (pp none none none) = .live
#guard placeVerdict 1000 (rp none none none) (pp none none none) = .live
#guard placeVerdict 1000 (rp none (some (.ordered s10)) none)
  (pp none (some (.ordered s10)) (some (.ordered s10))) = .dead
#guard placeVerdict 1000 (rp none (some (.ordered s20)) none)
  (pp none (some (.ordered s20)) (some (.ordered s10))) = .live
#guard placeVerdict 1000 (rp none (some (.ordered s20)) none)
  (pp none none (some (.ordered s10))) = .uncertain

/-! ### Witness construction (2) -/

def st0 : State :=
  { store := Store.empty, homes := [], callerHome := "h0",
    branchProject := fun _ => none, now := 1000 }

def i0 : Intent :=
  { op := 1, state := .live, branch := none, project := none,
    machine := none, sandbox := none, ownerBoot := none,
    ownerEvidence := .none,
    recorded := { machine := none, sandbox := none, leaseExpires := none, fence := none },
    evidence := "", doneBy := none, uncertain := false, settled := false,
    action := none, witness := none, releasedWith := none }

#guard (witnessFor st0 { i0 with ownerEvidence := .oldBoot }).verdict = .dead
#guard (auditWitness st0).verdict = .live

/-! ### Transitions, G1, G2, G4 (5) -/

def iMount : Intent :=
  { i0 with op := 5, state := .live, branch := some 7, machine := some "m1" }

def stRemoved : State :=
  { st0 with store := { Store.empty with branches := fun b => if b = 7 then some .removed else none } }

-- Inv1: a mount on a removed Branch is refused.
#guard (step (.sandboxMount iMount) stRemoved).store.intents 5 = none

def liveIntent : Intent := { i0 with op := 1, state := .live, branch := some 7 }

def stLive : State :=
  { st0 with store :=
      { (Store.empty.addIntent 1 liveIntent) with branches := fun _ => some .live } }

-- Inv5: a live intent blocks compact.
#guard (step .storeCompact stLive).store.compacted = false

def fenceIntent : Intent :=
  let r : RecordedPlace :=
    { machine := none, sandbox := none, leaseExpires := none, fence := some "f1" }
  { i0 with op := 1, state := .uncertain, uncertain := true, recorded := r }

def stFence : State := { st0 with store := Store.empty.addIntent 1 fenceIntent }

-- Inv6: a stale fence token leaves the row untouched.
#guard (step (.operatorRelease 1 "op" (some "f2")) stFence).store.intents 1 =
  stFence.store.intents 1

def doneIntent : Intent :=
  { i0 with op := 1, state := .done, doneBy := some .operator, action := some .release, settled := true }

def stDone : State := { st0 with store := Store.empty.addIntent 1 doneIntent }

-- Inv7 / G2: archive exports the done row (export before prune).
#guard (step (.operatorArchive [1] false) stDone).store.exported.contains 1 = true

-- G4: preview retains a done row.
#guard ((step (.operatorPreview 7 9 "op") st0).store.intents 9).map (fun i => i.state) =
  some .done

def homeInc (v : Ordered) : Home :=
  { machine := "m1", incarnation := some (.ordered v), sandboxes := [], retired := [],
    reachable := true }

def stTwoHomes : State :=
  { store := { Store.empty with machines := [("m1", { home := some "h1" })] }
  , homes := [("h0", homeInc w20), ("h1", homeInc w10)]
  , callerHome := "h0"
  , branchProject := fun _ => none
  , now := 1000 }

def iG1 : Intent :=
  let r : RecordedPlace :=
    { machine := some (.ordered w10), sandbox := none, leaseExpires := none, fence := none }
  { i0 with op := 9, machine := some "m1", recorded := r }

-- G1: the merged view keeps the newer of two reachable homes.
#guard verdict stTwoHomes iG1 = .dead

end GcAdmission
