# LayerFS GC #41 项目体系 - C8b/N3/C9 在其中的位置

## 📍 #41 概览

**标题**: "LayerFS garbage collection: soft removal and Store compaction"  
**仓库**: `Ephemeral-AI-Lab/layerfs-project`  
**状态**: 🟢 OPEN  
**创建**: 2026-11-05  
**最后更新**: 2026-11-08

**所有权**: Engine (parent lane) + Core (content closure) + API (public bindings)

---

## 🎯 #41 的四个核心操作

### 1. `branch.remove(name)` — 分支软删除
- **什么**：逻辑删除分支，不物理删除行
- **隔离**：仅该分支不允许新 mount
- **允许继续**：其他分支（包括同项目的其他分支）
- **对应**：#44

### 2. `project.delete(name)` — 项目软删除
- **什么**：逻辑删除项目及其所有分支
- **隔离**：整个项目的所有分支都不允许新 mount
- **重要**：Store 和 volume 仍保留（不删除），保持可寻址
- **对应**：#45，**包含 N3（schema 变更）**

### 3. `project.remove_file(...)` — 文件/文件夹逻辑删除
- **什么**：跨项目历史删除文件/文件夹
- **隔离**：整个项目的所有分支/Commit mount 都必须关闭
- **对应**：#47

### 4. `store.compact(name)` — Store 显式 Compaction
- **什么**：物理回收：删除无用行 + 压缩数据
- **隔离**：整个 Store 的所有项目/分支/历史 mount 都必须关闭（**排他访问**）
- **对应**：#49（SQLite）+ #50（PostgreSQL），**包含 C8b**
- **报告**：逻辑字节 + 后端可重用空间 + 实际物理回收（分开报告）

---

## 🔗 10 个子 Issue 清单

| # | 标题 | 优先级 | 关键工作 | 与 C8b/N3/C9 的关系 |
|---|------|--------|--------|-------------------|
| **#42** | 设计评估 + 合约确认 | P0 🔴 | 三个问题的诊断 | ✅ **C8b/N3/C9 都在这** |
| **#43** | 准入矩阵 + 排他规则 | P1 | admission 实现 | C8b 的准入校验 |
| **#44** | branch.remove 实现 | P2 | 分支软删除 + 验证 | N3 的 removed_ms 列 |
| **#45** | project.delete 实现 | P2 | 项目软删除 + 验证 | ✅ **N3（deleted_ms）在这** |
| **#47** | project.remove_file | P3 | 文件逻辑删除 | 跨项目历史清理 |
| **#48** | 可达性闭包 | P1 | reachability walk | decode_references 复用 |
| **#49** | SQLite compact | P2 | compaction + 恢复 | ✅ **C8b（写者围栏）在这** |
| **#50** | PostgreSQL GC | P3 | remote PG 支持 | D3（围栏选择）在这 |
| **#51** | 公开 API/CLI/SDK | P3 | 四个操作的接口 | C9（HistoryCatalog）影响这 |
| **#52** | 验收 + 测试 | P4 | 两个后端集成验证 | 验收清单 |

---

## 🎯 三个问题在 #41 体系中的位置

### **C8b - SQLite 写者围栏**
```
#41 (GC 项目)
  └─ #49 (SQLite compact) ← C8b 在这
      ├─ 问题：pre-swap 写者的 silent data loss
      ├─ 解决：incarnation protocol（代际机制）
      ├─ 实现：writer_admission.rs + install 时代际递增
      └─ 验收：并发 compact+write 测试
```

**影响范围**：
- `store.compact()` 的核心安全机制
- 写入操作的 admission 校验点
- 代际持久化（history_meta 或独立表）

---

### **N3 - 逻辑删除表示**
```
#41 (GC 项目)
  ├─ #44 (branch.remove) ← removed_ms 列
  └─ #45 (project.delete) ← C8b 在这
      ├─ 问题：无可见性列，无法软删除
      ├─ 解决：schema v3.5 → v3.6（deleted_ms/removed_ms）
      ├─ 实现：部分唯一索引（允许 tombstone）
      └─ 验收：名称重用 + 可见性过滤
```

**影响范围**：
- `branch.remove()` 的 removed_ms 隐藏
- `project.delete()` 的 deleted_ms 隐藏
- 所有 list/get 查询的可见性过滤
- 名称重用机制

---

### **C9 - HistoryCatalog 约束**
```
#41 (GC 项目)
  ├─ #42 (设计) ← C9 在这
  ├─ #45 (project.delete)
  ├─ #49 (SQLite compact)
  ├─ #50 (PostgreSQL GC)
  └─ #51 (API 暴露) ← C9 影响这
      ├─ 问题：8 impl × 32 methods 维护爆炸
      ├─ 解决：default Unsupported 模式
      ├─ 4 个新方法：mark_branch_removed/deleted, get_retained_roots, remove_unreachable
      └─ 验收：8 个 impl 无需改动
```

