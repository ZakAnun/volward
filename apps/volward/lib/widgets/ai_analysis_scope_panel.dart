import 'package:flutter/material.dart';

import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';
import 'ai_results_hub.dart';

/// Collapsible header row for the analysis scope block.
class AiAnalysisScopeSummaryRow extends StatelessWidget {
  const AiAnalysisScopeSummaryRow({
    super.key,
    required this.summaryLine,
    required this.expanded,
    required this.onToggle,
  });

  static const toggleKey = Key('ai-results-scope-panel-toggle');

  final String summaryLine;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: toggleKey,
        onTap: onToggle,
        borderRadius: BorderRadius.circular(AppleRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppleSpacing.sm,
            horizontal: AppleSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  summaryLine,
                  style: context.vwBodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                expanded ? '▴' : '▾',
                style: context.vwBodyStrong.copyWith(color: tokens.inkMuted80),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsible analysis scope block at the top of the results overview hub.
class AiAnalysisScopePanel extends StatefulWidget {
  const AiAnalysisScopePanel({
    super.key,
    required this.hubMode,
    required this.summaryLine,
    required this.expandedBodyBuilder,
    this.fillRemaining = false,
  });

  static const toggleKey = AiAnalysisScopeSummaryRow.toggleKey;

  final ResultsHubMode hubMode;
  final String summaryLine;
  final WidgetBuilder expandedBodyBuilder;
  final bool fillRemaining;

  @override
  State<AiAnalysisScopePanel> createState() => _AiAnalysisScopePanelState();
}

class _AiAnalysisScopePanelState extends State<AiAnalysisScopePanel> {
  bool? _userExpanded;

  bool get _expanded {
    final user = _userExpanded;
    if (user != null) return user;
    return widget.hubMode == ResultsHubMode.awaitingAnalysis;
  }

  @override
  void didUpdateWidget(covariant AiAnalysisScopePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hubMode != widget.hubMode) {
      _userExpanded = null;
      setState(() {});
    }
  }

  void _toggle() {
    setState(() => _userExpanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final header = AiAnalysisScopeSummaryRow(
      summaryLine: widget.summaryLine,
      expanded: _expanded,
      onToggle: _toggle,
    );

    if (!_expanded) {
      return header;
    }

    if (widget.fillRemaining) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(child: widget.expandedBodyBuilder(context)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, widget.expandedBodyBuilder(context)],
    );
  }
}
