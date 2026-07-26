# Volward 扫描结果 Finder 式目录树 — 设计规格

| 字段 | 内容 |
|------|------|
| 日期 | 2026-07-23 |
| 状态 | 已实现 v2（全量扫描，2026-07-23） |
| 基线 | `main` @ 单页 `home_page.dart` + 客户端 `ScanTreeBuilder`（500 条 flat entries 反推目录） |
| 原则 | **全量**：walk 可达范围内 **所有目录 + 所有文件** 均收录，不做条数截断 |

---

## 1. 背景与问题

### 1.1 用户诉求

1. 扫描结果 **与 macOS Finder 一致**：目录树展示，目录下挂内容。  
2. **全量查出完整文件内容**：在 scan root 与权限允许范围内，**不遗漏** walk 到的文件与目录。  
3. Cache 等分类仍可用于筛选，删除闭环不变。

### 1.2 当前行为（问题）

| 层级 | 现状 | 问题 |
|------|------|------|
| Rust | `MAX_ENTRIES=500`，仅文件 | **严重截断**，非全量 |
| Platform | `MAX_DEPTH=8` | 深层目录不可见 |
| UI | flat entries 反推树 | 结构不完整 |

### 1.3 Cache 定义（不变）

路径匹配 `rules/desktop.yaml`：`/Caches/`、`/cache/`、`.cache/` → `category: Cache`。

---

## 2. 成功标准（v2 全量）

1. **完整性**：`stats.files_in_snapshot == stats.files_seen`（正常完成时）；`stats.truncated == false`（除非用户 Cancel 或 IO/权限错误）。  
2. **目录**：walk 到的 **每一个目录**（含空目录）进入 `tree`。  
3. **文件**：walk 到的 **每一个文件** 进入 `tree` 叶子 + flat `entries`（含分类 metadata）。  
4. **深度**：**取消 `MAX_DEPTH=8` 硬限制**，与 Finder「能 walk 多深就多深」一致（仍 `follow_links: false`）。  
5. **展示**：Finder 式 tree；**虚拟滚动** 支撑大结果集 UI 不卡死。  
6. **删除 / Cache 筛选**：行为不变（entries + prune tree）。

---

## 3. 方案（v2）

### 3.1 总体：Rust 全量 walk + 完整 tree + 虚拟 UI

| 项 | v1（已废弃） | **v2（采用）** |
|----|-------------|----------------|
| 文件上限 | 10_000 | **无** |
| 节点上限 | 50_000 | **无** |
| 深度 | 8 | **无硬限制** |
| truncated | 超上限 | **仅 Cancel / walk 错误** |
| 大 snapshot | 护栏 | **Isolate 写临时 JSON 文件，主 Isolate 按需加载** |

### 3.2 为何不保留条数护栏

用户明确要求 **全量完整**；条数截断与产品原则冲突。性能通过 **虚拟列表 + snapshot 落盘** 解决，而非少扫。

### 3.3 仍可能「不完整」的情况（须写进 warnings）

| 原因 | 说明 |
|------|------|
| 用户 Cancel | `truncated=true` |
| 无 FDA / 沙盒 | 部分 `~/Library` 等读不到，walk 跳过 |
| 权限 / IO 错误 | 单路径 skip，warnings 列出 |
| **不是** 条数上限 | 不再使用 |

---

## 4. 架构设计

### 4.1 数据模型

```rust
pub struct ScanTreeNode {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size_bytes: u64,
    pub entry_id: Option<String>,
    pub children: Vec<ScanTreeNode>,
}

pub struct ScanStats {
    pub paths_seen: u64,
    pub dirs_seen: u64,
    pub files_seen: u64,
    pub files_in_snapshot: u64,
    pub truncated: bool,       // Cancel or fatal walk abort only
    pub incomplete_reason: Option<String>,
}

pub struct StorageSnapshot {
    // ... existing ...
    pub tree: ScanTreeNode,
    pub stats: ScanStats,
    pub entries: Vec<StorageEntry>, // ALL files, same count as file leaves
}
```

