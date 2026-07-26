# Volward MVP 闭环补齐 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按闭环优先级补齐 Results→Confirm 选中传递、目录选择、YAML 分类规则、扫描进度 UI，使 PRD v0.1 macOS MVP 可完整演示。

**Architecture:** 不改 FRB；Flutter `VolwardSession` 集中跨 Tab 选中状态；Rust 新增 `rules` 模块加载 `desktop.yaml` 并注入 `Classifier`；Isolate worker 经 `SendPort` 回传进度 JSON。四波交付，每波可独立验证。

**Tech Stack:** Flutter 3.44 (FVM), Dart ffi, Rust 2021, serde_yaml, regex, file_selector

**Spec:** [2026-05-29-mvp-closure-design.md](../specs/2026-05-29-mvp-closure-design.md)

## Implementation Status

| 字段 | 内容 |
|------|------|
| 状态 | ✅ 已实现 |
| 收口日期 | 2026-07（单页形态；文档回写 2026-07-26） |
| 对照 | P0 筛选/排序/多选删除、P1 目录选择、P2 YAML 规则、P3 进度 UI 均已在 `main` |
| 形态变化 | 原 `features/{scan,results,confirm}` 多页已收敛为 `home_page.dart` 单页；下列 Task 步骤 checkbox 保留作历史执行说明，**不以勾选为准** |
| 验收 | PRD 闭环（扫 → 选 → 删至废纸篓 → 再扫）可演示；正式手测清单未单独归档 |

---

## File map

| Path | Responsibility |
|------|----------------|
| `apps/volward/lib/volward_session.dart` | `selectedEntryIds`, `scanProgress`, roots 状态 |
| `apps/volward/lib/features/results/results_page.dart` | 筛选 / 排序 / 多选 |
| `apps/volward/lib/features/confirm/confirm_page.dart` | 读取 session 预填选中 |
| `apps/volward/lib/features/scan/scan_page.dart` | 目录选择 + 进度展示 |
| `apps/volward/lib/bridge/scan_worker.dart` | SendPort 进度回传 |
| `crates/volward-core/src/rules.rs` | YAML 解析 `DesktopRules` |
| `crates/volward-core/src/classify.rs` | `Classifier::from_rules` |
| `crates/volward-facade/src/engine.rs` | 加载 rules 后构建 Classifier |
| `rules/desktop.yaml` | 补 `media_extensions` 段 |

---

## Wave 1 — P0: Results 筛选 / 排序 / 多选 → Confirm

### Task 1: Session 选中集

**Files:**
- Modify: `apps/volward/lib/volward_session.dart`
- Modify: `apps/volward/lib/features/confirm/confirm_page.dart`

- [ ] **Step 1: 在 VolwardSession 增加字段与方法**

```dart
// volward_session.dart — 新增
final Set<String> _selectedEntryIds = {};
Set<String> get selectedEntryIds => Set.unmodifiable(_selectedEntryIds);

void setSelectedEntryIds(Set<String> ids) {
  _selectedEntryIds
    ..clear()
    ..addAll(ids);
  notifyListeners();
}

void clearSelectedEntryIds() {
  _selectedEntryIds.clear();
  notifyListeners();
}
```

- [ ] **Step 2: ConfirmPage initState 合并 session 选中**

```dart
@override
void initState() {
  super.initState();
  _selected.addAll(widget.session.selectedEntryIds);
}
```

删除成功后（`_confirmDelete` 内 `setState(_selected.clear)` 之后）调用：

```dart
widget.session.clearSelectedEntryIds();
```

- [ ] **Step 3: 验证**

Run: `cd apps/volward && fvm flutter analyze`
Expected: No issues found

- [ ] **Step 4: Commit**

```bash
git add apps/volward/lib/volward_session.dart apps/volward/lib/features/confirm/confirm_page.dart
git commit -m "feat(ui): add cross-tab selected entry ids on session"
```

---

### Task 2: ResultsPage 交互

**Files:**
- Modify: `apps/volward/lib/features/results/results_page.dart`

- [ ] **Step 1: 改为 StatefulWidget，增加状态**

```dart
enum _SortMode { sizeDesc, sizeAsc, nameAsc }

class _ResultsPageState extends State<ResultsPage> {
  String? _categoryFilter; // null = All
  bool _deletableOnly = false;
  _SortMode _sort = _SortMode.sizeDesc;
  final Set<String> _localSelected = {};
```

