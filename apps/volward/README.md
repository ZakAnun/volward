# Volward Flutter App

macOS 桌面端 Flutter UI，依赖同仓库 Rust `libvolward_facade` dylib。支持即时目录预览、后台 checkpoint 合并与点击优先 Peek。

完整说明、功能列表与仓库结构见 **[仓库根目录 README](../../README.md)**。

## 运行

```bash
# 推荐：一键预检 Debug 签名、重建 Rust 并启动 macOS
bash scripts/run_macos_debug.sh

# 如需手动分步
cd macos && bash build_rust.sh
cd ..
fvm flutter pub get
fvm flutter run -d macos
```

## 测试

```bash
fvm flutter test
```

## 主要模块

| 路径 | 说明 |
|------|------|
| `lib/home_page.dart` | 单页主界面：预览、扫描、结果、列浏览、删除 |
| `lib/settings_page.dart` | 主题与 accent 设置 |
| `lib/volward_session.dart` | 扫描/删除会话、进度、`previewTarget` / `peekScan`、checkpoint 合并与 snapshot 恢复 |
| `lib/scan_preview.dart` | `quick_list_dir` → 即时预览 snapshot |
| `lib/scan_snapshot_merge.dart` | 子树合并（checkpoint upsert / peek 权威覆盖） |
| `lib/scan_tree_navigation.dart` | checkpoint 后按 path 刷新列导航链 |
| `lib/bridge/scan_worker.dart` | 主扫描 Isolate（含 checkpoint）与 peek Isolate |
| `lib/widgets/scan_filter_bar.dart` | 分类 / 排序 / 筛选 |
| `lib/widgets/scan_column_view.dart` | Finder 式列视图（未扫完目录加载态） |
| `lib/snapshot_cache.dart` | 读取磁盘 manifest / snapshot |
| `lib/theme/` | VolwardTokens、主题构建、settings 持久化 |
