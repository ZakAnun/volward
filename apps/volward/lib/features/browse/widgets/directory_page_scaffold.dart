import 'package:flutter/material.dart';

class DirectoryPageScaffold extends StatelessWidget {
  const DirectoryPageScaffold({
    super.key,
    required this.backgroundColor,
    required this.body,
  });

  final Color backgroundColor;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: backgroundColor, body: body);
  }
}
