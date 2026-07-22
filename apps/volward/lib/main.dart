import 'package:flutter/material.dart';

import 'home_page.dart';
import 'theme/volward_theme.dart';
import 'volward_session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VolwardApp());
}

class VolwardApp extends StatefulWidget {
  const VolwardApp({super.key});

  @override
  State<VolwardApp> createState() => _VolwardAppState();
}

class _VolwardAppState extends State<VolwardApp> {
  late final VolwardSession _session;

  @override
  void initState() {
    super.initState();
    _session = VolwardSession();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Volward',
      theme: buildVolwardTheme(),
      home: HomePage(session: _session),
    );
  }
}
