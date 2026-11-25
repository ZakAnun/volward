import 'package:flutter_test/flutter_test.dart';
import 'package:volward/capabilities/capability_models.dart';
import 'package:volward/snapshot_query.dart';
import 'package:volward/volward_session.dart';

void main() {
  test('VolwardSession keeps the delegated public API inventory', () {
    final session = VolwardSession.test();
    addTearDown(session.dispose);

    final Future<Map<String, dynamic>> Function(
      List<String>, {
      String? expectedSnapshotId,
      bool dryRun,
      bool rescanAfterDelete,
      String? refreshPath,
      Map<String, String>? targetPathById,
    })
    deleteEntries = session.deleteEntries;
    final Future<Map<String, dynamic>> Function({bool rescanAfterEmpty})
    emptyTrash = session.emptyTrash;
    final Future<void> Function([String? path]) refreshCurrentDirectory =
        session.refreshCurrentDirectory;
    final List<SnapshotNodeRecord>? Function(
      String, {
      String? categoryFilter,
      bool deletableOnly,
      String sortMode,
    })
    queryChildren = session.queryDirectoryChildrenFromCatalog;
    final void Function(List<String>) setScanRoots = session.setScanRoots;
    final Future<void> Function(String?, {bool validateBeforeSwitch})
    switchRoot = session.switchScanRoot;
    final Future<bool> Function(String, {bool force}) peekScan =
        session.peekScan;
    final void Function(bool) setIncremental = session.setIncrementalScan;
    final Future<CapabilityAnalysisResult> Function({
      required String snapshotId,
      required Capability capability,
      AnalysisOptions? options,
    })
    analyzeCapability = session.analyzeCapability;
    final String Function({
      required String snapshotId,
      required Capability capability,
      AnalysisOptions? options,
    })
    startCapabilityAnalysis = session.startCapabilityAnalysis;
    final CapabilityJobStatus Function(String) capabilityStatus =
        session.getCapabilityJobStatus;
    final bool Function(String) cancelCapability =
        session.cancelCapabilityAnalysis;
    final Stream<CapabilityAnalysisProgress> Function(
      String, {
      Duration pollInterval,
    })
    watchCapability = session.watchCapabilityJob;

    expect(deleteEntries, isNotNull);
    expect(emptyTrash, isNotNull);
    expect(refreshCurrentDirectory, isNotNull);
    expect(queryChildren, isNotNull);
    expect(setScanRoots, isNotNull);
    expect(switchRoot, isNotNull);
    expect(peekScan, isNotNull);
    expect(setIncremental, isNotNull);
    expect(analyzeCapability, isNotNull);
    expect(startCapabilityAnalysis, isNotNull);
    expect(capabilityStatus, isNotNull);
    expect(cancelCapability, isNotNull);
    expect(watchCapability, isNotNull);
  });
}
