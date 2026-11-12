# LayerFS GC 规格（单文件版）

> **状态：** 候选规格，可整体并入 #42。**本文是唯一权威版本**（工作区只保留本文件）。
> **范围：** #41 的机制层——回收判定的正确性、sweep 的可恢复性、围栏、报告口径、验收形态。
> **不在范围：** #41 已定的策略（admission 矩阵、logical/physical 分离、no-retry）。冲突时以 #41 owner policy 为准。
> **BrewFS 参照：** `github.com/brewfs/brewfs`，pin 2026-11-11 `#444`。**引用其数值一律取代码默认值**（`src/meta/config.rs`、`src/chunk/compact/gc.rs`）；它的 `doc/architecture/compaction-gc.md` 已存在漂移，不可作为参数来源。

---

## 1. 决策摘要

### 1.1 本规格已定（设计结论，不再开放）

| # | 决定 | 理由 / 依据 | 落点 |
|---|---|---|---|
| S1 | 可达性粒度 = **Store**（一个 Store 内所有 LayerStack） | #41 matrix 明写 "Selected Store, all projects/Branches/historical mounts"；一个 Store 可含多个 project | §5, C1 |
| S2 | 独占 = **复用 Store 锁 + lease + op 记录** | `store push/pull/remove` 已用同一套；lease 按 pid+内核start+boot 判活 | C8, §7.1 |
| S3 | 意图 = **`Stage` 副本 + op 记录**，不建 sidecar | `sqlite/transfer` 已有 `Stage/Verify{bytes,sha256,heads}/Install/Retire` 与 `resolve` | C7, §7.1 |
| S4 | **不设对象年龄**，删除只看闭包与 pinned | `object_location`/`pack` 无时间列；compact 是独占窗口，闭包现算 | C2, C4 |
| S5 | 候选 = **`object_location` 行 + `content_signature` 附属行**；`pack` 永不为候选 | `pack` 两端都有不可变触发器 | C2, §7.2 |
| S6 | 非 **native** 的 SQLite Store **拒绝** compact | `StoreRef::Sqlite{machine}`；#49 明确远程 SQLite 不在范围 | §7.2 |
| S7 | 上报三口径 + 峰值临时空间 + 残留物；估算必须标 `estimate`；带 cap 必须报 cap | #41 的三分口径 + `operator/files.rs` 的 "never silently reports a total" | C5 |
| S8 | 读者围栏 = **会话级 `(catalog_id, incarnation)` 校验 → `StaleStore`** | incarnation 只在 open 校验；WAL 下无锁可挡读者 | C8 |
| S9 | install 二元，`heads` 前后必须一致 | transfer 的 `Verify{heads}`；I1 | I1, I3 |
| S10 | 逻辑删除不改写历史、不改 ID | CommitId 内容派生；#41 的 "immutable IDs must not silently resolve" | I5 |
| S11 | compact 期间的读可用性 = **默认独占**（读不可用）；若要求「读可用」SLO（p99 ≤ 1.2× baseline），则 PG 走 A'（指针 + 版本化 schema） | 决定 R1 选 E 还是 A'；与 C10 的独占 admission 一致 | §1.3 R1, §7.3 |

### 1.2 仍待 #42 拍板（附建议 + 成本 + 选错代价）

| # | 问题 | 建议（推荐选项） | 工作量/成本 | 选错的代价 |
|---|---|---|---|---|
| Q1 | 名字复用：禁复用（tombstone）还是派生加 incarnation | **A：禁复用** + 终态 tombstone + `NameRetired`，零迁移 | 小：一个终态标记 + create 时检查；不加 incarnation 列 | 复用旧名会与旧历史共用 `BranchId`（`blake3(stack‖name)`），旧 Commit 的 Branch 归属会错 |
| Q2 | `remove_file` 到底能回收多少 | 先用 `fs.get_storage` + `list_overwritten` 实测；若恒为 0，文档写明它是**可见性操作**（不省空间） | 小：一条实测脚本 + 文档；不改机制 | 用户按「删了省空间」规划容量，结果不省 |
| Q3 | 引入在线回收时年龄门槛怎么定 | 本规格不做；届时先补时间戳列，再测最长 Commit / 最长 in-flight 句柄 | 中：加时间戳列 + 迁移 + 门槛契约 | 无时间戳就无法实现年龄门槛；硬做会误删 in-flight 写入 |
| Q4 | interrupted 副本的保留上限 | 不自动清；最多保留一份，超出要求人工 | 小：`doctor` 报告 + runbook | 残留累积占盘；自动清则违反 "no guessed cleanup" |
| Q5 | PG 换表时读者行为 | **已被 C8/R2 取代**：读者走 `(catalog_id, incarnation)` 会话校验 → `StaleStore`，重连后读新代；不版本化表名 | 小：session/事务入口校验（与 SQLite 共用） | 跨代际读（不崩溃但产错数据） |
| Q6 | `store.compact` 承诺「回收页」还是「重组数据」 | **拆两级**：`compact(name)` = 删引用 + `reclaim_space`（便宜，可能返回 0）；`compact(name, reorg)` = replacement（2× 空间） | 中：两个入口 + 两套报告口径 | 单级则小回收也付 2× 空间；只做页回收则文档过度承诺 |

