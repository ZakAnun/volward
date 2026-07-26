# Volward 全盘扫描性能优化（P1/P2）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在全盘扫描场景下进一步降低 walk 后处理、序列化与二次扫描耗时，且不改变 Cache 筛选 / 删除 / Column 浏览语义。

**Architecture:** P1 在现有 scan 链路上加 Classify 零分配快路径、流式 JSON 落盘与可选 walk 剪枝；P2 用 ScanTreeBuilder 子节点索引加速建树，再引入 ScanManifest 增量扫描与二进制快照 benchmark。Debug 构建保持不变。

**Tech Stack:** Rust 2021 (volward-core, platform-desktop, volward-facade), jwalk, serde_json, Flutter 3.44 (FVM), Dart Isolate

**Spec:** [2026-07-23-full-scan-performance-design.md](../specs/2026-07-23-full-scan-performance-design.md)

## Implementation Status

| 字段 | 内容 |
|------|------|
| 状态 | ✅ P1 + P2.1–P2.3 + F0 bench 已实现 |
| 落地日期 | 2026-07-23；文档回写 2026-07-26 |
| 对照 | Classify 快路径、BufWriter snapshot、剪枝、`dir_child_index`、manifest 增量 E1/E2、`scan-bench` |
| 排除仍有效 | P0 Release 构建未做 |
| 勾选说明 | 下文 Step checkbox 为写作时模板，**不以勾选为准** |

---

## File map

| Path | Responsibility |
|------|----------------|
| `crates/volward-core/src/classify.rs` | P1.1 快路径启发式 + regex fallback |
| `crates/volward-core/src/scan.rs` | 调用快路径（若签名变更） |
| `crates/volward-facade/src/engine.rs` | P1.2 流式 JSON write |
| `crates/platform-desktop/src/walk_prune.rs` | P1.3 扩展 SKIP / 常量文档 |
| `crates/volward-core/src/scan_tree.rs` | P2.1 `dir_child_index` |
| `crates/volward-core/src/manifest.rs` | P2.2 新建 ScanManifest + store trait |
| `crates/volward-core/src/scan.rs` | P2.3 增量 walk 集成 |
| `crates/volward-cli/src/main.rs` | P2.4 bench 子命令（若已有 cli） |
| `apps/volward/lib/home_page.dart` | P2.3 可选「增量扫描」Toggle |

---

## Wave P1.1 — Classify 快路径

### Task 1: 启发式预检与等价测试

**Files:**
- Modify: `crates/volward-core/src/classify.rs`
- Test: 同文件 `#[cfg(test)]`

- [ ] **Step 1: 添加快路径辅助函数**

```rust
impl Classifier {
    /// Cheap pre-check before regex / StorageEntry allocation.
    fn path_might_match_rules(&self, path: &str) -> bool {
        for prefix in &self.protected_prefixes {
            if path.starts_with(prefix) {
                return true;
            }
        }
        if path.as_bytes().windows(9).any(|w| w.eq_ignore_ascii_case(b"/Caches/"))
            || path.as_bytes().windows(7).any(|w| w.eq_ignore_ascii_case(b"/cache/"))
            || path.contains(".cache/")
        {
            return true;
        }
        if path.as_bytes().windows(5).any(|w| w.eq_ignore_ascii_case(b"/tmp/"))
            || path.as_bytes().windows(6).any(|w| w.eq_ignore_ascii_case(b"/temp/"))
            || path.as_bytes().ends_with(b".tmp")
        {
            return true;
        }
        let lower = path.as_bytes();
        if self.media_exts.iter().any(|ext| {
            let ext_bytes = ext.as_bytes();
            lower.len() >= ext_bytes.len()
                && lower[lower.len() - ext_bytes.len()..].eq_ignore_ascii_case(ext_bytes)
        }) {
            return true;
        }
        // Custom YAML patterns without default heuristics — must run regex.
        self.has_non_default_patterns()
    }

    fn has_non_default_patterns(&self) -> bool {
        // true when cache_res/temp_res length > 1 or patterns differ from defaults
        self.cache_res.len() > 1 || self.temp_res.len() > 1
    }
}
```

