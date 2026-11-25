import 'package:flutter/material.dart';

import '../../../theme/volward_tokens.dart';
import '../../../widgets/home/dashboard_theme.dart';
import '../ai_analysis_workspace_keys.dart';
import 'ai_analysis_workspace_body_view.dart';
import 'ai_analysis_workspace_header.dart';
import 'ai_analysis_workspace_view_actions.dart';
import 'ai_analysis_workspace_view_state.dart';

/// The AI workspace shell: header, divider and the active section body.
///
/// This view owns the chrome and composes [AiAnalysisWorkspaceBodyView]; it
/// never imports the page controller.
class AiAnalysisWorkspacePageView extends StatefulWidget {
  const AiAnalysisWorkspacePageView({
    super.key,
    required this.state,
    required this.actions,
    required this.onOpenSettings,
    required this.onBack,
  });

  final AiAnalysisWorkspaceViewState state;
  final AiAnalysisWorkspaceViewActions actions;
  final VoidCallback onOpenSettings;
  final VoidCallback? onBack;

  @override
  State<AiAnalysisWorkspacePageView> createState() =>
      _AiAnalysisWorkspacePageViewState();
}

class _AiAnalysisWorkspacePageViewState
    extends State<AiAnalysisWorkspacePageView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    return DecoratedBox(
      key: AiAnalysisWorkspaceKeys.workspaceKey,
      decoration: dashboardPanelDecoration(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            AiAnalysisWorkspaceHeader(
              shell: widget.state.overview,
              onBack: widget.onBack,
            ),
            Divider(height: 1, color: tokens.dividerSoft),
            Expanded(
              child: AiAnalysisWorkspaceBodyView(
                state: widget.state,
                actions: widget.actions,
                onOpenSettings: widget.onOpenSettings,
                scrollController: _scrollController,
                searchController: _searchController,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