> 拍板方式：Q1/Q2/Q4/Q5 建议直接采纳（成本小、风险可控）；Q3 明确本期不做；Q6 需要 owner 在「承诺层级」上签字，因为它决定文档措辞与容量规划。

### 1.3 与旧 `gc-spec.md` 的 reconcile 结论

| # | 旧设计 | 本规格 | 裁决 |
|---|---|---|---|
| R1 | PG: 两条 `ALTER SCHEMA RENAME` in one txn（旧设计） | **由 S11 决定**：独占窗口 → **E**（两条 `ALTER SCHEMA RENAME`，结尾仍是 `layerfs`，record 与 `{s}` 都有效）；读可用窗口 → **A'**（指针 + 版本化 schema，`self.schema` 在 open 时从指针解析）。不再采用「表名版本化」（A）——它需要第二条占位符，在独占窗口下没有收益 | **旧 R1 的理由作废**：`open.rs:37 schema_of` 接受调用传入的 schema，两条 rename 结束仍是 `layerfs`，所以「schema 名固定所以不能 rename」不成立。真正的决定因素是读可用性 SLO（S11），不是名字。 |
| R2 | 读者围栏 = 新增 `compact_intent` 行 | `catalog_incarnation += 1` + 每个 session/事务入口校验 `(catalog_id, incarnation)` → `StaleStore`；SQLite 额外 `(dev, ino)`；`lfq1` 跨代 → `StaleStore` | **采用本规格**。更完整，且复用现有 `history_meta`，不新增第二个代际字段。 |
| R3 | SQLite 写者围栏 = `Replaced` inode check（旧 spec 发现"代码里不存在"，P0 级新工作） | 本规格补为 C8b：install 前重读代际 + 写句柄在旧代际上必须失败（复用 `Conflict`） | **合并**：保留旧 spec 的 P0 分析，作为 C8b。 |
| R4 | rebuild into fresh container（自建新容器 → 真实 open 验证 → 原子 swap → retire） | 复用 transfer 的 `Stage/Verify/Install/Retire`，只插入 `rewrite` 阶段 | **采用本规格**。不重造机制，`transfer` 已存在。 |

**保留旧 spec 的额外发现：** HistoryCatalog 8 个 impl（见 C9）；`project.remove` 在 `remove.rs:62` 与 `family.rs:354` 两处删 project 目录（#45 要改成软删，且不得删 home dir，`resolve.rs::target` 需要 `ProjectRecord`）；`MountsActive` 目前唯一生产者是 `sandbox.close`，Branch 级 check 是新代码。


---

## 2. 现有设施（必须复用，不要重造）

| 设施 | 位置 | 用法 |
|---|---|---|
| Store 锁 | `record::lock`（`entity_lock`） | 独占窗口互斥 |
| Lease | `control/crates/layerfs-store/src/lease.rs` | `store/<name>/open/<pid>`；活持有者 → `InUse` |
| Op 记录 | `control/crates/layerfs-store/src/record.rs`、`control/crates/layerfs-home/src/op.rs` | `Standing = Running / Unresolved / Stale` |
| 复制—校验—安装 | `control/crates/layerfs-store/src/sqlite/transfer/{step,phases,resolve}.rs` | `StoreStep`：`Stat/Snapshot/Stage/Unstage/Read/Write/Verify/Install/Retire/Remove` |
| Store 身份与代际 | `history_meta(catalog_id, catalog_incarnation, binding_key, identity_format=3)` | `catalog_incarnation` 即代际 |
| 结构/内容审计 | `persistence/diagnostic/`（`sqlite_structure(path)`, `SqliteHandles::diagnose`）、`control/.../diagnostic.rs::sqlite(path, identity, …)` | install 前校验 |
| 页回收 | `backend/sqlite/lifecycle/reclamation.rs`（512 页/次，需 `auto_vacuum=2`） | 物理回收的廉价一半 |
| 计量 | `backend.store.project.get_storage`、`backend.store.fs.get_storage`、`backend.store.project.list_overwritten` | 三口径与 Q2 实测 |
| 有界遍历 | `core/crates/layerfs-content/src/filesystem/qualify/` | mark 的遍历骨架 |
| 运营面 | `store.*`（create/connect/list/status/push/pull/remove）、`backup.*`、`doctor`、`project.export` | 不新增并行设施 |

