# Volward Finder 式全量扫描目录树 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 scan root 与权限范围内 **全量 walk** 所有目录与文件，以 Finder 式目录树展示；无 500/10k 条数截断；大结果集 UI 虚拟滚动。

**Architecture:** Rust walk 构建完整 `ScanTreeNode` + 全量 `entries`；取消 `MAX_DEPTH` 与一切条数上限；`truncated` 仅表示 Cancel/错误；Isolate 将 snapshot 写入临时 JSON 文件再加载；Flutter 用 flatten + `SliverList.builder` 虚拟渲染 tree。

**Tech Stack:** Rust 2021 (volward-core, platform-desktop), jwalk, Flutter 3.44 (FVM), Dart Isolate, serde_json

**Spec:** [2026-07-23-scan-tree-finder-design.md](../specs/2026-07-23-scan-tree-finder-design.md) (v2 全量)

---

## File map

| Path | Responsibility |
|------|----------------|
| `crates/platform-desktop/src/desktop.rs` | 移除 `MAX_DEPTH`，全深度 walk |
| `crates/volward-core/src/model.rs` | `ScanTreeNode`, `ScanStats`（含 `incomplete_reason`） |
| `crates/volward-core/src/scan_tree.rs` | 全量插入目录/文件，**无节点上限** |
| `crates/volward-core/src/scan.rs` | 全量 walk 回调；删除 `MAX_ENTRIES` |
| `apps/volward/lib/bridge/scan_worker.dart` | snapshot 写临时 JSON，`done` 传路径 |
| `apps/volward/lib/volward_session.dart` | 异步读 snapshot 文件 |
| `apps/volward/lib/scan_tree.dart` | `fromSnapshotJson` |
| `apps/volward/lib/scan_tree_filter.dart` | prune |
| `apps/volward/lib/scan_tree_flatten.dart` | 展开节点扁平化 |
| `apps/volward/lib/widgets/scan_tree_view.dart` | 单行 tile（dir/file） |
| `apps/volward/lib/home_page.dart` | `SliverList.builder` + stats 全量文案 |
| `apps/volward/test/scan_tree_test.dart` | fromJson + prune + flatten 测试 |

---

## Wave 0 — 移除 walk 深度与条数限制

### Task 0: platform 全深度 walk

**Files:**
- Modify: `crates/platform-desktop/src/desktop.rs`

- [ ] **Step 1: 删除 MAX_DEPTH 常量及 `.max_depth(MAX_DEPTH)`**

```rust
for entry in WalkDir::new(root_path)
    .skip_hidden(false)
    .follow_links(false)
    .into_iter()
```

- [ ] **Step 2: 添加测试（可选 fixture 12 层目录仍可 walk）**

- [ ] **Step 3: Run**

Run: `cargo test -p platform-desktop`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add crates/platform-desktop/src/desktop.rs
git commit -m "feat(platform): remove max_depth cap for full directory walk"
```

---

## Wave 1 — Rust 模型与全量 tree builder

### Task 1: ScanTreeNode / ScanStats

**Files:**
- Modify: `crates/volward-core/src/model.rs`
- Modify: `crates/volward-core/src/delete.rs`

- [ ] **Step 1: 添加类型（含 incomplete_reason）**

```rust
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ScanStats {
    pub paths_seen: u64,
    pub dirs_seen: u64,
    pub files_seen: u64,
    pub files_in_snapshot: u64,
    pub truncated: bool,
    pub incomplete_reason: Option<String>,
}
```

- [ ] **Step 2: 扩展 `StorageSnapshot` 含 `tree` + `stats`**

- [ ] **Step 3: 修复 `sample_snapshot()` 测试 fixture**

- [ ] **Step 4: `cargo check -p volward-core` → PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(core): extend snapshot with full-scan tree and stats"
```

---

### Task 2: scan_tree 模块（无上限）

**Files:**
- Create: `crates/volward-core/src/scan_tree.rs`
- Modify: `crates/volward-core/src/lib.rs`

- [ ] **Step 1: 测试 — 1000 文件全插入**

