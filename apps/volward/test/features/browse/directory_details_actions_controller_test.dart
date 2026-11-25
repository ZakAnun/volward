import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/core/contracts/scan_contracts.dart';
import 'package:volward/features/browse/controllers/directory_browse_controller.dart';
import 'package:volward/features/browse/controllers/directory_details_actions.dart';
import 'package:volward/features/browse/controllers/directory_details_ports.dart';
import 'package:volward/features/browse/controllers/directory_details_query.dart';
import 'package:volward/features/browse/controllers/scan_presentation_controller.dart';
import 'package:volward/features/browse/directory_browse_session.dart';
import 'package:volward/features/deletion/deletion_actions.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/storage_overview.dart';
import 'package:volward/widgets/top_toast.dart';

void main() {
  late DirectoryDetailsActionsController actions;
  late DirectoryQueryController query;
  late DirectoryBrowseController browse;
  late _FakeSnapshot snapshot;
  late _FakeBrowse browseSession;
  late _FakeScan scan;
  late _FakeDeletion deletion;
  late _FakeActionState state;
  late ScanPresentationController presentation;
  final toasts = <(String, ToastType)>[];
  final overviewLoads = <String?>[];
  var mounted = true;
  bool? confirmResult;
  final confirmDialogs = <AlertDialog>[];

  setUp(() {
    mounted = true;
    toasts.clear();
    overviewLoads.clear();
    confirmDialogs.clear();
    snapshot = _FakeSnapshot();
    browseSession = _FakeBrowse();
    scan = _FakeScan(snapshot);
    deletion = _FakeDeletion();
    state = _FakeActionState();
    browse = DirectoryBrowseController();
    presentation = ScanPresentationController();
    query = DirectoryQueryController(
      session: snapshot,
      browse: browseSession,
      browseController: browse,
      scanPresentationController: presentation,
      isMounted: () => mounted,
      applySetState: (fn) => fn(),
      l10n: () => lookupAppLocalizations(const Locale('en')),
    );
    actions = DirectoryDetailsActionsController(
      session: snapshot,
      scan: scan,
      browse: browseSession,
      deletion: deletion,
      state: state,
      browseController: browse,
      query: query,
      isMounted: () => mounted,
      applySetState: (fn) => fn(),
      l10n: () => lookupAppLocalizations(const Locale('en')),
      showConfirm: (dialog) async {
        confirmDialogs.add(dialog);
        return confirmResult;
      },
      showToast: (message, type) => toasts.add((message, type)),
      attachedSession: () => Object(),
      isStartupPendingFor: (_) => false,
      loadOverview: overviewLoads.add,
      directoryPicker: ({required String confirmButtonText}) async => '/new',
    );
  });

  tearDown(() {
    presentation.dispose();
    browse.dispose();
  });

  test(
    'pickFolder switches root, enters browse and reloads the overview',
    () async {
      state.storageOverview = _overview();
      state.hasValidRoot = false;
      state.isBrowsing = false;

      await actions.pickFolder();

      expect(scan.switchedRoots, ['/new']);
      expect(state.homeTargetPath, '/new');
      expect(state.isBrowsing, isTrue);
      expect(overviewLoads, ['/new']);
      expect(snapshot.rememberedRoots, ['/new']);
    },
  );

  test(
    'confirmDelete runs the delete with refresh targeting and clears selection',
    () async {
      confirmResult = true;
      browse.selected.add('/a.bin');
      browse.selectedPaths['/a.bin'] = '/a.bin';
      browse.selectedSizes['/a.bin'] = 64;
      deletion.deleteResponse = {'deleted_count': 1, 'freed_bytes': 64};

      await actions.confirmDelete();

      expect(deletion.deleteCalls, hasLength(2));
      expect(deletion.deleteCalls.first.dryRun, isTrue);
      final commit = deletion.deleteCalls.last;
      expect(commit.dryRun, isFalse);
      expect(commit.rescanAfterDelete, isTrue);
      expect(commit.targets, ['/a.bin']);
      expect(commit.refreshPath, '/');
      expect(commit.targetPathById, {'/a.bin': '/a.bin'});
      expect(browse.selected, isEmpty);
      expect(toasts.single.$2, ToastType.success);
    },
  );

  test('confirmDelete cancellation skips the commit', () async {
    confirmResult = false;
    browse.selected.add('/a.bin');
    deletion.deleteResponse = {};

    await actions.confirmDelete();

    expect(deletion.deleteCalls, hasLength(1));
    expect(deletion.deleteCalls.single.dryRun, isTrue);
    expect(browse.selected, isNotEmpty);
  });

  test('confirmEmptyTrash cancellation never empties the trash', () async {
    confirmResult = false;

    await actions.confirmEmptyTrash();

    expect(deletion.emptyTrashCalls, 0);
  });

  test('canStartScan requires a valid resolved root', () {
    state.startupRootGate = Completer<bool>()..complete(true);
    state.hasValidRoot = false;

    expect(actions.canStartScan, isFalse);
  });

  test('startScan ignores stale generations', () async {
    state.startupRootGate = Completer<bool>()..complete(true);
    state.hasValidRoot = true;
    state.scanStartGeneration = 7;

    await actions.startScan(Object(), 3);

    expect(scan.runScanCalls, 0);
    expect(state.scanStartPending, isFalse);
  });

  test('homeSummary resolves the selected location from overview', () {
    state.storageOverview = _overview();
    state.homeTargetPath = '/home';
    snapshot.snapshot = _snapshot(
      ScanTreeNode(name: '/', path: '/', isDirectory: true),
    );

    final summary = actions.homeSummary(const ScanProgressViewState());

    expect(summary.selectedLocation?.path, '/home');
  });
}

