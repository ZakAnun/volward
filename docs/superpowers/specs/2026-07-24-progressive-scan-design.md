# Volward 渐进式扫描（预览 + 后台全量 + 点击优先）— 设计规格

| 字段 | 内容 |
|------|------|
| 日期 | 2026-07-24 |
| 状态 | ✅ 已实现（Wave 1 + Wave 2，含加固） |
| 基线 | `main`（含 2026-07-23 的 Finder 式列浏览、全盘扫描性能优化、增量扫描 E1/E2） |
| 范围 | Wave 1（预览 + 后台全量 checkpoint 流式渲染）+ Wave 2（点击优先分片扫描） |
| 落地说明 | 代码已合入 `main`（至 `4a16188` / `3e01c72`）；含权威 peek 合并、entries 清理、`scanned == true` 判定、UI snapshot 去抖、checkpoint 自适应间隔 |
| 已知残留 | 启动恢复 snapshot 在无匹配 Home 根时可能回退到全局最新自定义目录快照（体验问题，未修） |

---

## 1. 背景与问题

### 1.1 现状

`ScanOrchestrator::run_scan`（`crates/volward-core/src/scan.rs`）是一次同步、完整的递归 walk：discover roots → 全量 walk + 分类 → 建 tree → 序列化 → 一次性返回完整 `StorageSnapshot`。Dart 侧 `VolwardSession.runScan()` 在此期间保持 `scanning = true`，UI 展示一个阻塞的"扫描中"页面（`home_page.dart` 的 `_buildScanSection`），直到收到 `done` 消息才切换到结果浏览视图。

对于 Home 目录这种体量较大的扫描目标，用户在点击"开始扫描"之后，会经历较长一段时间的空白等待，看不到任何中间反馈或可操作的内容，体验较差。

### 1.2 用户诉求

1. 选定扫描目标后，**先立即展示该目录的结构**（不必等待深度扫描）。
2. 用户确认后，**再进行真正的深度扫描**，且扫描过程按"层"逐步产出结果，而不是一次性等到全部完成。
3. 用户点击浏览一个"后台还没扫到"的目录时，应该能**优先**看到它的内容，而不是傻等全局扫描顺序轮到它。
4. Cache 分类、可清理总量等统计的**最终完整性**不能降低——现有"全量、不截断"的产品原则保留，只是渲染方式从"一次性"变成"渐进式"。

### 1.3 非目标

- 不改变"全量扫描覆盖 walk 可达的每个文件/目录"这一原则（对应 `2026-07-23-scan-tree-finder-design.md` 的 v2 全量语义）。
- 不替换或重写 jwalk 的核心并行遍历实现（避免影响近期"全盘扫描性能优化"的成果）。
- 不改变删除闭环（Move to Trash / dry-run）的语义。
- 不在本阶段处理多 root 并行分片扫描的调度优化（分片扫描 Wave 2 的并发上限先取一个保守的固定值）。

---

## 2. 方案选型（Brainstorming 结论）

经过讨论确定的三个关键决策：

1. **导航模式**：懒加载按需展开 —— 目录默认按需显示，而不是等待整棵树扫完。
2. **完整性保证**：确认扫描后，后台**仍然跑一次完整的全量扫描**（不是"用户点开哪就只扫哪"的纯懒加载），保证 Cache 筛选/可清理总量最终与今天等价。
3. **点击优先机制**：不改造 jwalk 内部遍历顺序（方案 B，风险高），而是用**独立的小型分片扫描**模拟优先级效果（方案 A，推荐，本设计采用）——用户点击一个还未被主扫描覆盖的目录时，额外发起一个只扫这个子目录的 `run_scan(roots=[该路径])`，因为子目录通常远小于整个扫描根，能快速完成并合并进当前展示的树。

被否决的方案：

- **方案 B（重排 jwalk 队列）**：需要抛弃 jwalk 的并行迭代器、自研 BFS 遍历，风险和工作量显著更高，且威胁近期的全盘扫描性能优化成果。
- **方案 C（纯轮询补扫，无优先级）**：不满足"点击优先"的诉求，用户点开排序靠后的目录可能要等很久。

