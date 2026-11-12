# Excalidraw Architecture & Sequence Diagrams

All diagrams are in the Excalidraw collection: https://app.excalidraw.com/s/9Zq6XgRe98z/

## Issue #42 - Design Assessment

### C9: HistoryCatalog Architecture
- **Type:** Architecture diagram
- **Concept:** Three-layer history visibility (Full → Modified → Removed)
- **Link:** (Check collection for scene ID)

---

## Issue #43 - Admission Enforcement

### C10: Admission Matrix Decision Tree
- **Type:** Decision tree
- **Concept:** Mount validation rules for each GC operation
- **Rules:**
  - branch.remove → no mounts on that Branch
  - project.delete → no mounts in project
  - project.remove_file → no mounts in project
  - store.compact → exclusive Store access

---

## Issue #44 - Branch Removal

### N3: Name Reuse Timeline (Part 1)
- **Type:** Timeline / state machine
- **Concept:** Branch soft-delete with removed_ms timestamp
- **States:** Active → Removed → Eventually Reclaimed

---

## Issue #45 - Project Deletion  

### N3: Name Reuse Timeline (Part 2)
- **Type:** Timeline / state machine
- **Concept:** Project soft-delete with deleted_ms + schema migration
- **States:** Active → Deleted → Store Retained → Eventually Compacted

---

## Issue #47 - File Removal

**Diagrams:** (None required - design phase only)

---

## Issue #48 - Shared Data Reachability

### Closure & Generation Architecture
- **Type:** Architecture diagram
- **Concept:** 3-step reachability closure (Pinned → Historical → Cross-Project)
- **Components:**
  - Layer closure across project boundaries
  - Delta-base protection in shared packs
  - Transitive dependency graph

---

## Issue #49 - SQLite Compaction

### C8b: 5-Stage Incarnation Pipeline
- **Type:** Sequence diagram
- **Scene ID:** (Find in collection)
- **Stages:**
  1. Setup: Mark discarded rows
  2. Create & Rewrite: New tables without deleted rows
  3. Atomic Swap: Exchange table names
  4. Reader Fence: Wait for old readers
  5. Complete: Drop old tables
- **Key:** Writer-exclusive fence during stage 3 ensures no split-brain

---

## Issue #50 - PostgreSQL GC

### D3: PostgreSQL Compact Architecture Flow
- **Type:** Architecture diagram + flow chart
- **Scene ID:** 329NfoaidRt
- **Link:** https://app.excalidraw.com/s/9Zq6XgRe98z/329NfoaidRt
- **5 Stages:**
  1. Setup (blue)
  2. Create & Rewrite (orange)  
  3. Atomic Swap (pink)
  4. Reader Fence (purple)
  5. Complete (green)

### D3: PostgreSQL Compact Interaction Sequence
- **Type:** Sequence diagram
- **Scene ID:** Alhrgo0pPJ
- **Link:** https://app.excalidraw.com/s/9Zq6XgRe98z/Alhrgo0pPJ
- **Layers:**
  - L3: Adapter (control-plane facing)
  - L2: Engine (persistence layer)
  - PostgreSQL: Database schema
- **Key:** Remote clients receive explicit "compaction in progress" errors

---

## Issue #51 - API Exposure

### C9: HistoryCatalog API Design
- **Type:** Architecture / API contract diagram
- **Concept:** How removed files remain accessible via immutable IDs
- **Methods:**
  - project.get_file(path, immutable_id) → protected
  - project.list_history(path) → includes removed entries with visibility=Removed
  - project.stat_file(path, immutable_id) → can query removed files

---

## Issue #52 - Acceptance Testing

### Crash Recovery Testing Matrix
- **Type:** Matrix / decision table
- **Scene ID:** 9IZiVsP9Fnl  
- **Link:** https://app.excalidraw.com/s/9Zq6XgRe98z/9IZiVsP9Fnl
- **5 Crash Injection Points:**
  1. During Setup (assertion: discarded rows marked)
  2. During Create (assertion: new tables exist, old still readable)
  3. During Swap (state machine: one of old/new is active)
  4. During Fence (assertion: no new readers on old)
  5. During Drop (assertion: all old data gone)
- **Verification:** Cross-project pack protection, receipt byte consistency

---

## Diagram Collection Structure

```
tokenaissance-layerfs (Excalidraw workspace)
├── GC #42 - Design Assessment
│   └── HistoryCatalog Architecture
├── GC #43 - Admission Matrix
├── GC #44/#45 - Name Reuse Timeline (N3)
├── GC #48 - Closure & Generation
├── GC #49 - SQLite Incarnation Pipeline (C8b)
├── GC #50 - PostgreSQL Architecture (D3)
│   ├── 329NfoaidRt - 5-Stage Flow
│   └── Alhrgo0pPJ - Interaction Sequence
├── GC #51 - HistoryCatalog API (C9)
└── GC #52 - Crash Recovery Matrix
    └── 9IZiVsP9Fnl - Injection Points
```

## Linking Diagrams to GitHub Issues

Each GitHub issue #42-#52 has a comment that includes:
- Spec section reference (§ X.Y)
- Excalidraw diagram link(s)
- Bullet-point implementation checklist
- Acceptance criteria referencing diagram

**Example (Issue #49):**
```markdown
## GC Spec Reference
- § 7.2 C8b: SQLite Incarnation Protocol
- Excalidraw: C8b 5-Stage Incarnation Pipeline

## Implementation Checklist
- [ ] Stage 1: Mark discarded rows (see diagram)
- [ ] Stage 2: Create new tables
- [ ] Stage 3: Atomic swap with writer fence (critical)
  - Diagram shows fence timing
  - Writer-exclusive lock required
- [ ] Stage 4: Reader fence / grace period
- [ ] Stage 5: Drop old tables
```

## P3 Diagrams Status

| Issue | Diagram | Status | Link |
|-------|---------|--------|------|
| #50 | Architecture Flow | ✅ Complete | 329NfoaidRt |
| #50 | Sequence Diagram | ✅ Complete | Alhrgo0pPJ |
| #52 | Crash Matrix | ✅ Complete | 9IZiVsP9Fnl |

