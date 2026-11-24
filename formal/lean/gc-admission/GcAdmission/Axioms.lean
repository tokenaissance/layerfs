import GcAdmission.Proofs

/-!
  GcAdmission/Axioms.lean

  The axiom receipt for the main theorem.  `lake env lean GcAdmission/Axioms.lean`
  prints the closure; `tools/check_lean_axioms.py` accepts only `propext`,
  `Classical.choice` and `Quot.sound` and fails on `sorryAx` or any user axiom.
-/
open GcAdmission

#print axioms GcAdmission.step_preserves