**反例：** `filesystem/references/` 是引用效果 reducer（bounded ordering、checked release、custody），**不是对象图 refcount**，不能当 GC 的计数器。

---

## 3. 不变式

| # | 不变式 | 保证 |
|---|---|---|
| I1 | 保留历史不减少：存活根的 heads 前后一致 | `Verify{heads}` + 闭包比对 |
| I2 | 已发布 `pack` 不可变、不被删 | 两端触发器（`pack_immutable_*` / `pack_immutable()`） |
| I3 | install 二元：旧 Store 原样，或新 Store 完整生效 | 单次 `Install`（rename）+ op 阶段 |
| I4 | 读者不跨代际 | 会话级代际校验 → `StaleStore` |
| I5 | 逻辑删除不改写历史、不改 ID | `remove_file` 只做可见性；CommitId 内容派生 |
| I6 | 无自动回收 | #41；本规格不定义周期任务 |

---

## 4. 净新增（只有四项）

| # | 内容 | 性质 |
|---|---|---|
| N1 | 可达性闭包 + install 前代际复检 | 唯一新机制 |
| N2 | transfer 的 `rewrite` 步骤 + `resolve` 登记 | 唯一新代码 |
| N3 | 逻辑删除的表示（`branch`/`layer_stack` 无可见性列） | schema 变更，属 #42 |
| N4 | 读者侧会话级代际校验 + `lfq1` 失配映射 `StaleStore` | 小改动，决定 #50 可行 |

---

## 5. 契约

以下 8 条在实现前冻结，变更需 owner 批准。

### C1 根集合与代际（S1）
- `rootGeneration` 单调递增；必须 bump：`branch.create/fork`、`commit`、`merge`、`branch.remove`、`project.delete`、`project.remove_file`、`store.compact` 的 install。
- 根集合覆盖选中 Store 的全部内容：每个存活 project 的 `main` 与已发布 Layer + 每个存活 Branch 的 head + 保留的历史 Commit 根 + 未完成 op 的 staged 副本 + pooled 依赖。
- 闭包必须在独占窗口内、从冻结代际起算；禁止跨操作缓存。
- install 前必须重读代际；不等即整轮放弃，禁止重试。

### C2 可回收判定（S4, S5）
```
collectable(o) := o ∉ closure(Roots@G) ∧ o ∉ pinned
```
- 不引入对象年龄：`object_location` 与 `pack` 都没有时间列（`sql/sqlite/metadata.sql`、`sql/sqlite/objects.sql`）；独占窗口已消除"在途写入被误判"。
- 候选是具体的行：`object_location` + `content_signature`；`pack` 永不为候选；`history_meta`/`store_policy`/`scope_allocator` 等库表也永不为候选。
- 空根集合合法（sole-project 软删后）：闭包为空、全部对象可回收，但 compact 必须仍产出可 open、可 `doctor` 的 Store。
- `pinned` 至少包含：op 与 staged 副本引用的对象、正在 install 的两份 Store、`Unresolved` op 名下的工件。
- 判定必须落成 receipt（G、Roots 指纹、闭包大小、collectable 数、三口径）。

### C3 死亡判定绑 `(ObjectId, generation)`
逐对象/逐行删除时（PostgreSQL、未来的在线 GC），删除意图必须绑 `(ObjectId, G)`；ABA（删后又写入同字节）不得套用旧意图。SQLite 整文件替换由 C1 复检覆盖。

### C4 不设对象年龄（S4）
- 禁止把对象年龄作为删除条件。
- 唯一单调次序是 `pack_id` 与 `commit.created_ms`，只能用于审计/对账，不得作为删除判据。
- 旧副本的保留由 `Retire` + record 权威负责，与年龄无关。
- 若未来引入在线/并发回收，必须先补时间戳列并把年龄门槛重新定义为契约（Q3）。

