# Volward Flutter App

macOS 桌面端 Flutter UI，依赖同仓库 Rust `libvolward_facade` dylib。

完整说明、功能列表与仓库结构见 **[仓库根目录 README](../../README.md)**。

## 运行

```bash
# 先编译 Rust（Rust 变更后必做）
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
| `lib/home_page.dart` | 单页主界面：扫描、结果、列浏览、删除 |
| `lib/settings_page.dart` | 主题与 accent 设置 |
| `lib/volward_session.dart` | 扫描/删除会话、进度、snapshot 恢复 |
| `lib/widgets/scan_filter_bar.dart` | 分类 / 排序 / 筛选 |
| `lib/widgets/scan_column_view.dart` | Finder 式列视图 |
| `lib/snapshot_cache.dart` | 读取磁盘 manifest / snapshot |
| `lib/theme/` | VolwardTokens、主题构建、settings 持久化 |