---

## 3. 总体架构（三阶段）

```text
选定目标 (Home / 自定义目录)
        │
        ▼
┌───────────────────────┐
│ 阶段 1 · 目标预览        │  quick_list_dir(root) — 单层非递归 read_dir
│（新增，取代静态扫描前页） │  瞬时展示 root 下的直接子项（文件已知大小，目录待定）
└───────────┬───────────┘
            │ 用户点击"开始扫描"确认
            ▼
┌───────────────────────┐
│ 阶段 2 · 后台全量扫描     │  沿用 ScanOrchestrator::run_scan（全量语义不变）
│（改造：周期性 checkpoint）│  每 ~2s 吐出一次当前已建好的部分 tree/entries
│                        │  UI 渐进合并渲染，不阻塞浏览
└───────────┬───────────┘
            │ 用户点击一个还没被主扫描覆盖的目录
            ▼
┌───────────────────────┐
│ 阶段 3 · 点击优先（Wave 2）│  quick_list_dir(该路径) 瞬时展示下一层
│                        │  + 独立分片 run_scan(roots=[该路径]) 后台完成后合并
└────────────────────────┘
            │
            ▼
      主后台扫描 Done → 权威最终 snapshot（与今天全量扫描结果等价）
```

**关键不变量**：无论走预览、checkpoint 还是分片扫描哪条路径，最终以主后台扫描的 `Done` 结果为准；中间态只影响渲染时机，不影响最终数据的完整性和正确性。

---

## 4. 组件设计

### 4.1 Rust core（`volward-core`）

| 文件 | 改动 |
|------|------|
| `src/platform.rs` | `PlatformStorage` trait 新增 `fn quick_list_dir(&self, path: &str) -> Result<Vec<RawFsEntry>, PlatformError>` |
| `src/scan_tree.rs` | `ScanTreeBuilder` 新增非消费方法 `pub fn peek_snapshot(&self) -> ScanTreeNode`（克隆 + 聚合当前状态，不影响后续 `insert_file`/`finalize`） |
| `src/scan.rs` | `run_scan` 新增 `on_checkpoint: impl FnMut(StorageSnapshot)` 回调参数；在 Walking 阶段按**墙钟时间**（非文件计数）节流触发，默认 2 秒一次 |
| `src/model.rs` | `RawFsEntry` 复用（`quick_list_dir` 返回的目录条目 `dir_fingerprint: None`，语义为"未展开"） |

`quick_list_dir` 与现有 `walk_entries` 是两个独立入口，互不干扰、可并发调用（无共享可变状态需要互斥）。

### 4.2 Platform desktop（`platform-desktop`）

| 文件 | 改动 |
|------|------|
| `src/desktop.rs` | 实现 `quick_list_dir`：用 jwalk `WalkDir::new(path).max_depth(1)`，复用现有 `protected_prefixes` 过滤；目录条目 `size_bytes = 0`（占位，UI 侧按"未知"处理，不是真实 0），文件条目正常 `fs::metadata` 取真实大小 |

### 4.3 Rust facade（`volward-facade`）

| 文件 | 改动 |
|------|------|
| `src/engine.rs` | `VolwardEngine` 新增 `last_checkpoint: Arc<Mutex<Option<StorageSnapshot>>>`；`start_scan_async` 内部线程按 2 秒节流写入；新增 `quick_list_dir_json(path)`（无需 `is_scanning` 互斥，可在主扫描运行期间被并发调用，用于 Wave 2 分片扫描前的即时展示）、`write_last_checkpoint_to_path(path)` |
| `src/capi.rs` | 新增对应 C 导出：`volward_quick_list_dir_json`、`volward_write_last_checkpoint_to_path` |

### 4.4 Dart bridge（`apps/volward/lib/bridge/`）

