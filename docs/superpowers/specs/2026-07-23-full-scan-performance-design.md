# Volward 全盘扫描性能优化（P1/P2）— 设计规格

| 字段 | 内容 |
|------|------|
| 日期 | 2026-07-23 |
| 状态 | ✅ 已实现（P1 + P2.1–P2.3 + F0 bench；P0 Release 仍排除） |
| 基线 | `main` + 未提交 P0 前优化（walk 剪枝、无 sort、entries 仅分类项、UI 侧排序缓存） |
| 范围 | **P1**（近期可落地）+ **P2**（架构增强，分波交付） |
| 排除 | **P0 Release 构建** — 用户明确 Debug 版继续使用，本 spec 不涉及 |
| 落地说明 | Classify 快路径、BufWriter 写 snapshot、walk 剪枝扩展、`dir_child_index`、manifest + 增量 E1/E2、CLI `scan-bench` 已在 `main`；后续渐进式扫描另见 `2026-07-24-progressive-scan-design.md` |

---

## 1. 背景与目标

### 1.1 产品目标

以 **全盘扫描（`/` 或极大 root）** 为性能基准；全盘提速后，Home / 指定目录扫描自然受益。

### 1.2 当前链路（优化后基线）

```
Walk (jwalk + prune) → Classify (仅 interesting 文件写 entries) → ScanTreeBuilder → serde_json → tmp 文件 → Dart jsonDecode → UI _sortTree
```

| 阶段 | 现状（未提交改动） | 全盘瓶颈 |
|------|-------------------|----------|
| Walk | 剪枝 dev 目录、无 sort、目录免 metadata | 仍是主耗时（文件数 × syscall） |
| Classify | 每文件仍跑完整 classify（含 regex、name 分配） | CPU 随 files_seen 线性增 |
| Tree | `find_dir_child_mut` 线性查子节点 | 深宽目录建树偏慢 |
| Serialize | `to_string` 整包 snapshot 再 write | 峰值内存 + 二次拷贝 |
| Load | Dart `jsonDecode` 全量 Map | 大 JSON 加载慢、内存高 |

### 1.3 成功标准

| 指标 | 测量方式 | P1 目标 | P2 目标 |
|------|----------|---------|---------|
| 全盘 walk 耗时 | `stats.paths_seen` + wall clock | 较基线再降 **≥15%**（Classify 快路径 + 建树优化） | 二次扫描同 root **≥50%** 提速（增量） |
| SavingResults 耗时 | Isolate 日志 / phase 切换 | 较基线降 **≥30%**（流式 JSON） | 再降 **≥40%**（二进制快照） |
| LoadingResults 耗时 | `_loadSnapshotFromFile` | 随 JSON 缩小已改善；流式写后再测 | Dart 侧免全量 parse 或 Rust 直出 tree |
| 峰值内存 | Instruments / 进程 RSS | Serialize 峰值明显下降 | 增量扫描避免重复全量 tree |
| 功能回归 | `cargo test` + 手动 Home/`/` 扫描 | Cache 筛选、删除、Column 浏览行为不变 | 同上 |

---

## 2. 方案对比（Brainstorming）

### 2.1 P1-A：Classify 两阶段快路径（推荐）

**思路：** 在 `Classifier` 内增加 `classify_path_fast`：先做 **零分配 / 低开销** 启发式；不匹配则 `None`，跳过 regex 与 `StorageEntry` 构造。

**启发式顺序（与现有语义一致）：**

1. `protected_prefixes` — `path.starts_with`（已有）
2. Cache — 字节级子串：`/Caches/`、`/cache/`、`.cache/`（覆盖默认 rules 的主体，regex 作 fallback）
3. Temp — `/tmp/`、`/temp/`、路径以 `.tmp` 结尾
4. Media — 扩展名后缀（已有逻辑）
5. 若启发式未命中且 rules 含 **非默认** 自定义 pattern → 才跑对应 `Regex`

**trade-off：**

| | 优点 | 缺点 |
|---|------|------|
| 推荐 | 改动小、可单测、全盘 90%+ 文件直接跳过 | 自定义 YAML pattern 须明确「启发式 + regex fallback」契约 |

### 2.1 备选 P1-A′：Walk 层跳过 classify

