import GcAdmission.Invariants

/-!
  GcAdmission/Examples.lean

  Executable regression net.  `#guard` elaborates a `Bool` at build time, so a
  false example breaks `lake build`.  These are closed computations of the
  pure authority (and, later, of real transitions); they are not a substitute
  for the universal theorem in `Proofs.lean`.
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

/-! ### Ordered compare (9) -/

#guard comparePlace (.ordered w10) (.ordered w20) = .recordedOlder
#guard comparePlace (.ordered w20) (.ordered w10) = .recordedNewer
#guard comparePlace (.ordered w10) (.ordered w10) = .equal
#guard comparePlace (.ordered ⟨"worker", 10, "ab"⟩) (.ordered ⟨"worker", 10, "aa"⟩) = .recordedNewer
#guard comparePlace (.legacy "worker:7") (.legacy "worker:8") = .unordered
#guard comparePlace (.legacy "worker:7") (.legacy "worker:7") = .equal
#guard comparePlace (.ordered w10) (.ordered ⟨"sandbox", 10, "aa"⟩) = .unordered
#guard parseToken "p1:worker:0000000000000010:aa" = some w10
#guard parseToken "worker:10" = none
#guard parseToken "p1:worker:0000000000000010:" = none

/-! ### Place verdict (8) -/

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

/-! ### Witness construction (3) -/

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
#guard (witnessFor st0 i0).verdict = .live
#guard (auditWitness st0).verdict = .live

end GcAdmission
