// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Volward';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAppearanceSection => '外观';

  @override
  String get settingsThemeTitle => '主题';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsAccentColorTitle => '强调色';

  @override
  String get settingsAccentColorDescription => '应用于按钮、选中态和进度指示器。';

  @override
  String get settingsAccentPreview => '预览';

  @override
  String get settingsAccentPrimary => '主色';

  @override
  String get settingsLanguageTitle => '语言';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get settingsLanguageChinese => '中文';

  @override
  String get settingsLanguageEnglish => '英文';

  @override
  String get settingsScanResultsSection => '扫描与结果';

  @override
  String get settingsDeletableOnlyTitle => '只显示可清理项';

  @override
  String get settingsDeletableOnlyDescription =>
      '仅展示 Volward 判定为低风险清理候选的文件，目前主要是缓存和临时文件。';

  @override
  String get settingsIncrementalScanTitle => '增量扫描';

  @override
  String get settingsIncrementalScanDescription =>
      '扫描同一目录时复用上次未变化的子目录结果，加快后续扫描。';

  @override
  String get settingsIncrementalScanUnsupported =>
      '当前 Rust 库不支持该扫描模式，需要重新 build Rust 后使用。';

  @override
  String get filterAll => '全部';

  @override
  String get filterCategoryCache => '缓存';

  @override
  String get filterCategoryTemp => '临时文件';

  @override
  String get filterCategoryMedia => '媒体';

  @override
  String get filterCategorySystem => '系统';

  @override
  String get sortSizeDesc => '大小 ↓';

  @override
  String get sortSizeAsc => '大小 ↑';

  @override
  String get sortNameAsc => '名称';

  @override
  String get scanColumnPreparingFolder => '正在准备文件夹…';

  @override
  String get scanColumnNoFilterMatches => '没有匹配当前筛选的项目。';

  @override
  String get navSubtitle => '存储管家';

  @override
  String get settingsTooltip => '设置';

  @override
  String get scanActionFolder => '选择文件夹…';

  @override
  String get scanActionHome => '主目录';

  @override
  String get scanActionCancel => '取消';

  @override
  String get scanActionStart => '开始扫描';

  @override
  String get scanActionRescan => '刷新';

  @override
  String get trashActionEmpty => '清空废纸篓';

  @override
  String get trashEmptyConfirmTitle => '清空废纸篓？';

  @override
  String get trashEmptyConfirmMessage => '将废纸篓中的所有内容永久删除？此操作不可撤销。';

  @override
  String get trashEmptySuccess => '废纸篓已清空，结果已刷新。';

  @override
  String trashEmptyFailed(Object error) {
    return '清空废纸篓失败：$error';
  }

  @override
  String get deleteActionMoveToTrash => '移到废纸篓';

  @override
  String get deleteActionWorking => '处理中…';

  @override
  String get deleteConfirmTitle => '移到废纸篓？';

  @override
  String deleteConfirmMessage(int count, Object bytes) {
    return '将 $count 个项目移到废纸篓，预计释放 $bytes？\n\n需要时可以从废纸篓恢复。';
  }

  @override
  String get deleteActionDelete => '删除';

  @override
  String deleteSuccessWithFailures(int failedCount, Object bytes) {
    return '删除完成，但有 $failedCount 个失败。已释放 $bytes。';
  }

  @override
  String deleteSuccess(Object bytes) {
    return '已移到废纸篓，释放 $bytes。重新扫描完成。';
  }

  @override
  String deleteFailed(Object error) {
    return '删除失败：$error';
  }

  @override
  String get permissionNativeOutdatedTitle => '原生库版本过旧';

  @override
  String get permissionNativeOutdatedDescription =>
      '请为当前平台重新构建原生 Rust 库，并完整重启应用。';

  @override
  String get permissionDeepScanReady => '深度扫描可用。';

  @override
  String get permissionFullDiskRecommended => '建议开启完全磁盘访问，以扫描 ~/Library 缓存。';

  @override
  String get permissionFullDiskRecommendedTitle => '建议开启完全磁盘访问';

  @override
  String get permissionFullDiskInstructions =>
      '系统设置 → 隐私与安全性 → 完全磁盘访问 → 启用 Volward。调试构建：点击 +，按 Cmd+Shift+G，选择 volward.app。';

  @override
  String get permissionOpenSettings => '打开设置';

  @override
  String get permissionShowDetails => '显示详情';

  @override
  String get permissionHideDetails => '收起详情';

  @override
  String get permissionCopyAppPath => '复制 .app 路径';

  @override
  String get permissionCheckAgain => '重新检查';

  @override
  String permissionCopiedPath(Object path) {
    return '已复制：$path';
  }

  @override
  String permissionAppPath(Object path) {
    return '应用路径：$path';
  }

  @override
  String get permissionUnknownPath => '未知';

  @override
  String get folderPickerConfirm => '选择';

  @override
  String get scanTargetTitle => '扫描目标';

  @override
  String get scanTargetHomeDefault => '主目录（默认）';

  @override
  String get scanTargetHomeShort => '主目录';

  @override
  String get scanTargetCustomShort => '自定义';

  @override
  String get scanHomeLongRunningHint => '主目录全量扫描在大账户上可能需要较长时间，请关注上方项目数量。';

  @override
  String resultsClassifiedCount(int count) {
    return '$count 个已分类';
  }

  @override
  String resultsReclaimableBytes(Object bytes) {
    return '可清理 $bytes';
  }

  @override
  String resultsTreeSummary(int count, Object bytes) {
    return '树中 $count 项 · $bytes';
  }

  @override
  String get resultsUpdating => '正在更新结果…';

  @override
  String get resultsNoFilterMatches => '没有匹配当前筛选的项目。';

  @override
  String resultsNoFilterMatchesWithCount(int count) {
    return '没有匹配当前筛选的项目（列表中 $count 项）。';
  }

  @override
  String resultsNoFilesUnder(Object path) {
    return '$path 下没有扫描到文件。';
  }

  @override
  String get resultsRestoringPreviousScan => '正在恢复上次扫描…';

  @override
  String get previewSelectPrompt => '选择一个文件夹或文件';

  @override
  String get previewFolderCategory => '文件夹';

  @override
  String previewItemCount(int count) {
    return '$count 个项目';
  }

  @override
  String get scanStatusScanning => '扫描中…';

  @override
  String get scanPhaseDiscoveringRoots => '正在发现扫描根目录…';

  @override
  String get scanPhaseWalking => '正在扫描文件…';

  @override
  String get scanPhaseClassifying => '正在分类项目…';

  @override
  String get scanPhaseAggregating => '正在汇总结果…';

  @override
  String get scanPhaseSavingResults => '正在保存结果…';

  @override
  String get scanPhaseLoadingResults => '正在加载结果…';

  @override
  String get scanPhaseDone => '完成';

  @override
  String scanProgressItems(int count) {
    return '$count 项';
  }

  @override
  String get scanStatusCancelled => '扫描已取消';

  @override
  String scanStatusFailed(Object error) {
    return '扫描失败：$error';
  }

  @override
  String get scanStatusFull => '全量';

  @override
  String get scanStatusIncremental => '增量';

  @override
  String scanStatusFiles(Object mode, int count) {
    return '$mode扫描：$count 个文件';
  }

  @override
  String stickySelected(int count, Object bytes) {
    return '已选择：$count · $bytes';
  }

  @override
  String stickyDirectoriesLoading(int count) {
    return '$count 个目录加载中…';
  }

  @override
  String get stickyBrowseResults => '选择要移到废纸篓的项目';

  @override
  String get stickyReadyToScan => '准备扫描';

  @override
  String get stickyLoadingEngine => '正在加载引擎…';

  @override
  String get settingsAboutSection => '关于';

  @override
  String settingsCurrentVersion(Object version) {
    return '版本 $version';
  }

  @override
  String get settingsCheckForUpdates => '检查更新';

  @override
  String get settingsCheckingForUpdates => '正在检查…';

  @override
  String get settingsUpToDate => '已是最新版本。';

  @override
  String settingsUpdateAvailable(Object version) {
    return '发现新版本：$version';
  }

  @override
  String get settingsUpdateNow => '立即更新';

  @override
  String get settingsUpdateLater => '稍后';

  @override
  String settingsDownloadingUpdate(int percent) {
    return '正在下载更新… $percent%';
  }

  @override
  String get settingsInstallingUpdate => '正在安装更新…';

  @override
  String settingsUpdateError(Object error) {
    return '检查更新失败：$error';
  }

  @override
  String settingsUpdateActionError(Object error) {
    return '更新失败：$error';
  }

  @override
  String get settingsOpenDownloadPage => '打开下载页';

  @override
  String updateAvailableTitle(Object version) {
    return '发现新版本 — $version';
  }

  @override
  String updateAvailableMessage(Object notes) {
    return '$notes';
  }

  @override
  String get updateNotesUnavailable => '有新的 Volward 版本可以安装。';

  @override
  String get aiAnalysisTitle => 'AI 磁盘分析';

  @override
  String aiPreCheckSafeTitle(int count) {
    return '$count 项已预判为可安全移除';
  }

  @override
  String aiPreCheckSafeSelectable(int count) {
    return '$count 项已由本地规则标记为安全';
  }

  @override
  String aiPreCheckUnknownTitle(int count, int tokens) {
    return '$count 项将发送给 AI 分析（约 $tokens tokens）';
  }

  @override
  String get aiStartAnalysis => '开始 AI 分析';

  @override
  String get aiNoApiKey => '未配置 API Key — 请在设置中配置';

  @override
  String get aiContractUnavailable => '当前原生库版本过旧，请更新 Volward 后再使用 AI 分析。';

  @override
  String aiDeleteSelected(int count) {
    return '删除选中的 $count 项';
  }

  @override
  String aiVerdictSafe(int count) {
    return '可安全移除（$count）';
  }

  @override
  String aiVerdictReview(int count) {
    return '建议检查（$count）';
  }

  @override
  String aiVerdictKeep(int count) {
    return '保留（$count）';
  }

  @override
  String get aiSettingsTitle => 'AI 分析';

  @override
  String get aiSettingsModeLabel => '模式';

  @override
  String get aiSettingsByokLabel => '自带密钥（DeepSeek）';

  @override
  String get aiSettingsPlatformLabel => 'Volward 平台（即将推出）';

  @override
  String get aiSettingsApiKeyHint => 'sk-...';

  @override
  String get aiSettingsApiKeySaved => 'API 密钥已保存';

  @override
  String get aiSettingsApiKeyCleared => 'API 密钥已清除';

  @override
  String get aiSettingsSaveKey => '保存';

  @override
  String get aiSettingsClearKey => '清除';

  @override
  String get aiAnalysisFab => 'AI 分析';

  @override
  String get aiPrivacyTitle => 'AI 分析隐私说明';

  @override
  String get aiPrivacyBody =>
      '仅发送路径、大小和文件数量。绝不上传文件内容。BYOK 模式下数据直接发送至你的 AI 服务商。';

  @override
  String get aiPrivacyAccept => '我已了解';

  @override
  String get aiOverwriteTitle => '已有分析结果';

  @override
  String get aiOverwriteBody => '此扫描已有 AI 分析结果。可加载上次结果，或重新分析以覆盖。';

  @override
  String get aiActionContinue => '重新分析';

  @override
  String get aiActionLoadPrevious => '加载上次结果';

  @override
  String get aiLoadPreviousFailed => '无法加载上次的 AI 分析结果。';

  @override
  String get aiAnalyzing => 'AI 分析中…';

  @override
  String get aiActionRetry => '重试';

  @override
  String get aiErrorUnknown => '未知错误';

  @override
  String get aiErrorNativeUnavailable => '无法加载 AI 候选项（原生接口不可用）。';

  @override
  String get aiErrorInvalidPayload => '候选项数据格式无效。';

  @override
  String aiTruncatedNotice(int shown, int total) {
    return '共 $total 项，已显示其中最大的 $shown 项，其余已跳过以控制请求体积。';
  }

  @override
  String get back => '返回';
}