| 文件 | 改动 |
|------|------|
| `native_bridge.dart` | 按现有 `_tryLookupX` 模式新增可选 FFI 绑定；新增 `hasQuickListApi`、`hasCheckpointApi` 能力探测 getter，缺失时优雅降级为今天的阻塞流程 |
| `scan_worker.dart` | 主扫描 Isolate 的 300ms 轮询循环中，每隔约 6-7 次 tick（≈2s）额外调用一次 `writeLastCheckpointToPath`，发送 `{type: 'checkpoint', snapshot_path}` 消息（通道不关闭，扫描继续） |
| `scan_worker.dart`（新增） | `volwardPeekScanIsolate(args)`：独立 Isolate 入口，创建**自己的** native engine（与主扫描引擎完全独立），对单一路径跑 `run_scan`，完成后通过结果端口回传、随后释放 engine（Wave 2） |

### 4.5 Dart session（`volward_session.dart`）

- `runScan()` 语义调整：`startScanAsyncWithOptions` 发出后立即返回控制权（不再 `await` 到 `Done`），后续通过监听 `checkpoint`/`done` 消息持续更新 `_lastSnapshot` 并 `notifyListeners()`。
- 新增 `Future<void> previewTarget()`：调用 `quickListDir(root)`，包装为最小可渲染的"预览 snapshot"（`{snapshot_id: 'preview', tree: {...}, entries: [], stats: {...}}`），在用户点击"开始扫描"之前就设置进 `_lastSnapshot` 供 UI 渲染。
- 新增 `_mergeSubtree(String path, Map subtreeTree, List subtreeEntries)`：把 checkpoint 或分片扫描结果拼接进 `_lastSnapshot` 中对应路径的节点，替换其 `children`；去重合并 `entries`（按 `id` 覆盖旧值）；本地重新累加 `reclaimable_estimate_bytes`（不完全信任 Rust 吐出的"截至那一刻"的全局字段）。
- 新增 `bool get backgroundScanActive`：区分"整体会话是否有后台扫描在跑"（不阻塞 UI）与今天 `scanning`（阻塞语义），供 UI 决定是否展示非阻塞的后台进度条。
- 新增 `Future<void> peekScan(String path)`（Wave 2）：若目标路径已被最近一次 checkpoint/分片扫描覆盖则直接返回；否则限流（同时最多 2 个并发分片任务，超出的排队），spawn `volwardPeekScanIsolate`，完成后调用 `_mergeSubtree`。

### 4.6 Dart UI（`home_page.dart` / `scan_tree.dart` / `widgets/scan_column_view.dart`）

- `ScanTreeNode`（Dart model，`scan_tree.dart`）新增 `bool scanned` 字段：预览/分片结果尚未确认的目录节点为 `false`；来自 checkpoint/最终快照的节点为 `true`。`displayBytes` 在 `scanned == false` 时不返回 0，由 UI 层展示为"—"。
- 选定目标后立即调用 `previewTarget()` 展示 root 直接子项；结果浏览视图（`hasResults` 判定条件）从"仅当 `lastSnapshot != null` 且扫描已完成"改为"只要有预览或部分数据即可浏览"。
- "开始扫描"按钮触发 `runScan()`，但**不再切换到阻塞页面**——浏览视图保持可交互，顶部新增一条非阻塞的"后台扫描中 · 部分统计"提示条，`Done` 后消失。
- `checkpoint` 消息到达时，**只失效受影响子树的缓存**，不重置当前列导航选择（`_columnChain`）——这是对现有 `_invalidateSnapshotCaches` 的重要修正，避免用户浏览到一半被打断。
- （Wave 2）`ScanColumnView` 选中一个 `scanned == false` 的目录节点时，触发 `_s.peekScan(node.path)`，该列位置显示局部 loading 态（而非整页 loading）。

---

## 5. 错误处理与边界情况