ScanSnapshotState _snapshot(ScanTreeNode tree) {
  return ScanSnapshotState(
    snapshotId: 'snap',
    scannedAtMs: 1,
    stats: const {},
    reclaimableEstimateBytes: 0,
    tree: tree,
    entryCount: 0,
    categoryCounts: const {},
    deletableCategoryCounts: const {},
    deletableCount: 0,
    extraFields: const {},
  );
}

StorageOverviewData _overview() {
  return StorageOverviewData(
    selectedVolumeId: '/',
    volumes: [
      const StorageVolumeInfo(
        id: '/',
        name: 'Disk',
        rootPath: '/',
        totalBytes: 1000,
        availableBytes: 400,
        freshness: StorageDataFreshness.live,
      ),
    ],
    locations: const [
      StorageLocationInfo(
        id: 'home',
        name: 'home',
        path: '/home',
        kind: StorageLocationKind.home,
        volumeId: '/',
      ),
    ],
  );
}

class _FakeSnapshot implements DirectorySnapshotSource {
  @override
  List<String> scanRoots = const ['/'];
  ScanSnapshotState? snapshot;
  @override
  bool scanning = false;
  @override
  bool deleting = false;
  @override
  bool targetPreviewLoading = false;
  @override
  bool restoringSnapshot = false;
  @override
  bool postDeleteRefreshPending = false;
  @override
  bool hasAiSessionApi = false;
  @override
  bool hasSnapshotFileApi = true;
  @override
  bool ready = true;
  @override
  List<String> recentCustomRoots = const [];
  final List<String> rememberedRoots = [];

  @override
  ScanSnapshotState? get lastSnapshot => snapshot;

  @override
  void rememberCustomRoot(String path) => rememberedRoots.add(path);
}

class _FakeBrowse implements DirectoryBrowseSession {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  int catalogVersion = 1;

  @override
  bool hasIndexApi = false;

  @override
  String? get currentDirectoryPath => null;

  @override
  Set<String> consumeInvalidatedPrefixes() => const {};
}

class _FakeScan implements ScanLifecycle {
  _FakeScan(this.snapshot);

  final _FakeSnapshot snapshot;
  final List<String?> switchedRoots = [];
  int runScanCalls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> switchScanRoot(
    String? path, {
    bool validateBeforeSwitch = false,
  }) async {
    switchedRoots.add(path);
    snapshot.scanRoots = path == null ? const [] : [path];
  }

  @override
  Future<String> runScan({ScanRunMode mode = ScanRunMode.auto}) async {
    runScanCalls++;
    return 'scan-id';
  }
}

class _FakeDeletion implements DeletionActions {
  final List<
    ({
      List<String> targets,
      bool dryRun,
      bool rescanAfterDelete,
      String? refreshPath,
      Map<String, String>? targetPathById,
    })
  >
  deleteCalls = [];
  Map<String, dynamic> deleteResponse = {};
  int emptyTrashCalls = 0;

  @override
  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    String? expectedSnapshotId,
    bool dryRun = false,
    bool rescanAfterDelete = false,
    String? refreshPath,
    Map<String, String>? targetPathById,
  }) async {
    deleteCalls.add((
      targets: List.of(targets),
      dryRun: dryRun,
      rescanAfterDelete: rescanAfterDelete,
      refreshPath: refreshPath,
      targetPathById: targetPathById,
    ));
    return deleteResponse;
  }

  @override
  Future<Map<String, dynamic>> emptyTrash({
    bool rescanAfterEmpty = true,
  }) async {
    emptyTrashCalls++;
    return const {};
  }
}

class _FakeActionState implements DirectoryDetailsActionState {
  @override
  bool isBrowsing = false;
  @override
  bool hasValidRoot = false;
  @override
  bool targetPreparationPending = false;
  @override
  bool scanStartPending = false;
  @override
  String? scanStatus;
  @override
  String? homeTargetPath;
  @override
  List<StorageLocationInfo> recentCustomLocations = const [];
  @override
  StorageOverviewData storageOverview = const StorageOverviewData.loading();
  @override
  Completer<bool> startupRootGate = Completer<bool>();
  @override
  int scanStartGeneration = 0;
  @override
  int sessionGeneration = 1;
  @override
  int overviewLoadGeneration = 0;
}
