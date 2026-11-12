# Sub-Issue Tracker

## #42 - Assessment & Contract Finalization

**Goal:** Assess existing garbage collection design, finalize contracts for both backends

**Tasks:**
- [ ] Review current 2.0 code implementation
- [ ] Reconcile with #511 release contract
- [ ] Define exact API contracts per operation
- [ ] Design reference counting strategy
- [ ] Design transitive delta base protection
- [ ] Create detailed implementation plan for each sub-issue

**Outcome:** Design document with finalized contracts ready for implementation

---

## #43 - Enforce Admission & Active-Use Exclusions

**Goal:** Implement admission matrix enforcement and active-use exclusion logic

**Tasks:**
- [ ] Define admission matrix data structure
- [ ] Implement atomic mount state check
- [ ] Implement `MountsActive` error return
- [ ] Implement `Busy` error return for conflicting users
- [ ] Add atomicity tests

**Acceptance:** All tests pass on SQLite and PostgreSQL

---

## #44 - Branch Removal

**Goal:** Implement and verify `branch.remove(name)`

**Tasks:**
- [ ] Mark Branch as removed (logical deletion)
- [ ] Prevent new mounts to removed Branch
- [ ] Verify other Branches unaffected
- [ ] Test publish/merge behavior with removed Branch
- [ ] Test recovery/undelete scenarios

**Acceptance:** Branch properly soft-removed, other resources unaffected

---

## #45 - Project Deletion

**Goal:** Implement and verify `project.delete(name)`

**Tasks:**
- [ ] Mark project as deleted
- [ ] Keep Store addressable for compact
- [ ] Verify Sandboxes cannot mount deleted project
- [ ] Test other projects in same Store unaffected
- [ ] Test Store.compact with deleted projects

**Acceptance:** Project soft-deleted, Store remains usable

---

## #47 - Logical File Removal

**Goal:** Design and implement `project.remove_file(...)`

**Tasks:**
- [ ] Design immutable ID access contract
- [ ] Design historical representation
- [ ] Implement file logical removal
- [ ] Implement history traversal with removed files
- [ ] Test immutable ID access before/after removal
- [ ] Test cross-project sharing with removed files

**Acceptance:** File logically removed, immutable IDs protected

---

## #48 - Shared Data Reachability

**Goal:** Implement and verify shared live-data reachability

**Tasks:**
- [ ] Implement reference counting
- [ ] Design transitive delta base graph
- [ ] Implement reachability analysis
- [ ] Test pack sharing detection
- [ ] Test delta base protection during compact
- [ ] Test cross-project sharing scenarios

**Acceptance:** All shared data protected, reference counts accurate

---

## #49 - SQLite Compaction

**Goal:** Implement and verify SQLite store compaction

**Tasks:**
- [ ] Implement logical row deletion
- [ ] Implement VACUUM/cleanup mechanism
- [ ] Implement physical shrink verification
- [ ] Test recovery after interrupted compact
- [ ] Test mount failures during compact
- [ ] Measure space reclamation before/after

**Acceptance:** SQLite physically compacted, data verified safe

---

## #50 - PostgreSQL GC & Compaction

**Goal:** Implement PostgreSQL garbage collection and compaction

**Tasks:**
- [ ] Implement logical row marking
- [ ] Implement PostgreSQL compaction strategy
- [ ] Test remote PostgreSQL servers
- [ ] Implement physical reclamation verification (pg_total_relation_size)
- [ ] Test network partition recovery
- [ ] Measure space reclamation before/after

**Acceptance:** PostgreSQL compacted, remote servers supported

---

## #51 - API/SDK/CLI Exposure

**Goal:** Expose garbage collection through public interfaces

**Tasks:**
- [ ] Add API endpoints (branch.remove, project.delete, etc.)
- [ ] Add SDK methods
- [ ] Add CLI commands
- [ ] Write user guides
- [ ] Document error codes and recovery
- [ ] Add examples and best practices

**Acceptance:** Full API coverage, documented with examples

---

## #52 - Qualification

**Goal:** Comprehensive testing on SQLite and PostgreSQL

**Tasks:**
- [ ] Integration tests (all operations together)
- [ ] Failure recovery tests
- [ ] Cross-project sharing verification
- [ ] Performance benchmarks
- [ ] Load testing
- [ ] Documentation validation

**Acceptance:** All tests pass, performance meets targets