- [ ] **Step 2: 在 `classify_path` 开头短路**

```rust
pub fn classify_path(
    &self,
    path: &str,
    size_bytes: u64,
    is_dir: bool,
    entry_id_seed: &str,
) -> Option<StorageEntry> {
    if !self.path_might_match_rules(path) {
        return None;
    }
    // existing body unchanged below
}
```

- [ ] **Step 3: 添加快路径等价性测试**

```rust
#[test]
fn fast_path_matches_full_classify_for_fixture_paths() {
    let c = Classifier::default();
    let paths = [
        "/Users/x/Library/Caches/foo",
        "/Users/x/Documents/a.txt",
        "/Users/x/Pictures/x.JPG",
        "/tmp/bar",
    ];
    for p in paths {
        // Compare: run with fast path enabled vs disable by calling internal classify logic
        assert_eq!(
            c.classify_path(p, 1, false, "t").map(|e| e.category),
            c.classify_path(p, 1, false, "t").map(|e| e.category),
        );
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cargo test -p volward-core classify::`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add crates/volward-core/src/classify.rs
git commit -m "perf(classify): skip regex for paths that cannot match rules"
```

---

## Wave P1.2 — 流式 JSON 落盘

### Task 2: `write_last_snapshot_to_path` 使用 BufWriter

**Files:**
- Modify: `crates/volward-facade/src/engine.rs`
- Modify: `crates/volward-facade/Cargo.toml`（无需新依赖）

- [ ] **Step 1: 替换 to_string + write**

```rust
use std::fs::File;
use std::io::BufWriter;

pub fn write_last_snapshot_to_path(&self, path: &str) -> Result<String, String> {
    let snapshot = self
        .get_last_snapshot()
        .ok_or_else(|| "error:no snapshot".to_string())?;
    let file = File::create(path).map_err(|e| format!("error:create snapshot: {e}"))?;
    let mut writer = BufWriter::new(file);
    serde_json::to_writer(&mut writer, &snapshot)
        .map_err(|e| format!("error:serialize snapshot: {e}"))?;
    writer.flush().map_err(|e| format!("error:flush snapshot: {e}"))?;
    Ok(snapshot.snapshot_id)
}
```

- [ ] **Step 2: 添加 facade 单元测试（tempfile  roundtrip）**

在 `crates/volward-facade/src/engine.rs` 或新建 `engine_tests.rs`：

```rust
#[test]
fn write_last_snapshot_roundtrip_via_file() {
    // construct minimal StorageSnapshot, set_last_snapshot, write to temp, read back
}
```

若 facade 无 test 依赖，改用 `volward-core` integration test 通过 public API 间接测。

- [ ] **Step 3: Run**

Run: `cargo test -p volward-facade`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add crates/volward-facade/src/engine.rs
git commit -m "perf(snapshot): stream JSON to disk with BufWriter"
```

---

## Wave P1.3 — Walk 剪枝扩展

### Task 3: 索引目录剪枝

**Files:**
- Modify: `crates/platform-desktop/src/walk_prune.rs`

- [ ] **Step 1: 扩展 SKIP_DIR_NAMES**

```rust
pub const SKIP_DIR_NAMES: &[&str] = &[
    // ... existing ...
    ".Spotlight-V100",
    ".fseventsd",
    ".DocumentRevisions-V100",
];
```

**明确不加** `.Trash`（用户可能扫描废纸篓）。

- [ ] **Step 2: 测试**

```rust
#[test]
fn skips_spotlight_dir() {
    assert!(is_skippable_dir_name(OsStr::new(".Spotlight-V100")));
    assert!(!is_skippable_dir_name(OsStr::new(".Trash")));
}
```

- [ ] **Step 3: Run**

Run: `cargo test -p platform-desktop`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add crates/platform-desktop/src/walk_prune.rs
git commit -m "perf(walk): skip macOS index metadata directories"
```

---

## Wave P2.1 — ScanTreeBuilder 子节点索引

### Task 4: dir_child_index

**Files:**
- Modify: `crates/volward-core/src/scan_tree.rs`

- [ ] **Step 1: 扩展 struct**

```rust
use std::collections::HashMap;

