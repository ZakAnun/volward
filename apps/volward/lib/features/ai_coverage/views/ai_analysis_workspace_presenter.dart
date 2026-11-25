/// UI effects the workspace controllers need, owned by the presentation layer.
abstract interface class AiAnalysisWorkspacePresenter {
  Future<bool> confirm({required String title, required String message});

  Future<int?> promptCredits({
    required int? currentValue,
    required int? estimate,
  });

  Future<String?> promptText({required String title, String? initialValue});

  void showToast(String message);

  void openSettings();

  void openDetailPage(String path);

  Future<void> copyText(String value);

  void exitWorkspace();

  void schedulePostFrame(void Function() callback);
}