**影响范围**：
- HistoryCatalog trait 的 GC 方法扩展
- SQLite + PostgreSQL impl 的一致性
- 测试 double 的零改动保证
- 错误码的冻结（6 个变体不再增加）

---

## 📊 优先级和依赖

```
Legend:
  P0 = 设计决策
  P1 = 基础设施
  P2 = 核心功能
  P3 = 扩展功能
  P4 = 验收/测试

Timeline:
  Phase 1 (Week 1-2)   : #42 (P0) + #43 (P1) + #48 (P1)
                         ↓ 决策点确认 (D1/D3/D6/D7)
  
  Phase 2 (Week 3-4)   : #44 (P2) + #45 (P2) + #49 (P2)
                         ├─ N3 schema 迁移 (#45 内)
                         └─ C8b writer fence (#49 内)
  
  Phase 3 (Week 5-6)   : #47 (P3) + #50 (P3) + #51 (P3)
                         ├─ C9 HistoryCatalog (#51 涉及)
                         └─ PostgreSQL compaction (#50)
  
  Phase 4 (Week 7)     : #52 (P4) 集成验收
```

---

## ✅ 完成条件（Completion Criteria）

#41 要求的 7 个完成条件中，三个问题直接影响：

| 条件 | 对应问题 | 当前状态 |
|------|--------|--------|
| 1️⃣ 设计协调 v2.0 | 全部（C8b/N3/C9） | ✅ LayerFS-GC-spec.md 已覆盖 |
| 2️⃣ 四操作 SQLite+PG | C8b (SQLite) + C9 (API) | 🔲 待实现 |
| 3️⃣ 所有删除都逻辑删除 | N3 (soft delete) | 🔲 待实现 |
| 4️⃣ 准入矩阵原子性 | C8b (代际) + C9 (HistoryCatalog) | 🔲 待实现 |
| 5️⃣ 共享内容保护 | N3 (reachability) | ✅ 机制已有 |
| 6️⃣ 后端验证 + 报告 | C8b + C9 | 🔲 待验证 |
| 7️⃣ 公开合约匹配 | C9 (HistoryCatalog) | 🔲 待匹配 |

---

## 📍 当前工作的上下文

```
GitHub 仓库体系：
  Ephemeral-AI-Lab/layerfs (主仓库)
    ├─ issue #511 (产品政策) → CLOSED ✓
    │   └─ 策略已冻结，权力转移到...
    │
    └─ Ephemeral-AI-Lab/layerfs-project (项目仓库)
        └─ issue #41 (实现规划) → OPEN 🟢
            ├─ 母议题，10 个子 issue
            │
            ├─ #42 (设计评估) ← 你现在在这
            │   ├─ C8b (SQLite 写者围栏)
            │   ├─ N3 (逻辑删除表示)
            │   └─ C9 (HistoryCatalog 约束)
            │
            ├─ #43 (准入矩阵)
            ├─ #44 (branch.remove)
            ├─ #45 (project.delete) ← 含 N3
            ├─ #47 (remove_file)
            ├─ #48 (可达性)
            ├─ #49 (SQLite compact) ← 含 C8b
            ├─ #50 (PostgreSQL)
            ├─ #51 (API 暴露) ← 含 C9
            └─ #52 (验收)
```

---

## 🚀 建议的后续行动

### 立即（Phase 1）
- [ ] 读 #41 的 completion criteria（7 个条件）
- [ ] 产品确认 D1/D3/D6/D7 决策点
- [ ] 标记 #42 assessment 中的决策为 confirmed

### 短期（Phase 2）
- [ ] 实现 N3（#45 作为主承载）
- [ ] 实现 C8b（#49 作为主承载）
- [ ] 实现 C9 GC 方法的 default 体

### 中期（Phase 3）
- [ ] #47 project.remove_file
- [ ] #50 PostgreSQL compaction
- [ ] #51 API 暴露（使用 C9）

### 晚期（Phase 4）
- [ ] #52 集成验收，验证所有 7 个完成条件

---

## 📁 文档对应

| #41 需求 | 你的文档 | 链接 |
|---------|---------|------|
| 设计协调 | LayerFS-GC-spec.md | ✅ 已覆盖 |
| C8b/N3/C9 诊断 | C8b-N3-C9-Resolution-Plan.md | ✅ 560 行详述 |
| Issue 映射 | GC-ISSUE-MAPPING.md | ✅ 已创建 |
| 快速入门 | README.md | ✅ 导航完备 |

**完整资源位置**：`/Users/reina/Project/gc-spec/`

