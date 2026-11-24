import GcAdmission.Invariants

/-!
  GcAdmission/Proofs.lean

  Pure lemmas, the per-transition preservation lemmas and `step_preserves`.
  No Mathlib: `simp`, `split`, `cases`, `omega`, `decide`.
-/
namespace GcAdmission

/-! ## Store: the visible intent map -/

theorem Store.intents_mem {s : Store} {op : OpId} {i : Intent}
    (h : s.intents op = some i) : op ∈ s.entries := by
  unfold Store.intents at h
  by_cases hm : op ∈ s.entries
  · exact hm
  · simp [hm] at h

theorem Store.intents_add_self (s : Store) (op : OpId) (i : Intent) :
    (s.addIntent op i).intents op = some i := by
  change (if op ∈ op :: s.entries.filter (fun y => y ≠ op)
          then (if op = op then some i else s.intentMap op) else none) = some i
  rw [if_pos (by simp), if_pos rfl]

theorem Store.intents_add_other (s : Store) (op x : OpId) (i : Intent) (hx : x ≠ op) :
    (s.addIntent op i).intents x = s.intents x := by
  by_cases h : x ∈ s.entries
  · have h' : x ∈ op :: s.entries.filter (fun y => y ≠ op) := by
      simp [List.mem_filter, h, hx]
    change (if x ∈ op :: s.entries.filter (fun y => y ≠ op)
            then (if x = op then some i else s.intentMap x) else none)
           = (if x ∈ s.entries then s.intentMap x else none)
    rw [if_pos h', if_pos h, if_neg hx]
  · have h' : x ∉ op :: s.entries.filter (fun y => y ≠ op) := by
      simp [List.mem_filter, hx, h]
    change (if x ∈ op :: s.entries.filter (fun y => y ≠ op)
            then (if x = op then some i else s.intentMap x) else none)
           = (if x ∈ s.entries then s.intentMap x else none)
    rw [if_neg h', if_neg h]

theorem Store.intents_remove_self (s : Store) (op : OpId) :
    (s.removeIntent op).intents op = none := by
  have hnot : op ∉ s.entries.filter (fun x => x ≠ op) := by
    simp [List.mem_filter]
  change (if op ∈ s.entries.filter (fun x => x ≠ op) then s.intentMap op else none) = none
  rw [if_neg hnot]

theorem Store.intents_remove_other (s : Store) (op x : OpId) (hx : x ≠ op) :
    (s.removeIntent op).intents x = s.intents x := by
  change (if x ∈ s.entries.filter (fun y => y ≠ op) then s.intentMap x else none)
       = (if x ∈ s.entries then s.intentMap x else none)
  by_cases h : x ∈ s.entries
  · have h' : x ∈ s.entries.filter (fun y => y ≠ op) := by
      simp [List.mem_filter, h, hx]
    rw [if_pos h', if_pos h]
  · have h' : x ∉ s.entries.filter (fun y => y ≠ op) := by
      simp [List.mem_filter, h]
    rw [if_neg h', if_neg h]

theorem Store.intents_removeWhere_sub (s : Store) (p : OpId → Intent → Bool)
    (op : OpId) (i : Intent) (h : (s.removeWhere p).intents op = some i) :
    s.intents op = some i := by
  change (if op ∈ List.filter (fun x =>
      match s.intents x with
      | some i => !p x i
      | none => true) s.entries then s.intentMap op else none) = some i at h
  change (if op ∈ s.entries then s.intentMap op else none) = some i
  by_cases hm : op ∈ s.entries
  · rw [if_pos hm]
    by_cases hf : op ∈ List.filter (fun x =>
        match s.intents x with
        | some i => !p x i
        | none => true) s.entries
    · rw [if_pos hf] at h
      exact h
    · rw [if_neg hf] at h
      simp at h
  · rw [if_neg hm]
    have hf : op ∉ List.filter (fun x =>
        match s.intents x with
        | some i => !p x i
        | none => true) s.entries := by
      intro hmem
      rw [List.mem_filter] at hmem
      exact hm hmem.1
    rw [if_neg hf] at h
    simp at h

theorem Store.intents_removeWhere_removed (s : Store) (p : OpId → Intent → Bool)
    (op : OpId) (i : Intent) (hi : s.intents op = some i) (hp : p op i = true) :
    (s.removeWhere p).intents op = none := by
  have hnot : op ∉ List.filter (fun x =>
      match s.intents x with
      | some i => !p x i
      | none => true) s.entries := by
    intro hmem
    rw [List.mem_filter] at hmem
    obtain ⟨_, hpred⟩ := hmem
    simp [hi, hp] at hpred
  change (if op ∈ List.filter (fun x =>
      match s.intents x with
      | some i => !p x i
      | none => true) s.entries then s.intentMap op else none) = none
  rw [if_neg hnot]

theorem Store.intents_removeWhere_kept (s : Store) (p : OpId → Intent → Bool)
    (op : OpId) (i : Intent) (hi : s.intents op = some i) (hp : p op i = false) :
    (s.removeWhere p).intents op = s.intents op := by
  have hmem : op ∈ List.filter (fun x =>
      match s.intents x with
      | some i => !p x i
      | none => true) s.entries := by
    rw [List.mem_filter]
    exact ⟨Store.intents_mem hi, by simp [hi, hp]⟩
  change (if op ∈ List.filter (fun x =>
      match s.intents x with
      | some i => !p x i
      | none => true) s.entries then s.intentMap op else none) = s.intents op
  rw [if_pos hmem]
  show s.intentMap op = s.intents op
  simp [Store.intents, Store.intents_mem hi]

theorem Store.intents_update_self (s : Store) (op : OpId) (i : Intent)
    (f : Intent → Intent) (hi : s.intents op = some i) :
    (s.updateIntent op f).intents op = some (f i) := by
  have hm : op ∈ s.entries := Store.intents_mem hi
  have hi' : s.intentMap op = some i := by
    simpa [Store.intents, hm] using hi
  change (if op ∈ s.entries then (if op = op then (s.intentMap op).map f else s.intentMap op) else none)
       = some (f i)
  rw [if_pos hm, if_pos rfl, hi']
  rfl

theorem Store.intents_update_other (s : Store) (op x : OpId) (f : Intent → Intent)
    (hx : x ≠ op) : (s.updateIntent op f).intents x = s.intents x := by
  change (if x ∈ s.entries then (if x = op then (s.intentMap x).map f else s.intentMap x) else none)
       = (if x ∈ s.entries then s.intentMap x else none)
  rw [if_neg hx]

theorem Store.audit_eq_some_iff {s : Store} {op : OpId} {i : Intent} :
    s.audit op = some i ↔ s.intents op = some i ∧ i.state = .done := by
  unfold Store.audit
  constructor
  · intro h
    have := (Option.filter_eq_some_iff.mp h)
    exact ⟨this.1, by simpa using this.2⟩
  · intro ⟨h1, h2⟩
    rw [Option.filter_eq_some_iff]
    exact ⟨h1, by simp [h2]⟩

theorem Store.audit_intents {s : Store} {op : OpId} {i : Intent}
    (h : s.audit op = some i) : s.intents op = some i :=
  Store.audit_eq_some_iff.mp h |>.1

/-! ## Witnesses -/

theorem witnessFor_consistent (s : State) (i : Intent) :
    WitnessConsistent (witnessFor s i) := by
  unfold witnessFor
  split
  · rename_i p hp
    exact ⟨p, rfl, rfl⟩
  · rename_i hp
    exact ⟨rfl, rfl⟩

theorem auditWitness_consistent (s : State) :
    WitnessConsistent (auditWitness s) := by
  unfold auditWitness WitnessConsistent
  exact ⟨rfl, rfl⟩

theorem auditWitness_not_place (s : State) :
    (auditWitness s).kind ≠ .place := by
  unfold auditWitness; simp

/-- Every place witness that says `dead` names an ordered cause. -/
theorem compareMachine_dead {r c : Option PlaceValue}
    (h : compareMachine r c = some .dead) :
    ∃ rm cm, r = some rm ∧ c = some cm ∧ comparePlace rm cm = .recordedOlder := by
  cases r with
  | none => simp [compareMachine] at h
  | some rm =>
    cases c with
    | none => simp [compareMachine] at h
    | some cm =>
      cases hcp : comparePlace rm cm with
      | equal => simp [compareMachine, hcp] at h
      | recordedOlder => exact ⟨rm, cm, rfl, rfl, hcp⟩
      | recordedNewer => simp [compareMachine, hcp] at h
      | unordered => simp [compareMachine, hcp] at h

theorem compareSandbox_dead {r c ret : Option PlaceValue}
    (h : compareSandbox r c ret = some .dead) :
    (∃ rs cs, r = some rs ∧ c = some cs ∧ comparePlace rs cs = .recordedOlder) ∨
    (∃ rs t, r = some rs ∧ ret = some t ∧
        (comparePlace rs t = .recordedOlder ∨ comparePlace rs t = .equal)) := by
  cases r with
  | none => simp [compareSandbox] at h
  | some rs =>
    cases c with
    | some cs =>
      cases hcp : comparePlace rs cs with
      | recordedOlder => exact Or.inl ⟨rs, cs, rfl, rfl, hcp⟩
      | equal =>
        cases ret with
        | none => simp [compareSandbox, hcp] at h
        | some t =>
          cases hrt : comparePlace rs t with
          | equal => exact Or.inr ⟨rs, t, rfl, rfl, Or.inr hrt⟩
          | recordedOlder => exact Or.inr ⟨rs, t, rfl, rfl, Or.inl hrt⟩
          | recordedNewer => simp [compareSandbox, hcp, hrt] at h
          | unordered => simp [compareSandbox, hcp, hrt] at h
      | recordedNewer => simp [compareSandbox, hcp] at h
      | unordered => simp [compareSandbox, hcp] at h
    | none =>
      cases ret with
      | none => simp [compareSandbox] at h
      | some t =>
        cases hrt : comparePlace rs t with
        | equal => exact Or.inr ⟨rs, t, rfl, rfl, Or.inr hrt⟩
        | recordedOlder => exact Or.inr ⟨rs, t, rfl, rfl, Or.inl hrt⟩
        | recordedNewer => simp [compareSandbox, hrt] at h
        | unordered => simp [compareSandbox, hrt] at h

theorem placeVerdict_dead_ordered (now : Ms) (r : RecordedPlace) (p : PlaceRecord)
    (h : placeVerdict now r p = .dead) :
    (∃ rm cm, r.machine = some rm ∧ p.machine = some cm ∧
        comparePlace rm cm = .recordedOlder) ∨
    (∃ rs cs, r.sandbox = some rs ∧ p.sandbox = some cs ∧
        comparePlace rs cs = .recordedOlder) ∨
    (∃ rs t, r.sandbox = some rs ∧ p.retired = some t ∧
        (comparePlace rs t = .recordedOlder ∨ comparePlace rs t = .equal)) := by
  unfold placeVerdict at h
  split at h
  · rename_i hcm
    cases h
    exact Or.inl (compareMachine_dead hcm)
  · rename_i hcm
    split at h
    · rename_i hcs
      cases h
      rcases compareSandbox_dead hcs with h1 | h2
      · exact Or.inr (Or.inl h1)
      · exact Or.inr (Or.inr h2)
    · rename_i hcs
      split at h
      · split at h <;> simp at h
      · simp at h

theorem witnessFor_orderedDeath (s : State) (i : Intent) :
    OrderedDeath (witnessFor s i) := by
  unfold OrderedDeath witnessFor
  split
  · rename_i p hp
    intro _ hdead
    exact ⟨p, rfl, placeVerdict_dead_ordered s.now i.recorded p hdead⟩
  · rename_i hp
    intro hkind
    simp at hkind

theorem witnessFor_orderedRule (s : State) (i : Intent) :
    OrderedRule (witnessFor s i) := by
  unfold OrderedRule witnessFor
  split
  · rename_i p hp
    intro _
    cases hcm : compareMachine i.recorded.machine p.machine with
    | some v =>
        cases v <;> simp [placeVerdict, hcm]
    | none =>
        cases hcs : compareSandbox i.recorded.sandbox p.sandbox p.retired with
        | some v => cases v <;> simp [placeVerdict, hcm, hcs]
        | none =>
            cases hle : i.recorded.leaseExpires with
            | some e =>
                by_cases he : e ≤ s.now <;> simp [placeVerdict, hcm, hcs, hle, he]
            | none => simp [placeVerdict, hcm, hcs, hle]
  · rename_i hp
    intro hkind
    simp at hkind

theorem auditWitness_orderedDeath (s : State) :
    OrderedDeath (auditWitness s) := by
  unfold OrderedDeath
  intro hkind
  exact absurd hkind (auditWitness_not_place s)

theorem auditWitness_orderedRule (s : State) :
    OrderedRule (auditWitness s) := by
  unfold OrderedRule
  intro hkind
  exact absurd hkind (auditWitness_not_place s)

/-! ## Intent-map case lemmas -/

theorem Store.intents_remove_sub {s : Store} {op0 : OpId} {op : OpId} {j : Intent}
    (h : (s.removeIntent op0).intents op = some j) : s.intents op = some j := by
  by_cases hh : op = op0
  · subst hh
    rw [Store.intents_remove_self] at h
    simp at h
  · rw [Store.intents_remove_other s op0 op hh] at h
    exact h

theorem Store.intents_add_cases {s : Store} {op0 : OpId} {i0 : Intent}
    {op : OpId} {j : Intent}
    (h : (s.addIntent op0 i0).intents op = some j) :
    (op = op0 ∧ j = i0) ∨ (op ≠ op0 ∧ s.intents op = some j) := by
  by_cases hh : op = op0
  · subst hh
    left
    have hs := Store.intents_add_self s op i0
    rw [hs] at h
    exact ⟨rfl, (Option.some.inj h).symm⟩
  · right
    refine ⟨hh, ?_⟩
    rw [Store.intents_add_other s op0 op i0 hh] at h
    exact h

theorem Store.intents_update_cases {s : Store} {op0 : OpId} {f : Intent → Intent}
    {op : OpId} {j : Intent}
    (h : (s.updateIntent op0 f).intents op = some j) :
    (op = op0 ∧ ∃ i, s.intents op = some i ∧ j = f i) ∨
    (op ≠ op0 ∧ s.intents op = some j) := by
  by_cases hh : op = op0
  · subst hh
    cases hi : s.intents op with
    | none =>
        exfalso
        have hnone : (s.updateIntent op f).intents op = none := by
          by_cases hm : op ∈ s.entries
          · have him : s.intentMap op = none := by
              have := hi
              simpa [Store.intents, hm] using this
            simp [Store.updateIntent, Store.intents, hm, him]
          · simp [Store.updateIntent, Store.intents, hm]
        rw [hnone] at h
        simp at h
    | some i =>
        left
        have hs := Store.intents_update_self s op i f hi
        rw [hs] at h
        refine ⟨rfl, ?_⟩
        refine ⟨i, ?_⟩
        exact ⟨rfl, (Option.some.inj h).symm⟩
  · right
    refine ⟨hh, ?_⟩
    rw [Store.intents_update_other s op0 op f hh] at h
    exact h

theorem Store.intents_foldl_remove_sub (rows : List OpId) (s : Store)
    (op : OpId) (i : Intent)
    (h : (rows.foldl (fun st op => st.removeIntent op) s).intents op = some i) :
    s.intents op = some i := by
  induction rows generalizing s with
  | nil => simpa using h
  | cons r rs ih =>
      simp only [List.foldl_cons] at h
      exact Store.intents_remove_sub (ih (s.removeIntent r) h)

theorem State.intents_mapHome (s : State) (m : MachineId) (f : Home → Home) :
    (s.mapHome m f).store.intents = s.store.intents := by
  rfl

theorem Store.intents_export (s : Store) (rows : List OpId) :
    ({ s with exported := rows ++ s.exported } : Store).intents = s.intents := by
  rfl

/-! ## Witness-good predicates -/

def WitnessGood3 (i : Intent) : Prop :=
  ∀ w, i.witness = some w → WitnessConsistent w → OrderedDeath w

def WitnessGood4 (i : Intent) : Prop :=
  ∀ w, i.witness = some w → WitnessConsistent w → OrderedRule w

theorem WitnessGood3_eq {i j : Intent} (h : WitnessGood3 i)
    (hw : j.witness = i.witness) : WitnessGood3 j := by
  intro w hj hc
  exact h w (by rw [← hw]; exact hj) hc

theorem WitnessGood4_eq {i j : Intent} (h : WitnessGood4 i)
    (hw : j.witness = i.witness) : WitnessGood4 j := by
  intro w hj hc
  exact h w (by rw [← hw]; exact hj) hc

theorem WitnessGood3_witnessFor {s : State} {i j : Intent}
    (hw : j.witness = some (witnessFor s i)) : WitnessGood3 j := by
  intro w hj hc
  have hwj : w = witnessFor s i := by
    have : some (witnessFor s i) = some w := by rw [← hw]; exact hj
    exact (Option.some.inj this).symm
  rw [hwj]
  exact witnessFor_orderedDeath s i

theorem WitnessGood4_witnessFor {s : State} {i j : Intent}
    (hw : j.witness = some (witnessFor s i)) : WitnessGood4 j := by
  intro w hj hc
  have hwj : w = witnessFor s i := by
    have : some (witnessFor s i) = some w := by rw [← hw]; exact hj
    exact (Option.some.inj this).symm
  rw [hwj]
  exact witnessFor_orderedRule s i

theorem WitnessGood3_audit {s : State} {i : Intent}
    (hw : i.witness = some (auditWitness s)) : WitnessGood3 i := by
  intro w hj hc
  have hwj : w = auditWitness s := by
    have : some (auditWitness s) = some w := by rw [← hw]; exact hj
    exact (Option.some.inj this).symm
  rw [hwj]
  exact auditWitness_orderedDeath s

theorem WitnessGood4_audit {s : State} {i : Intent}
    (hw : i.witness = some (auditWitness s)) : WitnessGood4 i := by
  intro w hj hc
  have hwj : w = auditWitness s := by
    have : some (auditWitness s) = some w := by rw [← hw]; exact hj
    exact (Option.some.inj this).symm
  rw [hwj]
  exact auditWitness_orderedRule s

/-- The shared intent-map step lemma for Inv3/Inv4: any witness we add is
either a `witnessFor` snapshot or the audit witness, and every other visible
row is an old row or keeps its witness. -/
theorem WitnessGood_step (G : Intent → Prop)
    (hWF : ∀ (s : State) (i j : Intent), j.witness = some (witnessFor s i) → G j)
    (hAW : ∀ (s : State) (i : Intent), i.witness = some (auditWitness s) → G i)
    (hEq : ∀ {i j : Intent}, G i → j.witness = i.witness → G j)
    (s : State)
    (h : ∀ op i, s.store.intents op = some i → G i) :
    ∀ op' i, (step op s).store.intents op' = some i → G i := by
  intro op' i hi
  cases op with
  | sandboxCreate m sb gen =>
      by_cases hg : sandboxCreateOk s m sb gen = true
      · simp [step, doSandboxCreate, hg, State.mapHome] at hi
        exact h op' i hi
      · simp [step, doSandboxCreate, hg] at hi
        exact h op' i hi
  | sandboxMount i0 =>
      by_cases hg : mountOk s i0 = true
      · simp [step, doSandboxMount, hg, settlePlace] at hi
        rcases Store.intents_add_cases hi with ⟨rfl, rfl⟩ | ⟨hne, hi0⟩
        · exact hWF s i0 _ rfl
        · exact h op' i (Store.intents_removeWhere_sub s.store _ op' i hi0)
      · simp [step, doSandboxMount, hg] at hi
        exact h op' i hi
  | sandboxUnmount op0 =>
      by_cases hg : sandboxUnmountOk s op0 = true
      · simp [step, doSandboxUnmount, hg] at hi
        exact h op' i (Store.intents_remove_sub hi)
      · simp [step, doSandboxUnmount, hg] at hi
        exact h op' i hi
  | sandboxClose m sb gen =>
      by_cases hg : sandboxCloseOk s m sb gen = true
      · simp [step, doSandboxClose, hg, State.mapHome] at hi
        exact h op' i hi
      · simp [step, doSandboxClose, hg] at hi
        exact h op' i hi
  | sandboxForceRemove m sb gen =>
      by_cases hg : sandboxCloseOk s m sb gen = true
      · simp [step, doSandboxClose, hg, State.mapHome] at hi
        exact h op' i hi
      · simp [step, doSandboxClose, hg] at hi
        exact h op' i hi
  | machineStart m inc =>
      by_cases hg : machineStartOk s m inc = true
      · simp [step, doMachineStart, hg, State.mapHome] at hi
        exact h op' i (Store.intents_removeWhere_sub s.store _ op' i hi)
      · simp [step, doMachineStart, hg] at hi
        exact h op' i hi
  | machineRestore m inc =>
      by_cases hg : machineRestoreOk s m inc = true
      · simp [step, doMachineRestore, hg, State.mapHome] at hi
        exact h op' i hi
      · simp [step, doMachineRestore, hg] at hi
        exact h op' i hi
  | admissionRecheck op0 =>
      cases hrow : s.store.intents op0 with
      | none =>
          simp [step, doAdmissionRecheck, hrow] at hi
          exact h op' i hi
      | some i0 =>
          by_cases hd : (i0.state != .done) = true
          · simp [step, doAdmissionRecheck, hrow, hd] at hi
            rcases Store.intents_update_cases hi with ⟨rfl, i1, hi1, hj⟩ | ⟨hne, hi1⟩
            · subst hj
              exact hWF s i1 _ rfl
            · exact h op' i hi1
          · simp [step, doAdmissionRecheck, hrow, hd] at hi
            exact h op' i hi
  | leaseRenew op0 f e =>
      by_cases hg : leaseRenewOk s op0 f = true
      · simp [step, doLeaseRenew, hg] at hi
        rcases Store.intents_update_cases hi with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
        · exact hEq (h op' i1 hi1) (by rw [hj])
        · exact h op' i hi1
      · simp [step, doLeaseRenew, hg] at hi
        exact h op' i hi
  | branchRemove b =>
      by_cases hg : allDeadCertainOnB s b = true
      · simp [step, doBranchRemove, hg] at hi
        exact h op' i (Store.intents_removeWhere_sub s.store _ op' i hi)
      · simp [step, doBranchRemove, hg] at hi
        exact h op' i hi
  | storeCompact =>
      by_cases hg : allDeadCertainB s = true
      · simp [step, doStoreCompact, hg] at hi
        exact h op' i (Store.intents_removeWhere_sub s.store _ op' i hi)
      · simp [step, doStoreCompact, hg] at hi
        exact h op' i hi
  | operatorPreview branch row label =>
      by_cases hg : previewOk s row = true
      · simp [step, doOperatorPreview, hg] at hi
        rcases Store.intents_add_cases hi with ⟨rfl, rfl⟩ | ⟨hne, hi0⟩
        · exact hAW s _ rfl
        · exact h op' i hi0
      · simp [step, doOperatorPreview, hg] at hi
        exact h op' i hi
  | operatorSettle op0 label =>
      cases hrow : s.store.intents op0 with
      | none =>
          simp [step, doOperatorSettle, hrow] at hi
          exact h op' i hi
      | some i0 =>
          by_cases hd : (i0.state != .done) = true
          · simp [step, doOperatorSettle, hrow, hd] at hi
            rcases Store.intents_update_cases hi with ⟨rfl, i1, hi1, hj⟩ | ⟨hne, hi1⟩
            · subst hj
              exact hWF s i1 _ rfl
            · exact h op' i hi1
          · simp [step, doOperatorSettle, hrow, hd] at hi
            exact h op' i hi
  | operatorRelease op0 label f =>
      by_cases hg : operatorReleaseOk s op0 f = true
      · simp [step, doOperatorRelease, hg] at hi
        rcases Store.intents_update_cases hi with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
        · rw [heq] at hi1
          exact hEq (h op0 i1 hi1) (by rw [hj])
        · exact h op' i hi1
      · simp [step, doOperatorRelease, hg] at hi
        exact h op' i hi
  | operatorArchive rows prune =>
      by_cases hg : archiveOk s rows = true
      · by_cases hp : prune = true
        · simp [step, doOperatorArchive, hg, hp, Store.intents_export] at hi
          exact h op' i (Store.intents_foldl_remove_sub rows s.store op' i hi)
        · simp [step, doOperatorArchive, hg, hp] at hi
          exact h op' i hi
      · simp [step, doOperatorArchive, hg] at hi
        exact h op' i hi

theorem Inv3_preserves (op : Op) (s : State) (h : Inv s) : Inv3 (step op s) := by
  intro op' i w hi hw hc
  have hgood : WitnessGood3 i :=
    WitnessGood_step WitnessGood3
      (fun s i j hw => WitnessGood3_witnessFor hw)
      (fun s i hw => WitnessGood3_audit hw)
      (fun h hw => WitnessGood3_eq h hw)
      s (fun op i hi => fun w0 hw0 hc0 => h.inv3 op i w0 hi hw0 hc0)
      op' i hi
  exact hgood w hw hc

theorem Inv4_preserves (op : Op) (s : State) (h : Inv s) : Inv4 (step op s) := by
  intro op' i w hi hw hc
  have hgood : WitnessGood4 i :=
    WitnessGood_step WitnessGood4
      (fun s i j hw => WitnessGood4_witnessFor hw)
      (fun s i hw => WitnessGood4_audit hw)
      (fun h hw => WitnessGood4_eq h hw)
      s (fun op i hi => fun w0 hw0 hc0 => h.inv4 op i w0 hi hw0 hc0)
      op' i hi
  exact hgood w hw hc


/-! ## Inv7 is structural -/

theorem Inv7_always (s : State) : Inv7 s := by
  refine ⟨?_, ?_, ?_⟩
  · intro op i hi hdone
    left
    rw [Store.audit_eq_some_iff]
    exact ⟨hi, hdone⟩
  · intro op i h
    exact (Store.audit_eq_some_iff.mp h).2
  · intro _ op i h
    exact (Store.audit_eq_some_iff.mp h).1

/-! ## Inv2: operator done rows and uncertain rows -/

theorem Inv2_of_sub {s s' : State} (h : Inv2 s)
    (hsub : ∀ op i, s'.store.intents op = some i → s.store.intents op = some i) :
    Inv2 s' := by
  constructor
  · intro op i hi hdone
    exact h.1 op i (hsub op i hi) hdone
  · intro op i hi hunc
    exact h.2 op i (hsub op i hi) hunc

theorem Inv2_of_eq {s s' : State} (h : Inv2 s)
    (heq : ∀ op, s'.store.intents op = s.store.intents op) : Inv2 s' :=
  Inv2_of_sub h (fun op i hi => by rw [← heq op]; exact hi)

theorem mountOk_live {s : State} {i : Intent} (h : mountOk s i = true) :
    i.state = .live := by
  by_cases hne : i.state = .live
  · exact hne
  · have h' := h
    simp [mountOk, hne] at h' 

theorem Inv2_mount (s : State) (i : Intent) (h : Inv2 s) :
    Inv2 (doSandboxMount s i) := by
  by_cases hg : mountOk s i = true
  · have hlive := mountOk_live hg
    constructor
    · intro op j hj hdone
      simp [doSandboxMount, hg, settlePlace] at hj
      rcases Store.intents_add_cases hj with ⟨rfl, rfl⟩ | ⟨hne, hj0⟩
      · unfold OperatorDone at hdone
        simp at hdone
      · exact h.1 op j (Store.intents_removeWhere_sub s.store _ op j hj0) hdone
    · intro op j hj hunc
      simp [doSandboxMount, hg, settlePlace] at hj
      rcases Store.intents_add_cases hj with ⟨rfl, rfl⟩ | ⟨hne, hj0⟩
      · simp at hunc
      · exact h.2 op j (Store.intents_removeWhere_sub s.store _ op j hj0) hunc
  · simp [doSandboxMount, hg]
    exact h

theorem Inv2_recheck (s : State) (op0 : OpId) (h : Inv2 s) :
    Inv2 (doAdmissionRecheck s op0) := by
  cases hrow : s.store.intents op0 with
  | none => simp [doAdmissionRecheck, hrow]; exact h
  | some i0 =>
      by_cases hd : (i0.state != .done) = true
      · have hi0ne : i0.state ≠ .done := by
          intro hc; rw [hc] at hd; simp at hd
        constructor
        · intro op j hj hdone
          simp [step, doAdmissionRecheck, hrow, hd] at hj
          rcases Store.intents_update_cases hj with ⟨rfl, i1, hi1, hj⟩ | ⟨hne, hi1⟩
          · have hi1' : i1 = i0 := by
              rw [hrow] at hi1
              exact (Option.some.inj hi1).symm
            subst hi1'
            unfold OperatorDone at hdone
            rw [hj] at hdone
            exact absurd hdone.1 hi0ne
          · exact h.1 op j hi1 hdone
        · intro op j hj hunc
          simp [step, doAdmissionRecheck, hrow, hd] at hj
          rcases Store.intents_update_cases hj with ⟨rfl, i1, hi1, hj⟩ | ⟨hne, hi1⟩
          · rw [hj]
            exact ⟨witnessFor s i1, rfl, witnessFor_consistent s i1⟩
          · exact h.2 op j hi1 hunc
      · simp [doAdmissionRecheck, hrow, hd]
        exact h

theorem Inv2_settle (s : State) (op0 : OpId) (label : String) (h : Inv2 s) :
    Inv2 (doOperatorSettle s op0 label) := by
  cases hrow : s.store.intents op0 with
  | none => simp [doOperatorSettle, hrow]; exact h
  | some i0 =>
      by_cases hd : (i0.state != .done) = true
      · constructor
        · intro op j hj hdone
          simp [doOperatorSettle, hrow, hd] at hj
          rcases Store.intents_update_cases hj with ⟨rfl, i1, hi1, hj⟩ | ⟨hne, hi1⟩
          · rw [hj] at hdone
            unfold OperatorDone at hdone
            simp at hdone
          · exact h.1 op j hi1 hdone
        · intro op j hj hunc
          simp [doOperatorSettle, hrow, hd] at hj
          rcases Store.intents_update_cases hj with ⟨rfl, i1, hi1, hj⟩ | ⟨hne, hi1⟩
          · rw [hj]
            exact ⟨witnessFor s i1, rfl, witnessFor_consistent s i1⟩
          · exact h.2 op j hi1 hunc
      · simp [doOperatorSettle, hrow, hd]
        exact h

theorem Inv2_release (s : State) (op0 : OpId) (label : String)
    (f : Option Fence) (h : Inv2 s) :
    Inv2 (doOperatorRelease s op0 label f) := by
  by_cases hg : operatorReleaseOk s op0 f = true
  · constructor
    · intro op j hj hdone
      simp [doOperatorRelease, hg] at hj
      rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
      · rw [heq] at hi1
        have hunc : i1.state = .uncertain := by
          have h' := hg
          unfold operatorReleaseOk at h'
          rw [hi1] at h'
          simp at h'
          exact h'.1
        rcases h.2 op0 i1 hi1 hunc with ⟨w, hw, hc⟩
        refine ⟨w, ?_, hc, ?_⟩
        · rw [hj]; exact hw
        · right; right; simpa [hj]
      · exact h.1 op j hi1 hdone
    · intro op j hj hunc
      simp [doOperatorRelease, hg] at hj
      rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
      · rw [hj] at hunc; simp at hunc
      · exact h.2 op j hi1 hunc
  · simp [doOperatorRelease, hg]
    exact h

theorem Inv2_preview (s : State) (branch : BranchId) (row : OpId)
    (label : String) (h : Inv2 s) :
    Inv2 (doOperatorPreview s branch row label) := by
  by_cases hg : previewOk s row = true
  · constructor
    · intro op j hj hdone
      simp [doOperatorPreview, hg] at hj
      rcases Store.intents_add_cases hj with ⟨rfl, rfl⟩ | ⟨hne, hj0⟩
      · unfold OperatorDone at hdone
        simp [previewIntent] at hdone
      · exact h.1 op j hj0 hdone
    · intro op j hj hunc
      simp [doOperatorPreview, hg] at hj
      rcases Store.intents_add_cases hj with ⟨rfl, rfl⟩ | ⟨hne, hj0⟩
      · simp [previewIntent] at hunc
      · exact h.2 op j hj0 hunc
  · simp [doOperatorPreview, hg]
    exact h

theorem Inv2_lease (s : State) (op0 : OpId) (f : Option Fence) (e : Ms)
    (h : Inv2 s) : Inv2 (doLeaseRenew s op0 f e) := by
  by_cases hg : leaseRenewOk s op0 f = true
  · constructor
    · intro op j hj hdone
      simp [step, doLeaseRenew, hg] at hj
      rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
      · rw [heq] at hi1
        have hd : OperatorDone i1 := by
          unfold OperatorDone at hdone ⊢
          rw [hj] at hdone
          exact hdone
        rcases h.1 op0 i1 hi1 hd with ⟨w, hw, hc, hv⟩
        refine ⟨w, ?_, hc, ?_⟩
        · rw [hj]; exact hw
        · rcases hv with hv | hv | hv
          · left; exact hv
          · right; left; exact hv
          · right; right; simpa [hj] using hv
      · exact h.1 op j hi1 hdone
    · intro op j hj hunc
      simp [step, doLeaseRenew, hg] at hj
      rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
      · rw [heq] at hi1
        rw [hj] at hunc
        rcases h.2 op0 i1 hi1 hunc with ⟨w, hw, hc⟩
        exact ⟨w, by rw [hj]; exact hw, hc⟩
      · exact h.2 op j hi1 hunc
  · simp [doLeaseRenew, hg]
    exact h


/-! ## Inv6: fence -/

theorem Inv6_of_sub {s s' : State} (h : Inv6 s)
    (hsub : ∀ op i, s'.store.intents op = some i → s.store.intents op = some i) :
    Inv6 s' := by
  intro op i hi f hf
  exact h op i (hsub op i hi) f hf

theorem Inv6_of_eq {s s' : State} (h : Inv6 s)
    (heq : ∀ op, s'.store.intents op = s.store.intents op) : Inv6 s' :=
  Inv6_of_sub h (fun op i hi => by rw [← heq op]; exact hi)

theorem Inv6_of_fields {s s' : State} (h : Inv6 s)
    (hfields : ∀ op i, s'.store.intents op = some i →
      ∃ i0, s.store.intents op = some i0 ∧ i.releasedWith = i0.releasedWith ∧
            i.recorded.fence = i0.recorded.fence) :
    Inv6 s' := by
  intro op i hi f hf
  rcases hfields op i hi with ⟨i0, hi0, hrel, hfence⟩
  rw [hrel] at hf
  rw [hfence]
  exact h op i0 hi0 f hf

theorem fenceOk_sound {i : Intent} {f : Option Fence} (h : fenceOk i f = true) :
    ∀ x, f = some x → i.recorded.fence = some x := by
  intro x hx
  subst hx
  simp [fenceOk] at h
  exact h

/-- A release introduces the row's fence from the guard; explicit. -/
theorem Inv6_release (s : State) (op0 : OpId) (label : String)
    (f : Option Fence) (h : Inv6 s) :
    Inv6 (doOperatorRelease s op0 label f) := by
  by_cases hg : operatorReleaseOk s op0 f = true
  · intro op j hj x hx
    simp [doOperatorRelease, hg] at hj
    rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
    · rw [heq] at hi1
      rw [hj] at hx
      rw [hj]
      have hfence : fenceOk i1 f = true := by
        have h' := hg
        unfold operatorReleaseOk at h'
        rw [hi1] at h'
        simp at h'
        exact h'.2
      exact fenceOk_sound hfence x hx
    · exact h op j hi1 x hx
  · simp [doOperatorRelease, hg]
    exact h

/-- Lease, recheck and settle leave `releasedWith` and `recorded.fence`. -/
theorem Inv6_lease (s : State) (op0 : OpId) (f : Option Fence) (e : Ms)
    (h : Inv6 s) : Inv6 (doLeaseRenew s op0 f e) := by
  apply Inv6_of_fields h
  intro op j hj
  by_cases hg : leaseRenewOk s op0 f = true
  · simp [step, doLeaseRenew, hg] at hj
    rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
    · rw [heq] at hi1
      rw [heq]
      exact ⟨i1, hi1, by rw [hj], by rw [hj]⟩
    · exact ⟨j, hi1, rfl, rfl⟩
  · simp [step, doLeaseRenew, hg] at hj
    exact ⟨j, hj, rfl, rfl⟩

theorem Inv6_settle (s : State) (op0 : OpId) (label : String) (h : Inv6 s) :
    Inv6 (doOperatorSettle s op0 label) := by
  apply Inv6_of_fields h
  intro op j hj
  cases hrow : s.store.intents op0 with
  | none => simp [doOperatorSettle, hrow] at hj; exact ⟨j, hj, rfl, rfl⟩
  | some i0 =>
      by_cases hd : (i0.state != .done) = true
      · simp [doOperatorSettle, hrow, hd] at hj
        rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
        · rw [heq] at hi1
          rw [heq]
          exact ⟨i1, hi1, by rw [hj], by rw [hj]⟩
        · exact ⟨j, hi1, rfl, rfl⟩
      · simp [doOperatorSettle, hrow, hd] at hj
        exact ⟨j, hj, rfl, rfl⟩

theorem Inv6_recheck (s : State) (op0 : OpId) (h : Inv6 s) :
    Inv6 (doAdmissionRecheck s op0) := by
  apply Inv6_of_fields h
  intro op j hj
  cases hrow : s.store.intents op0 with
  | none => simp [step, doAdmissionRecheck, hrow] at hj; exact ⟨j, hj, rfl, rfl⟩
  | some i0 =>
      by_cases hd : (i0.state != .done) = true
      · simp [step, doAdmissionRecheck, hrow, hd] at hj
        rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
        · rw [heq] at hi1
          rw [heq]
          exact ⟨i1, hi1, by rw [hj], by rw [hj]⟩
        · exact ⟨j, hi1, rfl, rfl⟩
      · simp [step, doAdmissionRecheck, hrow, hd] at hj
        exact ⟨j, hj, rfl, rfl⟩

theorem Inv6_mount (s : State) (i : Intent) (h : Inv6 s) :
    Inv6 (doSandboxMount s i) := by
  by_cases hg : mountOk s i = true
  · intro op j hj x hx
    simp [doSandboxMount, hg, settlePlace] at hj
    rcases Store.intents_add_cases hj with ⟨rfl, rfl⟩ | ⟨hne, hj0⟩
    · simp at hx
    · exact h op j (Store.intents_removeWhere_sub s.store _ op j hj0) x hx
  · simp [doSandboxMount, hg]
    exact h

theorem Inv6_preview (s : State) (branch : BranchId) (row : OpId)
    (label : String) (h : Inv6 s) :
    Inv6 (doOperatorPreview s branch row label) := by
  by_cases hg : previewOk s row = true
  · intro op j hj x hx
    simp [doOperatorPreview, hg] at hj
    rcases Store.intents_add_cases hj with ⟨rfl, rfl⟩ | ⟨hne, hj0⟩
    · simp [previewIntent] at hx
    · exact h op j hj0 x hx
  · simp [doOperatorPreview, hg]
    exact h

/-! ## Inv8: done rows are operator-created -/

theorem Inv8_of_sub {s s' : State} (h : Inv8_no_automatic_release s)
    (hsub : ∀ op i, s'.store.intents op = some i → s.store.intents op = some i) :
    Inv8_no_automatic_release s' := by
  intro op i hi hdone
  exact h op i (hsub op i hi) hdone

theorem Inv8_of_eq {s s' : State} (h : Inv8_no_automatic_release s)
    (heq : ∀ op, s'.store.intents op = s.store.intents op) :
    Inv8_no_automatic_release s' :=
  Inv8_of_sub h (fun op i hi => by rw [← heq op]; exact hi)

theorem Inv8_of_fields {s s' : State} (h : Inv8_no_automatic_release s)
    (hfields : ∀ op i, s'.store.intents op = some i →
      ∃ i0, s.store.intents op = some i0 ∧ i.state = i0.state ∧ i.doneBy = i0.doneBy) :
    Inv8_no_automatic_release s' := by
  intro op i hi hdone
  rcases hfields op i hi with ⟨i0, hi0, hstate, hdoneBy⟩
  have hd : i0.state = .done := by rw [← hstate]; exact hdone
  rw [hdoneBy]
  exact h op i0 hi0 hd

theorem Inv8_release (s : State) (op0 : OpId) (label : String)
    (f : Option Fence) (h : Inv8_no_automatic_release s) :
    Inv8_no_automatic_release (doOperatorRelease s op0 label f) := by
  by_cases hg : operatorReleaseOk s op0 f = true
  · intro op j hj hdone
    simp [doOperatorRelease, hg] at hj
    rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
    · rw [hj]
    · exact h op j hi1 hdone
  · simp [doOperatorRelease, hg]
    exact h

theorem Inv8_preview (s : State) (branch : BranchId) (row : OpId)
    (label : String) (h : Inv8_no_automatic_release s) :
    Inv8_no_automatic_release (doOperatorPreview s branch row label) := by
  by_cases hg : previewOk s row = true
  · intro op j hj hdone
    simp [doOperatorPreview, hg] at hj
    rcases Store.intents_add_cases hj with ⟨rfl, rfl⟩ | ⟨hne, hj0⟩
    · simp [previewIntent]
    · exact h op j hj0 hdone
  · simp [doOperatorPreview, hg]
    exact h

/-! ## Inv5: the compact barrier -/

theorem Inv5_of_sub {s s' : State} (h : Inv5 s)
    (hcomp : s'.store.compacted = s.store.compacted)
    (hsub : ∀ op i, s'.store.intents op = some i → s.store.intents op = some i) :
    Inv5 s' := by
  intro hc
  rw [hcomp] at hc
  rintro ⟨op, i, hi, hnd⟩
  exact h hc ⟨op, i, hsub op i hi, hnd⟩

theorem Inv5_of_eq {s s' : State} (h : Inv5 s)
    (hcomp : s'.store.compacted = s.store.compacted)
    (heq : ∀ op, s'.store.intents op = s.store.intents op) : Inv5 s' :=
  Inv5_of_sub h hcomp (fun op i hi => by rw [← heq op]; exact hi)

theorem Store.intents_compact_done {s : Store} {op : OpId} {i : Intent}
    (h : (s.removeWhere (fun _ i => i.state != .done)).intents op = some i) :
    i.state = .done := by
  have hi := Store.intents_removeWhere_sub s _ op i h
  have hmem := Store.intents_mem h
  unfold Store.removeWhere at hmem
  rw [List.mem_filter] at hmem
  obtain ⟨_, hpred⟩ := hmem
  simp [hi] at hpred
  cases hst : i.state <;> simp_all



/-! ## Preservation of Inv2, Inv6 and Inv8 -/

theorem Inv2_preserves (op : Op) (s : State) (h : Inv s) : Inv2 (step op s) := by
  cases op with
  | sandboxCreate m sb gen =>
      apply Inv2_of_eq h.inv2
      intro op
      by_cases hg : sandboxCreateOk s m sb gen = true
      · simp [step, doSandboxCreate, hg, State.mapHome]
      · simp [step, doSandboxCreate, hg]
  | sandboxMount i =>
      simpa [step] using Inv2_mount s i h.inv2
  | sandboxUnmount op0 =>
      by_cases hg : sandboxUnmountOk s op0 = true
      · apply Inv2_of_sub h.inv2
        intro op j hj
        simp [step, doSandboxUnmount, hg] at hj
        exact Store.intents_remove_sub hj
      · simpa [step, doSandboxUnmount, hg] using h.inv2
  | sandboxClose m sb gen =>
      apply Inv2_of_eq h.inv2
      intro op
      by_cases hg : sandboxCloseOk s m sb gen = true
      · simp [step, doSandboxClose, hg, State.mapHome]
      · simp [step, doSandboxClose, hg]
  | sandboxForceRemove m sb gen =>
      apply Inv2_of_eq h.inv2
      intro op
      by_cases hg : sandboxCloseOk s m sb gen = true
      · simp [step, doSandboxClose, hg, State.mapHome]
      · simp [step, doSandboxClose, hg]
  | machineStart m inc =>
      by_cases hg : machineStartOk s m inc = true
      · apply Inv2_of_sub h.inv2
        intro op j hj
        simp [step, doMachineStart, hg, State.mapHome] at hj
        exact Store.intents_removeWhere_sub s.store _ op j hj
      · simpa [step, doMachineStart, hg] using h.inv2
  | machineRestore m inc =>
      apply Inv2_of_eq h.inv2
      intro op
      by_cases hg : machineRestoreOk s m inc = true
      · simp [step, doMachineRestore, hg, State.mapHome]
      · simp [step, doMachineRestore, hg]
  | admissionRecheck op0 =>
      simpa [step] using Inv2_recheck s op0 h.inv2
  | leaseRenew op0 f e =>
      simpa [step] using Inv2_lease s op0 f e h.inv2
  | branchRemove b =>
      by_cases hg : allDeadCertainOnB s b = true
      · apply Inv2_of_sub h.inv2
        intro op j hj
        simp [step, doBranchRemove, hg] at hj
        exact Store.intents_removeWhere_sub s.store _ op j hj
      · simpa [step, doBranchRemove, hg] using h.inv2
  | storeCompact =>
      by_cases hg : allDeadCertainB s = true
      · apply Inv2_of_sub h.inv2
        intro op j hj
        simp [step, doStoreCompact, hg] at hj
        exact Store.intents_removeWhere_sub s.store _ op j hj
      · simpa [step, doStoreCompact, hg] using h.inv2
  | operatorPreview branch row label =>
      simpa [step] using Inv2_preview s branch row label h.inv2
  | operatorSettle op0 label =>
      simpa [step] using Inv2_settle s op0 label h.inv2
  | operatorRelease op0 label f =>
      simpa [step] using Inv2_release s op0 label f h.inv2
  | operatorArchive rows prune =>
      by_cases hg : archiveOk s rows = true
      · by_cases hp : prune = true
        · apply Inv2_of_sub h.inv2
          intro op j hj
          simp [step, doOperatorArchive, hg, hp, Store.intents_export] at hj
          exact Store.intents_foldl_remove_sub rows s.store op j hj
        · apply Inv2_of_sub h.inv2
          intro op j hj
          simp [step, doOperatorArchive, hg, hp, Store.intents_export] at hj
          exact hj
      · simpa [step, doOperatorArchive, hg] using h.inv2

theorem Inv6_preserves (op : Op) (s : State) (h : Inv s) : Inv6 (step op s) := by
  cases op with
  | sandboxCreate m sb gen =>
      apply Inv6_of_eq h.inv6
      intro op
      by_cases hg : sandboxCreateOk s m sb gen = true
      · simp [step, doSandboxCreate, hg, State.mapHome]
      · simp [step, doSandboxCreate, hg]
  | sandboxMount i =>
      simpa [step] using Inv6_mount s i h.inv6
  | sandboxUnmount op0 =>
      by_cases hg : sandboxUnmountOk s op0 = true
      · apply Inv6_of_sub h.inv6
        intro op j hj
        simp [step, doSandboxUnmount, hg] at hj
        exact Store.intents_remove_sub hj
      · simpa [step, doSandboxUnmount, hg] using h.inv6
  | sandboxClose m sb gen =>
      apply Inv6_of_eq h.inv6
      intro op
      by_cases hg : sandboxCloseOk s m sb gen = true
      · simp [step, doSandboxClose, hg, State.mapHome]
      · simp [step, doSandboxClose, hg]
  | sandboxForceRemove m sb gen =>
      apply Inv6_of_eq h.inv6
      intro op
      by_cases hg : sandboxCloseOk s m sb gen = true
      · simp [step, doSandboxClose, hg, State.mapHome]
      · simp [step, doSandboxClose, hg]
  | machineStart m inc =>
      by_cases hg : machineStartOk s m inc = true
      · apply Inv6_of_sub h.inv6
        intro op j hj
        simp [step, doMachineStart, hg, State.mapHome] at hj
        exact Store.intents_removeWhere_sub s.store _ op j hj
      · simpa [step, doMachineStart, hg] using h.inv6
  | machineRestore m inc =>
      apply Inv6_of_eq h.inv6
      intro op
      by_cases hg : machineRestoreOk s m inc = true
      · simp [step, doMachineRestore, hg, State.mapHome]
      · simp [step, doMachineRestore, hg]
  | admissionRecheck op0 =>
      simpa [step] using Inv6_recheck s op0 h.inv6
  | leaseRenew op0 f e =>
      simpa [step] using Inv6_lease s op0 f e h.inv6
  | branchRemove b =>
      by_cases hg : allDeadCertainOnB s b = true
      · apply Inv6_of_sub h.inv6
        intro op j hj
        simp [step, doBranchRemove, hg] at hj
        exact Store.intents_removeWhere_sub s.store _ op j hj
      · simpa [step, doBranchRemove, hg] using h.inv6
  | storeCompact =>
      by_cases hg : allDeadCertainB s = true
      · apply Inv6_of_sub h.inv6
        intro op j hj
        simp [step, doStoreCompact, hg] at hj
        exact Store.intents_removeWhere_sub s.store _ op j hj
      · simpa [step, doStoreCompact, hg] using h.inv6
  | operatorPreview branch row label =>
      simpa [step] using Inv6_preview s branch row label h.inv6
  | operatorSettle op0 label =>
      simpa [step] using Inv6_settle s op0 label h.inv6
  | operatorRelease op0 label f =>
      simpa [step] using Inv6_release s op0 label f h.inv6
  | operatorArchive rows prune =>
      by_cases hg : archiveOk s rows = true
      · by_cases hp : prune = true
        · apply Inv6_of_sub h.inv6
          intro op j hj
          simp [step, doOperatorArchive, hg, hp, Store.intents_export] at hj
          exact Store.intents_foldl_remove_sub rows s.store op j hj
        · apply Inv6_of_sub h.inv6
          intro op j hj
          simp [step, doOperatorArchive, hg, hp, Store.intents_export] at hj
          exact hj
      · simpa [step, doOperatorArchive, hg] using h.inv6

theorem Inv8_mount (s : State) (i : Intent) (h : Inv8_no_automatic_release s) :
    Inv8_no_automatic_release (doSandboxMount s i) := by
  by_cases hg : mountOk s i = true
  · intro op j hj hdone
    simp [doSandboxMount, hg, settlePlace] at hj
    rcases Store.intents_add_cases hj with ⟨rfl, rfl⟩ | ⟨hne, hj0⟩
    · simp at hdone
    · exact h op j (Store.intents_removeWhere_sub s.store _ op j hj0) hdone
  · simp [doSandboxMount, hg]
    exact h

theorem Inv8_settle (s : State) (op0 : OpId) (label : String)
    (h : Inv8_no_automatic_release s) :
    Inv8_no_automatic_release (doOperatorSettle s op0 label) := by
  cases hrow : s.store.intents op0 with
  | none => simp [doOperatorSettle, hrow]; exact h
  | some i0 =>
      by_cases hd : (i0.state != .done) = true
      · intro op j hj hdone
        simp [doOperatorSettle, hrow, hd] at hj
        rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
        · rw [heq] at hi1
          rw [hj] at hdone
          simp at hdone
        · exact h op j hi1 hdone
      · simp [doOperatorSettle, hrow, hd]
        exact h

theorem Inv8_preserves (op : Op) (s : State) (h : Inv s) :
    Inv8_no_automatic_release (step op s) := by
  cases op with
  | sandboxCreate m sb gen =>
      apply Inv8_of_eq h.inv8
      intro op
      by_cases hg : sandboxCreateOk s m sb gen = true
      · simp [step, doSandboxCreate, hg, State.mapHome]
      · simp [step, doSandboxCreate, hg]
  | sandboxMount i =>
      simpa [step] using Inv8_mount s i h.inv8
  | sandboxUnmount op0 =>
      by_cases hg : sandboxUnmountOk s op0 = true
      · apply Inv8_of_sub h.inv8
        intro op j hj
        simp [step, doSandboxUnmount, hg] at hj
        exact Store.intents_remove_sub hj
      · simpa [step, doSandboxUnmount, hg] using h.inv8
  | sandboxClose m sb gen =>
      apply Inv8_of_eq h.inv8
      intro op
      by_cases hg : sandboxCloseOk s m sb gen = true
      · simp [step, doSandboxClose, hg, State.mapHome]
      · simp [step, doSandboxClose, hg]
  | sandboxForceRemove m sb gen =>
      apply Inv8_of_eq h.inv8
      intro op
      by_cases hg : sandboxCloseOk s m sb gen = true
      · simp [step, doSandboxClose, hg, State.mapHome]
      · simp [step, doSandboxClose, hg]
  | machineStart m inc =>
      by_cases hg : machineStartOk s m inc = true
      · apply Inv8_of_sub h.inv8
        intro op j hj
        simp [step, doMachineStart, hg, State.mapHome] at hj
        exact Store.intents_removeWhere_sub s.store _ op j hj
      · simpa [step, doMachineStart, hg] using h.inv8
  | machineRestore m inc =>
      apply Inv8_of_eq h.inv8
      intro op
      by_cases hg : machineRestoreOk s m inc = true
      · simp [step, doMachineRestore, hg, State.mapHome]
      · simp [step, doMachineRestore, hg]
  | admissionRecheck op0 =>
      apply Inv8_of_fields h.inv8
      intro op j hj
      cases hrow : s.store.intents op0 with
      | none => simp [step, doAdmissionRecheck, hrow] at hj; exact ⟨j, hj, rfl, rfl⟩
      | some i0 =>
          by_cases hd : (i0.state != .done) = true
          · simp [step, doAdmissionRecheck, hrow, hd] at hj
            rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
            · rw [heq] at hi1
              rw [heq]
              exact ⟨i1, hi1, by rw [hj], by rw [hj]⟩
            · exact ⟨j, hi1, rfl, rfl⟩
          · simp [step, doAdmissionRecheck, hrow, hd] at hj
            exact ⟨j, hj, rfl, rfl⟩
  | leaseRenew op0 f e =>
      apply Inv8_of_fields h.inv8
      intro op j hj
      by_cases hg : leaseRenewOk s op0 f = true
      · simp [step, doLeaseRenew, hg] at hj
        rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
        · rw [heq] at hi1
          rw [heq]
          exact ⟨i1, hi1, by rw [hj], by rw [hj]⟩
        · exact ⟨j, hi1, rfl, rfl⟩
      · simp [step, doLeaseRenew, hg] at hj
        exact ⟨j, hj, rfl, rfl⟩
  | branchRemove b =>
      by_cases hg : allDeadCertainOnB s b = true
      · apply Inv8_of_sub h.inv8
        intro op j hj
        simp [step, doBranchRemove, hg] at hj
        exact Store.intents_removeWhere_sub s.store _ op j hj
      · simpa [step, doBranchRemove, hg] using h.inv8
  | storeCompact =>
      by_cases hg : allDeadCertainB s = true
      · apply Inv8_of_sub h.inv8
        intro op j hj
        simp [step, doStoreCompact, hg] at hj
        exact Store.intents_removeWhere_sub s.store _ op j hj
      · simpa [step, doStoreCompact, hg] using h.inv8
  | operatorPreview branch row label =>
      simpa [step] using Inv8_preview s branch row label h.inv8
  | operatorSettle op0 label =>
      simpa [step] using Inv8_settle s op0 label h.inv8
  | operatorRelease op0 label f =>
      simpa [step] using Inv8_release s op0 label f h.inv8
  | operatorArchive rows prune =>
      by_cases hg : archiveOk s rows = true
      · by_cases hp : prune = true
        · apply Inv8_of_sub h.inv8
          intro op j hj
          simp [step, doOperatorArchive, hg, hp, Store.intents_export] at hj
          exact Store.intents_foldl_remove_sub rows s.store op j hj
        · apply Inv8_of_sub h.inv8
          intro op j hj
          simp [step, doOperatorArchive, hg, hp, Store.intents_export] at hj
          exact hj
      · simpa [step, doOperatorArchive, hg] using h.inv8



/-! ## Inv1: no reclaim of a live mount -/

theorem holdsBranchB_iff {s : State} {b : BranchId} {i : Intent} :
    holdsBranchB s b i = true ↔ HoldsBranch s b i := by
  cases hb : i.branch with
  | some b' => simp [holdsBranchB, HoldsBranch, hb]
  | none =>
      cases hp : i.project with
      | none => simp [holdsBranchB, HoldsBranch, hb, hp]
      | some p =>
          cases hbp : s.branchProject b with
          | none => simp [holdsBranchB, HoldsBranch, hb, hp, hbp]
          | some q =>
              simp [holdsBranchB, HoldsBranch, hb, hp, hbp, beq_iff_eq]
              exact eq_comm

theorem MountedOn_of_sub {s s' : State} {b : BranchId}
    (hbp : s'.branchProject = s.branchProject)
    (hsub : ∀ op i, s'.store.intents op = some i → s.store.intents op = some i)
    (h : MountedOn s' b) : MountedOn s b := by
  rcases h with ⟨op, i, hi, hh, hnd⟩
  refine ⟨op, i, hsub op i hi, ?_, hnd⟩
  unfold HoldsBranch at hh ⊢
  rcases hh with hh | hh | hh
  · exact Or.inl hh
  · exact Or.inr (Or.inl hh)
  · rcases hh with ⟨hb, p, hp, hbp'⟩
    exact Or.inr (Or.inr ⟨hb, p, hp, by rw [← hbp]; exact hbp'⟩)

theorem HoldsBranch_of_branchProject {s s' : State} {b : BranchId} {i : Intent}
    (hbp : s'.branchProject b = s.branchProject b) (h : HoldsBranch s' b i) :
    HoldsBranch s b i := by
  unfold HoldsBranch at h ⊢
  rcases h with hh | hh | hh
  · exact Or.inl hh
  · exact Or.inr (Or.inl hh)
  · rcases hh with ⟨hb, p, hp, hbp'⟩
    exact Or.inr (Or.inr ⟨hb, p, hp, by rw [← hbp]; exact hbp'⟩)

theorem Inv1_of_sub {s s' : State} (h : Inv1 s)
    (hbp : ∀ b, s'.branchProject b = s.branchProject b)
    (hbr : ∀ b, s'.store.branches b = s.store.branches b)
    (hcomp : s'.store.compacted = s.store.compacted)
    (hsub : ∀ op i, s'.store.intents op = some i → i.state ≠ .done →
        s.store.intents op = some i) : Inv1 s' := by
  refine ⟨?_, ?_, ?_⟩
  · intro op i hi hnd b hb
    rw [hbr b]
    exact h.1 op i (hsub op i hi hnd) hnd b hb
  · intro b hb
    have hb0 : s.store.branches b = some .removed := by rw [← hbr b]; exact hb
    rintro ⟨op, i, hi, hh, hd⟩
    exact h.2.1 b hb0 ⟨op, i, hsub op i hi hd,
      HoldsBranch_of_branchProject (hbp b) hh, hd⟩
  · intro hc
    rw [hcomp] at hc
    rintro ⟨op, i, hi, hd⟩
    exact h.2.2 hc ⟨op, i, hsub op i hi hd, hd⟩

theorem Inv1_of_fields {s s' : State} (h : Inv1 s)
    (hbp : ∀ b, s'.branchProject b = s.branchProject b)
    (hbr : ∀ b, s'.store.branches b = s.store.branches b)
    (hcomp : s'.store.compacted = s.store.compacted)
    (hfields : ∀ op i, s'.store.intents op = some i →
      ∃ i0, s.store.intents op = some i0 ∧ i.branch = i0.branch ∧
            i.project = i0.project ∧ (i.state ≠ .done → i0.state ≠ .done)) :
    Inv1 s' := by
  refine ⟨?_, ?_, ?_⟩
  · intro op i hi hnd b hb
    rcases hfields op i hi with ⟨i0, hi0, hbrch, hproj, hnd0⟩
    rw [hbr b]
    exact h.1 op i0 hi0 (hnd0 hnd) b (by rw [← hbrch]; exact hb)
  · intro b hb
    have hb0 : s.store.branches b = some .removed := by rw [← hbr b]; exact hb
    rintro ⟨op, i, hi, hh, hd⟩
    rcases hfields op i hi with ⟨i0, hi0, hbrch, hproj, hnd0⟩
    refine h.2.1 b hb0 ⟨op, i0, hi0, ?_, hnd0 hd⟩
    unfold HoldsBranch at hh ⊢
    rcases hh with hh | hh | hh
    · exact Or.inl (by rw [← hbrch]; exact hh)
    · exact Or.inr (Or.inl ⟨by rw [← hbrch]; exact hh.1,
                              by rw [← hproj]; exact hh.2⟩)
    · rcases hh with ⟨hbranch, p, hp, hbp'⟩
      exact Or.inr (Or.inr ⟨by rw [← hbrch]; exact hbranch, p, by rw [← hproj]; exact hp,
        by rw [← hbp b]; exact hbp'⟩)
  · intro hc
    rw [hcomp] at hc
    rintro ⟨op, i, hi, hd⟩
    rcases hfields op i hi with ⟨i0, hi0, _, _, hnd0⟩
    exact h.2.2 hc ⟨op, i0, hi0, hnd0 hd⟩

theorem mountOk_branch {s : State} {i : Intent} (h : mountOk s i = true) :
    ∃ b, i.branch = some b ∧ s.store.branches b = some .live := by
  cases hb : i.branch with
  | none => simp [mountOk, hb] at h
  | some b =>
      refine ⟨b, rfl, ?_⟩
      have h' := h
      simp [mountOk, hb] at h'
      exact h'.2

theorem Inv1_mount (s : State) (i : Intent) (h : Inv1 s) :
    Inv1 (doSandboxMount s i) := by
  by_cases hg : mountOk s i = true
  · have hbranches : ∀ b, (doSandboxMount s i).store.branches b = s.store.branches b := by
      intro b
      simp [doSandboxMount, hg, settlePlace, Store.addIntent, Store.removeWhere]
    have hcomp : (doSandboxMount s i).store.compacted = false := by
      simp [doSandboxMount, hg]
    obtain ⟨b0, hb0, hlive0⟩ := mountOk_branch hg
    refine ⟨?_, ?_, ?_⟩
    · intro op j hj hnd b hb
      simp [doSandboxMount, hg, settlePlace] at hj
      rcases Store.intents_add_cases hj with ⟨rfl, rfl⟩ | ⟨hne, hj0⟩
      · have hb' : i.branch = some b := by simpa using hb
        rw [hb0] at hb'
        have hbb : b0 = b := Option.some.inj hb'
        rw [← hbb, hbranches b0]
        exact hlive0
      · rw [hbranches b]
        exact h.1 op j (Store.intents_removeWhere_sub s.store _ op j hj0) hnd b hb
    · intro b hb
      rintro ⟨op, j, hj, hh, hnd⟩
      simp [doSandboxMount, hg, settlePlace] at hj
      rcases Store.intents_add_cases hj with ⟨rfl, rfl⟩ | ⟨hne, hj0⟩
      · unfold HoldsBranch at hh
        rcases hh with hh | hh | hh
        · have : i.branch = some b := hh
          rw [hb0] at this
          have hbb : b0 = b := Option.some.inj this
          rw [← hbb] at hb
          rw [hbranches b0] at hb
          rw [hb] at hlive0
          simp at hlive0
        · have : i.branch = none := hh.1
          rw [hb0] at this
          simp at this
        · have : i.branch = none := hh.1
          rw [hb0] at this
          simp at this
      · refine h.2.1 b ?_ ⟨op, j, Store.intents_removeWhere_sub s.store _ op j hj0,
          HoldsBranch_of_branchProject (s := s) (s' := doSandboxMount s i) (by simp [doSandboxMount, hg, settlePlace]) hh, hnd⟩
        rw [← hbranches b]
        exact hb
    · intro hc
      rw [hcomp] at hc
      simp at hc
  · simp [doSandboxMount, hg]
    exact h

theorem Inv1_preview (s : State) (branch : BranchId) (row : OpId)
    (label : String) (h : Inv1 s) :
    Inv1 (doOperatorPreview s branch row label) := by
  by_cases hg : previewOk s row = true
  · apply Inv1_of_sub h
    · intro b; simp [doOperatorPreview, hg, Store.addIntent]
    · intro b; simp [doOperatorPreview, hg, Store.addIntent]
    · simp [doOperatorPreview, hg, Store.addIntent]
    · intro op j hj hnd
      simp [doOperatorPreview, hg] at hj
      rcases Store.intents_add_cases hj with ⟨rfl, rfl⟩ | ⟨hne, hj0⟩
      · simp [previewIntent] at hnd
      · exact hj0
  · simp [doOperatorPreview, hg]
    exact h

theorem Inv1_compact (s : State) (h : Inv1 s) : Inv1 (doStoreCompact s) := by
  by_cases hg : allDeadCertainB s = true
  · refine ⟨?_, ?_, ?_⟩
    · intro op i hi hnd b hb
      simp [doStoreCompact, hg] at hi
      change (s.store.removeWhere (fun _ i => i.state != .done)).intents op = some i at hi
      exact absurd (Store.intents_compact_done hi) hnd
    · intro b hb
      rintro ⟨op, i, hi, hh, hnd⟩
      simp [doStoreCompact, hg] at hi
      change (s.store.removeWhere (fun _ i => i.state != .done)).intents op = some i at hi
      exact absurd (Store.intents_compact_done hi) hnd
    · rintro _ ⟨op, i, hi, hnd⟩
      simp [doStoreCompact, hg] at hi
      change (s.store.removeWhere (fun _ i => i.state != .done)).intents op = some i at hi
      exact absurd (Store.intents_compact_done hi) hnd
  · simp [doStoreCompact, hg]
    exact h

theorem Inv1_branchRemove (s : State) (b : BranchId) (h : Inv1 s) :
    Inv1 (doBranchRemove s b) := by
  by_cases hg : allDeadCertainOnB s b = true
  · have hpostBranch : ∀ b', (doBranchRemove s b).store.branches b' =
        (if b' = b then some .removed else s.store.branches b') := by
      intro b'; simp [doBranchRemove, hg]
    refine ⟨?_, ?_, ?_⟩
    · intro op j hj hnd b' hb'
      simp [doBranchRemove, hg] at hj
      change (s.store.removeWhere (fun _ i => holdsBranchB s b i)).intents op = some j at hj
      have hj0 := Store.intents_removeWhere_sub s.store (fun _ i => holdsBranchB s b i) op j hj
      by_cases hbb : b' = b
      · have hb : j.branch = some b := by rw [← hbb]; exact hb'
        have hhold : holdsBranchB s b j = true := by
          rw [holdsBranchB_iff]; exact Or.inl hb
        have hrem := Store.intents_removeWhere_removed s.store
          (fun _ i => holdsBranchB s b i) op j hj0 hhold
        rw [hrem] at hj; simp at hj
      · rw [hpostBranch b', if_neg hbb]
        exact h.1 op j hj0 hnd b' hb'
    · intro b' hb'
      by_cases hbb : b' = b
      · rw [hpostBranch b', if_pos hbb] at hb'
        rintro ⟨op, j, hj, hh, hnd⟩
        simp [doBranchRemove, hg] at hj
        change (s.store.removeWhere (fun _ i => holdsBranchB s b i)).intents op = some j at hj
        have hj0 := Store.intents_removeWhere_sub s.store
          (fun _ i => holdsBranchB s b i) op j hj
        have hh' : HoldsBranch s b j := by
          rw [hbb] at hh
          exact HoldsBranch_of_branchProject (s := s) (s' := doBranchRemove s b) (by simp [doBranchRemove, hg]) hh
        have hhold : holdsBranchB s b j = true := by
          rw [holdsBranchB_iff]; exact hh'
        have hrem := Store.intents_removeWhere_removed s.store
          (fun _ i => holdsBranchB s b i) op j hj0 hhold
        rw [hrem] at hj; simp at hj
      · have hb0 : s.store.branches b' = some .removed := by
          rw [hpostBranch b', if_neg hbb] at hb'
          exact hb'
        rintro ⟨op, j, hj, hh, hnd⟩
        simp [doBranchRemove, hg] at hj
        change (s.store.removeWhere (fun _ i => holdsBranchB s b i)).intents op = some j at hj
        have hj0 := Store.intents_removeWhere_sub s.store
          (fun _ i => holdsBranchB s b i) op j hj
        exact h.2.1 b' hb0 ⟨op, j, hj0,
          HoldsBranch_of_branchProject (s := s) (s' := doBranchRemove s b) (by simp [doBranchRemove, hg]) hh, hnd⟩
    · intro hc
      rintro ⟨op, j, hj, hnd⟩
      have hc' : s.store.compacted = true := by simpa [doBranchRemove, hg, Store.removeWhere] using hc
      simp [doBranchRemove, hg] at hj
      change (s.store.removeWhere (fun _ i => holdsBranchB s b i)).intents op = some j at hj
      have hj0 := Store.intents_removeWhere_sub s.store
        (fun _ i => holdsBranchB s b i) op j hj
      exact h.2.2 hc' ⟨op, j, hj0, hnd⟩
  · simp [doBranchRemove, hg]
    exact h


theorem Inv1_recheck (s : State) (op0 : OpId) (h : Inv1 s) :
    Inv1 (doAdmissionRecheck s op0) := by
  apply Inv1_of_fields h
  · intro b
    unfold doAdmissionRecheck
    split <;> (try split) <;> rfl
  · intro b
    unfold doAdmissionRecheck
    split <;> (try split) <;> rfl
  · unfold doAdmissionRecheck
    split <;> (try split) <;> rfl
  · intro op j hj
    cases hrow : s.store.intents op0 with
    | none => simp [doAdmissionRecheck, hrow] at hj; exact ⟨j, hj, rfl, rfl, fun h => h⟩
    | some i0 =>
        by_cases hd : (i0.state != .done) = true
        · simp [doAdmissionRecheck, hrow, hd] at hj
          rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
          · rw [heq] at hi1
            rw [heq]
            exact ⟨i1, hi1, by rw [hj], by rw [hj], by rw [hj]; exact fun h => h⟩
          · exact ⟨j, hi1, rfl, rfl, fun h => h⟩
        · simp [doAdmissionRecheck, hrow, hd] at hj
          exact ⟨j, hj, rfl, rfl, fun h => h⟩

theorem Inv1_lease (s : State) (op0 : OpId) (f : Option Fence) (e : Ms)
    (h : Inv1 s) : Inv1 (doLeaseRenew s op0 f e) := by
  apply Inv1_of_fields h
  · intro b; unfold doLeaseRenew; split <;> rfl
  · intro b; unfold doLeaseRenew; split <;> rfl
  · unfold doLeaseRenew; split <;> rfl
  · intro op j hj
    by_cases hg : leaseRenewOk s op0 f = true
    · simp [doLeaseRenew, hg] at hj
      rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
      · rw [heq] at hi1
        rw [heq]
        exact ⟨i1, hi1, by rw [hj], by rw [hj], by rw [hj]; exact fun h => h⟩
      · exact ⟨j, hi1, rfl, rfl, fun h => h⟩
    · simp [doLeaseRenew, hg] at hj
      exact ⟨j, hj, rfl, rfl, fun h => h⟩

theorem Inv1_settle (s : State) (op0 : OpId) (label : String) (h : Inv1 s) :
    Inv1 (doOperatorSettle s op0 label) := by
  apply Inv1_of_fields h
  · intro b; unfold doOperatorSettle; split <;> (try split) <;> rfl
  · intro b; unfold doOperatorSettle; split <;> (try split) <;> rfl
  · unfold doOperatorSettle; split <;> (try split) <;> rfl
  · intro op j hj
    cases hrow : s.store.intents op0 with
    | none => simp [doOperatorSettle, hrow] at hj; exact ⟨j, hj, rfl, rfl, fun h => h⟩
    | some i0 =>
        by_cases hd : (i0.state != .done) = true
        · simp [doOperatorSettle, hrow, hd] at hj
          rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
          · rw [heq] at hi1
            rw [heq]
            have hne : i1.state ≠ .done := by
              intro hc
              have heq' : i1 = i0 := by
                rw [hrow] at hi1
                exact (Option.some.inj hi1).symm
              subst heq'
              rw [hc] at hd
              simp at hd
            exact ⟨i1, hi1, by rw [hj], by rw [hj], fun _ => hne⟩
          · exact ⟨j, hi1, rfl, rfl, fun h => h⟩
        · simp [doOperatorSettle, hrow, hd] at hj
          exact ⟨j, hj, rfl, rfl, fun h => h⟩

theorem Inv1_release (s : State) (op0 : OpId) (label : String)
    (f : Option Fence) (h : Inv1 s) :
    Inv1 (doOperatorRelease s op0 label f) := by
  apply Inv1_of_fields h
  · intro b; unfold doOperatorRelease; split <;> rfl
  · intro b; unfold doOperatorRelease; split <;> rfl
  · unfold doOperatorRelease; split <;> rfl
  · intro op j hj
    by_cases hg : operatorReleaseOk s op0 f = true
    · simp [doOperatorRelease, hg] at hj
      rcases Store.intents_update_cases hj with ⟨heq, i1, hi1, hj⟩ | ⟨hne, hi1⟩
      · rw [heq] at hi1
        rw [heq]
        exact ⟨i1, hi1, by rw [hj], by rw [hj], by
          intro hc; rw [hj] at hc; simp at hc⟩
      · exact ⟨j, hi1, rfl, rfl, fun h => h⟩
    · simp [doOperatorRelease, hg] at hj
      exact ⟨j, hj, rfl, rfl, fun h => h⟩


theorem Store.branches_foldl_remove (rows : List OpId) (s : Store) :
    (rows.foldl (fun st op => st.removeIntent op) s).branches = s.branches := by
  induction rows generalizing s with
  | nil => rfl
  | cons r rs ih =>
      simp only [List.foldl_cons]
      exact ih (s.removeIntent r)

theorem Store.compacted_foldl_remove (rows : List OpId) (s : Store) :
    (rows.foldl (fun st op => st.removeIntent op) s).compacted = s.compacted := by
  induction rows generalizing s with
  | nil => rfl
  | cons r rs ih =>
      simp only [List.foldl_cons]
      exact ih (s.removeIntent r)

theorem Inv1_preserves (op : Op) (s : State) (h : Inv s) : Inv1 (step op s) := by
  cases op with
  | sandboxCreate m sb gen =>
      by_cases hg : sandboxCreateOk s m sb gen = true
      · apply Inv1_of_sub h.inv1
        · intro b; simp [step, doSandboxCreate, hg, State.mapHome]
        · intro b; simp [step, doSandboxCreate, hg, State.mapHome]
        · simp [step, doSandboxCreate, hg, State.mapHome]
        · intro op j hj hnd
          simpa [step, doSandboxCreate, hg, State.mapHome] using hj
      · simpa [step, doSandboxCreate, hg] using h.inv1
  | sandboxMount i =>
      simpa [step] using Inv1_mount s i h.inv1
  | sandboxUnmount op0 =>
      by_cases hg : sandboxUnmountOk s op0 = true
      · apply Inv1_of_sub h.inv1
        · intro b; simp [step, doSandboxUnmount, hg, Store.removeIntent]
        · intro b; simp [step, doSandboxUnmount, hg, Store.removeIntent]
        · simp [step, doSandboxUnmount, hg, Store.removeIntent]
        · intro op j hj hnd
          simp [step, doSandboxUnmount, hg] at hj
          exact Store.intents_remove_sub hj
      · simpa [step, doSandboxUnmount, hg] using h.inv1
  | sandboxClose m sb gen =>
      by_cases hg : sandboxCloseOk s m sb gen = true
      · apply Inv1_of_sub h.inv1
        · intro b; simp [step, doSandboxClose, hg, State.mapHome]
        · intro b; simp [step, doSandboxClose, hg, State.mapHome]
        · simp [step, doSandboxClose, hg, State.mapHome]
        · intro op j hj hnd
          simpa [step, doSandboxClose, hg, State.mapHome] using hj
      · simpa [step, doSandboxClose, hg] using h.inv1
  | sandboxForceRemove m sb gen =>
      by_cases hg : sandboxCloseOk s m sb gen = true
      · apply Inv1_of_sub h.inv1
        · intro b; simp [step, doSandboxClose, hg, State.mapHome]
        · intro b; simp [step, doSandboxClose, hg, State.mapHome]
        · simp [step, doSandboxClose, hg, State.mapHome]
        · intro op j hj hnd
          simpa [step, doSandboxClose, hg, State.mapHome] using hj
      · simpa [step, doSandboxClose, hg] using h.inv1
  | machineStart m inc =>
      by_cases hg : machineStartOk s m inc = true
      · apply Inv1_of_sub h.inv1
        · intro b; simp [step, doMachineStart, hg, State.mapHome, Store.removeWhere]
        · intro b; simp [step, doMachineStart, hg, State.mapHome, Store.removeWhere]
        · simp [step, doMachineStart, hg, State.mapHome, Store.removeWhere]
        · intro op j hj hnd
          simp [step, doMachineStart, hg, State.mapHome] at hj
          exact Store.intents_removeWhere_sub s.store _ op j hj
      · simpa [step, doMachineStart, hg] using h.inv1
  | machineRestore m inc =>
      by_cases hg : machineRestoreOk s m inc = true
      · apply Inv1_of_sub h.inv1
        · intro b; simp [step, doMachineRestore, hg, State.mapHome]
        · intro b; simp [step, doMachineRestore, hg, State.mapHome]
        · simp [step, doMachineRestore, hg, State.mapHome]
        · intro op j hj hnd
          simpa [step, doMachineRestore, hg, State.mapHome] using hj
      · simpa [step, doMachineRestore, hg] using h.inv1
  | admissionRecheck op0 =>
      simpa [step] using Inv1_recheck s op0 h.inv1
  | leaseRenew op0 f e =>
      simpa [step] using Inv1_lease s op0 f e h.inv1
  | branchRemove b =>
      simpa [step] using Inv1_branchRemove s b h.inv1
  | storeCompact =>
      simpa [step] using Inv1_compact s h.inv1
  | operatorPreview branch row label =>
      simpa [step] using Inv1_preview s branch row label h.inv1
  | operatorSettle op0 label =>
      simpa [step] using Inv1_settle s op0 label h.inv1
  | operatorRelease op0 label f =>
      simpa [step] using Inv1_release s op0 label f h.inv1
  | operatorArchive rows prune =>
      by_cases hg : archiveOk s rows = true
      · by_cases hp : prune = true
        · apply Inv1_of_sub h.inv1
          · intro b; simp [step, doOperatorArchive, hg, hp, Store.branches_foldl_remove]
          · intro b; simp [step, doOperatorArchive, hg, hp, Store.branches_foldl_remove]
          · simp [step, doOperatorArchive, hg, hp, Store.compacted_foldl_remove]
          · intro op j hj hnd
            simp [step, doOperatorArchive, hg, hp, Store.intents_export] at hj
            exact Store.intents_foldl_remove_sub rows s.store op j hj
        · apply Inv1_of_sub h.inv1
          · intro b; simp [step, doOperatorArchive, hg, hp, Store.branches_foldl_remove]
          · intro b; simp [step, doOperatorArchive, hg, hp, Store.branches_foldl_remove]
          · simp [step, doOperatorArchive, hg, hp, Store.compacted_foldl_remove]
          · intro op j hj hnd
            simp [step, doOperatorArchive, hg, hp, Store.intents_export] at hj
            exact hj
      · simpa [step, doOperatorArchive, hg] using h.inv1

theorem step_preserves (op : Op) (s : State) (h : Inv s) : Inv (step op s) :=
  { inv1 := Inv1_preserves op s h
    inv2 := Inv2_preserves op s h
    inv3 := Inv3_preserves op s h
    inv4 := Inv4_preserves op s h
    inv5 := (Inv1_preserves op s h).2.2
    inv6 := Inv6_preserves op s h
    inv7 := Inv7_always (step op s)
    inv8 := Inv8_preserves op s h }

end GcAdmission
