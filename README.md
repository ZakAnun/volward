# Volward

macOS 桌面存储管家：**Flutter UI + Rust 扫描核心 + 平台层**。扫描磁盘占用、按规则分类、Finder 式浏览，并将可删文件移入系统废纸篓。

> 当前主要开发与验证平台为 **macOS**。Rust 核心与 `platform-desktop` 亦面向 Windows / Linux，Flutter 壳已生成多平台工程，但 UI 与 FFI 联调以 macOS 为准。

## 功能

### 扫描

- **默认扫描用户 Home**，或通过「Folder…」选择自定义目录
- **全量 / 增量扫描**（增量需 rebuild Rust 且 native 库支持 `scan_options` FFI）
- **后台 Isolate 扫描**，UI 显示阶段与进度（Walking / Classifying / Saving…）
- **停滞检测**：20 分钟无进度超时；Save/Load 阶段放宽至 2 小时；绝对上限 8 小时
- 扫描结果写入 `~/Library/Application Support/Volward/`，**重启或 hot reload 后自动恢复**上次 snapshot

### 结果浏览

- **Finder 式多列目录浏览**（列宽固定，横向滚动）
- **筛选栏**：分类（All / Cache / Temp / Media / Unknown / System）、Deletable、排序（Size ↓/↑、Name）
- 底部 **预览条** 显示当前选中项；可勾选可删文件
- **Move to Trash**：先 dry-run 预览，确认后删除并可选自动重扫

### 外观

- 右上角 **Settings**：主题（跟随系统 / 浅色 / 深色）、6 种 accent 色
- Apple 风格设计 token，浅色/深色语义色一致

### macOS 权限

- 未授予 **Full Disk Access (FDA)** 时仍可扫描部分目录；深度扫描 `~/Library` 等 TCC 保护路径需 FDA
- 应用内提供打开系统设置、复制 `.app` 路径等引导

## 仓库结构

```text
volward/
├── crates/volward-core      # 领域模型、扫描/删除编排、分类
├── crates/platform-desktop  # macOS / Windows / Linux 平台实现（FDA、废纸篓等）
├── crates/volward-facade    # C API（供 Flutter FFI）
├── crates/volward-cli       # 命令行冒烟 / scan-bench
├── apps/volward             # Flutter 单页应用（Home + Settings）
│   ├── lib/                 # UI、VolwardSession、Snapshot 恢复
│   └── macos/build_rust.sh  # 编译并拷贝 libvolward_facade.dylib
└── rules/desktop.yaml       # 桌面端分类规则（Cache/Temp/Media 等）
```

## 环境要求

- **Rust**（stable，`~/.cargo/bin` 在 PATH 中）
- **FVM** + **Flutter stable**（`apps/volward` 锁定 stable，当前解析约 Flutter 3.44 / Dart 3.12）
- **macOS** 用于日常开发与运行

## 快速开始（macOS）

```bash
# 1. 编译 Rust 并拷贝 dylib（修改 Rust 后必做）
cd apps/volward/macos
bash build_rust.sh

# 2. Flutter 依赖与运行
cd ../..
fvm install stable    # 首次
fvm use stable
fvm flutter pub get
fvm flutter run -d macos
```

Rust 或 FFI 变更后请 **Hot restart (R)**，不要只 hot reload。若提示 native 库过时，重新执行 `build_rust.sh` 后再 restart。

## 网络代理（可选）

构建若遇 crates.io / pub 超时，可设置代理（`build_rust.sh` 在未设置时默认 `127.0.0.1:7890`）：

```bash
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export HTTP_PROXY=$http_proxy
export HTTPS_PROXY=$https_proxy
```

## 验证

```bash
# Rust
cd volward
export CARGO_TARGET_DIR="$(pwd)/target"
cargo test
cargo run -p volward-cli              # 冒烟扫描
cargo run -p volward-cli -- scan-bench # 可选性能基准

# Flutter
cd apps/volward
fvm flutter test
fvm flutter run -d macos
```

## 数据目录

| 路径 | 说明 |
|------|------|
| `~/Library/Application Support/Volward/manifests/` | 扫描 manifest（含 snapshot 路径、指纹） |
| `~/Library/Application Support/Volward/snapshots/` | 持久化 snapshot JSON |
| `~/Library/Application Support/Volward/settings.json` | 主题与 accent 偏好 |

测试可通过环境变量 `VOLWARD_CACHE_DIR` 指向临时目录。

## 文档

设计与计划文档见 `docs/superpowers/`（如 scan-tree Finder UI、全量扫描性能等）。
