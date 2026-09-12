# Volward

[![GitHub release](https://img.shields.io/github/v/release/ZakAnun/volward?label=release)](https://github.com/ZakAnun/volward/releases/latest)

跨平台桌面存储管家：更快找出占空间的文件，先预览、再浏览、最后安全删除。

**官网：** [volwardapp.com](https://www.volwardapp.com) · **下载：** [GitHub Releases（latest）](https://github.com/ZakAnun/volward/releases/latest)

> macOS 上验证最完整；Windows / Linux 已提供正式安装包与应用内更新。

---

## 用户使用

### 能做什么

| 能力 | 说明 |
|------|------|
| **渐进式扫描** | 启动或切换目录时先 `quick_list` 一层预览；后台异步扫描或从缓存恢复完整 catalog |
| **多列浏览** | Finder 式列视图；未扫完目录显示加载态，可 peek 优先补齐子树 |
| **按目录缓存** | 每个扫描根目录独立 manifest + index（`.pb`）；切回已完成目录优先 restore，不必重扫 |
| **增量扫描** | Settings 可开；基于目录指纹跳过未变化子树；暂停后可 resume |
| **分类与筛选** | 浏览态按 **Cache / Temp / Media / System** 筛选，支持「仅可删」与 Size/Name 排序 |
| **安全删除** | 删除前预览；确认后移入系统废纸篓，支持清空废纸篓 |
| **Home 仪表盘** | 容量概览、当前目标下最大子项、快捷切换 Home / Desktop / Downloads 等 |
| **AI Analyze** | 基于扫描 catalog 的 AI 覆盖分析（Platform 或 BYOK 模式，需联网） |
| **应用内更新** | 检查 GitHub Releases，校验 SHA-256 后安装（可关自动下载） |

Rust 侧还实现了大文件、重复文件、相似照片、清理候选、应用占用、浏览器隐私等 **Capability 分析器**，目前主要通过 Session/FFI 与测试覆盖；**主界面用户入口以浏览 + AI Analyze 为主**。

### 典型流程

1. **首次启动**：恢复上次扫描根（或默认 Home）→ 即时预览 → 后台尝试 restore 缓存；若无有效缓存则 **自动开扫**。
2. 扫描进行中可进入 **Browse** 多列查看；`paths_seen` 等进度会持续更新。
3. 用筛选栏缩小范围，选中项目 → 删除预览 → 移入废纸篓。
4. 需要 AI 辅助时进入 **AI Analyze**（Settings 中配置 Platform / BYOK / 关闭）。
5. **切换扫描根**（Home 侧栏或设置）：`completed` 目录 restore；`empty` 自动扫；`paused` restore 后增量续扫。

### 安装

从 [Releases](https://github.com/ZakAnun/volward/releases/latest) 下载：

| 平台 | 文件 | 说明 |
|------|------|------|
| macOS (Apple Silicon) | `volward-*-macos-arm64.zip` | 解压拖入 `/Applications` |
| macOS (Intel) | `volward-*-macos-x64.zip` | 同上 |
| Windows | `VolwardSetup-*-windows-x64.exe` | Inno Setup 安装器 |
| Linux（推荐） | `Volward-*-linux-x86_64.AppImage` | `chmod +x` 后运行 |
| Linux（便携） | `volward-*-linux-x64.tar.gz` | 解压后运行 `bundle/volward` |

各安装包附带 `.sha256`；应用内更新会自动校验。

**首次运行提示**

- **macOS**（未签名）：右键 `volward.app` → **打开**；或 `xattr -cr /Applications/volward.app`
- **Windows**：SmartScreen →「更多信息」→「仍要运行」
- **Linux**：AppImage 需执行权限；`tar.gz` 解压即用

自动更新支持 macOS `.zip`、Windows 安装器、Linux AppImage；`tar.gz` 需手动下载。

### macOS 权限

- 未授予 **完全磁盘访问（FDA）** 时，仍可扫描普通可读目录。
- 深度访问 `~/Library`、Safari、Messages 等受 TCC 保护路径需要 FDA。
- 应用内会引导打开 **系统设置 → 隐私与安全性 → 完全磁盘访问**。

### 设置（Settings）

| 项 | 说明 |
|----|------|
| 主题 | 跟随系统 / 浅色 / 深色 |
| Accent | 6 种预设色 |
| 增量扫描 | 默认关闭；开启后 resume/自动扫会走 fingerprint 增量 |
| 语言 | 跟随系统 / 中文 / English |
| 自动下载更新 | 控制是否在后台预拉更新包 |
| AI | Off / Platform（`api.volwardapp.com`）/ BYOK |

偏好写入缓存目录下的 `settings.json`（AI 密钥等敏感项走 secure storage）。

### 本机数据位置

| 平台 | 缓存根目录 |
|------|------------|
| macOS | `~/Library/Application Support/Volward/` |
| Linux | `$XDG_DATA_HOME/volward/` 或 `~/.local/share/volward/` |
| Windows | `%APPDATA%\Volward\`（回退 `%LOCALAPPDATA%\Volward\`） |

主要子目录（均在上述根目录下）：

| 路径 | 内容 |
|------|------|
| `manifests/` | 每 root 的 manifest（目录指纹、`snapshot_path`） |
| `snapshots/` | 持久化 SnapshotIndex（`.pb`；旧版可能仍有 `.json`） |
| `root_records/` | 各 root 状态：`completed` / `paused` / `empty` / `scanning` |
| `pauses/` | 扫描中途 pause 的截断 baseline |
| `settings.json` | 主题、语言、增量扫描、自动更新等 |

调试可设 `VOLWARD_CACHE_DIR` 指向临时目录（与 `SnapshotCache.cacheDir()` 一致）。

---

## 参与开发

### 技术栈

| 层 | 说明 |
|----|------|
| **UI** | Flutter 3（`apps/volward`，FVM 锁定 `stable`） |
| **核心** | Rust：`volward-core` 扫描/分类/index，`platform-desktop` 文件 walk |
| **FFI** | `volward-facade` → 各平台 `libvolward_facade` / `.dll` |
| **持久化** | `volward-index-pb`（SnapshotIndex protobuf） |
| **AI** | `volward-ai` + `server/`（`volward-platform-api` crate，可选部署） |
| **官网** | `apps/website`（Astro） |

Dart 通过 `VolwardNativeBridge` 调用 Rust；`VolwardSession` 统一编排扫描、restore、删除、AI。

### 环境要求

| 工具 | 用途 |
|------|------|
| Rust stable | workspace 构建与测试 |
| FVM + Flutter stable | `apps/volward`（见 `.fvmrc`） |
| `protoc` | `volward-facade` / index protobuf 生成 |
| macOS：Xcode + Apple ID | Debug 签名与 TCC 联调 |

### 仓库结构

```text
volward/
├── apps/volward/              # Flutter 桌面应用（见 apps/volward/README.md 模块表）
├── apps/website/              # 产品官网
├── crates/
│   ├── volward-core/          # ScanOrchestrator、SnapshotIndex、分类、删除
│   ├── volward-index-pb/      # index protobuf 编解码与原子写盘
│   ├── volward-facade/        # VolwardEngine + C API
│   ├── volward-ai/            # AI 协议与请求
│   ├── platform-desktop/      # jwalk 并行 walk、FDA 探测、quick_list
│   └── volward-cli/           # smoke / scan-bench
├── server/                    # volward-platform-api（Platform AI / 计费等）
├── proto/volward.proto
├── rules/desktop.yaml         # Tier-1 分类规则
├── rules/os_knowledge.yaml    # Tier-2 OS 知识库
└── scripts/                   # setup、test_core、发布
```

### 快速开始

**macOS（日常推荐）**

```bash
# 首次：Xcode → Settings → Accounts 登录 Apple ID
bash scripts/setup_macos.sh

cd apps/volward
bash ../../scripts/ensure_fvm_stable.sh   # 与 .fvmrc 对齐（幂等）
bash scripts/run_macos_debug.sh
```

`run_macos_debug.sh` 会：校验 Debug 签名配置 → `build_rust.sh` → `fvm flutter run -d macos`。  
可选 `--dart-define=VOLWARD_API_BASE=...`（默认 `https://api.volwardapp.com/v1`）。

**Linux**

```bash
cd apps/volward
bash ../../scripts/ensure_fvm_stable.sh
bash scripts/run_linux_debug.sh   # 需 Linux 本机；会先 cargo build -p volward-facade
```

**Windows**

```bash
# 在 Windows 的 Git Bash / MSYS2 中（脚本会拒绝 WSL/macOS 的 uname）
cd apps/volward
bash scripts/run_windows_debug.sh
```

**Rust 变更后** 必须重新编译 native 库再跑 Flutter：

```bash
# macOS
cd apps/volward/macos && bash build_rust.sh
# Linux / Windows debug 脚本内已包含 cargo build -p volward-facade
```

**手动分步（macOS）**

```bash
cd apps/volward/macos && bash build_rust.sh
cd ..
fvm flutter pub get
fvm flutter run -d macos
```

### 扫描架构

```text
VolwardSession (Dart, main isolate 轮询进度 ~300ms)
  → startScanAsyncWithOptions(incremental)
      → VolwardEngine：1× std::thread 跑 run_index_scan
          → DesktopPlatform.walk_entries
              jwalk + Rayon 专用线程池（默认 min(CPU, 8)，至少 2）
          → SnapshotIndexBuilder
          → 完成：snapshots/{hash}.pb + manifests/{hash}.json
```

| 环节 | 并发 |
|------|------|
| 目录 walk | 默认 **2–8** 线程（`VOLWARD_SCAN_THREADS=1..32` 可覆盖） |
| 扫描任务 | **1** 个 Rust OS 线程（分类/index 在 walk 回调中串行处理） |
| Index restore | **1** 个 Rust worker（`start_load_index_from_path_async`） |
| Peek 子树 | Dart **Isolate**（`volwardPeekScanIsolate`） |
| 旧路径全量扫 | Dart Isolate + 独立 engine（无 Index API 时 fallback） |

当前 release 构建均带 Index API，**主扫描路径不再走 Isolate**。

### 验证与诊断

```bash
# curated 核心回归（与 CI 接近的子集）
bash scripts/test_core.sh          # rust + flutter
bash scripts/test_core.sh rust
bash scripts/test_core.sh flutter

# 更广覆盖
cargo test                         # 全 workspace
cd apps/volward && fvm flutter test

# CLI
cargo run -p volward-cli              # smoke（空 root 快速扫）
cargo run -p volward-cli -- scan-bench [--root PATH] [--entries N]
```

修改 `lib/l10n/app_*.arb` 后：

```bash
cd apps/volward && fvm flutter gen-l10n
# 提交 generated/ 下的 app_localizations*.dart
```

提交前建议：`bash scripts/install_git_hooks.sh`（pre-commit 含 dart format）。

### 常见环境变量

| 变量 | 作用 |
|------|------|
| `VOLWARD_CACHE_DIR` | 覆盖缓存根目录 |
| `VOLWARD_SCAN_THREADS` | walk 并行线程数（1–32） |
| `VOLWARD_API_BASE` | Debug 时 Platform API 地址 |
| `VOLWARD_RULES_PATH` | 覆盖 `rules/desktop.yaml` 路径 |

### 贡献建议

1. 改动后跑相关测试：`bash scripts/test_core.sh` 或 targeted `cargo test -p …` / `fvm flutter test test/…dart`。
2. Rust：`cargo fmt`；Dart：`bash scripts/check_dart_format.sh`。
3. UI 文案改 ARB 并 `gen-l10n`。
4. PR 请说明用户可见行为；较大改动可先开 Issue。

---

## 当前状态

**主路径（已可用）：** 预览 → 扫描或缓存 restore → 多列浏览 → 筛选 → 废纸篓删除 → 按 root 切换与恢复 → 应用内更新 → AI Analyze（可选）。

**扫描分类（`classify.rs` / 筛选栏）：**

| 分类 | 扫描期行为 | 浏览筛选 |
|------|------------|----------|
| Cache / Temp | 低风险，文件默认可删 | 有独立 chip |
| Media | 媒体/安装包扩展名，默认不可删 | 有 |
| System | 受保护路径，不可删 | 有 |
| BuildArtifact | 如 `node_modules`、DerivedData，可删 | **无独立 chip**（仍计入 catalog） |
| AppData / Orphan / Duplicate | 枚举预留 | 无；重复等见 Capability 分析器 |

**已知限制：** macOS 正式签名/Notarization 未完成；超大规模 home（数十万 catalog 条目）restore 后首屏渲染仍偏重；Windows/Linux 联调深度低于 macOS。

---

## 许可证

Workspace crate 声明 **MIT**（见根目录 `Cargo.toml`）。
