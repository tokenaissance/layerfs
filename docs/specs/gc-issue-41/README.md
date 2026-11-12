# LayerFS GC #42 - 三问题解决方案文档

## 📌 快速导航

本目录包含针对 LayerFS GC 设计三个关键问题的完整解决方案分析。

### 问题清单

| 问题 | 文档 | 链接 | 优先级 |
|------|------|------|--------|
| **C8b** - SQLite 写者围栏 | C8b-N3-C9-Resolution-Plan.md § C8b | [Section](#c8b) | P0 风险 |
| **N3** - 逻辑删除表示 | C8b-N3-C9-Resolution-Plan.md § N3 | [Section](#n3) | Schema 变更 |
| **C9** - HistoryCatalog 约束 | C8b-N3-C9-Resolution-Plan.md § C9 | [Section](#c9) | API 合约 |

---

## 📂 文件描述

### 核心文档

#### 1. `LayerFS-GC-spec.md`（26 KB）
**覆盖旧的 `layerfs-specs/gc-spec.md`**

- **来源**：新提交的完整 GC 设计规范
- **内容**：5 章完整规格（frozen contract）
  - § 1-2：现有设施和要求
  - § 3：实现指标（retention / compact / removal）
  - § 4：数据模型（reachability closure）
  - § 5：契约约束（C8b, C9, N1-N4）
  - § 6-7：backend specifics + partial outcomes

---

#### 2. `C8b-N3-C9-Resolution-Plan.md`（17 KB，560 行）
**详细实现路径指南**

三个问题的完整解决方案分析：

**C8b - SQLite 写者围栏** (Section 1)
- 问题表述：pre-swap 写者的 silent data loss
- 规格决策：incarnation protocol (代际)
- 实现路径：5 步，含代码示例
- 关键位置：store/identity.rs, writer_admission.rs 等

**N3 - 逻辑删除表示** (Section 2)
- 问题表述：无可见性列，软删除做不了
- 规格决策：schema v3.5 → v3.6（deleted_ms, removed_ms）
- 实现路径：6 步，含 SQL DDL 脚本
- 关键位置：sql/sqlite, sql/postgresql, migrate.rs 等

**C9 - HistoryCatalog 约束** (Section 3)
- 问题表述：8 impl × 32 methods = 维护爆炸
- 规格决策：default `Unsupported` pattern
- 实现路径：5 步，含 Rust 代码示例
- 关键位置：contract/catalog.rs, backend/sqlite/catalog.rs 等

**集成验证清单** (Section 末尾)
- 每个问题的关键验证点和预期结果

---

#### 3. `RESOLUTION-SUMMARY.md`（6.5 KB）
**高阶总结与决策跟踪**

适合快速了解和会议讨论：
- 📋 问题总述表（类别、影响、状态）
- 🔧 各问题解决方案简明说明
- 📈 Excalidraw 架构图与时序图三个链接
- ✅ 集成验证清单（表格）
- 🎯 开放决策点（D1/D3/D6/D7）
- 🚀 后续行动（产品确认 + 开发顺序）

---

## 🎨 Excalidraw 架构图

三个可视化设计（在 Excalidraw 集合 "layerfs" 中）：

### 1. C8b - Writer Fence Sequence Diagram
**https://app.excalidraw.com/s/9Zq6XgRe98z/5fb5lT5yDKY**

时序图展示：
- Writer 进程取得 write handle（记录当前 generation）
- Compact 并发运行（进行 incarnation 递增）
- Pre-swap 写者后续操作：admission check 发现代际不匹配 → Conflict
- 验证 silent data loss 被正确阻止

**关键概念**：代际校验的两道关（install 前 + 每个 write 打开时）

---

### 2. N3 - Schema Migration Flow
**https://app.excalidraw.com/s/9Zq6XgRe98z/1dZkWEGOgA7**

流程图展示：
- 左：v3.5 硬删除模式（DELETE 行，全局唯一索引）
- 中：4 步迁移（ADD COLUMNS → DROP INDEXES → CREATE PARTIAL INDEXES → UPDATE META）
- 右：v3.6 软删除模式（UPDATE SET deleted_ms，部分唯一索引允许 tombstone）

**关键概念**：部分唯一索引的威力（name 重用、branch history 保护）

---

### 3. C9 - HistoryCatalog Architecture
**https://app.excalidraw.com/s/9Zq6XgRe98z/8ZPm9UyP100**

组件图展示：
- HistoryCatalog trait：32 methods（22 required + 10 optional）
- 8 implementations（2 real: SQLite/PostgreSQL, 6 test doubles）
- 4 new GC methods（each with Unsupported default）
- HistoryError constraint（6 frozen variants，禁止新增）

**关键概念**：default pattern 降低维护成本（test double 零改动）

---

## 🎯 快速查询

### 我想快速理解三个问题
→ 读 `RESOLUTION-SUMMARY.md` §问题总述表 (5 min)

### 我要实现 C8b
→ 读 `C8b-N3-C9-Resolution-Plan.md` § C8b (15 min) + 看时序图 (5 min)

### 我要做 N3 schema 迁移
→ 读 `C8b-N3-C9-Resolution-Plan.md` § N3 (20 min) + 看流程图 (5 min)

### 我要遵循 C9 约束
→ 读 `C8b-N3-C9-Resolution-Plan.md` § C9 (15 min) + 看架构图 (5 min)

### 我要做决策会议
→ 使用 `RESOLUTION-SUMMARY.md` 的决策点表格 (§ 🎯 Decision Points)

### 我要做完整的代码审查
→ 按这个顺序：
1. `LayerFS-GC-spec.md` 的 frozen contract § 5
2. `C8b-N3-C9-Resolution-Plan.md` 三个 section
3. 三个 Excalidraw 图的细节验证

---

## 📋 关键指标

| 度量 | 数值 |
|------|------|
| 规范文档行数 | 318 (LayerFS-GC-spec.md) |
| 解决方案详述行数 | 560 (C8b-N3-C9-Resolution-Plan.md) |
| 概要总结行数 | ~200 (RESOLUTION-SUMMARY.md) |
| 架构图数量 | 3 |
| 代码示例个数 | 15+ |
| 决策点数 | 4 (D1, D3, D6, D7) |

---

## 🚀 后续行动（优先级）

### Phase 1: 产品确认 (Week 1)
- [ ] 确认 D1：BranchId generation 编码方式
- [ ] 确认 D3：PostgreSQL 围栏实现选择
- [ ] 确认 D6：时间戳精度
- [ ] 确认 D7：源分支删除权限

### Phase 2: 基础设施 (Week 2-3)
- [ ] N3 schema 迁移实现
- [ ] migrate.rs + 迁移测试

### Phase 3: 风险缓解 (Week 3-4)
- [ ] C8b writer fence 实现
- [ ] 并发 compact+write 测试

### Phase 4: 功能完整 (Week 4-5)
- [ ] C9 GC 方法实现
- [ ] 集成测试

---

## 👥 相关角色

| 角色 | 责任 | 关键文档 |
|------|------|---------|
| 产品 | 决策点确认 (D1/D3/D6/D7) | RESOLUTION-SUMMARY.md § 🎯 |
| 设计 | C8b incarnation protocol 审查 | C8b-N3-C9-Resolution-Plan.md § C8b |
| 基础架构 | N3 schema 迁移规划 | C8b-N3-C9-Resolution-Plan.md § N3 |
| 后端工程 | C8b + N3 实现 | 两者 full section |
| QA | 测试用例设计 | 集成验证清单 |

---

## 📞 文档维护

- **作成**：2024-11-12
- **基准**：LayerFS v2.0.0 @ bdeb9e91f
- **覆盖**：#42 (GC Design Assessment) + #511 (Product Policy)
- **冻结**：契约内容已确认，实现细节仍可调整

**如需更新**：修改本 README，同时保持三份核心文档的一致性。