- [ ] **Step 2: 实现 `_filteredSortedEntries()`**

```dart
List<Map<String, dynamic>> _filteredSortedEntries() {
  final snap = widget.session.lastSnapshot;
  if (snap == null || snap['entries'] is! List) return [];
  final raw = (snap['entries'] as List)
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  Iterable<Map<String, dynamic>> out = raw;
  if (_categoryFilter != null) {
    out = out.where((e) => e['category']?.toString() == _categoryFilter);
  }
  if (_deletableOnly) {
    out = out.where((e) => e['deletable'] == true);
  }
  final list = out.toList();
  switch (_sort) {
    case _SortMode.sizeDesc:
      list.sort((a, b) => ((b['size_bytes'] as num?) ?? 0).compareTo((a['size_bytes'] as num?) ?? 0));
    case _SortMode.sizeAsc:
      list.sort((a, b) => ((a['size_bytes'] as num?) ?? 0).compareTo((b['size_bytes'] as num?) ?? 0));
    case _SortMode.nameAsc:
      list.sort((a, b) => (a['display_name']?.toString() ?? '').compareTo(b['display_name']?.toString() ?? ''));
  }
  return list;
}
```

- [ ] **Step 3: UI — FilterChip 行 + Sort Dropdown + CheckboxListTile 列表**

Category chips: `All`, `Cache`, `Temp`, `Media`, `Unknown`, `Deletable only` toggle.

底部按钮：

```dart
FilledButton(
  onPressed: _localSelected.isEmpty ? null : () {
    widget.session.setSelectedEntryIds(_localSelected);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_localSelected.length} items ready on Confirm tab')),
    );
  },
  child: Text('Continue to Confirm (${_localSelected.length})'),
)
```

Checkbox 仅当 `deletable == true` 时可勾选。

- [ ] **Step 4: 验证**

Run: `cd apps/volward && fvm flutter analyze`
Expected: No issues found

- [ ] **Step 5: Commit**

```bash
git add apps/volward/lib/features/results/results_page.dart
git commit -m "feat(ui): results filter, sort, and multi-select for confirm"
```

---

## Wave 2 — P1: 目录选择器

### Task 3: 添加 file_selector 依赖

**Files:**
- Modify: `apps/volward/pubspec.yaml`

- [ ] **Step 1: 添加依赖**

```yaml
dependencies:
  file_selector: ^1.0.3
```

- [ ] **Step 2: 安装**

Run: `cd apps/volward && fvm flutter pub get`
Expected: Got dependencies!

- [ ] **Step 3: Commit**

```bash
git add apps/volward/pubspec.yaml apps/volward/pubspec.lock
git commit -m "chore(flutter): add file_selector for directory picking"
```

---

### Task 4: ScanPage 目录选择与传参

**Files:**
- Modify: `apps/volward/lib/volward_session.dart`
- Modify: `apps/volward/lib/features/scan/scan_page.dart`

- [ ] **Step 1: Session 保存 scan roots**

```dart
List<String> _scanRoots = [];
List<String> get scanRoots => List.unmodifiable(_scanRoots);

void setScanRoots(List<String> roots) {
  _scanRoots = List.from(roots);
  notifyListeners();
}
```

`runScan` 改为使用 `_scanRoots`（若 empty 则传 `const []` 保持 HOME 默认）。

- [ ] **Step 2: ScanPage 选目录 UI**

```dart
import 'package:file_selector/file_selector.dart';

// state
String? _chosenPath;

Future<void> _pickFolder() async {
  final path = await getDirectoryPath(confirmButtonText: 'Select');
  if (path != null) {
    setState(() => _chosenPath = path);
    widget.session.setScanRoots([path]);
  }
}
```

显示：`Scan target: ${_chosenPath ?? 'Home (default)'}`

按钮：`Choose folder…` / `Reset to Home`（clear roots）

- [ ] **Step 3: macOS entitlements 检查**

确认 `apps/volward/macos/Runner/DebugProfile.entitlements` 与 `Release.entitlements` 含：

