# LayerFS GC Issue Mapping

## 主要 Issue

### 🎯 #42 - "Assess garbage-collection design and finalize contracts for SQLite and PostgreSQL"
**仓库**: `Ephemeral-AI-Lab/layerfs-project`

**当前文档对应**：
- `LayerFS-GC-spec.md` — frozen contract draft
- `gc-42-assessment.md` — design assessment & reconciliation
- `C8b-N3-C9-Resolution-Plan.md` — three key problems resolution

**#42 的六个验收点**（六 acceptance points）：
1. ✅ 可达性（reachability）— 已冻结
2. ✅ 回收判定（retention logic）— 已冻结
3. ✅ Compact 流程（SQLite + PostgreSQL）— 已冻结
4. 🔲 C8b SQLite 写者围栏（pre-swap writer fence）— 新代码，待实现
5. 🔲 N3 逻辑删除表示（soft delete visibility）— Schema 变更，待实现
6. 🔲 C9 HistoryCatalog 约束（maintenance pattern）— API 合约，待遵循

---

## 相关子 Issue（#42 的依赖）

### 📋 上游政策

**#511 - Product Policy** (`Ephemeral-AI-Lab/layerfs`)
- **标题**: GC 产品需求与收益
- **内容**: 定义 admission matrix、logical/physical 分离、no-retry 策略
- **关系**: #42 的权威参考，冻结了基本政策

**#506 - Store-first model**
- **标题**: Refactor: Store-first persistence backend
- **内容**: SQLite/PostgreSQL 统一后端架构
- **关系**: #42 的基础设施

---

### 🔧 功能子任务（mapped in spec §10）

| Issue | 标题 | 对应 Spec | 实现阶段 |
|-------|------|----------|--------|
| **#43** | Admission scope matrix | C10, §2, §7.1 | Phase 1 (基础) |
| **#44** | `branch.remove` tombstone | C6, Q1 | Phase 2 |
| **#45** | `project.delete` soft-delete | §8, N3 | Phase 2 (含 N3) |
| **#47** | `project.remove_file` hidden views | §8, §9.3, Q2 | Phase 3 |
| **#48** | Reachability closure (frozen roots) | §6, C1–C2 | Phase 1 |
| **#49** | SQLite fence & compaction | §7.2, C8b | Phase 2 (含 C8b) |
| **#50** | PostgreSQL backend & fencing | §7.3, D3 | Phase 3 |
| **#52** | Acceptance (测试验证) | §9, 集成验证 | Phase 4 |

---

## 当前文档在 Issue 体系中的位置

```
Ephemeral-AI-Lab/layerfs#511 (产品策略)
    ↓
Ephemeral-AI-Lab/layerfs-project#42 (设计审查) ← 当前任务
    ├─ C8b (SQLite 写者围栏) ← NEW PROBLEMS
    ├─ N3 (逻辑删除表示)     ← IDENTIFIED
    ├─ C9 (HistoryCatalog)   ←
    │
    └─ #43–#52 (功能子任务)
```

---

## 三个问题在 Issue 体系中的归属

| 问题 | 主 Issue | 子 Issue | 原因 |
|------|---------|---------|------|
| **C8b** | #42 | #49 | 属于 SQLite 写者围栏 (pre-swap fence) |
| **N3** | #42 | #45 | 属于项目软删除的 schema 变更 |
| **C9** | #42 | 跨 #43–#52 | 属于 HistoryCatalog 维护约束 (API 合约) |

---

## 关键文件映射

| Issue | 关键文件 | 路径 |
|-------|---------|------|
| #42 | GC 规范（frozen） | `layerfs-specs/gc-spec.md` |
| #42 | 设计评估 | `layerfs-specs/gc-42-assessment.md` |
| #42 | 三问题解决 | `gc-spec/C8b-N3-C9-Resolution-Plan.md` ✅ NEW |
| #49 | SQLite lifecycle | `backend/sqlite/lifecycle/installation.rs` |
| #50 | PostgreSQL schema | `sql/postgresql/schema.sql` |
| #45 | Project removal API | `api/crates/layerfs-api/src/project/remove.rs` |

---

## 决策跟踪（Decision Points）

四个仍需产品 / 设计确认的决策点：

| ID | 项目 | Issue | 建议 | 所有权 |
|----|------|-------|------|--------|
| **D1** | BranchId 代际编码方式 | #42, #44 | identity_format vs 独立列 | 产品 (🟡 待确认) |
| **D3** | PostgreSQL 围栏选择 | #42, #50 | advisory lock vs FOR UPDATE vs schema lock | 产品 (🟡 待确认) |
| **D6** | 时间戳精度 | #42, #45 | nullable BIGINT (ms) vs epoch | 产品 (🟡 待确认) |
| **D7** | 源分支删除权限 | #42, #44 | 允许 vs 禁止（建议允许，fork 保留所用） | 产品 (🟡 待确认) |

---

## 下一步：Issue 操作流程

### Step 1: 产品确认决策点（D1/D3/D6/D7）
→ 在 `Ephemeral-AI-Lab/layerfs#511` T3 thread 或新 comment 中确认

### Step 2: 更新 #42 Assessment 文档
→ 标记四个决策点为 `[x]` (confirmed) 或 `[decided: ...]`

### Step 3: 分解为子 Issue 实现任务
→ 在 #43–#52 中创建 subtask（如 "C8b: implement writer fence"）

### Step 4: 代码实现与 PR
→ PR 描述应关联对应的 Issue 编号

### Step 5: 验收（#52）
→ 集成验证清单对应 #52 acceptance criteria

---

## 快速链接

- **#42**: https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/42
- **#511**: https://github.com/Ephemeral-AI-Lab/layerfs/issues/511
- **#49**: SQLite fence sub-task
- **#50**: PostgreSQL backend sub-task
- **#45**: Project soft-delete sub-task