### C5 三个字节口径（S7）
| 口径 | SQLite | PostgreSQL |
|---|---|---|
| `logical_discarded` | 不可达对象/行按内容长度求和 | 按行 payload 求和 |
| `backend_reusable` | `freelist_count × page_size` | `n_dead_tup` 估算 + 可复用页 |
| `physical_shrink` | `page_count × page_size` 与旧文件之差；`reclaimed_pages` 单列 | `pg_relation_size` / `pg_total_relation_size` 差 |

- 现成来源：`commit` 行自带 `logical`/`new_canonical`/`new_stored`/`new_metadata`/`created_ms`。
- 必须一并上报：峰值临时空间、耗时、残留物（可枚举）。
- 估算值标 `estimate: true`；带 cap 的诊断必须同时报 cap。

### C6 名字复用与终态（Q1）
- `BranchId::named = blake3(stack ‖ name)`，且注释依赖"名字永不复用"（`core/crates/layerfs-history/src/contract/identity.rs:266`）；`branch.remove` 落地后该前提失效。
- 推荐 A：禁复用 + 终态 tombstone，同名 create 返回 `NameRetired`；零迁移。备选 B：incarnation 参与派生，需迁移。
- `branch`/`layer_stack`/`layer` 当前无可见性列（`persistence/sql/sqlite/history.sql`）；加列意味着每条 history 查询都要带该维度，加表则不用。#42 必须列出"哪些查询必须过滤"。
- shared / exclusive project tombstone 的分型由 #42 决定；本规格只要求"终态 + 代际可判定"。

### C7 意图 = `Stage` 副本 + op 记录（S3）
- 禁止新增 sidecar 意图文件。
- op 必须指名目标工件（staged 路径、代际）；失败 detail 至少带 `phase`、`authority`、`artifact`。
- 新阶段（`rewrite`）必须登记进 `transfer/resolve.rs` 的"该阶段不持有任何东西"清单，否则会留永久 `Unresolved`。
- 旧副本不得靠时间窗删除，由 `Retire` + record 权威决定。

### C8 身份、代际与读者围栏（S2, S8）
- 不新增 `store_uuid`：复用 `history_meta`，open 时 `validate` 校验。
- install 时 `catalog_incarnation += 1`；禁止第二个 generation 字段。
- 必须：每个 session/事务入口校验 `(catalog_id, incarnation)`，不符 → `StaleStore`（不重试、不自动重连）。
- SQLite 必须额外校验文件身份 `(dev, ino)`：Store 侧没有 `locking_mode=EXCLUSIVE`，同一路径可指向新 inode 而旧 fd 仍合法。
- `lfq1` 续页令牌已绑 incarnation，跨代失效；必须映射为 `StaleStore`，不得沿用 `invalid("… immutable pin …")`。
- admission 复用 Store 锁 + lease + op；新增的只有读者这一半。

### C8b SQLite 写者围栏（pre-swap writer）
- 仅靠 `(dev, ino)` 的 install 校验不够：rename 之后，pre-swap 写者手里的旧 fd 仍能写进被 retire 的 inode，而新 Store 看不到——静默丢数据。
- 因此 SQLite 必须有一个写者围栏：install 前重读代际，且任何在旧代际上取得的写句柄在 install 后必须失败（复用 `Conflict`，不新增拒绝码）。没有这个不变式，`store.compact` 只能在没有并发写者时运行，等于把互斥责任推给调用方。
- 该围栏是**新代码**（v2.0.0 里没有 `Replaced` 之类的证据），属于 #49 的 P0 级实现项。

### C9 HistoryCatalog 约束（#42 实现硬约束）
- `HistoryCatalog` = 32 方法（22 required + 10 default），实现有 8 个（1 真 + 6 daemon test double + 1 memory）。
- 新增的 GC 方法（remove_branch / soft_delete_project / remove_file / retained_roots / compact 相关的查询）必须有 default `Unsupported` 体，否则 8 个 impl 同时要改。
- 禁止新增 `HistoryError` 变体：两个映射点都用 `_ => "Failed"` 通配，新变体会静默降级成 `Failed`。

