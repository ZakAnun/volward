import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/ai_analysis_gateway.dart';
import '../../ai/ai_coverage_coordinator.dart';
import '../../ai/coverage_job_state.dart';
import '../../ai/coverage_pause_messages.dart';
import '../../ai/coverage_client_logic.dart';
import '../../l10n/l10n.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/apple_widgets.dart';
import '../../widgets/top_toast.dart';
import 'ai_analysis_workspace_config.dart';
import 'ai_analysis_workspace_keys.dart';
import 'controllers/ai_analysis_workspace_page_controller.dart';
import 'ports/workspace_ports.dart';
import 'views/ai_analysis_workspace_messages.dart';
import 'views/ai_analysis_workspace_page_view.dart';
import 'views/ai_analysis_workspace_presenter.dart';

class AiAnalysisWorkspace extends StatefulWidget {
  const AiAnalysisWorkspace({
    super.key,
    required this.snapshotId,
    required this.targetLabel,
    required this.onExit,
    required this.onOpenSettings,
    required this.onDeletingChanged,
    required this.onDeleteCompleted,
    this.gateway = const ProductionAiAnalysisGateway(),
    this.coverageJobs,
    this.coverageOwner,
    this.ports,
    this.debugCoverageJobState,
    this.onOpenDetailPage,
  });

  static const workspaceKey = AiAnalysisWorkspaceKeys.workspace;
  static const backKey = AiAnalysisWorkspaceKeys.back;
  static const loadPreviousKey = AiAnalysisWorkspaceKeys.loadPrevious;
  static const analyzeAgainKey = AiAnalysisWorkspaceKeys.analyzeAgain;
  static const startAnalysisKey = AiAnalysisWorkspaceKeys.startAnalysis;
  static const settingsKey = AiAnalysisWorkspaceKeys.settings;
  static const resultsListKey = AiAnalysisWorkspaceKeys.resultsList;
  static const summaryKey = AiAnalysisWorkspaceKeys.summary;
  static const decisionSummaryKey = AiAnalysisWorkspaceKeys.decisionSummary;
  static const searchToggleKey = AiAnalysisWorkspaceKeys.searchToggle;
  static const searchSortSheetKey = AiAnalysisWorkspaceKeys.searchSortSheet;
  static const resultsFilterKey = AiAnalysisWorkspaceKeys.resultsFilter;
  static const resultsKeepExpandHintKey =
      AiAnalysisWorkspaceKeys.resultsKeepExpandHint;
  static const deleteKey = AiAnalysisWorkspaceKeys.delete;
  static const precheckDeleteKey = AiAnalysisWorkspaceKeys.precheckDelete;
  static const headerKey = AiAnalysisWorkspaceKeys.header;
  static const hubStatusChipKey = AiAnalysisWorkspaceKeys.hubStatusChip;
  static const selectedSummaryKey = AiAnalysisWorkspaceKeys.selectedSummary;
  static const pendingReviewKey = AiAnalysisWorkspaceKeys.pendingReview;
  static const conclusionsOverviewKey =
      AiAnalysisWorkspaceKeys.conclusionsOverview;
  static const resultsScopePanelKey = AiAnalysisWorkspaceKeys.resultsScopePanel;
  static const showAllResultsKey = AiAnalysisWorkspaceKeys.showAllResults;
  static const detailListSecondaryKey =
      AiAnalysisWorkspaceKeys.detailListSecondary;
  static const reviewQueuePrimaryKey =
      AiAnalysisWorkspaceKeys.reviewQueuePrimary;
  static const reviewQueueKey = AiAnalysisWorkspaceKeys.reviewQueue;
  static const detailListKey = AiAnalysisWorkspaceKeys.detailList;
  static const resultsHeroKey = AiAnalysisWorkspaceKeys.resultsHero;
  static const resultsMetricSafeKey = AiAnalysisWorkspaceKeys.resultsMetricSafe;
  static const resultsMetricReviewKey =
      AiAnalysisWorkspaceKeys.resultsMetricReview;
  static const resultsMetricKeepKey = AiAnalysisWorkspaceKeys.resultsMetricKeep;
  static const pendingPreviewKey = AiAnalysisWorkspaceKeys.pendingPreview;
  static const resultsPreviewSafeKey =
      AiAnalysisWorkspaceKeys.resultsPreviewSafe;
  static const resultsPreviewReviewKey =
      AiAnalysisWorkspaceKeys.resultsPreviewReview;
  static const backToConclusionsKey = AiAnalysisWorkspaceKeys.backToConclusions;
  static const conclusionNarrativeKey =
      AiAnalysisWorkspaceKeys.conclusionNarrative;
  static const conclusionNarrativeLoadingKey =
      AiAnalysisWorkspaceKeys.conclusionNarrativeLoading;
  static const conclusionNarrativeGenerateKey =
      AiAnalysisWorkspaceKeys.conclusionNarrativeGenerate;
  static const directoryGridKey = AiAnalysisWorkspaceKeys.directoryGrid;
  static const directoryTypeFilterKey =
      AiAnalysisWorkspaceKeys.directoryTypeFilter;

