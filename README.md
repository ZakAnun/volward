# Volward

Volward 是一个跨平台桌面存储管家，帮你更快找出占空间的文件，先预览、再浏览、最后安全删除。

> 现在可以发布 macOS / Windows / Linux 安装包，但当前主要还是在 **macOS** 上验证和打磨。

## 当前能力

### 渐进式扫描

- 默认从用户 Home 开始，也可以手动选择任意目录。
- 选中目录后会先看到一层快速预览，不用等整盘扫完。
- 扫描过程中可以边看边用，结果会逐步变完整。
- 打开还没扫完的目录时，会优先补齐那一块内容。
- 支持增量扫描，避免重复扫已经没有变化的目录。
- 支持取消扫描，也有超时保护，避免任务卡太久。

### 目录浏览与筛选

- 主界面提供 Finder 式多列浏览，适合一路展开看文件夹层级。
- 未扫完的目录会先显示加载态，等结果回来后再补上大小和内容。
- 支持按分类、可删除状态和排序方式筛选：
  - 分类：All / Cache / Temp / Media / System
  - 删除状态：仅可删
  - 排序：Size ↓ / Size ↑ / Name
- 底部会显示当前选中的项目，方便先确认再操作。

### 分类与删除

- 目前会自动识别这些常见类型：
  - `Cache`：缓存路径，低风险，文件默认可删除
  - `Temp`：临时路径或 `.tmp` 文件，低风险，文件默认可删除
  - `Media`：图片、视频、PDF、DMG 等媒体/安装包，高风险，默认不可删除
  - `System`：受保护系统路径，高风险，不可删除
- 删除前会先做预览，告诉你大概能清出多少空间、哪些项目会失败。
- 确认后会先移入系统废纸篓，而不是直接永久删除。
- 还支持清空废纸篓。

### 快照、恢复与当前目录刷新

- 扫描结果会保存在本机，重启后可以继续上次的结果。
- 如果只想更新当前正在看的目录，也可以单独刷新这一层。

### 外观、语言与设置

- Settings 支持主题：跟随系统 / 浅色 / 深色。
- 支持 6 种 accent 色。
- 支持增量扫描开关。
- 支持语言：跟随系统 / 中文 / English。
- 这些设置都会保存在本地，下次打开还在。

### 应用内更新

- 从 **v0.0.2** 起支持应用内更新（更早的 v0.0.1 需先手动安装一次新版本）。
- 启动后会静默检查 GitHub Releases；有新版本时可选择立即更新或稍后。
- Settings → About 可查看当前版本、手动检查更新、下载安装，失败时可打开下载页。
- 发现可用更新时会展示 release notes 摘要（启动弹窗）。
- 下载前会确认校验文件与安装包可达；下载后校验 SHA-256，通过后再安装并重启。
- 自动更新支持：
  - macOS：`.app` zip（正式 `.app` 安装形态）
  - Windows：Inno Setup 安装器（x64）
  - Linux：AppImage（x86_64）
- Linux `tar.gz` 便携包可手动下载使用，但不参与自动更新。

### macOS 权限

- 未授予 Full Disk Access (FDA) 时仍可扫描普通可读目录。
- 深度扫描 `~/Library`、Safari、Messages、TCC 等受保护路径需要 FDA。
- 应用内会提示你去打开所需权限。

### 开发与诊断工具

- `volward-cli smoke`：命令行快速扫描一遍，方便确认程序可用。
- `volward-cli scan-bench`：做性能基准。
- 另外还有 Rust 和 Flutter 测试，用来保证核心流程稳定。

## 仓库结构

```text
volward/
├── crates/volward-core      # 扫描、分类、删除、快照等核心逻辑
├── crates/platform-desktop  # 桌面平台相关能力
├── crates/volward-facade    # Flutter 调用的 Rust 桥接层
├── crates/volward-cli       # 命令行工具
├── apps/volward             # Flutter 桌面应用（Home + Settings）
│   ├── lib/                 # UI 和应用状态
│   └── macos/build_rust.sh  # 本地构建脚本
└── rules/desktop.yaml       # 分类规则
```

## 安装 / 下载