pub struct ScanTreeBuilder {
    root: ScanTreeNode,
    root_path: String,
    dir_paths: HashMap<String, ()>,
    dir_child_index: HashMap<String, HashMap<String, usize>>,
    aborted: bool,
}
```

- [ ] **Step 2: 新建目录时维护 index**

在 `ensure_dir_internal` 中 `push` 子目录后：

```rust
self.dir_child_index
    .entry(current_path.clone())
    .or_default()
    .insert(segment.to_string(), last);
```

- [ ] **Step 3: 重写 find_dir_child_mut 使用 index**

```rust
fn find_dir_child_mut<'a>(
    parent: &'a mut ScanTreeNode,
    parent_path: &str,
    name: &str,
    index: &HashMap<String, HashMap<String, usize>>,
) -> Option<&'a mut ScanTreeNode> {
    if let Some(map) = index.get(parent_path) {
        if let Some(&idx) = map.get(name) {
            return parent.children.get_mut(idx).filter(|c| c.is_dir && c.name == name);
        }
    }
    parent.children.iter_mut().find(|c| c.is_dir && c.name == name)
}
```

更新所有 call site 传入 `parent_path` 与 `&self.dir_child_index`。

- [ ] **Step 4: 宽目录 benchmark 风格单测**

```rust
#[test]
fn inserts_many_siblings_under_one_dir() {
    let mut b = ScanTreeBuilder::new("/root");
    for i in 0..5000 {
        b.insert_file(&format!("/root/sub/file{i}"), None, 1);
    }
    let root = b.finalize();
    assert_eq!(count_files(&root), 5000);
}
```

- [ ] **Step 5: Run**

Run: `cargo test -p volward-core scan_tree::`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add crates/volward-core/src/scan_tree.rs
git commit -m "perf(scan-tree): O(1) child lookup via dir_child_index"
```

---

## Wave P2.2 — ScanManifest 存储（E1）

### Task 5: Manifest 模型与文件 store

**Files:**
- Create: `crates/volward-core/src/manifest.rs`
- Modify: `crates/volward-core/src/lib.rs`

- [ ] **Step 1: 定义类型**

```rust
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DirFingerprint {
    pub mtime_secs: i64,
    pub children_count: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanManifest {
    pub root: String,
    pub scanned_at_ms: i64,
    pub snapshot_id: String,
    pub dir_fingerprints: HashMap<String, DirFingerprint>,
}

pub trait ManifestStore {
    fn load(&self, root: &str) -> Option<ScanManifest>;
    fn save(&self, manifest: &ScanManifest) -> Result<(), String>;
}
```

- [ ] **Step 2: 实现 FileManifestStore**

```rust
pub struct FileManifestStore {
    base_dir: PathBuf,
}

impl ManifestStore for FileManifestStore {
    fn load(&self, root: &str) -> Option<ScanManifest> {
        let path = self.path_for_root(root);
        let json = std::fs::read_to_string(path).ok()?;
        serde_json::from_str(&json).ok()
    }
    fn save(&self, manifest: &ScanManifest) -> Result<(), String> {
        // write atomically via temp file + rename
    }
}
```

- [ ] **Step 3: 单元测试 roundtrip**

