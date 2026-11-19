import 'package:flutter/material.dart';

class AnalysisResultsView extends StatelessWidget {
  const AnalysisResultsView({super.key, required this.body, this.footer});

  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: body),
        if (footer case final footer?) footer,
      ],
    );
  }
}
