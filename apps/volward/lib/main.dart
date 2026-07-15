import 'package:flutter/material.dart';

import 'features/confirm/confirm_page.dart';
import 'features/overview/overview_page.dart';
import 'features/results/results_page.dart';
import 'features/scan/scan_page.dart';
import 'theme/volward_theme.dart';
import 'volward_session.dart';
import 'widgets/volward_shell.dart';

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
      home: VolwardHome(session: _session),
    );
  }
}

class VolwardHome extends StatefulWidget {
  const VolwardHome({super.key, required this.session});

  final VolwardSession session;

  @override
  State<VolwardHome> createState() => _VolwardHomeState();
}

class _VolwardHomeState extends State<VolwardHome> {
  int _index = 0;

  static const _destinations = [
    ('Overview', Icons.dashboard_outlined),
    ('Scan', Icons.search),
    ('Results', Icons.list_alt),
    ('Confirm', Icons.check_circle_outline),
  ];

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final pages = [
      OverviewPage(session: widget.session),
      ScanPage(session: widget.session),
      ResultsPage(session: widget.session),
      ConfirmPage(session: widget.session),
    ];

    return VolwardShell(
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      destinations: _destinations,
      body: IndexedStack(index: _index, children: pages),
    );
  }
}