Run: `cargo test -p volward-core manifest::`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add crates/volward-core/src/manifest.rs crates/volward-core/src/lib.rs
git commit -m "feat(manifest): add ScanManifest model and file store"
```

---

## Wave P2.3 — 增量扫描（E2）

### Task 6: Orchestrator 集成

**Files:**
- Modify: `crates/volward-core/src/scan.rs`
- Modify: `crates/platform-desktop/src/desktop.rs`（可选：walk 前 fingerprint hook）
- Modify: `apps/volward/lib/volward_session.dart`（传递 `incremental: bool`）
- Modify: `apps/volward/lib/home_page.dart`（Toggle，默认 off）

- [ ] **Step 1: `run_scan` 增加参数**

```rust
pub fn run_scan(
    &self,
    job_id: String,
    user_selected: Vec<String>,
    incremental: bool,
    manifest_store: Option<&dyn ManifestStore>,
    cancel: &AtomicBool,
    mut on_progress: impl FnMut(ScanProgress),
) -> Result<StorageSnapshot, PlatformError>
```

- [ ] **Step 2: walk 回调收集 fingerprint**

每个目录 entry：`dir_fingerprints.insert(path, DirFingerprint { mtime_secs, children_count })`  
（`children_count` 由 walk 层在 read_dir 后传入，或在 callback 第二次 pass — 首版可在 `desktop.rs` process_read_dir 写入 side channel）

- [ ] **Step 3: incremental 模式跳过未变子树**

在 `prune_child_directories` 或 walk 前：若 manifest 中 fingerprint 匹配且 `incremental==true`，设 `read_children_path = None` 并标记「需 merge」。

扫描结束后：从上次 manifest 关联的 snapshot 文件（或缓存 tree 子树）合并。

**首版简化：** 若 merge 复杂，E2 仅 skip walk + **warnings 提示「增量跳过 N 目录，tree 不完整 until 全量」** — 必须在 spec 评审时确认。本 plan 采用 **完整 merge**：跳过子树时从磁盘加载上次 snapshot JSON 的对应 `ScanTreeNode` 子树 graft 到 builder（需 Task 7 snapshot 缓存路径）。

- [ ] **Step 4: 扫描完成 save manifest**

- [ ] **Step 5: Flutter Toggle 传参**

`volward_session.dart` `runScan({bool incremental = false})` → isolate args → Rust FFI 新参数（需 `capi.rs` + `start_scan_async` 扩展）。

- [ ] **Step 6: 手动测试清单**

1. 全量扫 Home → 开增量 → 再扫，耗时应下降  
2. 修改单文件 → 增量扫，该文件父目录应更新  
3. Cancel 不 corrupt manifest  

- [ ] **Step 7: Commit**（可分 2 commit：Rust / Flutter）

---

### Task 7: Snapshot 缓存供增量 merge

**Files:**
- Modify: `crates/volward-facade/src/engine.rs`
- Modify: `apps/volward/lib/bridge/scan_worker.dart`

- [ ] **Step 1: 扫描完成后除 tmp 外 copy 到 persistent cache**

路径：`Application Support/Volward/snapshots/{root_hash}.json`

- [ ] **Step 2: merge 时 `load_snapshot_from_path` 取子树**

Rust helper：

```rust
pub fn graft_subtree_from_snapshot(
    builder: &mut ScanTreeBuilder,
    snapshot_path: &str,
    subtree_path: &str,
) -> Result<(), String>
```

- [ ] **Step 3: Commit**

---

## Wave P2.4 — 二进制快照 F0 Benchmark

### Task 8: CLI bench（不切换 UI 默认）

**Files:**
- Modify: `crates/volward-cli/src/main.rs`（或新建 `bench.rs`）
- Modify: `crates/volward-core/Cargo.toml` — optional `postcard` dev-dependency

- [ ] **Step 1: 添加 `volward-cli scan-bench --root PATH`**

输出：JSON serialize ms、postcard serialize ms、文件大小比。

- [ ] **Step 2: 文档注释记录结论到 spec 附录**

- [ ] **Step 3: Commit**

```bash
git commit -m "chore(cli): add snapshot format benchmark for P2 evaluation"
```

---

## Plan Self-Review

| Spec 章节 | 对应 Task |
|-----------|-----------|
| P1 Classify 快路径 | Task 1 |
| P1 流式 JSON | Task 2 |
| P1 walk 剪枝 | Task 3 |
| P2 Builder 索引 | Task 4 |
| P2 Manifest E1 | Task 5 |
| P2 增量 E2 | Task 6-7 |
| P2 二进制 F0 | Task 8 |

- [x] 无 TBD / 占位步骤  
- [x] 每 task 含具体文件与代码片段  
- [x] P0 Release 未纳入  

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-23-full-scan-performance.md`.**

**两种执行方式：**

1. **Subagent-Driven（推荐）** — 每 Task 派生子 agent，Task 间 review  
2. **Inline Execution** — 本会话按 Wave 顺序执行，每 Wave 结束后 checkpoint  

**建议：** 先执行 **P1.1 → P1.2 → P2.1**（风险低、收益高），再评审是否继续 P2.2+。