在 `scan.rs` 只对路径含特定片段的文件调用 classify。**不推荐**：规则重复、与 `desktop.yaml` 漂移。

### 2.2 P1-B：流式 JSON 落盘（推荐）

**思路：** `write_last_snapshot_to_path` 改为 `BufWriter` + `serde_json::to_writer`，避免 `String` 中间态。

**不变：** Snapshot 仍在内存中完整构建；仅优化 **序列化→磁盘** 段。

**trade-off：**

| | 优点 | 缺点 |
|---|------|------|
| 推荐 | 改动约 10 行，立刻降峰值内存 | 不解决「构建 snapshot 本身」内存 |

### 2.2 备选 P1-B′：NDJSON 分块 tree

扫描过程中流式写 tree 节点。**不推荐 P1**：格式变更、Dart 解析复杂，属 P2 二进制方案前置研究。

### 2.3 P1-C：扩展 walk 剪枝（可选、低风险）

在 `walk_prune.rs` 增加可维护列表（如 `.Trash`、`.Spotlight-V100`、Time Machine 快照路径 `.MobileBackups`）。

**原则：** 只剪 **明确无清理价值** 且 **体积极大** 的路径；不剪 `Caches`（产品核心）。

**默认：** P1 仅加 `.Trash`、`.Spotlight-V100`；其余进 `rules` 或配置后续迭代。

### 2.4 P2-D：ScanTreeBuilder 子节点索引（推荐）

**问题：** `find_dir_child_mut` 对每个 path segment 线性扫描 `children`（O(兄弟数)）。

**方案：** Builder 维护 `dir_child_index: HashMap<String, HashMap<String, usize>>`  
键：`parent_path` → `(child_name → index in parent.children)`。

**插入目录/文件时：** O(1) 定位父节点下标，避免按 name 线性 find。

**trade-off：** 额外内存 ~每个目录节点一条 index 项；全盘可接受。

### 2.5 P2-E：增量扫描（分阶段）

**思路：** 持久化 **ScanManifest**（JSON），记录上次扫描：

```json
{
  "root": "/",
  "scanned_at_ms": 123,
  "dir_fingerprints": { "/Users/x": { "mtime_secs": 1, "children_count": 42 } }
}
```

**二次扫描：** jwalk 进入目录前比对 fingerprint；未变则 **整棵子树跳过**（同时从 manifest 合并上次 tree 子树）。

**macOS 注意：** 目录 mtime 不一定随子文件变化而更新 → fingerprint 需含 **`children_count` + 可选 max child mtime**（子目录 stat 采样或一层 readdir 摘要）。

**分阶段：**

| 阶段 | 能力 |
|------|------|
| E1 | 仅 manifest 读写 + UI「增量扫描」开关；未命中则全量 |
| E2 | 子树跳过 + tree 合并 |
| E3 | 与 delete 后自动 invalidate 子路径 |

**不推荐一步到位：** 合并 tree + 分类 staleness 复杂度高。

### 2.6 P2-F：二进制快照（可选）

**格式：** `postcard` 或 `bincode` 序列化 `StorageSnapshot`；文件扩展名 `.vwsnap`。

**Dart：** 不直接 decode；新增 FFI `volward_load_snapshot_binary_to_engine` + `volward_export_tree_json_for_ui`（仅导出 UI 需要的 tree 子集）**或** 继续 JSON 仅含 tree+stats、entries 二进制分文件。

**推荐折中（F1）：** Rust 写 **双文件**：`*.tree.bin`（postcard）+ `*.entries.json`（小）；Dart UI 只读 entries JSON + 通过 FFI 按需拉 tree 子节点（后续）。

**P2 首版仅 F0：** 内部 benchmark crate/cli 验证体积与速度；**不切换 UI 默认路径**，避免 Dart 大改。

---

## 3. 架构设计

### 3.1 P1 数据流（不变语义）

```
RawFsEntry
  → is_dir ? ensure_dir : classify_path_fast → Option<StorageEntry>
  → tree_builder.insert_file(path, entry_id?, size)
  → finalize → StorageSnapshot
  → serde_json::to_writer(BufWriter) → tmp path
  → Dart jsonDecode（暂不变）
```

**语义保持：**

- `stats.files_seen` = walk 到的文件总数  
- `stats.files_in_snapshot` = 写入 `entries` 的分类文件数  
- Column 浏览依赖 **tree**（全量文件）；Cache 筛选依赖 **entries**