```xml
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

若无则添加。

- [ ] **Step 4: 验证**

Run: `cd apps/volward && fvm flutter analyze && fvm flutter build macos --debug`
Expected: analyze clean; build succeeds

- [ ] **Step 5: Commit**

```bash
git add apps/volward/lib/volward_session.dart apps/volward/lib/features/scan/scan_page.dart apps/volward/macos/Runner/*.entitlements
git commit -m "feat(scan): let user pick directory via file_selector"
```

---

## Wave 3 — P2: YAML 规则加载

### Task 5: rules 模块 + serde_yaml

**Files:**
- Create: `crates/volward-core/src/rules.rs`
- Modify: `crates/volward-core/src/lib.rs`
- Modify: `crates/volward-core/Cargo.toml`
- Modify: `rules/desktop.yaml`

- [ ] **Step 1: 添加依赖**

`crates/volward-core/Cargo.toml`:

```toml
serde_yaml = "0.9"
```

Workspace 根 `Cargo.toml` 的 `[workspace.dependencies]` 若无则直接 crate 内写版本。

- [ ] **Step 2: 写 failing test**

`crates/volward-core/src/rules.rs`:

```rust
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct DesktopRules {
    pub version: u32,
    pub protected_prefixes: Vec<String>,
    pub cache_patterns: Vec<String>,
    pub temp_patterns: Vec<String>,
    #[serde(default = "default_media_extensions")]
    pub media_extensions: Vec<String>,
}

fn default_media_extensions() -> Vec<String> {
    vec![
        ".jpg".into(), ".jpeg".into(), ".png".into(), ".gif".into(),
        ".mp4".into(), ".mov".into(), ".pdf".into(), ".dmg".into(),
    ]
}

impl DesktopRules {
    pub fn parse_yaml(yaml: &str) -> Result<Self, serde_yaml::Error> {
        serde_yaml::from_str(yaml)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_desktop_yaml_fixture() {
        let yaml = r#"
version: 1
protected_prefixes:
  - /System
cache_patterns:
  - "(?i)/Caches/"
temp_patterns:
  - "(?i)/tmp/"
"#;
        let rules = DesktopRules::parse_yaml(yaml).unwrap();
        assert_eq!(rules.version, 1);
        assert!(rules.protected_prefixes.contains(&"/System".to_string()));
        assert_eq!(rules.cache_patterns.len(), 1);
    }
}
```

`lib.rs`: `pub mod rules;`

- [ ] **Step 3: Run test**

Run: `cd /Users/liminglin/Funny/molars/volward && cargo test -p volward-core rules::`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add crates/volward-core/Cargo.toml crates/volward-core/src/rules.rs crates/volward-core/src/lib.rs
git commit -m "feat(core): parse desktop.yaml into DesktopRules"
```

---

### Task 6: Classifier::from_rules

**Files:**
- Modify: `crates/volward-core/src/classify.rs`
- Modify: `crates/volward-facade/src/engine.rs`
- Modify: `rules/desktop.yaml`

- [ ] **Step 1: 写 failing test**

```rust
#[test]
fn from_rules_classifies_yaml_cache_pattern() {
    use crate::rules::DesktopRules;
    let rules = DesktopRules::parse_yaml(r#"
version: 1
protected_prefixes: []
cache_patterns: ["(?i)/Caches/"]
temp_patterns: []
"#).unwrap();
    let c = Classifier::from_rules(&rules, &[]);
    let e = c.classify_path("/Users/x/Library/Caches/foo", 10, false, "t");
    assert_eq!(e.category, EntryCategory::Cache);
}
```

- [ ] **Step 2: 实现 `from_rules`**

```rust
impl Classifier {
    pub fn from_rules(rules: &crate::rules::DesktopRules, extra_protected: &[String]) -> Self {
        let mut protected_prefixes: Vec<String> = extra_protected.to_vec();
        protected_prefixes.extend(rules.protected_prefixes.clone());
        let cache_re = Regex::new(&rules.cache_patterns.join("|")).expect("cache patterns");
        let temp_re = Regex::new(&rules.temp_patterns.join("|")).expect("temp patterns");
        let media_exts: Vec<&str> = rules.media_extensions.iter().map(String::as_str).collect();
        Self { cache_re, temp_re, media_exts, protected_prefixes }
    }
}
```

注意：多个 pattern 用 `|` 合并时需确保 YAML 内已是完整 regex；或逐条 compile 后 `OR` match — 推荐逐条：

```rust
let cache_res: Vec<Regex> = rules.cache_patterns.iter()
    .map(|p| Regex::new(p).expect("cache pattern"))
    .collect();
```

`classify_path` 内改为 `cache_res.iter().any(|re| re.is_match(path))`。

- [ ] **Step 3: Engine 加载 rules**

`engine.rs` `start_scan` 内：

```rust
let rules_path = std::env::var("VOLWARD_RULES_PATH").unwrap_or_else(|_| {
    // 相对 workspace：CARGO_MANIFEST_DIR/../../rules/desktop.yaml
    format!("{}/../../rules/desktop.yaml",
        env!("CARGO_MANIFEST_DIR"))
});
let rules_yaml = std::fs::read_to_string(&rules_path)
    .map_err(|e| format!("rules: {e}"))?; // 或 warn + fallback Classifier::new
let rules = volward_core::rules::DesktopRules::parse_yaml(&rules_yaml)
    .map_err(|e| format!("rules parse: {e}"))?;
let classifier = Classifier::from_rules(
    &rules,
    self.platform.protected_prefixes(),
);
```

开发时若路径解析失败，可 fallback `Classifier::new(platform.protected_prefixes())` 并 push warning 到 snapshot — 计划采用 **fail loud in test, fallback with warning in engine** 以免 Flutter 打包路径差异。

更稳妥：`DesktopPlatform::default_rules_path()` 返回 `Option<PathBuf>`，engine 优先 env，其次 compile-time include。

**最终方案（本 Task）：** engine 使用：

```rust
fn load_classifier(platform: &DesktopPlatform) -> Classifier {
    let path = std::env::var("VOLWARD_RULES_PATH").ok()
        .map(PathBuf::from)
        .or_else(|| {
            let p = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("../../rules/desktop.yaml");
            p.exists().then_some(p)
        });
    if let Some(path) = path {
        if let Ok(yaml) = std::fs::read_to_string(&path) {
            if let Ok(rules) = volward_core::rules::DesktopRules::parse_yaml(&yaml) {
                return Classifier::from_rules(&rules, platform.protected_prefixes());
            }
        }
    }
    Classifier::new(platform.protected_prefixes().to_vec())
}
```

- [ ] **Step 4: 更新 desktop.yaml**

```yaml
media_extensions:
  - ".jpg"
  - ".jpeg"
  - ".png"
  - ".gif"
  - ".mp4"
  - ".mov"
  - ".pdf"
  - ".dmg"
```

- [ ] **Step 5: Run tests**

Run: `cargo test -p volward-core && cargo test -p volward-facade`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add crates/volward-core/src/classify.rs crates/volward-facade/src/engine.rs rules/desktop.yaml
git commit -m "feat(core): classify from desktop.yaml rules with platform prefix merge"
```

---

## Wave 4 — P3: 扫描进度 UI

### Task 7: Isolate SendPort 进度

**Files:**
- Modify: `apps/volward/lib/bridge/scan_worker.dart`
- Modify: `apps/volward/lib/volward_session.dart`
- Modify: `apps/volward/lib/features/scan/scan_page.dart`

- [ ] **Step 1: 定义 ScanWorkerArgs**

```dart
class ScanWorkerArgs {
  ScanWorkerArgs({required this.roots, required this.progressPort});
  final List<String> roots;
  final SendPort progressPort;
}

@pragma('vm:entry-point')
Map<String, dynamic>? volwardScanWorker(ScanWorkerArgs args) {
  final bridge = VolwardNativeBridge.open();
  final engine = bridge.createEngine();
  try {
    final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}';
    // 简化：worker 内无法 poll engine progress 时，发送 synthetic heartbeat
    final timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      args.progressPort.send(<String, dynamic>{
        'phase': 'Walking',
        'paths_seen': 0,
        'current_path': 'Scanning…',
      });
    });
    try {
      bridge.startScan(engine, jobId, args.roots);
      return bridge.getLastSnapshot(engine);
    } finally {
      timer.cancel();
    }
  } finally {
    bridge.freeEngine(engine);
  }
}
```

**改进（同 Task 内 Step 2）：** 在 Rust C API 增加 `volward_get_last_progress_json` 的 worker 轮询：

```dart
Timer.periodic(const Duration(milliseconds: 300), (t) {
  final ptr = bridge.getLastProgress(engine); // 需在 native_bridge 暴露
  if (ptr != null) args.progressPort.send(ptr);
});
```

`native_bridge.dart` 增加 `getLastProgress` lookup `volward_get_last_progress_json`。

- [ ] **Step 2: Session 监听 ReceivePort**

```dart
Map<String, dynamic>? _scanProgress;
Map<String, dynamic>? get scanProgress => _scanProgress;

// runScan 内：
final receivePort = ReceivePort();
_lastSnapshot = await Isolate.run(() => volwardScanWorker(
  ScanWorkerArgs(roots: _scanRoots, progressPort: receivePort.sendPort),
));
// 改为 compute 模式：
final receivePort = ReceivePort();
final isolate = await Isolate.spawn(...); // 或 Isolate.run 不支持 port 传入时：

final result = await Isolate.run(() async {
  // 不行 — Isolate.run 单返回值
});
```

**修正：** `Isolate.run` 只接受单返回值，**必须改用**：

```dart
final receivePort = ReceivePort();
await Isolate.spawn(_scanIsolateEntry, [receivePort.sendPort, _scanRoots]);
// 监听 receivePort 直到收到 '__done__' 或 snapshot
```

或：

```dart
Future<Map<String, dynamic>?> runScan(...) async {
  final progressPort = ReceivePort();
  final completer = Completer<Map<String, dynamic>?>();
  late final StreamSubscription sub;
  sub = progressPort.listen((msg) {
    if (msg is Map && msg['_type'] == 'progress') {
      _scanProgress = Map<String, dynamic>.from(msg)..remove('_type');
      notifyListeners();
    } else if (msg is Map && msg['_type'] == 'done') {
      _lastSnapshot = Map<String, dynamic>.from(msg['snapshot'] as Map);
      completer.complete(_lastSnapshot);
      sub.cancel();
      progressPort.close();
    }
  });
  await Isolate.spawn(scanIsolateMain, [progressPort.sendPort, _scanRoots]);
  return completer.future;
}
```

`scan_worker.dart` 顶部：

```dart
@pragma('vm:entry-point')
void scanIsolateMain(List<dynamic> args) {
  final sendPort = args[0] as SendPort;
  final roots = (args[1] as List).cast<String>();
  // poll progress + send done
}
```

- [ ] **Step 3: ScanPage 展示进度**

```dart
if (widget.session.scanning) ...[
  const LinearProgressIndicator(),
  if (widget.session.scanProgress != null) ...[
    Text('Paths: ${widget.session.scanProgress!['paths_seen']}'),
    Text(
      widget.session.scanProgress!['current_path']?.toString() ?? '',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  ],
],
```

- [ ] **Step 4: native_bridge getLastProgress**

```dart
Map<String, dynamic>? getLastProgress(Pointer<Void> engine) {
  final ptr = _getLastProgressJson(engine);
  if (ptr == nullptr) return null;
  return _decodeJsonPtr(ptr);
}
```

Worker 内 loop：`startScan` 是阻塞的 — 在 **spawn 前** 无法 poll。因此 worker 架构改为：

```dart
void scanIsolateMain(List<dynamic> args) async {
  final sendPort = args[0] as SendPort;
  final roots = args[1] as List<String>;
  final bridge = VolwardNativeBridge.open();
  final engine = bridge.createEngine();
  final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}';
  // 在单独 isolate 中 startScan 阻塞；progress 只能在 scan 完成后发送 Done
  // → 必须用 Rust 侧 walk 中更频繁 on_progress + 第二个 isolate 轮询
}
```

**实际可行方案：** worker 内 `startScan` 阻塞期间无法 Dart 轮询。Rust `walk_entries` 已调用 `on_progress` 但 engine 存 `last_progress` — worker 的 engine 与 UI 不同。

**最终设计（本计划采用）：** 在 worker 用 **双线程**：Dart isolate 内 spawn 一个 `Timer` 不可能与阻塞 FFI 并发同一 isolate。

→ **Rust 小改：** `volward_start_scan` 改为非阻塞（返回 job_id，后台线程 scan）— **超出 YAGNI**。

→ **本 Task 采用 MVP：** worker 发送阶段事件：`Discovering` → `Walking (please wait)` → `Done`；ScanPage 显示 indeterminate + `paths_seen` 仅在 Done 后 — **不够好**。

**更好 MVP：** 修改 `scan_worker` 为 Rust 内 `on_progress` 写共享 — 不可跨 isolate。

**计划锁定方案 P3A-精简：** Engine `start_scan` 在 **blocking 调用前** 无法 progress；在 worker isolate 中：

1. 启动 `Isolate.spawn` 的子逻辑改为：**不用 Isolate.run**，用 `ReceivePort` + `Isolate.spawn`
2. Worker 调用 blocking `startScan` 之前，向 port 发送 `{phase: Discovering}`
3. Blocking 期间 UI 显示 indeterminate
4. 完成后发送 `{phase: Done, paths_seen: N}` 从 snapshot entry count 推断

若需真实 paths_seen mid-flight：**Task 7b（可选 follow-up）** 将 `start_scan` 改为 Rust 后台线程 + poll API。

**本计划 Task 7 范围：** 
- 暴露 `getLastProgress` FFI（已有 C API）
- Worker：`Timer` 不可与 blocking FFI 并行 → 文档注明 **Phase 1 仅 pre/post 进度 + indeterminate**
- **追加 Rust 小改：** `ScanOrchestrator` 每 1000 paths 调用 `on_progress`（已有），engine 存 progress；**worker 改用 `std::thread` 跑 `startScan`，主 worker isolate `loop { sleep; getLastProgress; send }`** — 可行！

```dart
void scanIsolateMain(List<dynamic> args) {
  final sendPort = args[0] as SendPort;
  final roots = args[1] as List<String>;
  final bridge = VolwardNativeBridge.open();
  final engine = bridge.createEngine();
  final jobId = 'job-...';
  final done = Completer<void>();
  Thread.run(() { // 不存在 Dart Thread
```

Dart 无 Thread — 用 **two isolates**：
- Isolate A: poll `getLastProgress` every 300ms, forward to SendPort
- Isolate B: blocking startScan

```dart
final scanDonePort = ReceivePort();
await Isolate.spawn(_scanBlocking, [scanDonePort.sendPort, roots]);
// main listener merges progress from poll isolate
```

**简化落地方案写入 Step 2：**

```dart
@pragma('vm:entry-point')
void volwardScanIsolate(List<dynamic> init) {
  final replyPort = init[0] as SendPort;
  final roots = (init[1] as List).cast<String>();
  final bridge = VolwardNativeBridge.open();
  final engine = bridge.createEngine();
  final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}';
  replyPort.send({'type': 'progress', 'phase': 'Discovering'});
  final snapshotId = bridge.startScan(engine, jobId, roots);
  final snap = bridge.getLastSnapshot(engine);
  bridge.freeEngine(engine);
  replyPort.send({'type': 'done', 'snapshot': snap, 'snapshot_id': snapshotId});
}
```

Session 监听 progress 仅 Discovering → Done（两阶段）。**Task 7 标题改为「扫描阶段反馈」**，真实 paths_seen 作为 **Follow-up Task 8（可选）**：Rust 非阻塞 scan。

为符合 spec P3A，在计划中增加 **Task 8（Optional）** Rust background scan thread。

- [ ] **Step 4: 验证 + Commit**

Run: `fvm flutter analyze && cargo test`
Commit: `feat(scan): isolate spawn with scan phase progress events`

---

### Task 8（Optional）: Rust 非阻塞 scan + 真实 progress poll

**Files:**
- Modify: `crates/volward-facade/src/engine.rs`
- Modify: `crates/volward-facade/src/capi.rs`
- Modify: `apps/volward/lib/bridge/scan_worker.dart`

- [ ] **Step 1: `start_scan_async` 返回立即，内部 `std::thread::spawn` 跑 orchestrator**
- [ ] **Step 2: C API `volward_is_scan_running` + poll progress**
- [ ] **Step 3: Worker isolate 300ms poll loop**
- [ ] **Step 4: cargo test + flutter analyze + commit**

---

## Wave 5 — 验收

### Task 9: MVP 闭环手测清单

- [x] **Step 1: 闭环能力已落地**（单页：选目录/Home → 扫 → 筛选多选 → 删至废纸篓 → 可选复扫；正式书面手测记录未单独归档）

- [x] **Step 2: README** 已随后续能力更新（含渐进式扫描）

- [x] **Step 3:** 本 plan / 对应 spec 于 2026-07-26 标记为已实现

---

## Spec coverage self-review

| Spec 要求 | Task |
|-----------|------|
| P0 Results 筛选排序多选 | Task 1–2 |
| P0 → Confirm 预填 | Task 1 |
| P1 目录选择 | Task 3–4 |
| P2 YAML + from_rules | Task 5–6 |
| P3 扫描进度 | Task 7 (+ optional 8) |
| 保护路径 deletable=false | Task 6 单测 + Task 9 |
| FRB 不迁移 | 无 Task |

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-29-mvp-closure.md`.

**Two execution options:**

1. **Subagent-Driven（推荐）** — 每 Task 派生子 agent，Task 间 review  
2. **Inline Execution** — 本会话按 Wave 批量执行，Wave 末 checkpoint

**Which approach?**
