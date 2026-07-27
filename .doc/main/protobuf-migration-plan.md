# Protobuf 迁移方案：快照传输去 JSON 化

**目标**：把 Rust ↔ Flutter 的 **snapshot / checkpoint** 传输从 JSON + `Map<String,dynamic>`
改为 protobuf + 类型化消息，消除大扫描时的内存膨胀（此前一次运行占用 60+GB）。

**前置**：`#2`（限流 isolate 重算）已完成。**先测量 #2 的内存效果**，再决定是否执行本方案。
本方案是 #2 之后的进一步优化，二者独立、可叠加。

---

## 关键认知：省内存的来源不是 wire 格式

单次 checkpoint（~49MB，每 ~2s）当前物化整棵快照约 5 次：

| # | 拷贝 | 形态 | protobuf 是否改善 |
|---|------|------|------------------|
| 1 | Rust 序列化 → 文件 | JSON 字节 | ✅ 文件更小 |
| 2 | `jsonDecode` → Dart 图 | `Map<String,dynamic>`（字节的 3–5×） | ✅ 解析更快 + 若解析成**类型化消息**则更省 |
| 3 | `mergeSubtreeIntoSnapshot` → 新全量快照 | `Map<String,dynamic>` | ⚠️ 仅当 merge 改用类型化消息才改善 |
| 4 | `compute()` 深拷贝入 isolate | `Map<String,dynamic>` | ⚠️ 同上 |
| 5 | isolate 深拷贝出 tree | `ScanTreeNode` | ⚠️ 同上 |

**结论**：protobuf 的 wire 格式只改善 #1/#2。真正的内存收益来自把 Dart 全链路
（decode → merge → display）从 `Map<String,dynamic>`（每节点一张哈希表 + 装箱值 +
重复字符串 key，约为扁平对象的 3–5×）换成**类型化生成类**。protobuf 是实现这一点
的干净载体——但**只有当 merge 也改为在生成类上操作**（而非 decode 回 map）时才生效。

---

## Schema

见 `proto/volward.proto`（已创建）。要点：

- 与 `crates/volward-core/src/model.rs` 逐字段对齐，enum → protobuf enum。
- **只迁移快照负载**；`ScanProgress` / `PlatformCapabilities` / `DeleteReport` /
  `quick_list_dir` 保持 JSON（小、低频，迁移无收益）。
- **`ScanTreeNode.scanned` / `peek_scanned` 是 client-only 字段**：Rust 从不写入
  （默认 false），Flutter 在 merge 中标记。放进消息里，才能让 merge 在类型化节点上运行。
  （Rust `ScanTreeNode` 模型本身没有这两个字段——它们目前是 Dart 侧在 map 上贴的。）

---

## 分阶段实施

### Phase 0 — 工具链接入（无行为变更）
- Rust：`volward-facade` 加 `prost`；`build.rs` 用 `prost-build` 从 `proto/volward.proto` 生成。
- Dart：`dart pub global activate protoc_plugin`；`protoc --dart_out=lib/gen proto/volward.proto`；
  `pubspec.yaml` 加 `protobuf` runtime 依赖。生成物提交仓库（避免 CI 依赖 protoc）。
- **验证**：`cargo build` + `flutter analyze` 通过；生成类可 import，未被调用。

### Phase 1 — Rust 端 encode（与 JSON 并存）
- 加 `From<&model::StorageSnapshot> for proto::StorageSnapshot` 转换（或直接让 core 结构体
  `#[derive(prost::Message)]`——但会污染 core，倾向在 facade 做转换层）。
- 新增 `write_last_checkpoint_to_path_pb(path)` / `write_last_snapshot_to_path_pb(path)`：
  写 protobuf 字节（**沿用 #FormatException 修复的原子/唯一路径策略**）。
- 保留旧 JSON 函数，暂不删。
- **验证**：Rust 单测 round-trip（encode → decode → 断言等值）。

### Phase 2 — Dart 端类型化管线（核心工作量）
这是真正省内存的部分，也是最大改动：
- `_decodeSnapshotJsonFile` → `_decodeSnapshotPbFile`：`StorageSnapshot.fromBuffer(bytes)`。
- **重写 `scan_snapshot_merge.dart`**：在生成的 `StorageSnapshot` / `ScanTreeNode`（可变，
  支持 `..field=` 与 `deepCopy`/`rebuild`）上做 splice/merge，取代当前的 map 操作。
  - `_markDiscoveredDirsScanned` → 设 `node.scanned = true`。
  - `peekScanned` 哨兵 → `node.peekScanned`。
- `_computeDisplayIsolate`：输入改为 `StorageSnapshot` 消息（protobuf 消息可跨 isolate 发送，
  且比等价 map 拷贝更省）；prune/sort/aggregate 直接在消息上做，或转 `ScanTreeNode`（scan_tree.dart）。
- **枚举↔过滤**：`_categoryFilter` 当前是字符串（"Cache"…）与 `entry['category']` 比较；
  改为与 `entry.category`（`EntryCategory` enum）比较，或建一次性映射。
- **验证**：`scan_snapshot_merge_test.dart` 全部改写并通过（现有 2 个 progressive/peek 用例是关键回归保护）。

### Phase 3 — 切换热路径（checkpoint）
- `scan_worker.dart`：checkpoint 改调 `..._pb` 写函数，消息类型 `'checkpoint'` 传 protobuf 路径。
- `volward_session.dart`：`_applyCheckpointFromFile` 走 protobuf decode + 类型化 merge。
- **验证**：手动跑一次大扫描，对比内存（目标：数量级下降）；进度/spinner/peek 行为不回归。

### Phase 4 — 切换其余快照路径
- `set/get_last_snapshot`、`load_last_snapshot_from_path`（删除操作用）→ protobuf。
- 缓存落盘（`writeLastSnapshotToPath`）→ protobuf。注意**旧 JSON 缓存的兼容**：
  首次启动可能读到旧 JSON 缓存——保留 JSON 读路径做一次性回退，或版本化缓存文件名。
- **验证**：删除流程、缓存 restore、增量扫描 base 全链路。

### Phase 5 — 清理
- 删除 `*_json` 快照函数与 JSON decode 旧路径。
- **验证**：全量 `flutter test` + `cargo test`。

---

## 风险与注意

- **client-only 字段**：`scanned`/`peek_scanned` 一旦漏进 Rust 生产逻辑会造成语义混淆——
  约定 Rust 永不写、只有 merge 写。
- **缓存兼容**：Phase 4 的落盘缓存要处理旧 JSON → protobuf 的迁移窗口（回退读或清缓存）。
- **生成物提交**：Dart/Rust 生成代码入库，避免 CI/开发机强依赖 `protoc` 版本漂移。
- **`compute()` 仍在**：protobuf 消息跨 isolate 仍是拷贝（非零拷贝）。若 Phase 3 后内存仍高，
  下一步才考虑 FlatBuffers/Cap'n Proto 零拷贝，或"树留在 Rust、Dart 只读可见切片"的架构级方案。

---

## 决策点

1. **先测 #2**：若 #2 已把 60GB 压到可接受，protobuf 降为 CPU/包体的低优项。
2. 若仍高：执行 Phase 0→3（热路径），通常已拿到主要收益；Phase 4/5 视情况跟进。
