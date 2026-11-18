import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class BrowseResultsPane extends StatelessWidget {
  const BrowseResultsPane({
    super.key,
    required this.revision,
    required this.builder,
  });

  final ValueListenable<int> revision;
  final Widget Function(BuildContext) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      key: const Key('volward-browse-results'),
      valueListenable: revision,
      builder: (context, _, _) => builder(context),
    );
  }
}