### C10 每个操作的 admission 范围（#43）
- `branch.remove`：只排除该 Branch 的 mount/session；Store 内其它 Branch/project 保持可读可写。
- `project.delete`：排除该 project 的全部 mount/session（跨 Branch 与历史 Commit）；共享 Store 里其它 project 保持活跃；sole project 也必须让 Store 保持可寻址。
- `store.compact`：排除整个 Store（mounts、SDK sessions、reads、saves、merge/publication、未完成的 transfer）。
- 拒绝矩阵：`MountsActive`（有 mount/会话）、`Busy`（另一个 op 在跑）、`InUse`（lease 活着）。
- `project.remove` 当前是硬删（`remove_layerstack`），#45 要改成软删；`project.remove` 在 PG 上返回 `Unsupported` 也必须一并修掉。



---

## 6. Mark

```
GC(Roots@G):
  pinned  = op/staged 副本 ∪ in-flight installs ∪ Unresolved-op 工件
  closure = walk(Roots@G)        // 复用 qualify，禁止新 walker
  candidates = all_objects − closure − pinned
  receipt = (G, fingerprint(Roots), |closure|, |candidates|, bytes…)
  if rootGeneration ≠ G: abort, no writes
```

- 有界窗口 + 索引化 visited 状态；禁止第二个持久化数据库。
- 必须能报告三类异常：缺失依赖、损坏依赖、跨项目共享 pack。缺依赖必须中止，不得跳过。
- 多根取闭包用最低代际 `G_min` 作保守下界；`generation > G_min` 的根必须在 install 前重算。

---

## 7. Sweep

### 7.1 时序（复用 transfer，仅插入 `rewrite`）
```
check      锁外：两侧文件与磁盘、resolve 遗留副本
           锁内：record.unblocked()、收集 lease、写 op（args 指名源/目标）
snapshot   空闲 Store 的字节、sha256、heads
stage      在 Store 旁边生成一致快照副本
rewrite    在副本上删不可达行 + 回收        ← 唯一新增
verify     bytes / sha256 / heads
install    rename 已验证副本就位
retire     删除 record 不再指名的旧副本
```
- `uncertain` 沿用现有规则：`Unknown` 或 `record` 阶段为 uncertain；`send/verify/install` 的确定失败 → 保留副本、把 op 记为确定结果、由 doctor 报告。
- install 是唯一不可逆点，禁止"半新半旧"。

### 7.2 SQLite（#49）
0. **只在本机执行**：非 `native`（`Placement::Machine(m)` / `Unknown`）必须拒绝 `Unsupported`；文档写"先 `store.pull` 回家再压"。
1. 旧 Store 先过 `doctor`/`diagnose`，再进 `check`。
2. `rewrite` 在 staged 副本上删不可达行并重算 totals，保留不可变编码与 ID；只有选 `reorg`（Q6）才重编码。
3. 校验两层：`sqlite_structure(path, …)`（任意路径、只读）→ 能当 Store 打开后 `SqliteHandles::diagnose(options, …)`。CLI 的 `doctor store integrity <store>` 只认已注册 Store，**不能**用于副本；副本走 `control/.../diagnostic.rs::sqlite(path, identity, …)`。
4. 在 diagnostic 之上只加两条断言：闭包一致性、行数与对象数守恒。
5. install 复用 `StoreStep::Install`，校验 `(catalog_id, catalog_incarnation, dev, ino)`。
6. 旧副本由 `StoreStep::Retire` 删除。
7. 磁盘不足报 `Capacity`；失败时保留 op 与 staged 副本，不得自行清理。
8. **删除顺序由 FK 图决定**：`content_signature.object_id → object_location.object_id`、`object_location.pack_id → pack.pack_id`（`sql/sqlite/metadata.sql:12-29`），约束 IMMEDIATE（无 DEFERRABLE），`foreign_keys=ON`。必须按 `content_signature` → `object_location` 删，`pack` 不动。删不干净会被引擎拒绝并回滚（安全属性），但附属行必须先清。
9. 与 `reclaim_space` 分工：先判断 `auto_vacuum=2`；可回收者用它产出 `backend_reusable`，不可回收者只有替换一条路。

