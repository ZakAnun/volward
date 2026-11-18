import 'package:flutter/material.dart';

import '../../../widgets/apple_widgets.dart';

class StickyActionBar extends StatelessWidget {
  const StickyActionBar({
    super.key,
    required this.leading,
    required this.action,
  });

  final Widget leading;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return AppleStickyBar(leading: leading, action: action);
  }
}
