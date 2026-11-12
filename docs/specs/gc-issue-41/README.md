# Issue #41: LayerFS Garbage Collection - Soft Removal and Store Compaction

**Repository:** [Ephemeral-AI-Lab/layerfs-project](https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/41)  
**Status:** OPEN  
**Labels:** task, lane:engine  
**Created:** 2026-11-05

## Outcome

Deliver explicit LayerFS garbage collection for **SQLite and PostgreSQL** through:
- Soft Branch removal
- Soft project deletion
- Logical historical file/folder removal
- Explicit Store compaction

## Core Operations

### 1. `branch.remove(name)` - Soft Branch Removal
- Soft-removes a Branch without physical data reclamation
- Other Branches in the same project remain usable
- No physical rows/content deleted

### 2. `project.delete(name)` - Soft Project Deletion
- Soft-deletes a project
- Store and volume remain addressable
- Requires all Sandboxes/clients within project to close
- Other projects in Store remain usable

### 3. `project.remove_file(...)` - Logical File Removal
- Logically removes a file/folder across project history
- No physical data reclamation
- Immutable IDs must not silently resolve to changed contents
- Separate from ordinary versioned `file.rm`

### 4. `store.compact(name)` - Explicit Store Compaction
- Physically reclaims discarded rows and data
- Protects all shared content/dependencies
- **Exclusive access required** for whole operation
- PostgreSQL compaction required, including remote servers

## Completion Criteria

- [ ] Design reconciles current 2.0 code with updated #511 release contract
- [ ] All remove/delete calls are logical only (no automatic physical reclamation)
- [ ] Admission matrix enforced atomically while unrelated resources remain usable
- [ ] Retained history/content, cross-project sharing, transitive delta bases survive
- [ ] Backend compaction/recovery verified on both SQLite and PostgreSQL
- [ ] Public frontend contracts and guides match release scope
- [ ] Physical vs. logical reclamation separately reported

## Admission and Mount Policy

| Operation | No mounts within | Other restrictions | What may remain active |
|-----------|------------------|-------------------|------------------------|
| `branch.remove(name)` | Selected Branch only | Existing validity rules | Other Branches in same project |
| `project.delete(name)` | Selected project, all Branches and historical Commits | Target-project Sandboxes must close | Other projects in same Store |
| `project.remove_file(...)` | Selected project, all Branches and Commits | Target-project Sandboxes must close | Other projects in same Store |
| `store.compact(name)` | Selected Store, all projects/Branches | Exclusive access for whole operation | Other Stores |

**Mount violations:** `MountsActive`  
**Conflicting users:** `Busy`

## Engineering Rules

- **No pruning in this release** - branch.prune/project.prune deferred
- **No automatic collection** - online in-place sweep or main-Layer pruning excluded
- **Remote PostgreSQL supported** - server compaction required, not unsupported stub
- **Disposable only** - Durable disabled, follow LOC rules
- **Build timeout** ≤120 seconds
- **Command timeout** ≤15 seconds (≤25 with declared exception)
- **Measurement timeout** <10 seconds unless authorized otherwise

## Active Sub-Issues

### Design & Assessment (#42)
- [ ] #42 — Assess garbage-collection design and finalize contracts

### Implementation Tasks
- [ ] #43 — Enforce cleanup admission and active-use exclusions
- [ ] #44 — Implement and verify Branch removal
- [ ] #45 — Implement and verify project deletion
- [ ] #47 — Design and implement logical historical file and folder removal
- [ ] #48 — Implement and verify shared live-data reachability
- [ ] #49 — Implement SQLite compaction with verified replacement and recovery
- [ ] #50 — Implement PostgreSQL garbage collection and space reclamation

### Integration & Qualification
- [ ] #51 — Expose garbage collection through API, SDKs and CLI
- [ ] #52 — Qualify garbage collection on SQLite and PostgreSQL

## Coordination

- **#23** (layerfs-project) - Control/recovery coordination
- **#30** (layerfs-project) - Public interfaces
- **#1** (layerfs-project) - Backup integration
- **#8** (layerfs-project) - SQLite transfer
- **#511** (layerfs) - Release contract and decision authority

## Deferred / Not in Scope

- ✋ Branch pruning (#46) - deferred
- ✋ Automatic LayerFS collection
- ✋ Online in-place sweep
- ✋ Main-Layer pruning
- ✋ Compaction of remote object-storage replicas

---

**Release Target:** LayerFS 2.0.0  
**Base Issue:** #511 (release contract)
