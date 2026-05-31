import 'package:flutter/material.dart';

import 'features/confirm/confirm_page.dart';
import 'features/overview/overview_page.dart';
import 'features/results/results_page.dart';
import 'features/scan/scan_page.dart';
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B6B5C)),
        useMaterial3: true,
      ),
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

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Scan'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Results'),
          NavigationDestination(icon: Icon(Icons.check_circle_outline), label: 'Confirm'),
        ],
      ),
    );
  }
}
