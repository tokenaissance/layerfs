# GC Implementation Workflow

## Design Specs Foundation

**Base Branch:** `layerfs_v2_0_0`  
**Design Branch:** `design-specs`  
**PR:** https://github.com/tokenaissance/layerfs/pull/69

All specification documents are in `/docs/specs/gc-issue-41/`

---

## Implementation Phases

### Phase 1: Design Finalization (#42)

**Branch:** `gc-42-design-assessment`  
**Base:** `design-specs`

**Tasks:**
- [ ] Review LayerFS-GC-spec.md (560 lines)
- [ ] Confirm all 11 committed decisions (D1-D11)
- [ ] Product sign-off on 6 pending decisions
- [ ] Finalize contracts for SQLite and PostgreSQL
- [ ] Create detailed implementation plans for #43-#52

**Acceptance:** All decisions documented in code/comments

**GitHub:** Reference spec sections in issue comments

---

### Phase 2a: Admission & Reachability (#43, #48)

**Branch #43:** `gc-43-admission-enforcement`  
**Branch #48:** `gc-48-shared-reachability`  
**Base:** `design-specs`

#### #43 - Admission Enforcement
- [ ] Define admission matrix data structure
- [ ] Implement mount state check (atomic)
- [ ] Implement `MountsActive` error return
- [ ] Implement `Busy` error for conflicting users
- [ ] Tests on SQLite and PostgreSQL

#### #48 - Shared Data Reachability
- [ ] Implement 3-step reachability closure
- [ ] Design reference counting algorithm
- [ ] Protect transitive delta bases
- [ ] Test cross-project sharing scenarios
- [ ] Verify pack sharing detection

**Acceptance:** Admission matrix enforced, no unprotected shared data

---

### Phase 2b: Soft Removal (#44, #45, #47)

**Branch #44:** `gc-44-branch-removal`  
**Branch #45:** `gc-45-project-deletion`  
**Branch #47:** `gc-47-file-removal`  
**Base:** `design-specs`

#### #44 - Branch Removal
- [ ] Mark Branch as removed (removed_ms timestamp)
- [ ] Prevent new mounts to removed Branch
- [ ] Verify other Branches unaffected
- [ ] Test publish/merge with removed Branch
- [ ] Tests on SQLite and PostgreSQL

#### #45 - Project Deletion
- [ ] Mark project as deleted (deleted_ms timestamp)
- [ ] Keep Store addressable for compact
- [ ] Verify Sandboxes cannot mount deleted project
- [ ] Schema migration for deleted_ms column
- [ ] Tests on SQLite and PostgreSQL

#### #47 - File Removal
- [ ] Design immutable ID access contract (C9)
- [ ] Implement logical file removal
- [ ] Implement history traversal with removed files
- [ ] Protect immutable IDs before/after removal
- [ ] Tests on cross-project sharing

**Acceptance:** Logical removal working, other resources unaffected

---

### Phase 3: Physical Compaction (#49, #50)

**Branch #49:** `gc-49-sqlite-compaction`  
**Branch #50:** `gc-50-postgresql-gc`  
**Base:** `design-specs`

#### #49 - SQLite Compaction
- [ ] Implement C8b: 5-stage incarnation protocol
  - Stage 1: Mark discarded rows
  - Stage 2: Create new tables
  - Stage 3: Atomic swap with writer fence (critical)
  - Stage 4: Reader fence / grace period
  - Stage 5: Drop old tables
- [ ] Implement writer-exclusive fence during Stage 3
- [ ] Recovery after interrupted compact
- [ ] Tests: mount failures, grace period, reader stalls
- [ ] Measure physical shrink (verify bytes reclaimed)

#### #50 - PostgreSQL Compaction
- [ ] Implement PostgreSQL-specific compaction
- [ ] Support remote PostgreSQL servers
- [ ] Implement physical reclamation (pg_total_relation_size)
- [ ] Test network partition recovery
- [ ] Measure space reclamation
- [ ] Remote server tests (not local stub)

**Acceptance:** Physical compaction verified on both backends

**Ref Diagrams:**
- Excalidraw: https://app.excalidraw.com/s/9Zq6XgRe98z/329NfoaidRt
- Excalidraw: https://app.excalidraw.com/s/9Zq6XgRe98z/Alhrgo0pPJ

---

### Phase 4: Integration & Qualification (#51, #52)

**Branch #51:** `gc-51-api-exposure`  
**Branch #52:** `gc-52-qualification`  
**Base:** `design-specs`

#### #51 - API/SDK/CLI Exposure
- [ ] Add API endpoints (branch.remove, project.delete, etc.)
- [ ] Add SDK methods for all operations
- [ ] Add CLI commands with proper error handling
- [ ] Implement C9: HistoryCatalog for removed file access
- [ ] Write user guides and best practices
- [ ] Document error codes and recovery procedures
- [ ] Add code examples

#### #52 - Acceptance Testing
- [ ] Integration tests (all operations together)
- [ ] Crash recovery tests at 5 injection points
  - During Setup (discarded rows marked)
  - During Create (new tables exist)
  - During Swap (one of old/new active)
  - During Fence (no new readers on old)
  - During Drop (old data gone)
- [ ] Cross-project sharing verification
- [ ] Performance benchmarks
- [ ] Load testing
- [ ] Documentation validation
- [ ] Receipt byte consistency verification

