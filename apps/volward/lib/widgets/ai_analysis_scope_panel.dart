import 'package:flutter/material.dart';

import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';
import 'ai_results_hub.dart';

/// Collapsible analysis scope block at the top of the results overview hub.
class AiAnalysisScopePanel extends StatefulWidget {
  const AiAnalysisScopePanel({
    super.key,
    required this.hubMode,
    required this.summaryLine,
    required this.expandedBody,
    this.fillRemaining = false,
  });

  static const toggleKey = Key('ai-results-scope-panel-toggle');

  final ResultsHubMode hubMode;
  final String summaryLine;
  final Widget expandedBody;
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
    if (oldWidget.hubMode != widget.hubMode && _userExpanded == null) {
      setState(() {});
    }
  }

  void _toggle() {
    setState(() => _userExpanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final header = Material(
      color: Colors.transparent,
      child: InkWell(
        key: AiAnalysisScopePanel.toggleKey,
        onTap: _toggle,
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
                  widget.summaryLine,
                  style: context.vwBodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                _expanded
                    ? Icons.expand_less_outlined
                    : Icons.expand_more_outlined,
                color: tokens.inkMuted80,
              ),
            ],
          ),
        ),
      ),
    );

    if (!_expanded) {
      return header;
    }

    if (widget.fillRemaining) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(child: widget.expandedBody),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, widget.expandedBody],
    );
  }
}