### 3.2 P2 增量扫描组件

```
┌─────────────────┐     ┌──────────────────┐
│ ScanOrchestrator│────▶│ ScanManifestStore│  ~/Library/Application Support/Volward/manifests/
└────────┬────────┘     └──────────────────┘
         │
         ▼
┌─────────────────┐
│ IncrementalWalk │  skip unchanged subtrees
│ (wraps jwalk)   │
└─────────────────┘
```

**接口（volward-core）：**

```rust
pub struct ScanManifest { /* root, scanned_at_ms, fingerprints */ }
pub trait ManifestStore { fn load(&self, root: &str) -> Option<ScanManifest>; fn save(&self, m: &ScanManifest) -> Result<()>; }
```

Platform 层 **不** 感知 manifest；Orchestrator 在 walk 回调前后决策。

### 3.3 P2 ScanTreeBuilder 索引

```rust
struct ScanTreeBuilder {
    // existing fields
    dir_child_index: HashMap<String, HashMap<String, usize>>,
}
```

`ensure_dir_internal` / `find_dir_mut` 改用 index，fallback 线性 scan 仅用于测试一致性。

### 3.4 错误处理

| 场景 | 行为 |
|------|------|
| 流式 JSON write 失败 | 返回 `error:write snapshot`，删除不完整文件 |
| Manifest 损坏 | 忽略 manifest，全量扫描 + warning |
| 增量合并 tree 冲突 | 以本次 walk 为准覆盖子树 |
| 二进制快照版本不匹配 | 回退 JSON 路径 |

### 3.5 测试策略

| 层级 | 内容 |
|------|------|
| Rust unit | classify 快路径与旧行为等价；builder index；manifest roundtrip |
| Rust integration | temp dir 两次扫描：第二次改单文件，断言增量命中 |
| Flutter | 现有 `scan_tree_test` 不变；手动 Home + 选目录回归 |
| Bench | 可选 `volward-cli bench scan --root /Users/...` 输出各 phase ms |

---

## 4. 交付波次

| 波次 | 内容 | 依赖 | 状态 |
|------|------|------|------|
| **P1.1** | Classify 快路径 | 无 | ✅ |
| **P1.2** | 流式 JSON write | 无 | ✅ |
| **P1.3** | walk 剪枝扩展（.Trash 等） | 无 | ✅ |
| **P2.1** | ScanTreeBuilder 子节点索引 | 无 | ✅ |
| **P2.2** | ScanManifest 存储 + E1 全量 fallback | P2.1 可选 | ✅ |
| **P2.3** | 增量 walk + tree 合并 E2 | P2.2 | ✅ |
| **P2.4** | 二进制快照 F0 benchmark | 无 | ✅（`volward-cli scan-bench`；UI 仍走 JSON） |

**建议实施顺序：** P1.1 → P1.2 → P2.1 → P1.3 → P2.2 → P2.3 → P2.4（均已落地）

---

## 5. 非目标

- Debug/Release 构建切换（用户明确 P0 暂不处理）
- 多 root 并行 walk（jwalk 已并行，不额外拆）
- UI 改为 Isolate 外解析 binary tree（留 P2.4 研究；F0 bench 已有，默认路径仍 JSON）
- 改变 Cache/删除产品语义

---

## 6. 待确认项

1. **P2 增量扫描** 是否必须在 v1 对用户可见（开关），还是仅内部 manifest 为后续预留？
   → 已落地：**E1 暴露「增量扫描」Toggle**，默认关闭。
2. **剪枝 `.Trash`** 是否接受（用户可能想清理废纸篓）？
   → 已按默认：**不剪 `.Trash`**，仅剪 `.Spotlight-V100` 等索引目录。

---

## 7. Spec Self-Review

- [x] 无 TBD 占位
- [x] P1/P2 边界清晰，P0 已排除
- [x] 与现有 `entries` 精简、`tree` 全量语义一致
- [x] 增量扫描分 E1/E2/E3，可独立交付
- [x] 成功标准可测量

---

## 8. 修订记录

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-07-23 | 初稿：P1/P2 性能与增量 |
| 0.2 | 2026-07-26 | 标记 P1 + P2.1–P2.4(F0) 已实现；关闭待确认项 |