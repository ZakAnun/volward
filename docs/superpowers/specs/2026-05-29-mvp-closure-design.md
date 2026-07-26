# Volward MVP 闭环补齐 — 设计规格

| 字段 | 内容 |
|------|------|
| 日期 | 2026-05-29 |
| 状态 | ✅ 已实现（2026-07 单页形态收口） |
| 依赖 | [PRD v0.1](../../../../docs/volward/PRD.md) · [IMPLEMENTATION-PLAN](../../../../docs/volward/IMPLEMENTATION-PLAN.md) |
| 基线 commit | `6d96196`（W3 删除闭环 + FDA 引导已落地） |
| 落地说明 | P0–P3 均已在 `main`；原多 Tab（Scan/Results/Confirm）已收敛为 `home_page.dart` 单页，闭环语义不变 |

---

## 1. 背景

PRD v0.1 定义 macOS MVP 成功标准：

> FDA 授权下：**扫描 → 列表 → 删至废纸篓 → 再扫**，释放量可见。

当前状态（`6d96196`）：

| 链路环节 | 状态 |
|----------|------|
| S1 总览 + FDA | ✅ |
| S2 扫描（Isolate 后台） | ⚠️ 仅 `$HOME`，无进度 UI |
| S3 结果列表 | ⚠️ 仅 Top 50 只读，无筛选/排序/多选 |
| S4 确认删除 + 复扫 | ✅ |
| 分类规则 YAML | ❌ 硬编码 regex |
| FRB | ❌（技术债，本阶段不迁移） |

**核心问题：** 删除闭环在工程上已通，但 **用户无法高效地从 S3 找到并选中要删的项**，且 **无法选择扫描目录**、**分类质量未配置化**。本规格补齐这四块，按闭环优先级排序实施。

---

## 2. 闭环优先级排序

| 优先级 | 工作项 | 闭环角色 | 理由 |
|--------|--------|----------|------|
| **P0** | Results 筛选 / 排序 / 多选 → Confirm | S3→S4 枢纽 | 500 条 Top 列表无法支撑「看清 → 选择 → 删除」；Confirm 有 UI 但缺入口数据 |
| **P1** | 目录选择器 | S2 输入 | PRD 明确要求「预设根 + 用户选目录」；否则只能扫 HOME |
| **P2** | `rules/desktop.yaml` 加载 | 分类质量 | 提升 CACHE/TEMP 命中率，减少 UNKNOWN；不阻塞演示闭环 |
| **P3** | 扫描进度 UI | S2 体验 | ~1min 扫描需要反馈；Isolate 架构需小改，不阻塞闭环 |

**不纳入本阶段：** FRB 迁移、Win/Linux、重复文件、Treemap、设计 token 系统化。

---

## 3. 方案对比（摘要）

### P0 — Results → Confirm 选中传递

| 方案 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **A（推荐）** | `VolwardSession.pendingDeleteIds` + Results 多选 +「在 Confirm 删除」 | 与现有 Confirm 复用；状态集中 | Session 略增字段 |
| B | Confirm 内嵌 Results 子 Tab | 单页操作 | 违背四屏 IA |
| C | 路由 arguments 一次性传 id | 无全局状态 | 切换 Tab 丢失选中 |

### P1 — 目录选择

| 方案 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **A（推荐）** | `file_selector` 单目录 pick → `runScan(roots: [path])` | 跨桌面、与现有 API 对齐 | 需 macOS entitlements 检查 |
| B | 仅文本输入路径 | 零依赖 | 体验差、易错 |

### P2 — YAML 规则

| 方案 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **A（推荐）** | `RulesConfig` + `Classifier::from_rules()`；platform 保护前缀 **合并** YAML | 符合 ARCHITECTURE；可单测 | 需 `serde_yaml` |
| B | Flutter 读 YAML 传 JSON 给 Rust | 不改 core | 违反「规则在 Rust」约束 |

### P3 — 扫描进度

| 方案 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **A（推荐）** | `Isolate.run` 传 `SendPort`；worker 周期性 `port.send(progressMap)` | 不改 Rust；主 engine 不动 | worker 内仍无 engine 级 progress |
| B | Rust 扫描改后台线程 + 主 engine poll `get_last_progress` | 复用已有 C API | 改动大、与 Isolate 策略冲突 |
| C | 仅 indeterminate 进度条 | 极简 | 不满足 PRD「进度」语义 |

**推荐组合：** P0A + P1A + P2A + P3A。

---

## 4. 详细设计

### 4.1 P0 — Results 交互（S3）

**职责边界**

- `VolwardSession`：持有 `Set<String> selectedEntryIds`（跨 Tab 持久）
- `ResultsPage`：筛选（category chip）、排序（size ↓/↑、name）、多选 checkbox、仅 `deletable==true` 可勾选
- `ConfirmPage`：启动时合并 `session.selectedEntryIds` 到本地 `_selected`；删除成功后清空 session 选中集

