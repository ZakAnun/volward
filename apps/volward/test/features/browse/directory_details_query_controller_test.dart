import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:volward/features/browse/controllers/directory_browse_controller.dart';
import 'package:volward/features/browse/controllers/directory_details_query.dart';
import 'package:volward/features/browse/controllers/scan_presentation_controller.dart';
import 'package:volward/features/browse/controllers/directory_details_ports.dart';
import 'package:volward/features/browse/directory_browse_session.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/scan_entry_record.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/snapshot_query.dart';

void main() {
  late DirectoryQueryController query;
  late DirectoryBrowseController browse;
  late _FakeSnapshot snapshot;
  late _FakeBrowse session;
  late ScanPresentationController presentation;
  var mounted = true;

  setUp(() {
    mounted = true;
    snapshot = _FakeSnapshot();
    session = _FakeBrowse();
    browse = DirectoryBrowseController();
    presentation = ScanPresentationController();
    query = DirectoryQueryController(
      session: snapshot,
      browse: session,
      browseController: browse,
      scanPresentationController: presentation,
      isMounted: () => mounted,
      applySetState: (fn) => fn(),
      l10n: () => lookupAppLocalizations(const Locale('en')),
    );
  });

  tearDown(() {
    presentation.dispose();
    browse.dispose();
  });

  group('tree resolution', () {
    test('resolves and caches the tree per snapshot id', () {
      snapshot.snapshot = _snapshot(
        'snap-1',
        ScanTreeNode(
          name: '/',
          path: '/',
          isDirectory: true,
          children: [
            ScanTreeNode(
              name: 'docs',
              path: '/docs',
              isDirectory: true,
              sizeBytes: 10,
            ),
          ],
        ),
      );

      final tree = query.resolveResultTree();
      expect(tree?.path, '/');
      expect(tree!.children.single.path, '/docs');
      expect(browse.cachedResolvedTreeKey, 'snap-1');

      snapshot.snapshot = _snapshot(
        'snap-2',
        ScanTreeNode(name: '/', path: '/', isDirectory: true),
      );
      expect(query.resolveResultTree()?.children, isEmpty);
      expect(browse.cachedResolvedTreeKey, 'snap-2');
    });

    test('rebuilds the tree from flat entries when the tree is empty', () {
      snapshot.snapshot = ScanSnapshotState(
        snapshotId: 'flat',
        scannedAtMs: 1,
        stats: const {},
        reclaimableEstimateBytes: 0,
        tree: ScanTreeNode(name: '/', path: '/', isDirectory: true),
        entryCount: 1,
        flatEntries: const [
          ScanEntryRecord(
            id: 'e1',
            displayName: 'cache.bin',
            pathOrUri: '/cache.bin',
            sizeBytes: 512,
            category: 'Cache',
            deletable: true,
          ),
        ],
        categoryCounts: const {},
        deletableCategoryCounts: const {},
        deletableCount: 0,
        extraFields: const {},
      );

      final tree = query.resolveResultTree();
      expect(tree!.children.single.path, '/cache.bin');
      expect(browse.cachedResolvedTreeKey, 'flat');
    });
  });

  group('snapshot matching', () {
    test('matches target after path normalization', () {
      snapshot.snapshot = _snapshot(
        'snap-1',
        ScanTreeNode(name: 'docs', path: '/docs', isDirectory: true),
      );
      snapshot.scanRoots = ['/docs'];

      expect(query.snapshotMatchesTarget('/docs/'), isTrue);
      expect(query.snapshotMatchesTarget('/other'), isFalse);
      expect(query.hasResults, isTrue);
    });

    test('hasResults is false while a preview for another root loads', () {
      snapshot.snapshot = _snapshot(
        'snap-1',
        ScanTreeNode(name: 'docs', path: '/docs', isDirectory: true),
      );
      snapshot.scanRoots = ['/home'];
      snapshot.scanning = true;

      expect(query.hasResults, isFalse);
    });
  });

  group('visible children', () {
    test('sorts direct children by size desc and caches per key', () {
      snapshot.snapshot = _snapshot(
        'snap-1',
        ScanTreeNode(
          name: '/',
          path: '/',
          isDirectory: true,
          children: [
            ScanTreeNode(
              name: 'small.bin',
              path: '/small.bin',
              isDirectory: false,
              sizeBytes: 10,
            ),
            ScanTreeNode(
              name: 'large.bin',
              path: '/large.bin',
              isDirectory: false,
              sizeBytes: 100,
            ),
            ScanTreeNode(
              name: 'dir',
              path: '/dir',
              isDirectory: true,
              sizeBytes: 5,
            ),
          ],
        ),
      );

      final children = query.visibleChildrenFor(snapshot.snapshot!.tree!);
      expect(children.map((record) => record.name), [
        'dir',
        'large.bin',
        'small.bin',
      ]);
      expect(
        browse.visibleChildrenCache[query.visibleChildrenKeyFor(
          snapshot.snapshot!.tree!,
        )],
        children,
      );
    });

    test('filters by category and drops empty projections', () {
      snapshot.snapshot = _snapshot(
        'snap-1',
        ScanTreeNode(
          name: '/',
          path: '/',
          isDirectory: true,
          children: [
            ScanTreeNode(
              name: 'cache.bin',
              path: '/cache.bin',
              isDirectory: false,
              sizeBytes: 10,
              category: 'Cache',
            ),
            ScanTreeNode(
              name: 'doc.txt',
              path: '/doc.txt',
              isDirectory: false,
              sizeBytes: 20,
              category: 'Documents',
            ),
          ],
        ),
      );
      browse.categoryFilter = 'Cache';

      final children = query.visibleChildrenFor(snapshot.snapshot!.tree!);
      expect(children.single.name, 'cache.bin');
    });
  });

  group('selection and delete targets', () {
    ScanTreeNode node(String name, String path, {bool isDirectory = false}) {
      return ScanTreeNode(
        name: name,
        path: path,
        isDirectory: isDirectory,
        sizeBytes: 64,
      );
    }

    test('selection projects delete targets, count and bytes', () {
      final first = node('a.bin', '/a.bin');
      final second = node('b.bin', '/b.bin');
      query.toggleNodeSelection(first);
      query.toggleNodeSelection(second);
      query.toggleNodeSelection(first);

      expect(query.deleteTargetStrings(), ['/b.bin']);
      expect(query.deleteTargetCount(), 1);
      expect(query.deleteTargetBytes(), 64);
      expect(query.selectedBytes(), 64);
    });

    test('focus fallback provides a single delete target', () {
      snapshot.snapshot = _snapshot(
        'snap-1',
        ScanTreeNode(name: '/', path: '/', isDirectory: true),
      );
      browse.columnChain.add(node('focus.bin', '/focus.bin'));

      expect(query.deleteTargetStrings(), ['/focus.bin']);
      expect(query.deleteTargetCount(), 1);
      expect(query.deleteTargetBytes(), 64);
    });

    test('directory selection removes child selections', () {
      final parent = node('dir', '/dir', isDirectory: true);
      final child = node('child.bin', '/dir/child.bin');
      query.addNodeSelection(child);
      query.addNodeSelection(parent);

      expect(query.deleteTargetStrings(), ['/dir']);
    });
  });

  group('cache invalidation', () {
    test('session update invalidates only the announced prefixes', () {
      snapshot.snapshot = _snapshot(
        'snap-1',
        ScanTreeNode(
          name: '/',
          path: '/',
          isDirectory: true,
          children: [
            ScanTreeNode(
              name: 'dir',
              path: '/dir',
              isDirectory: true,
              sizeBytes: 5,
            ),
          ],
        ),
      );
      query.visibleChildrenFor(snapshot.snapshot!.tree!);
      query.visibleChildrenFor(snapshot.snapshot!.tree!.children.single);
      session.consumeInvalidatedPrefixesResult = {'/dir'};

      query.invalidateSnapshotCachesForSessionUpdate();

      expect(browse.visibleChildrenCache.latestForPath('/dir'), isNull);
      expect(browse.cachedResolvedTreeKey, isNull);
      expect(browse.pendingVisibleChildrenQueries, isEmpty);
    });
  });
}

ScanSnapshotState _snapshot(String id, ScanTreeNode tree) {
  return ScanSnapshotState(
    snapshotId: id,
    scannedAtMs: 1,
    stats: const {'files_seen': 3},
    reclaimableEstimateBytes: 0,
    tree: tree,
    entryCount: 0,
    categoryCounts: const {},
    deletableCategoryCounts: const {},
    deletableCount: 0,
    extraFields: const {},
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

  Set<String>? consumeInvalidatedPrefixesResult;

  @override
  Set<String> consumeInvalidatedPrefixes() =>
      consumeInvalidatedPrefixesResult ?? const {};

  @override
  ScanTreeNode? directoryOverlayForPath(String path) => null;

  @override
  bool isDirectoryRefreshing(String path) => false;

  @override
  Set<String> get peekInFlight => const {};

  @override
  void setCurrentDirectory(String? path) {}

  @override
  List<SnapshotNodeRecord>? queryDirectoryChildrenFromCatalog(
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  }) => null;
}
