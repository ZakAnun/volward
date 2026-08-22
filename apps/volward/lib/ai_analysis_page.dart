import 'package:flutter/material.dart';

import 'widgets/ai_analysis_workspace.dart';

/// Temporary route wrapper while callers migrate to [AiAnalysisWorkspace].
class AiAnalysisPage extends StatelessWidget {
  const AiAnalysisPage({super.key, required this.snapshotId});

  final String snapshotId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AiAnalysisWorkspace(
        snapshotId: snapshotId,
        targetLabel: '',
        onExit: () => Navigator.of(context).maybePop(),
        onOpenSettings: () {},
        onDeletingChanged: (_) {},
        onDeleteCompleted: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