  static Key directoryCardKey(String path) =>
      AiAnalysisWorkspaceKeys.directoryCard(path);

  static Key directoryTypeChipKey(String type) =>
      AiAnalysisWorkspaceKeys.directoryTypeChip(type);

  final String snapshotId;
  final String targetLabel;
  final VoidCallback onExit;
  final VoidCallback onOpenSettings;
  final ValueChanged<bool> onDeletingChanged;
  final VoidCallback onDeleteCompleted;
  final AiAnalysisGateway gateway;
  final AiCoverageJobs? coverageJobs;
  final Object? coverageOwner;
  final AiWorkspacePorts? ports;

  @visibleForTesting
  final CoverageJobState? debugCoverageJobState;

  final ValueChanged<String>? onOpenDetailPage;

  AiAnalysisWorkspaceConfig toConfig({
    AiAnalysisWorkspacePresenter? presenter,
    AiAnalysisWorkspaceMessages? messages,
    VoidCallback? onResetResultsScroll,
    VoidCallback? onClearResultsSearch,
  }) => AiAnalysisWorkspaceConfig(
    snapshotId: snapshotId,
    targetLabel: targetLabel,
    onExit: onExit,
    onOpenSettings: onOpenSettings,
    onDeletingChanged: onDeletingChanged,
    onDeleteCompleted: onDeleteCompleted,
    gateway: gateway,
    coverageJobs: coverageJobs,
    coverageOwner: coverageOwner,
    ports: ports,
    debugCoverageJobState: debugCoverageJobState,
    onOpenDetailPage: onOpenDetailPage,
    presenter: presenter,
    messages: messages,
    onResetResultsScroll: onResetResultsScroll,
    onClearResultsSearch: onClearResultsSearch,
  );

  @override
  State<AiAnalysisWorkspace> createState() => _AiAnalysisWorkspaceState();
}

class _AiAnalysisWorkspaceState extends State<AiAnalysisWorkspace> {
  late final AiAnalysisWorkspacePageController pageController;
  late final _WorkspacePresenterAdapter _presenter;
  final ScrollController _resultsScrollController = ScrollController();
  final TextEditingController _resultsSearchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _presenter = _WorkspacePresenterAdapter(this);
    pageController =
        AiAnalysisWorkspacePageController(
            widget.toConfig(
              presenter: _presenter,
              messages: _presenter,
              onResetResultsScroll: () {
                if (_resultsScrollController.hasClients) {
                  _resultsScrollController.jumpTo(0);
                }
              },
              onClearResultsSearch: _resultsSearchController.clear,
            ),
          )
          ..addListener(_handleControllerChanged)
          ..initialize();
  }

  @override
  void didUpdateWidget(covariant AiAnalysisWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldConfig = oldWidget.toConfig(presenter: _presenter);
    pageController.page = widget.toConfig(
      presenter: _presenter,
      messages: _presenter,
    );
    pageController.updateConfig(oldConfig);
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    pageController
      ..removeListener(_handleControllerChanged)
      ..dispose();
    _presenter.dispose();
    _resultsScrollController.dispose();
    _resultsSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = pageController.buildViewState();
    final actions = pageController.viewActions;
    return AiAnalysisWorkspacePageView(
      state: state,
      actions: actions,
      onOpenSettings: widget.onOpenSettings,
      onBack: state.delete.busy ? null : actions.goBack,
    );
  }
}