### 7.3 PostgreSQL（#50）
- **范围**：远程 PostgreSQL Store 在范围内（含远端服务）；不在范围的是远程 SQLite 与远程对象存储副本。
- Store 是一个 schema；`{s}` 由 `backend/postgresql/mechanics.rs:21` 替换成 `self.schema`，而 `self.schema` 来自 `schema_of`（`open.rs:37`，调用传入或默认 `layerfs`）。
- **swap 方式由 S11 决定**：
  - **E（默认，独占窗口）**：`BEGIN; ALTER SCHEMA layerfs RENAME TO layerfs_c_<n>_old; ALTER SCHEMA layerfs_c_<n> RENAME TO layerfs; COMMIT;` 之后 `DROP SCHEMA layerfs_c_<n>_old`。结尾名字仍是 `layerfs`，所有 record 与 `{s}` 不变；一把 namespace 锁。
  - **A'（读可用窗口）**：数据在版本化 schema `layerfs_c_<n>`；固定 schema 里只放一个指针行；`self.schema` 在 open 时从指针解析；swap = 一次 UPDATE 指针行 + 之后 `DROP SCHEMA` 旧代。不采用「版本化表名」（A），因为它要给每条 SQL 加第二个占位符。
  - **B（备选）**：同事务成对 `ALTER TABLE RENAME`（每表 ACCESS EXCLUSIVE，须验证 `lock_timeout`）。
  - **C 视图间接**：可写性需 trigger，作为最后的备选。
- 无论选哪个，读者围栏（C8/R2）都是必需的。
- `pack` 在 PG 侧同样有不可变触发器，禁止删旧表行；回收必须"新表 + 新触发器"。
- 删除次序：先删引用（`object_location` 等），后删 payload；中间态即 `backend_reusable`，单独上报。
- 读者围栏：lane 只挡写者；读者统一走 C8 的 `(catalog_id, incarnation)` 会话校验 → `StaleStore`（Q5 由 C8/R2 取代，不再单独选）。
- 回收指标：`pg_relation_size` / `pg_total_relation_size` 前后差；`autovacuum` 仍启用但不计入。

### 7.4 遗留物恢复
- 每次 `check` 先跑 `resolve`，按 op 的 phase 判断该阶段是否持有任何东西。
- 无法判定时必须报 `Unresolved`，禁止自动 install 或自动清理。
- 无 op 的孤立文件报 `OrphanArtifact`，不删。

---

## 8. 运营面

- 方法：`store.compact(name)` 注册 op，进度从 `store.status` 读；禁止新增 `operation.get`。
- 四个操作都只取资源标识——`branch.remove(name)`、`project.delete(name)`、`store.compact(name)`、`project.remove_file(project, path)`——共同禁止 `confirm`/`force`/`dryRun`/`stopSandboxes`/Store 或 volume 选项（#41 原文）。实现不做隐式 unmount、不等待、不重试；未清场返回 `MountsActive`/`Busy`/`InUse`。
- 后端路由：`backend.store.compact`（沿用 `backend.store.*` 命名族）；CLI `store compact`。
- 拒绝码：复用 `Busy`/`InUse`/`MountsActive`/`NoSuchStore`/`Unsupported`/`NotFound`；新增 `StaleStore`/`NameRetired`/`OrphanArtifact`/`Capacity`（对照 `StaleSandbox`）。`Unresolved`/`Stale` 是 op 状态，不是返回码。
- 文档必须并列：`store.remove`（整体删除 Store 与其所有 project）与 `project.delete`（软删、Store 仍可寻址）。

---

## 9. 验收（#52）

### 9.1 崩溃注入（每后端、每阶段 `kill -9`）
| 阶段 | 断言 |
|---|---|
| `stage` | 旧 Store 完整可用；op 与 staged 副本可识别；无字节丢失 |
| `rewrite` | 同上；旧 Store 一个字节都没动 |
| `verify` 后、`install` 前 | 不出现半新半旧；不自动 install |
| `install`（rename 前后各一次） | 要么全旧、要么全新 |
| install 后首次 open | 代际 bump 生效；旧会话收到 `StaleStore` |

### 9.2 无误删性质测试
- 随机 DAG：`fork / commit / merge / publish / branch.remove / project.delete`。
- 断言：存活根闭包内对象一个都没被删；闭包集合与大小前后逐一比对。
- ABA 变体：删候选 `A` 后立即写回同字节内容，旧意图不得生效。

