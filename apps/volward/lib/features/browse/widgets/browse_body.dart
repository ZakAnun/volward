import 'package:flutter/material.dart';

/// Chooses the loading, empty, or results body for browse mode.
class BrowseBody extends StatelessWidget {
  const BrowseBody({
    super.key,
    required this.restoring,
    required this.loadingTarget,
    required this.hasResults,
    required this.scanSection,
    required this.restoreLoading,
    required this.emptyBody,
    required this.resultsBody,
  });

  final bool restoring;
  final bool loadingTarget;
  final bool hasResults;
  final Widget scanSection;
  final Widget restoreLoading;
  final Widget emptyBody;
  final Widget resultsBody;

  @override
  Widget build(BuildContext context) {
    if ((restoring || loadingTarget) && !hasResults) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          scanSection,
          Expanded(child: restoreLoading),
        ],
      );
    }
    if (hasResults) return resultsBody;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: scanSection),
        SliverToBoxAdapter(child: emptyBody),
      ],
    );
  }
}