class _WorkspacePresenterAdapter
    implements AiAnalysisWorkspacePresenter, AiAnalysisWorkspaceMessages {
  _WorkspacePresenterAdapter(this._state);

  final _AiAnalysisWorkspaceState _state;
  final List<TextEditingController> _transientControllers = [];

  void dispose() {
    for (final controller in _transientControllers) {
      controller.dispose();
    }
    _transientControllers.clear();
  }

  void _retain(TextEditingController controller) {
    _transientControllers.add(controller);
  }

  @override
  Future<bool> confirm({required String title, required String message}) async {
    if (!_state.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: _state.context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Future<int?> promptCredits({
    required int? currentValue,
    required int? estimate,
  }) async {
    if (!_state.mounted) return null;
    final controller = TextEditingController(text: estimate?.toString() ?? '');
    final confirmed = await showDialog<bool>(
      context: _state.context,
      builder: (dialogContext) => AlertDialog(
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    _retain(controller);
    if (confirmed != true) return null;
    return int.tryParse(text);
  }

  @override
  Future<String?> promptText({
    required String title,
    String? initialValue,
  }) async {
    if (!_state.mounted) return null;
    final controller = TextEditingController(text: initialValue ?? '');
    final confirmed = await showDialog<bool>(
      context: _state.context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    _retain(controller);
    if (confirmed != true) return null;
    return text;
  }

  @override
  void showToast(String message) {
    if (!_state.mounted) return;
    showTopToast(_state.context, message: message);
  }

  @override
  void openSettings() => _state.widget.onOpenSettings();

  @override
  void openDetailPage(String path) {
    _state.widget.onOpenDetailPage?.call(path);
  }

  @override
  Future<void> copyText(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
  }

  @override
  void exitWorkspace() => _state.widget.onExit();

  @override
  void schedulePostFrame(void Function() callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_state.mounted) callback();
    });
  }

  @override
  AppLocalizations get l10n => _state.context.l10n;

  @override
  String coverageFailedReason(
    CoveragePauseDetail? detail, {
    String? pauseMessage,
  }) {
    return l10n.aiCoverageFailedReason(
      coverageFailedReasonCategory(l10n, detail, pauseMessage: pauseMessage),
    );
  }

  @override
  Future<bool> confirmPrivacy() async {
    if (!_state.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: _state.context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.aiPrivacyTitle),
        content: Text(l10n.aiPrivacyBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.scanActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.aiPrivacyAccept),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Future<bool> confirmLegacyResume() async {
    if (!_state.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: _state.context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.aiCoverageLegacyResumeTitle),
        content: Text(l10n.aiCoverageLegacyResumeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.scanActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.aiCoverageLegacyResumeConfirm),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Future<bool> confirmFailedResume(CoverageJobState state) async {
    if (!_state.mounted) return false;
    final count = state.failedBatchPaths.isNotEmpty
        ? state.failedBatchPaths.length
        : 1;
    final body = state.creditsChargedNoVerdict > 0
        ? l10n.aiCoverageFailedResumeBody(state.creditsChargedNoVerdict, count)
        : l10n.aiCoverageFailedResumeBodyNoCredit(count);
    final confirmed = await showDialog<bool>(
      context: _state.context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.aiCoverageFailedResumeTitle),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.scanActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.aiCoverageFailedResumeConfirm),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Future<bool> confirmRestartFull() async {
    if (!_state.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: _state.context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.aiCoverageRestartFullTitle),
        content: Text(l10n.aiCoverageRestartFullBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.scanActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.aiCoverageRestartFullConfirm),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Future<bool> confirmBillingModeMismatch(CoverageJobState job) async {
    if (!_state.mounted) return false;
    final body = switch (coverageJobBillingKind(job)) {
      CoverageJobBillingKind.tokens =>
        l10n.aiCoverageJobBillingModeMismatchPlatform(
          job.budgetTokens,
          job.usedTokens,
        ),
      CoverageJobBillingKind.credits =>
        l10n.aiCoverageJobBillingModeMismatchByok(
          job.usedCredits,
          job.budgetCredits,
        ),
      CoverageJobBillingKind.unset =>
        l10n.aiCoverageJobBillingModeMismatchBanner(l10n.aiSettingsOffLabel),
    };
    var restart = false;
    await showDialog<void>(
      context: _state.context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.aiCoverageJobBillingModeMismatchTitle),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.scanActionCancel),
          ),
          TextButton(
            onPressed: () {
              restart = true;
              Navigator.pop(dialogContext);
            },
            child: Text(l10n.aiCoverageRestartFull),
          ),
        ],
      ),
    );
    return restart;
  }

  @override
  Future<int?> promptCoverageBudget({
    required bool isTokenBudget,
    required int suggested,
  }) async {
    if (!_state.mounted) return null;
    final controller = TextEditingController(text: '$suggested');
    final confirmed = await showDialog<bool>(
      context: _state.context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.aiCoverageRaiseBudgetTitle),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isTokenBudget
                ? l10n.aiSettingsCoverageBudgetTokensHint
                : l10n.aiSettingsCoverageBudgetCreditsHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.scanActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.aiCoverageRaiseBudget),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    _retain(controller);
    if (confirmed != true) return null;
    return int.tryParse(text);
  }

  @override
  Future<bool> confirmDelete({
    required int count,
    required String freedLabel,
  }) async {
    if (!_state.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: _state.context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmMessage(count, freedLabel)),
        actions: [
          AppleButton(
            label: l10n.scanActionCancel,
            variant: AppleButtonVariant.pearl,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          AppleButton(
            label: l10n.deleteActionDelete,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  void toastCoverageBusyOtherSnapshot() {
    if (!_state.mounted) return;
    showTopToast(_state.context, message: l10n.aiCoverageBusyOtherSnapshot);
  }

  @override
  void toastCoverageBudgetInvalid() {
    if (!_state.mounted) return;
    showTopToast(_state.context, message: l10n.aiCoverageBudgetInvalid);
  }
}
