# Design Questions & Decisions Log

## Q1: Physical vs. Logical Reclamation

**Decision:** All remove/delete operations are logical first. Only `store.compact()` performs physical reclamation.

**Rationale:**
- Allows atomic enforcement of admission rules
- Prevents accidental data loss
- Separates visibility changes from physical cleanup
- Simplifies recovery and rollback

**Implementation Impact:**
- `branch.remove()` - marks Branch invisible, data remains
- `project.delete()` - marks project invisible, Store remains addressable
- `project.remove_file()` - marks file logically removed, history accessible via immutable IDs
- `store.compact()` - requires exclusive lock, physically reclaims discarded data

## Q2: Cross-Project Sharing Durability

**Decision:** All cross-project sharing and transitive delta bases must survive garbage collection.

**Test Case:**
- Project A contains shared pack P
- Project B references P via delta base
- `project.delete(A)` must not break B's reference
- `store.compact()` must protect P

**Implementation Impact:**
- Reference counting required during design phase
- Reachability analysis must span projects
- Compact must preserve shared immutable objects

## Q3: PostgreSQL Remote Compaction

**Decision:** Remote PostgreSQL servers must support full compaction, not "Unsupported" stub.

**Requirements:**
- Compaction works with remote database servers
- Physical reclamation verified on remote systems
- Network failures handled gracefully
- Recovery verified end-to-end

**Test Strategy:**
- Real remote PostgreSQL instance
- Network partition simulation
- Physical shrink verification (SELECT pg_total_relation_size)

## Q4: Immutable ID Access After removal

**Decision:** Existing immutable IDs must not silently resolve to changed contents after `project.remove_file()`.

**Implementation Pattern:**
```
// Before removal
project.get_file("/path", immutable_id=abc123) → original content

// After remove_file("/path")
project.get_file("/path", immutable_id=abc123) → still original content OR explicit error
project.get_file("/path")                      → file not found or error
```

**Not Allowed:**
```
// ❌ WRONG - silently returns different content
project.get_file("/path", immutable_id=abc123) → new/different content
```

## Q5: Sandboxes Close Requirement

**Decision:** Target-project Sandboxes/clients must close before deletion/remove_file operations.

**Mechanism:**
- Check active mounts atomically
- Return `Busy` if clients active
- Atomically exclude new mounts during operation
- No implicit stop/unmount

**Client Responsibility:**
- `unmount()` before requesting delete
- No automatic cleanup
- No wait for active users to disappear
- One attempt without retry/replay

## Q6: Store.compact() Isolation

**Decision:** `store.compact()` requires exclusive access for the whole Store.

**Isolation Scope:**
- All projects/Branches/historical mounts within Store blocked
- No new mounts during compaction
- No in-flight work allowed
- Remote PostgreSQL clients also blocked
- Other Stores remain independent

**Error Handling:**
- `Busy` if conflicting operations in progress
- `MountsActive` if any mounts exist
- Preliminary scan insufficient
- No implicit wait or retry

---

## Open Items for #42

- [ ] Exact reference counting strategy
- [ ] Transitive delta base protection algorithm
- [ ] PostgreSQL compaction implementation approach
- [ ] Immutable ID access contract detail
- [ ] Recovery/repair procedures after failed compact
- [ ] Monitoring and observability design