```rust
#[test]
fn inserts_all_files_without_cap() {
    let mut b = ScanTreeBuilder::new("/r");
    for i in 0..1000 {
        b.insert_file(&format!("/r/f{i}"), Some(&format!("id{i}")), 1);
    }
    let root = b.finalize();
    assert_eq!(count_files(&root), 1000);
    assert!(!b.was_aborted());
}
```

- [ ] **Step 2: 实现 `ScanTreeBuilder`（无 MAX_TREE_NODES，无 truncated 标志）**

```rust
pub struct ScanTreeBuilder { /* root, path_index */ }

impl ScanTreeBuilder {
    pub fn new(root_path: &str) -> Self { ... }
    pub fn ensure_dir(&mut self, path: &str) { ... }  // 总是插入
    pub fn insert_file(&mut self, path: &str, entry_id: &str, size: u64) { ... }
    pub fn finalize(self) -> ScanTreeNode { ... }
}
```

- [ ] **Step 3: `cargo test -p volward-core scan_tree` → PASS**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(core): ScanTreeBuilder without node count limits"
```

---

## Wave 2 — 全量 scan.rs

### Task 3: 删除 MAX_ENTRIES，全量收录

**Files:**
- Modify: `crates/volward-core/src/scan.rs`

- [ ] **Step 1: 删除 `const MAX_ENTRIES: usize = 500`**

- [ ] **Step 2: walk 回调 — 每个文件都 classify + push**

```rust
let mut tree_builder = ScanTreeBuilder::new(&roots[0].path);
let mut stats = ScanStats::default();

let mut walk = |e: RawFsEntry| -> WalkAction {
    stats.paths_seen += 1;
    if e.is_dir {
        stats.dirs_seen += 1;
        tree_builder.ensure_dir(&e.path);
        return WalkAction::Continue;
    }
    stats.files_seen += 1;
    let classified = self.classifier.classify_path(&e.path, e.size_bytes, false, &job_id);
    let id = classified.id.clone();
    entries.push(classified);
    stats.files_in_snapshot += 1;
    tree_builder.insert_file(&e.path, &id, e.size_bytes);
    WalkAction::Continue
};
```

- [ ] **Step 3: Cancel 时设置 truncated**

```rust
PlatformError::Cancelled => {
    stats.truncated = true;
    stats.incomplete_reason = Some("Scan cancelled.".into());
    warnings.push("Scan cancelled.".into());
}
```

- [ ] **Step 4: 正常完成断言一致**

```rust
debug_assert_eq!(stats.files_seen, stats.files_in_snapshot);
stats.truncated = false;
let tree = tree_builder.finalize();
```

- [ ] **Step 5: 集成测试 — temp dir 200 文件**

Run: `cargo test -p volward-core`
Expected: `files_seen == 200`, `truncated == false`

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(scan): index every walked file and directory without entry cap"
```

---

## Wave 3 — Snapshot 落盘（Isolate 安全）

### Task 4: worker 写 JSON 文件

**Files:**
- Modify: `apps/volward/lib/bridge/scan_worker.dart`
- Modify: `apps/volward/lib/volward_session.dart`

- [ ] **Step 1: scan_worker done 分支写文件**

```dart
import 'dart:convert';
import 'dart:io';

// in done handler before send:
final snap = m['snapshot'];
if (snap is Map) {
  final dir = Directory.systemTemp;
  final file = File('${dir.path}/volward-$snapshotId.json');
  await file.writeAsString(jsonEncode(snap));
  progressPort.send(<String, dynamic>{
    'type': 'done',
    'snapshot_path': file.path,
    'stats': snap['stats'],
  });
}
```

注意：worker isolate 内需在 `volwardScanIsolate` 改为 async 或用 `Isolate.run` 包装写文件；若保持同步 isolate，用 `File.writeAsStringSync`。

- [ ] **Step 2: VolwardSession 读文件**

```dart
} else if (type == 'done') {
  final path = m['snapshot_path']?.toString();
  if (path != null) {
    final raw = await File(path).readAsString();
    completer.complete(jsonDecode(raw) as Map<String, dynamic>);
    try { await File(path).delete(); } catch (_) {}
  }
}
```