### 4.2 扫描流程

```text
discover_roots
  → WalkDir (no max_depth cap, follow_links=false)
  → for each RawFsEntry:
        paths_seen++
        is_dir  → tree.ensure_dir; dirs_seen++
        !is_dir → classify → entries.push; tree.insert_file; files_seen++
  → aggregate sizes, sort children
  → assert files_in_snapshot == files_seen (debug)
  → StorageSnapshot
```

**删除：** `MAX_ENTRIES`、`MAX_FILES`、`MAX_TREE_NODES` 及一切「满 N 条停止收录」逻辑。

### 4.3 Platform：`desktop.rs`

```rust
// 删除 const MAX_DEPTH: usize = 8;
WalkDir::new(root_path)
    .skip_hidden(false)
    .follow_links(false)
    // 不设置 .max_depth(...)，全深度 walk
```

### 4.4 大 snapshot 传输（Isolate → UI）

当前 worker 经 `SendPort` 传整份 snapshot Map，全量 Home 可能 **数百 MB JSON**。

**v2 方案：**

1. Worker 扫描完成后将 snapshot **写入临时文件**（`Directory.systemTemp/volward-{jobId}.json`）。  
2. `done` 消息只传 `{ type, snapshot_path, stats_summary }`。  
3. 主 Isolate **异步读取** JSON → `VolwardSession.lastSnapshot`。  
4. 可选：UI 只先读 `stats` + `tree` 顶层，entries 懒解析（二期）；v2.0 先整文件加载，虚拟 UI 保流畅。

涉及文件：

- `apps/volward/lib/bridge/scan_worker.dart`
- `apps/volward/lib/volward_session.dart`

### 4.5 Flutter UI：虚拟 Tree

**问题：** 全量 tree 可能有 10⁵+ 节点，递归 `Column` 会卡死。

**方案：** `ScanTreeList` — 将 **已展开** 节点 **扁平化** 为 `List<VisibleRow>`，`SliverList.builder` 渲染。

| 文件 | 职责 |
|------|------|
| `scan_tree_flatten.dart` | `flattenVisible(ScanTreeNode root, Set expanded) → List<FlatRow>` |
| `widgets/scan_tree_view.dart` | 改用 builder；仅渲染可见行 |
| `home_page.dart` | `SliverList.builder` 替代整块 `SliverToBoxAdapter(ScanTreeView)` |

### 4.6 筛选

Cache / Deletable：对 tree **prune**（保留匹配文件及祖先目录），再 flatten 渲染。

---

## 5. 不在本阶段

- Treemap、重复文件  
- FRB 迁移  
- 跨 scan root 多森林合并（v2 仍用第一 root 或 common parent，与现逻辑一致）

---

## 6. 测试

| 层 | 内容 |
|----|------|
| Rust | 临时目录 1000+ 文件：assert `files_seen == entries.len()`，`truncated == false` |
| Rust | 深层嵌套 >8 层：assert 仍收录 |
| Dart | flatten 仅输出 expanded 子树 |
| 手动 | Home 全扫：stats 显示全量文件数；滚动流畅 |

---

## 7. 风险

| 风险 | 缓解 |
|------|------|
| Home 扫描耗时长 | 保留 progress UI；可 Cancel |
| 内存 / JSON 过大 | snapshot 落盘 + 虚拟列表 |
| Isolate 传大 Map OOM | **禁止** port 传全量 Map，改传文件路径 |

---

## 8. 评审确认（v2）

- [x] 全量：无条数截断  
- [x] 取消 MAX_DEPTH=8  
- [x] truncated 仅 Cancel/错误  
- [x] UI 虚拟滚动  
- [x] 大 snapshot 走临时文件  

---

## 9. 修订记录

| 版本 | 日期 | 说明 |
|------|------|------|
| v2 | 2026-07-23 | 全量扫描 + Finder 列浏览已实现 |
| v2.1 | 2026-07-26 | plan 回写 Implementation Status；能力叠加快进式扫描 |