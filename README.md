# Volward

Flutter UI + Rust Core + Platform 桌面端脚手架。

## 结构

```text
volward/
├── crates/volward-core      # 领域模型、PlatformStorage trait、扫描编排
├── crates/platform-desktop  # macOS / Win / Linux 平台实现
├── crates/volward-facade    # C API（供 Flutter ffi）；后续可换 FRB
├── crates/volward-cli       # 命令行冒烟
├── apps/volward             # Flutter 四屏壳（Overview / Scan / Results / Confirm）
└── rules/desktop.yaml       # 分类规则（后续加载）
```

## 网络代理（7890）

构建脚本与本地开发若遇 crates.io / pub 超时，可先设置：

```bash
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export HTTP_PROXY=$http_proxy
export HTTPS_PROXY=$https_proxy
```

`macos/build_rust.sh` 在未设置时会默认使用 `127.0.0.1:7890`。

## Flutter 版本（FVM）

工程使用 **FVM** 锁定 **stable** 通道（当前解析为 **Flutter 3.44.0**，Dart **3.12.0**）。

```bash
cd apps/volward
fvm install stable   # 首次
fvm use stable
fvm flutter pub get
fvm flutter run -d macos
```

配置见 `.fvmrc`、`.fvm/fvm_config.json`。IDE 请指向 `.fvm/flutter_sdk`（已提供 `.vscode/settings.json`）。

## 验证

```bash
cd volward
export CARGO_TARGET_DIR="$(pwd)/target"
cargo test
cargo run -p volward-cli

cd apps/volward
fvm flutter pub get
fvm flutter run -d macos
```

## 文档

- [PRD](../docs/volward/PRD.md)
- [ARCHITECTURE](../docs/volward/ARCHITECTURE.md)
- [IMPLEMENTATION-PLAN](../docs/volward/IMPLEMENTATION-PLAN.md)