| 场景 | 行为 |
|------|------|
| `quick_list_dir` 遇到权限拒绝的子路径 | 跳过该条目，不中断整体列表，标记 `partial: true` |
| 预览阶段（尚未点"开始扫描"）切换目标目录 | 丢弃旧预览，对新 root 重新 `quick_list_dir`；此时没有后台扫描在跑，无需额外清理 |
| 扫描中点击"取消" | 复用现有 `cancelScan()`；最后一次 checkpoint 停留的状态即为最终展示结果（`truncated=true`，但用户已浏览过的内容不丢失） |
| checkpoint 到达时用户正浏览其他路径 | 只合并受影响子树，不重置列导航 |
| dylib 过旧、不支持新增 FFI | 复用 `hasSnapshotFileApi` 一样的探测 + 降级模式：探测不到就回退今天"点确认后阻塞直到 Done"的旧流程，并提示 rebuild Rust |
| 主后台扫描已扫完某目录，用户此时才点开 | 直接展示已有数据，无需触发分片扫描（最常见路径） |
| （Wave 2）分片扫描进行中，用户又点开另一未扫描目录 | 并发上限 2，超出排队；避免并发 IO 打满 |
| （Wave 2）分片扫描完成后，主扫描随后也扫到同一目录 | 复用现有 `DirFingerprint` 增量跳过机制；即使未跳过、重复扫描覆盖也不影响正确性 |

---

## 6. 测试策略

| 层级 | 内容 |
|------|------|
| Rust unit（`scan_tree.rs`） | `peek_snapshot` 非破坏性：调用后 builder 仍可继续 `insert_file`，最终 `finalize()` 结果不受影响 |
| Rust unit（`scan.rs`） | 模拟扫描中触发多次 `on_checkpoint`，断言各次 checkpoint 的 entries 是递增子集，最终等于完整结果 |
| Rust unit（`platform.rs`/`desktop.rs`） | `quick_list_dir`：临时目录只返回一层；文件有真实 size，目录 size 为占位；权限错误路径跳过不 panic |
| Dart（`volward_session_test.dart`，新增） | `previewTarget()` 正确包装可渲染的预览 snapshot；`_mergeSubtree` 合并后不影响其他路径数据；重复合并同一路径幂等 |
| Dart（`scan_tree_test.dart`） | `ScanTreeNode.scanned` 字段语义正确；`displayBytes` 未扫描时不误报 0 |
| Dart widget（`home_page`/`scan_column_view`） | 预览阶段结果可见可点击；`checkpoint` 到达不重置当前列导航选择 |
| 手动回归 | Home 目录：确认前先看到顶层目录列表 → 点击开始 → 立即可浏览、数字随后台扫描逐步变实 → 完成后数字与今天全量扫描结果一致；取消后已浏览内容不丢失；点击未扫描目录能看到瞬时预览并较快补全聚合大小 |

---

## 7. 交付波次

| 波次 | 内容 | 依赖 | 状态 |
|------|------|------|------|
| **Wave 1** | `quick_list_dir`（预览）+ checkpoint 流式渲染 + UI 从阻塞页改为始终可浏览 | 无 | ✅ 已实现 |
| **Wave 2** | 点击优先分片扫描（独立 Isolate + engine，合并结果，并发限流） | Wave 1（依赖 `quick_list_dir`、`ScanTreeNode.scanned`、`_mergeSubtree`） | ✅ 已实现 |

本次 `writing-plans` 按用户要求**一次性覆盖 Wave 1 + Wave 2**；均已落地。

---

## 8. Spec Self-Review

- [x] 无 TBD 占位
- [x] 与既有"全量扫描、不截断"原则一致，只改变渲染时机
- [x] 三个关键架构决策（懒加载导航、后台全量保完整性、分片扫描代替 jwalk 重排）均已在文中体现并给出理由
- [x] 组件改动按文件列出，边界清晰
- [x] 错误处理覆盖 dylib 过旧降级、取消、并发限流、重复扫描去重
- [x] 测试策略覆盖 Rust unit / Dart unit / widget / 手动回归
- [x] Wave 1 / Wave 2 可独立交付，依赖关系明确

---

## 9. 修订记录

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-07-24 | 初稿：预览 + checkpoint + 点击优先 |
| 0.2 | 2026-07-26 | 标记 Wave 1/2 已实现；记录加固与已知残留 |