- [ ] **Step 3: 手动 — Home scan 不再 OOM**

Run: `fvm flutter run -d macos` → 大目录 scan 完成

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(ui): spool full scan snapshot to temp file across isolate boundary"
```

---

## Wave 4 — Flutter 解析、筛选、虚拟 Tree

### Task 5: scan_tree fromJson + filter

**Files:**
- Modify: `apps/volward/lib/scan_tree.dart`
- Create: `apps/volward/lib/scan_tree_filter.dart`
- Create: `apps/volward/test/scan_tree_test.dart`

- [ ] **Step 1–4:** 同 v1 Task 4–5（fromSnapshotJson + pruneTree）

- [ ] **Step 5: Commit**

---

### Task 6: scan_tree_flatten + 虚拟列表

**Files:**
- Create: `apps/volward/lib/scan_tree_flatten.dart`
- Modify: `apps/volward/lib/widgets/scan_tree_view.dart`
- Modify: `apps/volward/lib/home_page.dart`

- [ ] **Step 1: 测试 flatten**

```dart
test('flatten only includes expanded branches', () {
  // root/a, root/b; expanded={root} → rows: root, a, b if a,b dirs expanded...
});
```

- [ ] **Step 2: 实现 FlatRow**

```dart
class FlatRow {
  final ScanTreeNode node;
  final int depth;
  final bool isExpanded;
}

List<FlatRow> flattenVisible(ScanTreeNode root, Set<String> expandedPaths) {
  final out = <FlatRow>[];
  void walk(ScanTreeNode n, int depth) {
    out.add(FlatRow(node: n, depth: depth, isExpanded: expandedPaths.contains(n.path)));
    if (!n.isDirectory || !expandedPaths.contains(n.path)) return;
    for (final c in n.children) walk(c, depth + 1);
  }
  walk(root, 0);
  return out;
}
```

- [ ] **Step 3: home_page 改用 SliverList.builder**

```dart
final rows = flattenVisible(displayTree, _expandedPaths);
SliverList(
  delegate: SliverChildBuilderDelegate(
    (ctx, i) => ScanTreeRow(
      row: rows[i],
      onToggleExpand: () => _toggleTreeExpand(rows[i].node.path),
      ...
    ),
    childCount: rows.length,
  ),
),
```

- [ ] **Step 4: header 全量 stats**

```dart
'Full scan: ${stats['dirs_seen']} dirs · ${stats['files_in_snapshot']} files'
if (stats['truncated'] == true) ' · Incomplete: ${stats['incomplete_reason']}'
```

- [ ] **Step 5: Run analyze + test**

Run: `cd apps/volward && fvm flutter analyze && fvm flutter test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(ui): virtualized full scan tree with flatten and sliver builder"
```

---

## Wave 5 — 验证与文档

### Task 7: 全量验收

- [ ] **Rust:** `cargo test --workspace`

- [ ] **手动 Home scan：**
  - `files_in_snapshot` 与 Finder「显示简介」数量级一致（同一 root）
  - `Library/Caches` 完整层级可见
  - Cache 筛选 prune 正确
  - 滚动 1 万+ 行不冻结

- [ ] **更新 spec 状态为「已实现 v2」**

```bash
git add docs/superpowers/specs/2026-07-23-scan-tree-finder-design.md
git commit -m "docs: mark full-scan tree spec v2 as implemented"
```

---

## Spec coverage（v2 全量）

| 要求 | Task |
|------|------|
| 无条数截断 | Task 2, 3 |
| 无 MAX_DEPTH | Task 0 |
| 全目录+全文件 tree | Task 2, 3 |
| truncated 仅 Cancel/错误 | Task 3 |
| snapshot 落盘 | Task 4 |
| 虚拟 UI | Task 6 |
| Cache prune | Task 5, 6 |

---

## Execution handoff

Plan saved to `docs/superpowers/plans/2026-07-23-scan-tree-finder.md` (**v2 全量**).

1. **Subagent-Driven（推荐）** — 每 Task 独立 subagent  
2. **Inline Execution** — 本会话按 Wave 执行  

**Which approach?**