**数据流**

```text
Scan → lastSnapshot.entries
  → ResultsPage（filter/sort/select）
  → session.selectedEntryIds
  → ConfirmPage（pre-check + deleteEntries + rescan）
```

**UI 约束**

- 默认排序：size 降序（与 Rust Top 500 一致）
- 默认筛选：All；快捷 chip：Cache、Temp、Deletable only
- 「Continue to Confirm (N)」按钮：写入 session 并 SnackBar 提示切 Tab（不强制 NavigationBar 跳转，避免 IndexedStack 耦合）

**错误处理**

- 无 snapshot：空态文案（已有）
- 选中含不可删 id：Confirm 侧 Rust 已 skip，UI 仅展示 deletable 项

### 4.2 P1 — 目录选择（S2）

**ScanPage 变更**

- 显示当前 roots：`Home`（默认）或用户选中的绝对路径
- 按钮：`Choose folder…` → `getDirectoryPath()`（`file_selector`）
- `Start scan` 将 `List<String> roots` 传入 `session.runScan(roots: roots)`

**默认行为**

- `roots` 为空 → Rust `discover_roots` 回退 HOME（保持兼容）

**macOS**

- `macos/Runner/DebugProfile.entitlements` + `Release.entitlements`：确认已有 user-selected file access（file_selector 文档要求）

### 4.3 P2 — YAML 规则加载

**新类型** `volward-core/src/rules.rs`：

```rust
pub struct DesktopRules {
    pub version: u32,
    pub protected_prefixes: Vec<String>,
    pub cache_patterns: Vec<String>,
    pub temp_patterns: Vec<String>,
    pub media_extensions: Vec<String>, // 可选，缺省用内置列表
}
```

**加载路径**

- CLI / Engine：`VOLWARD_RULES_PATH` 或默认 `{workspace}/rules/desktop.yaml`
- Facade `VolwardEngine::new()` / `start_scan`：加载一次，合并 `platform.protected_prefixes()` + YAML `protected_prefixes`

**Classifier 变更**

- `Classifier::from_rules(rules: &DesktopRules, extra_protected: &[String]) -> Self`
- 编译 regex 失败 → 启动时 `Err` 明确报错
- 保留 `Classifier::new()` 供现有单测；新增 `from_rules` 单测

**desktop.yaml 扩展**（向后兼容）：

```yaml
version: 1
protected_prefixes: [...]
cache_patterns: [...]
temp_patterns: [...]
media_extensions: [".jpg", ".mp4", ...]  # 新增可选段
```

### 4.4 P3 — 扫描进度（S2）

**Worker 协议**

```dart
// scan_worker.dart
Future<Map<String, dynamic>?> volwardScanWorker(ScanWorkerArgs args);

class ScanWorkerArgs {
  final List<String> roots;
  final SendPort progressPort;
}
```

Worker 内在独立 engine 上扫描；每 200ms（或每 500 paths）向 `progressPort` 发送：

```json
{"phase":"Walking","paths_seen":1234,"bytes_seen":5678,"current_path":"/Users/..."}
```

**VolwardSession.runScan**

- 创建 `ReceivePort`，监听 progress → 更新 `_scanProgress` Map → `notifyListeners()`
- ScanPage：展示 `LinearProgressIndicator`（indeterminate 直到有 paths_seen）+ `paths_seen` / `current_path` 单行截断

**取消**

- 保持现有 `cancelScan()`；worker 内 engine cancel 与主 engine 分离 — **本阶段不修复 worker cancel**（YAGNI，文档注明限制）

---

## 5. 测试策略

| 层级 | 覆盖 |
|------|------|
| Rust | `rules` 解析单测；`Classifier::from_rules` 与 YAML fixture；既有 classify 单测不回归 |
| Flutter | `VolwardSession` 选中集 unit test（可选）；手动 E2E：选目录 → 扫 → Results 筛 Cache → Confirm 删 → 复扫 |
| 验收 | PRD 6.3 闭环手测清单（见实施计划 Task 5） |

---

## 6. 成功标准

- [x] 结果可筛 Cache/Temp、按 size 排序、多选 deletable 项，并进入删除确认（现为单页列浏览 + Move to Trash）
- [x] 可选择单个目录作为 root（`Folder…` / Home）
- [x] `cargo test` 含 rules/from_rules 用例；分类行为与 `desktop.yaml` 一致
- [x] 扫描过程显示阶段 / paths_seen 等进度（现含 Isolate 轮询；后续另有渐进式 checkpoint）
- [x] 保护路径仍 `deletable=false`（Rust 单测覆盖）

---

## 7. 修订记录

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-05-29 | 初稿：四块闭环优先级 + 推荐方案 |
| 0.2 | 2026-07-26 | 标记已实现；补充单页 IA 收口说明；勾选成功标准 |
