# Spec 任务完整映射到 GitHub Issue

## 📋 概览

```
LayerFS-GC-spec.md (本地规范文档)
  │
  ├─ § 1-2: 决策摘要 + 现有设施
  │   └─ 映射到 #42 (设计评估)
  │
  ├─ § 3-4: 不变式 + 新增项
  │   └─ 映射到 #43-#52 (各子任务)
  │
  ├─ § 5: 契约 (C1-C10)
  │   ├─ C1 → #48 (可达性)
  │   ├─ C2-C3 → #48 (回收判定)
  │   ├─ C4-C7 → #43-#49 (各项)
  │   ├─ C8/C8b → #49 (SQLite fence)
  │   ├─ C9 → #42/#51 (HistoryCatalog)
  │   └─ C10 → #43 (准入矩阵)
  │
  ├─ § 6-7: Mark + Sweep
  │   ├─ Mark → #48 (reachability)
  │   ├─ SQLite Sweep → #49
  │   ├─ PostgreSQL Sweep → #50
  │   └─ 恢复 → #52 (验收)
  │
  ├─ § 8-9: 运营面 + 验收
  │   ├─ 运营 → #51 (API暴露)
  │   └─ 验收 → #52 (集成测试)
  │
  └─ § 10-12: 对应 + 非目标
      └─ 映射到 #41-#52
```

---

## 📊 详细映射表

### 第 1 部分：决策与设计（#42）

| Spec 章节 | 内容 | Issue | 截止条件 |
|---------|------|-------|---------|
| § 1.1 S1-S11 | 11 个已定决策 | #42 | 文档冻结 ✅ |
| § 1.2 Q1-Q6 | 6 个待拍板问题 | #42 | 产品签字 (D1/D3/D6/D7) |
| § 1.3 R1-R3 | 与旧 spec 的 reconcile | #42 | 设计协调 |
| **C9** | HistoryCatalog 约束 | #42 | 确认 8 impl 模式 ✅ |

---

### 第 2 部分：基础设施（#43, #48）

| Spec 章节 | 内容 | Issue | 工作项 |
|---------|------|-------|--------|
| **C1** | 根集合与代际 | #48 | `rootGeneration` 单调性 |
| **C1** | 代际 bump 时机 | #48 | 7 个操作的 bump 点 |
| **C2** | 可回收判定 | #48 | `receipt` 生成逻辑 |
| **C2** | 闭包边界 | #48 | `decode_references` 验证 |
| **C3** | 死亡判定绑定 | #48 | `(ObjectId, generation)` 检查 |
| **C8** | 身份与围栏 | #48 | `(catalog_id, incarnation)` 校验 |
| **C10** | 准入矩阵 | #43 | 排他规则 + `MountsActive` 检查 |
| 7.1 时序 | transfer 复用 | #43/#48 | 4 个阶段（+rewrite）|

---

### 第 3 部分：核心功能实现

#### #44 - branch.remove

| Spec 章节 | 内容 | 工作项 |
|---------|------|--------|
| **C1** | 代际 bump | branch.remove → rootGeneration += 1 |
| **C6** | 名字复用 | removed_ms 列 + 部分索引 |
| **C10** | 准入排他 | 仅该 Branch 不允许新 mount |
| § 8 | API 签名 | `branch.remove(name)` 无选项 |

**对应 spec 验收点**：名字可重用 + 代际一致

---

#### #45 - project.delete（✅ **包含 N3**）

| Spec 章节 | 内容 | 工作项 |
|---------|------|--------|
| **N3** | 逻辑删除表示 | 添加 `deleted_ms` 列 + 部分索引 |
| **C1** | 代际 bump | project.delete → rootGeneration += 1 |
| **C6** | 名字复用 | deleted_ms NULL 检查 |
| **C10** | 准入排他 | 整 project 所有 Branch 排他 |
| § 8 | Store 保留 | Delete 后 Store 仍可寻址 |
| § 8 | API 签名 | `project.delete(name)` 无选项 |

**对应 spec 验收点**：软删 + Store 不删 + name 重用 ✅

---

#### #47 - project.remove_file

| Spec 章节 | 内容 | 工作项 |
|---------|------|--------|
| § 8 | 文件隐藏表示 | 设计 remove_file 的表示 |
| § 8 | 历史访问合约 | "absent" vs `NoSuchFile` |
| § 9.3 | 验收 | receipt 中的回收字节 |
| **C10** | 准入排他 | 整 project 所有 mount 排他 |

