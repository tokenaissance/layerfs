# 重要澄清：C8b/N3/C9 的来源

## ⚠️ 关键区别

用户是对的 — **GitHub issue #42 线上没有 C8b、N3、C9**

### C8b/N3/C9 来自哪里？

**不是 GitHub issue 中的结构**，而是：
- 📄 **本地新提交的规范文档** 中的标记
- `LayerFS-GC-spec.md` — § 5「契约」中的约束标记（C8b, C9）
- `LayerFS-GC-spec.md` — § 1.2「待 #42 拍板」中的新增项（N3）

### 文件关系

```
GitHub Issue #42 (线上)
  │
  └─ 任务描述：Assess garbage-collection design and finalize contracts
       ↓
这个任务的产出物之一是：

本地 /Users/reina/Project/gc-spec/
  ├─ LayerFS-GC-spec.md (新规范，规范中包含 C8b、N3、C9 的标记)
  ├─ gc-42-assessment.md (现有评估文件)
  └─ C8b-N3-C9-Resolution-Plan.md (我为这三个问题制作的诊断文档)
```

---

## 为什么 GitHub #42 中看不到它们？

### 原因

#42 是一个 **设计评估任务**（issue），任务的具体内容要求是：

> "Assess garbage-collection design and finalize contracts for SQLite and PostgreSQL"

### #42 中有什么

线上 GitHub issue #42 包含：
- ✅ 任务描述（assess & finalize contracts）
- ✅ 六个验收点（acceptance points）
- ✅ 相关文件链接

### #42 中**没有**的是什么

- ❌ **具体的"C8b、N3、C9"标记** — 这是新规范中首次引入的标记
- ❌ **实现细节** — #42 只要求评估设计，不包含实现方案

---

## 流程梳理

```
Timeline:

2026-11-05
  ↓
  产品发布 #511 (policy) → 关闭
    ↓
  创建 #41 (implementation planning) → OPEN
    ├─ 10 个子 issue，其中 #42
    │
    └─ #42 (Assess design) → 任务启动
        │
        ├─ 输入：
        │   ├─ 旧 spec (layerfs-specs/gc-spec.md)
        │   ├─ 现有代码 (layerfs_v2_0_0)
        │   ├─ #511 policy (已冻结)
        │   └─ github issues #43-#52 (功能需求)
        │
        ├─ 处理过程：
        │   ├─ 调查现有设施 (assessment)
        │   ├─ 识别设计差距
        │   ├─ 制定新合约 (frozen contract)
        │   └─ 提出三个关键问题 ← C8b, N3, C9 在这
        │
        └─ 输出（本地文档）：
            ├─ LayerFS-GC-spec.md (新规范)
            │   ├─ § 5: C8b, C9 作为约束标记
            │   └─ § 1.2: N3 作为新增设计项
            │
            └─ 我的诊断文档：
                └─ C8b-N3-C9-Resolution-Plan.md
```

---

## 正确的理解

### ❌ 错误理解
"C8b、N3、C9 是 #42 GitHub issue 中的结构"

### ✅ 正确理解
"C8b、N3、C9 是在执行 #42 任务过程中，从新规范文档中**识别出来的三个关键设计问题**"

换句话说：
- #42 要求「评估设计并确定合约」
- 评估的结果就是「识别出三个需要解决的问题：C8b、N3、C9」
- 这三个问题是在 **LayerFS-GC-spec.md** 中以标记形式出现
- 但 **GitHub issue #42 本身没有这些标记**（因为 #42 只是任务描述，不是文档）

---

## 你应该参考的资源

### 线上
- ✅ GitHub issue #41 — 项目总体规划
- ✅ GitHub issue #42 — 任务描述
- ✅ GitHub issue #511 — 产品政策

### 本地
- ✅ `LayerFS-GC-spec.md` — 规范文档（包含 C8b/N3/C9 标记）
- ✅ `C8b-N3-C9-Resolution-Plan.md` — 我的诊断方案
- ✅ 这些都在 `/Users/reina/Project/gc-spec/`

---

## 为什么我把它们叫「核心结构」

我说「核心结构是指本地 spec 里说明的」是对的。

更准确的表述：

> **C8b、N3、C9 是在新 GC spec 规范文档（LayerFS-GC-spec.md）中识别出的三个关键设计问题，它们是执行 #42 评估任务的成果。**

不是 GitHub issue 中预先定义的结构，而是通过评估发现的。