### 9.3 契约测试
- 删除判定只依赖闭包与 pinned：断言实现不读任何时间列。
- 并发 compact 第二次 `Busy`，且不产生第二个 op 或第二份 staged 副本。
- 空根集合：删掉唯一 project 后 compact 仍可 open、可 `doctor`，Store 仍可寻址。
- `remove_file` 后回收字节与 receipt 解释一致（为 0 必须解释）。
- PG 换表期间并发读者得到 `StaleStore`；重连后读到完整新代际。
- 替换/换表前后各跑一次 diagnostic，`store.identity` 等项 Pass 且无新增 Fail。
- 远端客户端在 compact 期间被拒 `MountsActive`。
- 每次注入结束证明无残留 staged / target / op / schema。

---

## 10. 与 #41 子任务的对应

| 子任务 | 本规格交付 | 章节 |
|---|---|---|
| #42 契约 | C1–C8、代际算术、Q1–Q6、history 过滤清单 | §1.2, §5, §6 |
| #43 准入 | 复用 Store 锁 + lease + op；TOCTOU 复检；Branch/project/Store 三级排除矩阵（C10） | §2, C8, C10, §7.1 |
| #44 branch.remove | 终态 tombstone + 代际（Q1） | C6 |
| #45 project.delete | 软删 + Store 可寻址 | §8 |
| #47 remove_file | 视图层隐藏 + 回收口径（Q2） | §8, §9.3 |
| #48 可达性 | 冻结根 + 有界遍历 + 缺依赖中止 | §6 |
| #49 SQLite compact | 复用 transfer + `rewrite` + FK 顺序 + 拒绝非 native | §7.1–7.2 |
| #50 PostgreSQL GC | swap 方式由 S11 决定（E 默认 / A' 读可用）；代际 + 真实尺寸指标 | §7.3 |
| #51 API/SDK/CLI | 复用 op 与 `store.status` | §8 |
| #52 验收 | §9 全部 | §9 |

---

## 11. 非目标与参数纪律

- 自动周期回收（#41 禁止）。BrewFS 的 compaction 600 s / GC 3600 s 两个循环不借鉴。
- BrewFS 的碎片率阈值（代码默认 `min_slice_count=3`、`min_fragment_ratio=0.1`、`sync_threshold=200`）：那是"同一 chunk 内互相覆盖的 slice"的度量，LayerFS 对象不可变，应改用"不可达字节占比"。
- light / heavy 两级压缩：LayerFS 的"轻量"等价物就是 logical removal，已独立成 operation。
- `VACUUM FULL` 式整表回收（阻塞、2× 空间）。
- 远程对象存储副本的 compact（#41 不在范围）。
- 任何掉电持久性承诺（Disposable 仍是唯一执行 profile）。

> **参数纪律：** 引用 BrewFS 数值必须 pin 代码。其文档写的 5 / 350 / 1h / 100 与代码 3 / 200 / 600 s / 1000 不一致；`LockTtlConfig`(10/30/50/5/300) 与 `BlockGcConfig`(3600/3600/1000/3600) 一致。

---

## 12. 证据与校验记录

- **BrewFS 侧证据：** `src/chunk/compact/{gc.rs,compactor.rs,worker.rs}`（两阶段删除、`record_uncommitted_slice`/`confirm_slice_committed`、锁的 Drop+TTL 自愈）、`src/meta/config.rs`（`CompactConfig`/`LockTtlConfig` 默认值）、`doc/superpowers/plans/2026-10-10-packed-v3-temporary-handoff.md`（G13 的 root generation / Deleting 复检 / 层集合代数和，以及仍未闭合的 reader pins / mark-sweep / 无误删）。
- **LayerFS 侧证据：** `control/crates/layerfs-store/src/{lease.rs,record.rs}`、`.../sqlite/transfer/{step,phases,resolve}.rs`、`control/crates/layerfs-home/src/op.rs`、`engine/crates/layerfs-persistence/src/{backend/sqlite/profile.rs,backend/sqlite/schema.rs,backend/sqlite/lifecycle/reclamation.rs,diagnostic/*}`、`engine/crates/layerfs-store-service/src/operator/{dispatch,store,files}.rs`、`core/crates/layerfs-content/src/filesystem/qualify/`、`core/crates/layerfs-history/src/contract/identity.rs`。
- **校验：** 共 33 遍（含洁净版 12 遍），其中洁净版最后两遍无改动后收敛。设计层最后三次改动是：删对象年龄 grace、补非 native 拒绝与空根集合、补候选行集合。
- **仍未覆盖（需写代码回答）：** `rewrite` 的具体 SQL 批次与事务边界；`resolve` 清单的边界；`Retire` 跨机器失败语义；PG 读者策略（Q5）；`store.compact` 承诺层级（Q6）。
