# Issue #511 Comment 解析

## 原文
```
### Closure after owner-requested review

Implementation is now owned by [planning #41 and its ten sub-issues]
(https://github.com/Ephemeral-AI-Lab/layerfs-project/issues/41). 
This issue remains the historical owner-policy reference. 

Follow the current scope: soft branch.remove/project.delete/project.remove_file, 
explicit store.compact, both SQLite and PostgreSQL, scoped mount/user exclusion, 
no pruning, no confirm/force/shutdown/dry-run options. 

Older claimant plans mentioning pruning or dry-run are superseded. 
Closing this proposal does not mean GC is implemented.

Review baseline: LayerFS `layerfs_v2_0_0` at `d4304741356e0a93e8dc8bee83a94e02054fd28a`. 
This closure follows the owner-requested issue consolidation; 
no new runtime test was run during this review.
```

---

## 中文解读

### 核心意思
这是一条 **closure comment**（结束评论），宣布 #511（产品政策提案）的审查完成，实现工作转交给 #41。

### 关键内容

#### 1️⃣ 权利转移（Ownership Transfer）
- ❌ #511 不再是实现的主要追踪点
- ✅ #41 与其 10 个子 issue 成为实现的主要追踪点
- **#511 的角色**：保留为「历史政策参考」（historical owner-policy reference）

#### 2️⃣ 确定的范围（Finalized Scope）
✅ **包括**：
- `branch.remove` — 分支删除（软删除）
- `project.delete` — 项目删除（软删除）
- `project.remove_file` — 项目文件删除
- `store.compact` — 显式 compaction
- **两个后端**：SQLite 和 PostgreSQL
- **隔离策略**：scoped mount/user exclusion

❌ **不包括**：
- `pruning` — 自动后台回收
- `confirm` — 确认选项
- `force` — 强制选项
- `shutdown` — 自动 shutdown
- `dry-run` — 干运行选项

#### 3️⃣ 过时内容（Superseded）
- 旧的「包含 pruning 或 dry-run」的计划已作废
- 遵循这份已确定的范围，不再修改

#### 4️⃣ 审查基准（Review Baseline）
- **代码版本**：LayerFS `layerfs_v2_0_0` @ `d4304741356e0a93e8dc8bee83a94e02054fd28a`
- **审查方式**：owner-requested issue consolidation（产品主持人要求的 issue 整合）
- **没有**运行新的 runtime test

#### 5️⃣ 重要声明
> "Closing this proposal does not mean GC is implemented."
> （结束这个提案不意味着 GC 已实现）

即：#511 关闭 ≠ GC 功能完成，只是政策方向已确定。

---

## 对当前工作的影响

### 🎯 #511 现在是什么
- ✅ **产品政策的权威参考**（authoritative policy reference）
- ✅ **需求定义和收益说明**（what to build & why）
- ❌ **不再是实现追踪点**（not for implementation tracking）

### 📍 #42 现在的角色
- ✅ **设计评估和验收点**（design assessment & acceptance criteria）
- ✅ **#41 下的关键里程碑**（key milestone under #41）

### 🔧 #41 的角色
- ✅ **实现的主要追踪点**（implementation tracking）
- ✅ **10 个子 issue 的集合**（#43–#52）

---

## 时间线

```
2026-11-05 17:57 UTC
    ↓
[yifanxuaaa 发布 closure comment]
    ↓
#511 (政策提案) → CLOSED ✓
    ↓
政策转移到 #41 (实现规划) + #42 (设计评估)
    ↓
你现在正在: #42 的三个关键问题（C8b, N3, C9）
```

---

## 关键决策已冻结

从这条评论，我们知道以下**已经确定**，不再改变：

| 项 | 状态 | 是否改变 |
|----|------|--------|
| 软删除 (branch/project) | ✅ 确定 | ❌ 不改 |
| Explicit compact | ✅ 确定 | ❌ 不改 |
| 两个后端都支持 | ✅ 确定 | ❌ 不改 |
| Mount/user 隔离 | ✅ 确定 | ❌ 不改 |
| 无自动 pruning | ✅ 确定 | ❌ 不改 |
| 无 dry-run | ✅ 确定 | ❌ 不改 |

---

## 与 C8b/N3/C9 的关系

这条评论说明：
- C8b (SQLite 写者围栏) ✅ 在范围内（属于 explicit compact 和隔离策略）
- N3 (逻辑删除表示) ✅ 在范围内（属于 soft delete 的实现）
- C9 (HistoryCatalog 约束) ✅ 在范围内（属于两个后端的统一 API）

三个问题都是 #511 确定范围内的必需实现细节。

