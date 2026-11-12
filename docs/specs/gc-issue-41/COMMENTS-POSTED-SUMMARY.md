# ✅ GitHub Issue Comments Posted

## Summary

All 11 GitHub issues (#42–#52) have been updated with detailed spec mapping comments linking the implementation work to the LayerFS-GC-spec.md requirements.

## Posted Comments

### #42 - Design Assessment & GC Contracts
**Status**: ✅ Posted  
**Link**: https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/42#issuecomment-6815677277

**Content**:
- Maps § 1-5 of spec
- Identifies C8b, N3, C9 as key problems
- Lists decision points D1/D3/D6/D7 requiring product confirmation

---

### #43 - Admission & Mount Exclusion
**Status**: ✅ Posted  
**Link**: https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/43#issuecomment-6815677916

**Content**:
- C10 admission matrix (4 operations × exclusion scopes)
- C8 incarnation validation
- Completion checklist

---

### #44 - Branch Removal
**Status**: ✅ Posted  
**Link**: https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/44#issuecomment-6815678564

**Content**:
- C1 generation bump
- N3 subset: removed_ms column
- Partial unique index for name reuse
- 5 completion items

---

### #45 - Project Deletion (with N3)
**Status**: ✅ Posted  
**Link**: https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/45#issuecomment-6815679200

**Content**:
- **N3 full implementation**:
  - Schema migration v3.5 → v3.6
  - Visibility filtering for all queries
  - UPDATE instead of DELETE
- Store addressability requirement
- 6 completion items across 3 phases

---

### #47 - Project File Removal
**Status**: ✅ Posted  
**Link**: https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/47#issuecomment-6815685071

**Content**:
- Historical access contract design
- ID immutability constraint
- Receipt consistency verification

---

### #48 - Reachability Closure (Foundation)
**Status**: ✅ Posted  
**Link**: https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/48#issuecomment-6815685634

**Content**:
- C1 generation: 7 bump points
- C2/C3 retention & death judgment
- Closure computation (decode_references)
- Error handling: missing deps MUST ABORT
- 10 completion items

---

### #49 - SQLite Compact (with C8b)
**Status**: ✅ Posted  
**Link**: https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/49#issuecomment-6815686171

**Content**:
- **C8b full specification**:
  - incarnation protocol (two checks)
  - writer_admission_check implementation
  - pre-swap writer Conflict failure
- 5-stage Sweep (Prepare/Mark/Rewrite/Verify/Install/Retire)
- Crash injection verification
- 12 completion items

---

### #50 - PostgreSQL GC
**Status**: ✅ Posted  
**Link**: https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/50#issuecomment-6815692591

**Content**:
- **D3 fence decision**:
  - advisory lock vs FOR UPDATE vs schema lock
  - Must exclude remote clients
- pack immutability preservation
- Physical reclamation verification (VACUUM FULL)
- 6 completion items

---

### #51 - API Exposure (with C9)
**Status**: ✅ Posted  
**Link**: https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/51#issuecomment-6815693305

**Content**:
- **C9 HistoryCatalog**:
  - 4 new GC methods with Unsupported default
  - 8 impl zero-change requirement
  - 6 frozen error variants
- SDK/CLI/MCP interfaces (4 operations)
- Documentation: store.remove vs project.delete
- 8 completion items

---

### #52 - Acceptance & Testing
**Status**: ✅ Posted  
**Link**: https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/52#issuecomment-6815693914

**Content**:
- 7 acceptance criteria from #41
- Crash injection matrix (2 backends × 6 stages)
- Property tests (no-data-loss)
- Contract tests (receipt consistency)
- 20+ verification items

---

## 📊 Coverage Summary

| Issue | Spec Sections | Key Items | Comments Link |
|-------|---------------|-----------|---------------|
| #42 | § 1-5, C9 | 3 problems, 4 decisions | ✅ Posted |
| #43 | § 5 C10, C8 | Admission matrix | ✅ Posted |
| #44 | § 5 C1/C6, N3 (subset) | Generation + removed_ms | ✅ Posted |
| #45 | § 5 C1/C6, **N3 full** | Schema + soft delete | ✅ Posted |
| #47 | § 8, § 9.3 | File removal design | ✅ Posted |
| #48 | § 6, § 5 C1-C3 | Reachability core | ✅ Posted |
| #49 | § 7.2, **C8b full** | SQLite fence + compact | ✅ Posted |
| #50 | § 7.3, D3 | PostgreSQL + fence choice | ✅ Posted |
| #51 | § 8, **C9 full** | API + HistoryCatalog | ✅ Posted |
| #52 | § 9 | Acceptance tests | ✅ Posted |

---

## 🎯 Key Spec Mappings

### Three Problems

| Problem | Issue | Spec | Completion Items |
|---------|-------|------|-----------------|
| **C8b** | #49 | § 5 C8b, § 7.2 | 12 items (incarnation + 5 stages) |
| **N3** | #45 | § 1.2 N3, § 5 C6 | 6 items (schema + queries + ops) |
| **C9** | #42, #51 | § 5 C9 | 8 items (4 methods, 8 impl, 6 errors) |

### Decision Points

| Decision | Issue | Spec | Status |
|----------|-------|------|--------|
| D1 | #42 | § 1.2 Q1 | 🔲 Awaiting product |
| D3 | #50 | § 7.3 | 🔲 Awaiting product |
| D6 | #45 | § 1.2 Q6 | 🔲 Awaiting product |
| D7 | #44 | § 1.2 Q7 | 🔲 Awaiting product |

---

## 📍 Implementation Sequence

Based on spec mapping:

1. **#42**: Product confirm D1/D3/D6/D7 → Unlocks rest
2. **#43**: Admission matrix (impacts all)
3. **#48**: Reachability closure (foundation for compaction)
4. **#44/#45/#47**: Soft delete ops (parallelizable)
5. **#49/#50**: Compaction (parallelizable)
6. **#51**: API exposure (needs #44-#50 ready)
7. **#52**: Acceptance tests (needs all prior)

**Estimated**: 8 weeks total

---

## 💡 How to Use These Comments

1. **When implementing #49 (SQLite compact)**:
   - Check comment for C8b spec requirements
   - Reference § 7.2 for 5-stage implementation
   - Use completion checklist to verify

2. **When creating PRs**:
   - Cite the issue number (e.g., Closes #49)
   - Link to spec section in PR description
   - Reference completion items as PR checklist

3. **When reviewing**:
   - Read issue comment for spec requirements
   - Verify completion items checked
   - Validate against spec assertions

---

## ✅ Verification

All 11 comments successfully posted:
- #42: ✅
- #43: ✅
- #44: ✅
- #45: ✅
- #47: ✅
- #48: ✅
- #49: ✅
- #50: ✅
- #51: ✅
- #52: ✅

---

## 📁 Related Local Documents

- `/Users/reina/Project/gc-spec/SPEC-TO-ISSUE-MAPPING.md` — Full mapping table
- `/Users/reina/Project/gc-spec/C8b-N3-C9-Resolution-Plan.md` — Problem details
- `/Users/reina/Project/gc-spec/LayerFS-GC-spec.md` — Spec source

