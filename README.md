# Volward

macOS 桌面存储管家：**Flutter UI + Rust 扫描核心 + 平台层**。渐进式扫描磁盘占用（即时预览 → 后台全量 → 点击优先 Peek）、按规则分类、Finder 式浏览，并将可删文件移入系统废纸篓。

> 当前主要开发与验证平台为 **macOS**。Rust 核心与 `platform-desktop` 亦面向 Windows / Linux，Flutter 壳已生成多平台工程，但 UI 与 FFI 联调以 macOS 为准。

## 功能

### 扫描（渐进式）

- **默认目标为用户 Home**，或通过「Folder…」选择自定义目录；切回 Home 会先刷新该目录的即时预览
- **即时预览**：选定目标后先 `quick_list_dir` 展示一层目录，无需等待全量扫描结束即可浏览
- **后台全量 / 增量扫描**（增量需 rebuild Rust 且 native 库支持 `scan_options` FFI）；扫描在 Isolate 中进行，UI 显示阶段与进度（Walking / Classifying / Saving…）
- **Checkpoint 流式更新**：扫描过程中周期性写出中间快照并合并进 UI；大树场景下间隔会按克隆开销自适应拉长（约 2s 起、上限约 15s）
- **点击优先 Peek**：点进尚未扫完的文件夹时，会触发对该路径的小范围优先扫描，结果权威覆盖该子树（含删除与可释放空间估算校正）
- **停滞检测**：20 分钟无进度超时；Save/Load 阶段放宽至 2 小时；绝对上限 8 小时
- 扫描结果写入 `~/Library/Application Support/Volward/`，**重启或 hot reload 后自动恢复**上次 snapshot（优先匹配当前目标根；无匹配时可能看到最近一次自定义目录的结果）

### 结果浏览

- **Finder 式多列目录浏览**（列宽固定，横向滚动）；后台 checkpoint / peek 合并时**保持当前列导航位置**
- 未扫完的目录显示加载态与尺寸占位「—」，扫完后填入真实大小与子项
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
│   ├── lib/                 # UI、VolwardSession、渐进式预览/合并、Snapshot 恢复
│   └── macos/build_rust.sh  # 编译并拷贝 libvolward_facade.dylib
└── rules/desktop.yaml       # 桌面端分类规则（Cache/Temp/Media 等）
```

## 环境要求

- **macOS** + **Xcode**（App Store），并在 Xcode → Settings → Accounts 登录自己的 Apple ID（用于 Debug 签名）
- **Rust**（stable，`~/.cargo/bin` 在 PATH 中；也可由 setup 安装）
- **FVM** + **Flutter stable**（`apps/volward` 锁定 stable；也可由 setup 安装）
- **protoc**（`brew install protobuf`；Rust facade 的 `build.rs` 需要；也可由 setup 安装）

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

`setup_macos.sh` 会：检查 Xcode/CLT → **先配置本地签名**（缺证书会立刻失败并提示）→ 安装/检查 Homebrew `protobuf`、Rust、FVM + Flutter → `pub get` / `cargo fetch` → 编译 `libvolward_facade`。  
每人各自生成 gitignore 的 `TeamSettings.local.xcconfig`（用自己的 Apple Development Team，**不必共用证书**）。常用参数：`--team <ID>`、`-y`（仅当能唯一判定 Personal Team 时自动选择）、`--skip-build`。

Rust 或 FFI 变更后请 **Hot restart (R)**，不要只 hot reload。若提示 native 库过时，重新执行 `build_rust.sh` 后再 restart。

## 网络代理（可选）

构建若遇 crates.io / pub 超时，可设置代理（`setup_macos.sh` / `build_rust.sh` 仅在本机 `127.0.0.1:7890` 可连通时才会自动使用该代理）：

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

设计与计划文档见 `docs/superpowers/`（状态以各 spec 文首「状态」字段为准）：

| 主题 | Spec | 状态（2026-07-26） |
|------|------|-------------------|
| MVP 闭环 | `specs/2026-05-29-mvp-closure-design.md` | ✅ 已实现 |
| Finder 全量树 | `specs/2026-07-23-scan-tree-finder-design.md` | ✅ 已实现 v2 |
| 全盘扫描性能 / 增量 | `specs/2026-07-23-full-scan-performance-design.md` | ✅ P1 + P2（F0 bench） |
| 渐进式扫描 | `specs/2026-07-24-progressive-scan-design.md` | ✅ Wave 1 + Wave 2 |
