import 'package:flutter/material.dart';

import '../../../ai/ai_analysis_activity_model.dart';
import '../../../widgets/ai_analysis_activity_card.dart';

class AnalysisActivityView extends StatelessWidget {
  const AnalysisActivityView({
    super.key,
    required this.model,
    required this.substageLabel,
    this.compact = false,
    this.freezeActiveMotion = false,
  });

  final AiAnalysisActivityModel model;
  final String Function(AiActivitySubstage) substageLabel;
  final bool compact;
  final bool freezeActiveMotion;

  @override
  Widget build(BuildContext context) {
    return AiAnalysisActivityCard(
      variant: compact
          ? AiAnalysisActivityCardVariant.compact
          : AiAnalysisActivityCardVariant.expanded,
      model: model,
      substageLabel: substageLabel,
      freezeActiveMotion: freezeActiveMotion,
    );
  }
}