从 [GitHub Releases](https://github.com/ZakAnun/volward/releases/latest) 下载最新版本（当前为 **v0.0.2**）：

| 平台 | 文件 | 安装方式 |
|------|------|----------|
| macOS (Apple Silicon) | `volward-*-macos-arm64.zip` | 解压后拖入 `/Applications`，首次打开：右键 → 打开 |
| macOS (Intel) | `volward-*-macos-x64.zip` | 同上 |
| Windows | `VolwardSetup-*-windows-x64.exe` | 运行安装器，按提示安装后从开始菜单启动 |
| Linux (recommended) | `Volward-v*-linux-x86_64.AppImage` | `chmod +x` 后双击或直接运行 |
| Linux (portable) | `volward-*-linux-x64.tar.gz` | 解压后运行 `bundle/volward` |

所有 release 资产都会附带对应的 `.sha256` 校验文件；应用内更新会验证后再安装。`.sha256` 文件本身不用来运行。

### 首次运行绕过系统警告

macOS 未签名应用：

```bash
# 方式一：右键点击 volward.app → 打开（不要双击）
# 方式二：终端移除隔离标记
xattr -cr /Applications/volward.app
```

Windows SmartScreen 警告：点击「更多信息」→「仍要运行」。

Linux：AppImage 首次运行前需要授予执行权限；tar.gz 版本解压即用。

## 环境要求

- macOS + Xcode，并在 Xcode -> Settings -> Accounts 登录自己的 Apple ID（用于 Debug 签名）。
- Rust stable，`~/.cargo/bin` 在 PATH 中；也可由 setup 脚本安装。
- FVM + Flutter stable，`apps/volward` 锁定 stable；也可由 setup 脚本安装。
- `protoc`，可通过 `brew install protobuf` 安装；Rust facade 的 `build.rs` 需要它，也可由 setup 脚本安装。

## 快速开始（macOS）

```bash
# 1) 首次：在仓库根目录执行（请先完成上面的 Xcode Apple ID 登录）
bash scripts/setup_macos.sh

# 2) 日常开发 / 运行
cd apps/volward
bash scripts/run_macos_debug.sh

# 如需手动分步（均从仓库根目录开始）
cd apps/volward/macos && bash build_rust.sh
cd ..
fvm install stable    # 首次（setup 已做过可跳过）
fvm use stable
fvm flutter pub get
fvm flutter run -d macos
```

`setup_macos.sh` 会帮你检查环境、安装依赖并完成本地构建准备。

Rust 或相关桥接变更后，请重新构建再启动。

## 网络代理（可选）

构建若遇 crates.io / pub 超时，可设置代理。

```bash
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export HTTP_PROXY=$http_proxy
export HTTPS_PROXY=$https_proxy
```

## 验证

```bash
# Rust
export CARGO_TARGET_DIR="$(pwd)/target"
cargo test
cargo run -p volward-cli              # 等价于 volward-cli smoke
cargo run -p volward-cli -- scan-bench # 可选性能基准

# Flutter
cd apps/volward
fvm flutter test
fvm flutter run -d macos
```

## 数据目录

| 路径 | 说明 |
|------|------|
| `~/Library/Application Support/Volward/manifests/` | 扫描 manifest，含 snapshot / index 路径与目录指纹 |
| `~/Library/Application Support/Volward/snapshots/` | 持久化 snapshot / catalog index |
| `~/Library/Application Support/Volward/settings.json` | 主题、accent、语言、增量扫描等偏好 |

测试可通过环境变量 `VOLWARD_CACHE_DIR` 指向临时目录。

## 当前状态

Volward 现在已经能完成一条完整的日常流程：选目录、快速预览、边扫边看、筛选出可删项、移入废纸篓、再刷新结果。macOS 上验证最完整；Windows / Linux 已随 [v0.0.2](https://github.com/ZakAnun/volward/releases/tag/v0.0.2) 提供安装包，并从该版本起支持应用内更新。

还留着一些预留能力和分发工作：

- `AppData` / `Orphan` / `Duplicate` 目前还是预留分类。
- 正式分发还需要补齐签名、Notarization，以及 Windows / Linux 的更完整联调。

## 设计文档

设计与计划文档见 `docs/superpowers/`（本地参考；下表为 README 汇总状态）：

| 主题 | Spec | 状态 |
|------|------|------|
| MVP 闭环 | `specs/2026-05-29-mvp-closure-design.md` | 已实现 |
| Finder 全量树 | `specs/2026-07-23-scan-tree-finder-design.md` | 已实现 v2 |
| 全盘扫描性能 / 增量 | `specs/2026-07-23-full-scan-performance-design.md` | 已实现 P1 + P2（F0 bench；P0 Release 排除） |
| 渐进式扫描 | `specs/2026-07-24-progressive-scan-design.md` | 已实现 Wave 1 + Wave 2 |
| 单份快照 + 增量视图 | `specs/2026-07-29-single-snapshot-incremental-view-design.md` | 已实现（catalog/query 层） |
| 中英 i18n | `specs/2026-07-30-volward-i18n-design.md` | 已实现 |
| macOS Debug 签名 / TCC | `specs/2026-07-30-macos-debug-signing-tcc-design.md` | 已实现（分发未做） |
| Catalog 当前目录刷新 | `specs/2026-07-31-catalog-backed-current-directory-refresh-design.md` | 已实现 |
| 应用内更新 | `specs/2026-08-10-in-app-updater-design.md` | 已实现（v0.0.2+） |
