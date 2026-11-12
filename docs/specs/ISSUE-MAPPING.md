# Issue to Specification Mapping

## Primary: #41 - LayerFS Garbage Collection

### Specification Files
- `gc-issue-41/README.md` - Complete issue overview
- `gc-issue-41/DESIGN-QUESTIONS.md` - Design decisions
- `gc-issue-41/SUB-ISSUE-TRACKER.md` - Implementation breakdown

### Operations Specified
- ✅ `branch.remove(name)` - Soft Branch removal
- ✅ `project.delete(name)` - Soft project deletion
- ✅ `project.remove_file(...)` - Logical file removal
- ✅ `store.compact(name)` - Explicit Store compaction

### Sub-Issues (#42-#52)

| # | Title | Status | Component |
|---|-------|--------|-----------|
| #42 | Design assessment & contract finalization | Design | Core |
| #43 | Admission enforcement | Impl | Engine |
| #44 | Branch removal | Impl | Engine |
| #45 | Project deletion | Impl | Engine |
| #47 | File removal | Impl | Engine |
| #48 | Shared data reachability | Impl | Engine |
| #49 | SQLite compaction | Impl | Persistence |
| #50 | PostgreSQL compaction | Impl | Persistence |
| #51 | API/SDK/CLI exposure | Impl | API |
| #52 | Qualification testing | Test | QA |

### Key Constraints
- ⚠️ **No physical reclamation** except in `store.compact()`
- ⚠️ **Exclusive access** required during `store.compact()`
- ⚠️ **Cross-project safety** must be maintained
- ⚠️ **Immutable IDs protected** after file removal
- ⚠️ **PostgreSQL remote** compaction required (not stub)

---

## Related: #379 - Full-disk Commit & Free-space Guard

### Specification Files
- `gc-cleanup/README.md` - Issue overview
- `gc-cleanup/01-*.md` - Implementation details

### Relationship to #41
- **Dependency:** #379 (free-space guard) should integrate with #41 (GC)
- **Coordination:** Free-space margin protection during store.compact()
- **Interaction:** Guard triggers before compact capacity checks

### Key Components
- Error code standardization
- Free-space guard (64 MiB headroom)
- Pack lifecycle management
- Storage layer error mapping

---

## Related: #301 - Phase 7 Immutable Architecture

### Specification Files
- `phase7-immutable-architecture/README.md` - Design overview
- `phase7-immutable-architecture/01-architecture.md` - System architecture
- `phase7-immutable-architecture/02-workspace-overlay.md` - Workspace layer
- `phase7-immutable-architecture/03-commit-workflow.md` - Commit handling
- `phase7-immutable-architecture/04-storage-interfaces.md` - Storage interfaces

### Relationship to #41
- **Foundation:** #301 defines storage schema and pack structure that #41 operates on
- **Immutable Objects:** #41 GC must preserve #301 immutable object guarantees
- **Shared Packs:** #301 introduces pack sharing that #41 reference counting protects

### Key Components
- PostgreSQL + S3 immutable objects
- Daemon SQLite overlay
- Workspace overlay isolation
- Commit workflow with crash recovery

---

## Storage Architecture

### Specification Files
- `storage/05-storage.md` - Comprehensive storage design

### Applies To All GC Operations
- Pack structure and addressing
- Reference semantics
- Shared object protection
- Physical vs. logical layer separation

---

## Coordination Matrix

| Issue | #41 GC | #379 Guard | #301 Phase7 | #511 Contract |
|-------|--------|-----------|-----------|---------------|
| **#42** Design | Primary | Reference | Foundation | Authority |
| **#43** Admission | Primary | Support | - | Constraint |
| **#44** Branch RM | Primary | - | - | Requirement |
| **#45** Project RM | Primary | - | - | Requirement |
| **#47** File RM | Primary | - | Uses | Requirement |
| **#48** Sharing | Primary | - | Critical | Constraint |
| **#49** SQLite | Primary | Integration | Implementation | Requirement |
| **#50** PostgreSQL | Primary | Integration | Implementation | Requirement |
| **#51** API | Primary | - | - | Exposure |
| **#52** Qualify | Test | Coverage | Validation | Sign-off |

