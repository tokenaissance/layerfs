# LayerFS Design Specifications

This directory contains comprehensive design documentation and specifications for LayerFS v2.0.0 development, organized by issue and component.

## Contents

### Garbage Collection & Storage Management

#### [gc-issue-41/](./gc-issue-41/) - Issue #41: LayerFS Garbage Collection
**Source:** [Ephemeral-AI-Lab/layerfs-project/issues/41](https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/41)

Main garbage collection epic covering soft removal and explicit Store compaction:

- **Operations:**
  - `branch.remove(name)` - Soft Branch removal
  - `project.delete(name)` - Soft project deletion  
  - `project.remove_file(...)` - Logical historical file/folder removal
  - `store.compact(name)` - Explicit Store compaction

- **Key Files:**
  - `README.md` - Complete issue overview and requirements
  - `DESIGN-QUESTIONS.md` - Design decisions and rationales
  - `SUB-ISSUE-TRACKER.md` - Implementation tasks for sub-issues #42-#52

- **Sub-Issues:**
  - #42 - Design assessment and contract finalization
  - #43 - Admission and active-use exclusion enforcement
  - #44-#45 - Branch removal and project deletion
  - #47-#48 - File removal and shared data reachability
  - #49-#50 - SQLite and PostgreSQL compaction
  - #51-#52 - API exposure and qualification

#### [gc-cleanup/](./gc-cleanup/) - Issue #379 (Related)
Full-disk Commit error codes and free-space guard implementation.

### Phase 7: Immutable Object Architecture  
[phase7-immutable-architecture/](./phase7-immutable-architecture/) - Issue #301

- Immutable-object architecture on PostgreSQL + S3
- Daemon SQLite overlay design
- Workspace overlay mechanism
- Commit workflow and storage interfaces
- Migration planning

### Storage Architecture
[storage/](./storage/) - Core reference documentation

- Main storage design document (05-storage.md)

## Reading Guide

### For GC Implementation (#41)

**Phase 1: Understanding** (Start here)
1. `gc-issue-41/README.md` - Overview and requirements
2. `gc-issue-41/DESIGN-QUESTIONS.md` - Design principles
3. `storage/05-storage.md` - Storage foundation

**Phase 2: Sub-Issue Planning** (#42-#52)
1. `gc-issue-41/SUB-ISSUE-TRACKER.md` - Task breakdown per sub-issue
2. Review specific sub-issue requirements

**Phase 3: Implementation**
1. Follow the implementation order: #42 (design) → #43 (admission) → #44-#45 (removal) → #47-#48 (sharing) → #49-#50 (compaction) → #51-#52 (API & qualification)
2. Cross-reference with storage layer requirements

### For Storage Architecture

1. `storage/05-storage.md` - Comprehensive storage design
2. `gc-issue-41/README.md` - GC constraints on storage
3. `phase7-immutable-architecture/` - Schema and interface changes

## Issue Relationships

```
#41 (GC Main Epic)
├── #42 (Design & Assessment)
├── #43 (Admission Enforcement)
├── #44 (Branch Removal)
├── #45 (Project Deletion)
├── #47 (File Removal)
├── #48 (Shared Data)
├── #49 (SQLite Compaction)
├── #50 (PostgreSQL Compaction)
├── #51 (API Exposure)
└── #52 (Qualification)

Cross-Cutting Concerns:
├── #511 (Release Contract - authority)
├── #23 (Control/Recovery)
├── #30 (Public Interfaces)
└── #379 (Free-space Guard)
```

## Key Decisions

| Decision | Details |
|----------|---------|
| **Logical First** | All remove/delete operations are logical; only `store.compact()` performs physical reclamation |
| **Exclusive Compact** | `store.compact()` requires exclusive Store access; no concurrent operations |
| **Cross-Project Safety** | All cross-project sharing and transitive delta bases must survive GC |
| **PostgreSQL Remote** | Remote PostgreSQL servers must support full compaction (not "Unsupported") |
| **Immutable IDs Protected** | Existing immutable IDs must not silently resolve to changed contents |
| **No Auto Collection** | No automatic collection, online sweep or main-Layer pruning in this release |
| **No Pruning** | Branch pruning (#46) deferred to future release |

## Compliance & Testing

- **Backends:** SQLite and PostgreSQL (both required)
- **Timeout Budget:** ≤120 seconds per command (≤15 seconds typical, ≤25 with exception)
- **Measurement:** <10 seconds unless authorized
- **Build & Test:** Build before tests; full coverage required
- **Disposable Only:** Durable disabled, follow LOC rules

## Repository Links

- **Main Repo:** https://github.com/Ephemeral-AI-Lab/layerfs
- **Project Repo:** https://github.com/Ephemeral-AI-Lab/layerfs-project
- **Base Branch:** `layerfs_v2_0_0`
- **Release Target:** LayerFS 2.0.0

---

**Last Updated:** 2026-11-12  
**Maintainer:** Design Team  
**Status:** Draft - Awaiting #42 design finalization