**Acceptance:** All tests pass on SQLite and PostgreSQL

**Ref Diagram:**
- Excalidraw: https://app.excalidraw.com/s/9Zq6XgRe98z/9IZiVsP9Fnl

---

## Branch Strategy

```
layerfs_v2_0_0 (upstream base)
    │
    └─→ design-specs (PR #69) ← foundation
         │
         ├─→ gc-42-design-assessment
         │   └─→ PR to design-specs
         │
         ├─→ gc-43-admission-enforcement
         │   └─→ PR to design-specs
         │
         ├─→ gc-44-branch-removal
         │   └─→ PR to design-specs
         │
         ├─→ gc-45-project-deletion
         │   └─→ PR to design-specs
         │
         ├─→ gc-47-file-removal
         │   └─→ PR to design-specs
         │
         ├─→ gc-48-shared-reachability
         │   └─→ PR to design-specs
         │
         ├─→ gc-49-sqlite-compaction
         │   └─→ PR to design-specs
         │
         ├─→ gc-50-postgresql-gc
         │   └─→ PR to design-specs
         │
         ├─→ gc-51-api-exposure
         │   └─→ PR to design-specs
         │
         └─→ gc-52-qualification
             └─→ PR to design-specs
```

## Parallel Development

**Can run in parallel:**
- Phase 1 (blocking): #42 → all others
- Phase 2a: #43, #48 (foundation for Phase 2b)
- Phase 2b: #44, #45, #47 (independent, need #43/#48)
- Phase 3: #49, #50 (can start after #43/#48)
- Phase 4: #51, #52 (need #43-#50)

**Dependency chain:**
```
#42 (Design)
 ├─→ #43 (Admission)
 │   ├─→ #44 (Branch RM)
 │   ├─→ #45 (Project RM)
 │   └─→ #47 (File RM)
 │
 ├─→ #48 (Reachability)
 │   ├─→ #44, #45, #47
 │   ├─→ #49 (SQLite)
 │   └─→ #50 (PostgreSQL)
 │
 └─→ #51, #52 (API & Tests)
     ├─→ #43-#50 all complete
     └─→ Cross-platform verification
```

## Spec References

Each PR should include:

**PR Title:**
```
feat: GC #XX - [Short description]
```

**PR Description (always include):**
```markdown
## Spec Reference
- Issue: #XX
- Spec Section: § X.Y (LayerFS-GC-spec.md)
- Related Diagrams: [Link to Excalidraw]

## Changes
- [Bullet point of changes]

## Tests
- [Test coverage]

## Acceptance
- [ ] Spec requirement met
- [ ] Tests pass on SQLite and PostgreSQL
- [ ] [Issue-specific acceptance]
```

**Code Comments:**
- Reference spec section: `// § 7.2 C8b: incarnation protocol`
- Link to Excalidraw: `// See diagram: https://app.excalidraw.com/s/9Zq6XgRe98z/329NfoaidRt`
- Reference GitHub issue: `// Issue #49: SQLite compaction`

## Checklist Template

For each implementation branch:

```markdown
## Spec Alignment
- [ ] Read spec section (§ X.Y)
- [ ] Reviewed related diagrams
- [ ] Understood acceptance criteria
- [ ] Identified dependencies

## Implementation
- [ ] [Task 1]
- [ ] [Task 2]
- [ ] [Task 3]

## Testing
- [ ] SQLite backend tests pass
- [ ] PostgreSQL backend tests pass
- [ ] Cross-backend scenarios covered

## Review
- [ ] Code follows LayerFS conventions
- [ ] Comments reference spec sections
- [ ] PR links to GitHub issue
- [ ] All acceptance criteria met
```

---

## Merging to Upstream

When all phases complete:

1. **Merge all PRs to design-specs** (in tokenaissance/layerfs)
2. **Create PR to layerfs_v2_0_0** (design-specs → layerfs_v2_0_0)
3. **Final PR to upstream** (design-specs → Ephemeral-AI-Lab/layerfs)

```bash
# From fork
git push fork design-specs

# Create PR to upstream
gh pr create \
  -R Ephemeral-AI-Lab/layerfs \
  -B layerfs_v2_0_0 \
  -H tokenaissance:design-specs \
  -t "docs: LayerFS GC spec + implementation (#41)"
```

---

## Status Tracking

Use this table to track progress:

| Issue | Branch | Status | PR | Merged |
|-------|--------|--------|----|----|
| #42 | gc-42-design-assessment | 🔲 Not Started | - | - |
| #43 | gc-43-admission-enforcement | 🔲 Not Started | - | - |
| #44 | gc-44-branch-removal | 🔲 Not Started | - | - |
| #45 | gc-45-project-deletion | 🔲 Not Started | - | - |
| #47 | gc-47-file-removal | 🔲 Not Started | - | - |
| #48 | gc-48-shared-reachability | 🔲 Not Started | - | - |
| #49 | gc-49-sqlite-compaction | 🔲 Not Started | - | - |
| #50 | gc-50-postgresql-gc | 🔲 Not Started | - | - |
| #51 | gc-51-api-exposure | 🔲 Not Started | - | - |
| #52 | gc-52-qualification | 🔲 Not Started | - | - |

---

**Last Updated:** 2026-11-12