**对应 spec 验收点**：ID 不变 + 历史可读 + 回收计数正确

---

#### #48 - Reachability Closure（基础）

| Spec 章节 | 内容 | 工作项 |
|---------|------|--------|
| § 6 冻结根 | Retained roots | Layer/Commit/provenance 的集合 |
| § 6 闭包 | 内容闭包 | `decode_references` (chain, inode, file) |
| § 6 闭包 | 物理依赖 | delta `stored_base` + inode_value ordinals |
| § 6 代际 | `G_min` 保守 | 多根取最低代际 |
| § 6 验证 | 缺依赖中止 | 三类异常，缺依赖 MUST ABORT |

**对应 spec 验收点**：闭包完整性 + 异常处理

---

#### #49 - SQLite Compact（✅ **包含 C8b**）

| Spec 章节 | 内容 | 工作项 |
|---------|------|--------|
| **C8b** | 写者围栏 | incarnation protocol (代际递增) |
| **C8b** | 准入检查 | writer_admission_check(gen) |
| **C8b** | 安全 | pre-swap 写者 Conflict 失败 |
| 7.2 本机限制 | native 检查 | 非本机拒 `Unsupported` |
| 7.2 Mark | reachability walk | 5 个步骤精确 |
| 7.2 Rewrite | 新容器 | 临时 Store 文件 |
| 7.2 Verify | 签名 + roots | 每个根验证闭包 |
| 7.2 Install | 原子 rename | install_check(inode) + rename |
| 7.2 Retire | 删除旧文件 | 原子性保证 |
| § 9.1-9.3 | 崩溃注入 | 每阶段 kill -9 |

**对应 spec 验收点**：Silent loss 不发生 + 恢复正确 ✅

---

#### #50 - PostgreSQL GC

| Spec 章节 | 内容 | 工作项 |
|---------|------|--------|
| **D3** | 围栏选择 | advisory lock vs FOR UPDATE vs schema lock |
| 7.3 remote | 远程 Server 支持 | 不含 libpq 限制 |
| 7.3 pack 不变 | 触发器 | `pack_immutable()` + 新 pack 创建 |
| 7.3 物理回收 | VACUUM FULL / TRUNCATE | 验证实际物理回收 |
| § 9.1-9.3 | 崩溃注入 + 回收验证 | remote PG 同样覆盖 |

**对应 spec 验收点**：远程支持 + 物理回收验证

---

### 第 4 部分：API 暴露与文档（#51）

| Spec 章节 | 内容 | 工作项 |
|---------|------|--------|
| **C9** | HistoryCatalog 方法 | 4 个 GC 方法 + Unsupported default |
| § 8 | API 签名 | 4 个操作的 SDK/CLI 接口 |
| § 8 | 文档 | `store.remove` vs `project.delete` 对比 |
| § 8 | 无选项 | 禁止 confirm/force/dryRun/stopSandboxes |

**对应 spec 验收点**：公开合约清晰 + 选项约束

---

### 第 5 部分：验收测试（#52）

| Spec 章节 | 内容 | 工作项 |
|---------|------|--------|
| § 9.1 | 崩溃注入 | 每后端、每阶段 kill -9 |
| § 9.2 | 无误删性质 | 跨 branch 共享 content 不丢 |
| § 9.3 | 契约测试 | receipt 与实际物理回收对应 |
| § 9.3 | remove_file | 回收字节 vs receipt 一致性 |

**完成条件**：7 个完成条件全部绿 ✅

---

## 🎯 三个问题的 Issue 分配

| 问题 | 主 Issue | 次影响 | Spec 出现位置 | 实现工作 |
|------|---------|--------|-------------|---------|
| **C8b** | #49 | #43, #51 | § 5 C8b, § 7.2 | incarnation protocol |
| **N3** | #45 | #44 | § 1.2 N3, § 5 C6 | schema 迁移 + 可见性过滤 |
| **C9** | #42 | #51 | § 5 C9, § 8 | HistoryCatalog 4 方法 |

---

## ✅ Issue 完成清单

### #42 设计评估
- [ ] **C9**: HistoryCatalog 约束确认（8 impl 零改动）
- [ ] **Q1-Q6**: 6 个问题拍板（Q3=本期不做, 其他直接采纳）
- [ ] **S1-S11**: 11 个已定决策的文档冻结
- [ ] **R1-R3**: 与旧 spec reconcile

### #43 准入矩阵
- [ ] **C10**: 4 个操作的排他矩阵
- [ ] **C8**: `(catalog_id, incarnation)` 校验
- [ ] `MountsActive` 返回码实现

