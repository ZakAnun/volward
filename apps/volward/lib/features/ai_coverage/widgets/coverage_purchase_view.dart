import 'package:flutter/material.dart';

class CoveragePurchaseView extends StatelessWidget {
  const CoveragePurchaseView({
    super.key,
    required this.title,
    required this.body,
    required this.action,
  });

  final Widget title;
  final Widget body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        const SizedBox(height: 8),
        body,
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: action),
      ],
    );
  }
}