### #44 branch.remove
- [ ] **C1**: 代际 bump
- [ ] **C6**: removed_ms 列（part of N3）
- [ ] **C10**: 分支级排他检查

### #45 project.delete
- [ ] **N3**: Schema 迁移（v3.5 → v3.6）
- [ ] **C1**: 代际 bump
- [ ] **C6**: deleted_ms 列 + 部分索引
- [ ] **C10**: 项目级排他检查
- [ ] **§ 8**: Store 保留不删

### #47 project.remove_file
- [ ] **§ 8**: 文件隐藏表示设计
- [ ] **C10**: 项目级排他检查

### #48 可达性
- [ ] **C1**: rootGeneration 单调性
- [ ] **C2**: receipt 生成
- [ ] **§ 6**: 3 类异常处理（缺依赖 ABORT）
- [ ] `decode_references` 验证

### #49 SQLite compact
- [ ] **C8b**: incarnation protocol（两道检查）
- [ ] **C8b**: writer_admission_check
- [ ] **7.2**: 5 个 Mark 步骤
- [ ] **7.2**: Rewrite + Verify + Install + Retire
- [ ] **§ 9.1**: 崩溃注入测试

### #50 PostgreSQL
- [ ] **D3**: 围栏选择（advisory vs FOR UPDATE）
- [ ] **7.3**: 远程 Server 支持
- [ ] **7.3**: 物理回收验证（VACUUM FULL）

### #51 API 暴露
- [ ] **C9**: HistoryCatalog 方法实现
- [ ] **§ 8**: SDK/CLI/MCP 接口
- [ ] **§ 8**: 文档（store.remove vs project.delete）

### #52 验收
- [ ] **§ 9.1**: 各阶段崩溃注入（SQLite + PG）
- [ ] **§ 9.2**: 无误删性质（共享 content 保护）
- [ ] **§ 9.3**: receipt 与物理回收一致

---

## 📝 PR 关联方式

当开发 #49 (SQLite compact) 时，PR 描述应该：

```markdown
# PR: Implement SQLite Store.compact with writer fence

Closes #49
Related: #42 (C8b), #43 (C8/C10), #52 (验收)

## Changes
- [ ] store/identity.rs: StoreGeneration 结构
- [ ] backend/sqlite/writer_admission.rs: admission check
- [ ] backend/sqlite/session/write_path.rs: 集成 check
- [ ] persistence/history/catalog.rs: incarnation bump

## Spec Reference
- LayerFS-GC-spec.md § 5 C8b
- LayerFS-GC-spec.md § 7.2 (SQLite Sweep)

## Verification
- [x] Unit tests: incarnation mismatch → Conflict
- [x] Integration: concurrent compact + write
- [x] Crash injection: each phase kill -9
```

---

## 🔍 Issue 间的依赖关系

```
#42 (设计)
  ├─ 前置: 无
  └─ 后置: #43, #44, #45, #47, #48, #49, #50

#43 (准入矩阵)
  ├─ 前置: #42 决策
  └─ 后置: #44, #45, #47, #49, #50

#48 (可达性)
  ├─ 前置: #42, #43
  └─ 后置: #49, #50, #52

#44, #45, #47 (删除操作)
  ├─ 前置: #42, #43, #48
  └─ 后置: #52

#49 (SQLite)
  ├─ 前置: #42, #43, #48
  └─ 后置: #52

#50 (PostgreSQL)
  ├─ 前置: #42, #43, #48
  └─ 后置: #52

#51 (API 暴露)
  ├─ 前置: #44, #45, #47, #49, #50
  └─ 后置: #52

#52 (验收)
  ├─ 前置: 所有上游
  └─ 后置: Release
```

---

## 🎯 建议的实现顺序

**优先级顺序**：
1. **#42**: 产品确认决策点 (D1/D3/D6/D7) → 解锁后续
2. **#43**: 准入矩阵（影响所有其他 issue）
3. **#48**: 可达性闭包（compaction 的基础）
4. **#44/#45/#47**: 三个删除操作（可并行）
5. **#49/#50**: Compact（两个后端可并行）
6. **#51**: API 暴露（基于 #44-#50）
7. **#52**: 验收测试

**时间估算**：
- Phase 1: #42 + #43 + #48 (2 weeks)
- Phase 2: #44 + #45 + #47 + #49 (3 weeks)
- Phase 3: #50 + #51 (2 weeks)
- Phase 4: #52 (1 week)

**总计**: 8 weeks

