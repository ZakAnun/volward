import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/storage_home_summary.dart';
import 'package:volward/storage_overview.dart';

ScanSnapshotState snapshot({
  String id = 'snap-done',
  String rootPath = '/Users/me',
  int total = 1000,
  int used = 600,
  int reclaimable = 25,
  String scanState = 'Done',
  int? scannedAtMs = 42,
  int sizeBytes = 50,
  int entryCount = 1,
  int? filesSeen,
  int? filesInSnapshot,
  Map<String, int> categoryCounts = const {},
}) {
  return ScanSnapshotState(
    snapshotId: id,
    scannedAtMs: scannedAtMs,
    stats: {
      'scan_state': scanState,
      if (filesSeen != null) 'files_seen': filesSeen,
      if (filesInSnapshot != null) 'files_in_snapshot': filesInSnapshot,
    },
    reclaimableEstimateBytes: reclaimable,
    tree: ScanTreeNode(
      name: 'me',
      path: rootPath,
      isDirectory: true,
      sizeBytes: sizeBytes,
    ),
    entryCount: entryCount,
    categoryCounts: categoryCounts,
    deletableCategoryCounts: const {},
    deletableCount: 0,
    extraFields: {'volume_total_bytes': total, 'volume_used_bytes': used},
  );
}

final liveOverview = StorageOverviewData(
  selectedVolumeId: '/',
  volumes: const [
    StorageVolumeInfo(
      id: '/',
      name: 'Macintosh HD',
      rootPath: '/',
      totalBytes: 2000,
      availableBytes: 500,
      freshness: StorageDataFreshness.live,
    ),
  ],
  locations: const [
    StorageLocationInfo(
      id: 'home',
      name: 'me',
      path: '/Users/me',
      kind: StorageLocationKind.home,
      volumeId: '/',
    ),
  ],
);

void main() {
  test('empty target remains neutral without a custom location', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: const StorageOverviewData.unavailable('missing-root'),
      targetPath: '',
      scanning: false,
      scanProgress: null,
    );

    expect(summary.selectedLocation, isNull);
    expect(summary.selectedVolume, isNull);
    expect(summary.hasUsableCapacity, isFalse);
  });

  test('live volume capacity stays separate from scanned directory bytes', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me',
      matchingSnapshot: snapshot(),
      scanning: false,
      scanProgress: null,
    );

    expect(summary.selectedVolume?.freshness, StorageDataFreshness.live);
    expect(summary.selectedVolume?.totalBytes, 2000);
    expect(summary.selectedVolume?.usedBytes, 1500);
    expect(summary.selectedVolume?.totalBytes, isNot(50));
    expect(summary.reclaimableBytes, 25);
  });

  test('known location volume id wins for a symlink-style path', () {
    final overview = StorageOverviewData(
      selectedVolumeId: 'system',
      volumes: const [
        StorageVolumeInfo(
          id: 'system',
          name: 'System',
          rootPath: '/',
          totalBytes: 1000,
          availableBytes: 100,
          freshness: StorageDataFreshness.live,
        ),
        StorageVolumeInfo(
          id: 'data',
          name: 'Data',
          rootPath: '/mnt/data',
          totalBytes: 8000,
          availableBytes: 3000,
          freshness: StorageDataFreshness.live,
        ),
      ],
      locations: const [
        StorageLocationInfo(
          id: 'home',
          name: 'me',
          path: '/home/me',
          kind: StorageLocationKind.home,
          volumeId: 'data',
        ),
      ],
    );

    final summary = StorageHomeSummary.fromInputs(
      overview: overview,
      targetPath: '/home/me',
      scanning: false,
      scanProgress: null,
    );

    expect(summary.selectedVolume?.id, 'data');
    expect(summary.selectedVolume?.totalBytes, 8000);
    expect(summary.selectedVolume?.usedBytes, 5000);
  });

  test('provider selected volume wins for a custom symlink-style path', () {
    final overview = StorageOverviewData(
      selectedVolumeId: 'data',
      volumes: const [
        StorageVolumeInfo(
          id: 'system',
          name: 'System',
          rootPath: '/',
          totalBytes: 1000,
          availableBytes: 100,
          freshness: StorageDataFreshness.live,
        ),
        StorageVolumeInfo(
          id: 'data',
          name: 'Data',
          rootPath: '/mnt/data',
          totalBytes: 8000,
          availableBytes: 3000,
          freshness: StorageDataFreshness.live,
        ),
      ],
      locations: const [],
    );

    final summary = StorageHomeSummary.fromInputs(
      overview: overview,
      targetPath: '/work/link',
      scanning: false,
      scanProgress: null,
    );

    expect(summary.selectedLocation!.kind, StorageLocationKind.custom);
    expect(summary.selectedLocation!.volumeId, 'data');
    expect(summary.selectedVolume?.id, 'data');
    expect(summary.selectedVolume?.totalBytes, 8000);
    expect(summary.selectedVolume?.usedBytes, 5000);
  });

  test('invalid provider selected volume falls back lexically', () {
    final overview = StorageOverviewData(
      selectedVolumeId: 'missing',
      volumes: const [
        StorageVolumeInfo(
          id: 'system',
          name: 'System',
          rootPath: '/',
          totalBytes: 1000,
          availableBytes: 100,
          freshness: StorageDataFreshness.live,
        ),
        StorageVolumeInfo(
          id: 'data',
          name: 'Data',
          rootPath: '/mnt/data',
          totalBytes: 8000,
          availableBytes: 3000,
          freshness: StorageDataFreshness.live,
        ),
      ],
      locations: const [],
    );

    final summary = StorageHomeSummary.fromInputs(
      overview: overview,
      targetPath: '/work/link',
      scanning: false,
      scanProgress: null,
    );

    expect(summary.selectedVolume?.id, 'system');
    expect(summary.selectedVolume?.totalBytes, 1000);
  });

  test('matching snapshot supplies explicitly cached volume capacity', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: const StorageOverviewData.unavailable('offline'),
      targetPath: '/Users/me',
      matchingSnapshot: snapshot(),
      scanning: false,
      scanProgress: null,
    );

    expect(summary.selectedVolume?.freshness, StorageDataFreshness.cached);
    expect(summary.selectedVolume?.totalBytes, 1000);
    expect(summary.selectedVolume?.availableBytes, 400);
  });

  test('matching snapshot remains cached while live overview is loading', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: const StorageOverviewData.loading(),
      targetPath: '/Users/me',
      matchingSnapshot: snapshot(),
      scanning: false,
      scanProgress: null,
    );

    expect(summary.overview.loading, isTrue);
    expect(summary.hasUsableCapacity, isTrue);
    expect(summary.selectedVolume?.freshness, StorageDataFreshness.cached);
  });

  test('matching snapshot replaces live volume with unavailable capacity', () {
    final overviewWithoutCapacity = StorageOverviewData(
      selectedVolumeId: '/',
      volumes: const [
        StorageVolumeInfo(
          id: '/',
          name: 'Macintosh HD',
          rootPath: '/',
          totalBytes: null,
          availableBytes: null,
          freshness: StorageDataFreshness.live,
        ),
      ],
      locations: const [],
    );

    final summary = StorageHomeSummary.fromInputs(
      overview: overviewWithoutCapacity,
      targetPath: '/Users/me',
      matchingSnapshot: snapshot(used: 1200),
      scanning: false,
      scanProgress: null,
    );

    expect(summary.selectedVolume?.freshness, StorageDataFreshness.cached);
    expect(summary.selectedVolume?.totalBytes, 1000);
    expect(summary.selectedVolume?.usedBytes, 1000);
    expect(summary.selectedVolume?.availableBytes, 0);
  });

  test('Windows target rejects selected volume fallback across drives', () {
    final windowsOverview = StorageOverviewData(
      selectedVolumeId: 'C:',
      volumes: const [
        StorageVolumeInfo(
          id: 'C:',
          name: 'Windows',
          rootPath: 'C:/',
          totalBytes: 2000,
          availableBytes: 500,
          freshness: StorageDataFreshness.live,
        ),
      ],
      locations: const [],
    );

    final withoutSnapshot = StorageHomeSummary.fromInputs(
      overview: windowsOverview,
      targetPath: 'E:/Photos',
      scanning: false,
      scanProgress: null,
    );
    final withMatchingSnapshot = StorageHomeSummary.fromInputs(
      overview: windowsOverview,
      targetPath: 'E:/Photos',
      matchingSnapshot: snapshot(rootPath: 'e:/Photos', used: 1200),
      scanning: false,
      scanProgress: null,
    );

    expect(withoutSnapshot.selectedVolume, isNull);
    expect(withoutSnapshot.selectedLocation!.volumeId, isEmpty);
    expect(
      withMatchingSnapshot.selectedVolume?.freshness,
      StorageDataFreshness.cached,
    );
    expect(withMatchingSnapshot.selectedVolume?.availableBytes, 0);
    expect(withMatchingSnapshot.selectedLocation!.volumeId, isEmpty);
  });

  test('Windows custom target falls back to its lexical drive volume', () {
    final overview = StorageOverviewData(
      selectedVolumeId: 'system',
      volumes: const [
        StorageVolumeInfo(
          id: 'system',
          name: 'Windows',
          rootPath: 'C:/',
          totalBytes: 2000,
          availableBytes: 500,
          freshness: StorageDataFreshness.live,
        ),
        StorageVolumeInfo(
          id: 'data',
          name: 'Data',
          rootPath: 'e:/',
          totalBytes: 8000,
          availableBytes: 3000,
          freshness: StorageDataFreshness.live,
        ),
      ],
      locations: const [],
    );

    final summary = StorageHomeSummary.fromInputs(
      overview: overview,
      targetPath: 'E:/Photos',
      scanning: false,
      scanProgress: null,
    );

    expect(summary.selectedLocation!.kind, StorageLocationKind.custom);
    expect(summary.selectedLocation!.volumeId, 'data');
    expect(summary.selectedVolume?.id, 'data');
    expect(summary.selectedVolume?.totalBytes, 8000);
  });

  test('Windows provider volume accepts the same drive case-insensitively', () {
    final overview = StorageOverviewData(
      selectedVolumeId: 'drive-data',
      volumes: const [
        StorageVolumeInfo(
          id: 'drive-data',
          name: 'Data',
          rootPath: 'e:/',
          totalBytes: 8000,
          availableBytes: 3000,
          freshness: StorageDataFreshness.live,
        ),
        StorageVolumeInfo(
          id: 'photos',
          name: 'Photos',
          rootPath: 'E:/Photos',
          totalBytes: 2000,
          availableBytes: 500,
          freshness: StorageDataFreshness.live,
        ),
      ],
      locations: const [],
    );

    final summary = StorageHomeSummary.fromInputs(
      overview: overview,
      targetPath: 'E:/Photos/Album',
      scanning: false,
      scanProgress: null,
    );

    expect(summary.selectedVolume?.id, 'drive-data');
    expect(summary.selectedVolume?.totalBytes, 8000);
  });

  test('UNC target rejects fixed-drive provider capacity', () {
    final overview = StorageOverviewData(
      selectedVolumeId: 'C:',
      volumes: const [
        StorageVolumeInfo(
          id: 'C:',
          name: 'Windows',
          rootPath: 'C:/',
          totalBytes: 2000,
          availableBytes: 500,
          freshness: StorageDataFreshness.live,
        ),
      ],
      locations: const [],
    );
    const uncPath = r'\\server\share\folder';

    final withoutSnapshot = StorageHomeSummary.fromInputs(
      overview: overview,
      targetPath: uncPath,
      scanning: false,
      scanProgress: null,
    );
    final withMatchingSnapshot = StorageHomeSummary.fromInputs(
      overview: overview,
      targetPath: uncPath,
      matchingSnapshot: snapshot(rootPath: '//server/share/folder'),
      scanning: false,
      scanProgress: null,
    );

    expect(withoutSnapshot.selectedLocation!.path, '//server/share/folder');
    expect(withoutSnapshot.selectedLocation!.volumeId, isEmpty);
    expect(withoutSnapshot.selectedVolume, isNull);
    expect(
      withMatchingSnapshot.selectedVolume?.freshness,
      StorageDataFreshness.cached,
    );
    expect(withMatchingSnapshot.selectedVolume?.totalBytes, 1000);
  });

  test('cached volume capacity is bounded to the matching snapshot total', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: const StorageOverviewData.unavailable('offline'),
      targetPath: '/Users/me',
      matchingSnapshot: snapshot(used: 1200),
      scanning: false,
      scanProgress: null,
    );

    expect(summary.selectedVolume?.usedBytes, 1000);
    expect(summary.selectedVolume?.availableBytes, 0);
  });

  test('snapshot for a different root is never reused', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: const StorageOverviewData.unavailable('offline'),
      targetPath: '/Users/me',
      matchingSnapshot: snapshot(rootPath: '/Users/other'),
      scanning: false,
      scanProgress: null,
    );

    expect(summary.selectedVolume, isNull);
    expect(summary.reclaimableBytes, isNull);
    expect(summary.lastScannedAtMs, isNull);
    expect(summary.hasCompletedScan, isFalse);
  });

  test('custom target is retained with its complete path', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me/Work/client',
      scanning: true,
      scanProgress: 1.4,
    );

    expect(summary.selectedLocation!.kind, StorageLocationKind.custom);
    expect(summary.selectedLocation!.name, 'client');
    expect(summary.selectedLocation!.path, '/Users/me/Work/client');
    expect(summary.scanProgress, 0.99);
  });

  test('recent custom locations survive a default target selection', () {
    const recent = StorageLocationInfo(
      id: 'custom:/Users/me/Work/client',
      name: 'client',
      path: '/Users/me/Work/client',
      kind: StorageLocationKind.custom,
      volumeId: '/',
    );
    final summary = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me',
      scanning: false,
      scanProgress: null,
      recentCustomLocations: [recent],
    );

    expect(summary.selectedLocation!.kind, StorageLocationKind.home);
    expect(summary.recentCustomLocations, [recent]);
  });

  test('legal path whitespace is preserved for custom targets', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me/Work/client ',
      scanning: false,
      scanProgress: null,
    );

    expect(summary.selectedLocation!.name, 'client ');
    expect(summary.selectedLocation!.path, '/Users/me/Work/client ');
  });

  test('scan progress is bounded and hidden while not scanning', () {
    final belowZero = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me',
      scanning: true,
      scanProgress: -0.2,
    );
    final notScanning = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me',
      scanning: false,
      scanProgress: 0.5,
    );

    expect(belowZero.scanProgress, 0);
    expect(notScanning.scanProgress, isNull);
  });

  test('matching completed scan exposes completion metadata', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me/',
      matchingSnapshot: snapshot(scannedAtMs: 8675309),
      scanning: false,
      scanProgress: null,
    );

    expect(summary.hasCompletedScan, isTrue);
    expect(summary.lastScannedAtMs, 8675309);
    expect(summary.reclaimableBytes, 25);
  });

  test('incomplete matching scan does not report completion', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me',
      matchingSnapshot: snapshot(scanState: 'Walking'),
      scanning: true,
      scanProgress: 0.5,
    );

    expect(summary.hasCompletedScan, isFalse);
    expect(summary.lastScannedAtMs, 42);
  });

  test('preview snapshot treats zero reclaimable as unknown', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me',
      matchingSnapshot: snapshot(
        id: 'preview-1',
        reclaimable: 0,
        scanState: 'Walking',
      ),
      scanning: false,
      scanProgress: null,
    );

    expect(summary.reclaimableBytes, isNull);
    expect(summary.hasCompletedScan, isFalse);
  });

  test('completed non-preview snapshot keeps known zero reclaimable', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me',
      matchingSnapshot: snapshot(reclaimable: 0),
      scanning: false,
      scanProgress: null,
    );

    expect(summary.reclaimableBytes, 0);
    expect(summary.hasCompletedScan, isTrue);
  });

  test(
    'incomplete non-preview snapshot treats zero reclaimable as unknown',
    () {
      final summary = StorageHomeSummary.fromInputs(
        overview: liveOverview,
        targetPath: '/Users/me',
        matchingSnapshot: snapshot(reclaimable: 0, scanState: 'Walking'),
        scanning: true,
        scanProgress: 0.5,
      );

      expect(summary.reclaimableBytes, isNull);
      expect(summary.hasCompletedScan, isFalse);
    },
  );

  test('matching snapshot drops malformed negative metadata', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me',
      matchingSnapshot: snapshot(reclaimable: -1, scannedAtMs: -42),
      scanning: false,
      scanProgress: null,
    );

    expect(summary.reclaimableBytes, isNull);
    expect(summary.lastScannedAtMs, isNull);
  });

  test('path display names remain compatible across desktop roots', () {
    expect(rootDisplayNameFor('/'), '/');
    expect(rootDisplayNameFor('C:/'), 'C:/');
    expect(rootDisplayNameFor(r'C:\Users\me\Documents'), 'Documents');
    expect(rootDisplayNameFor('/mnt/data'), 'data');
    expect(rootDisplayNameFor('/mnt/data '), 'data ');
  });

  test('category summaries keep scanned labels and other remainder', () {
    final summary = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me',
      matchingSnapshot: snapshot(
        filesSeen: 80,
        filesInSnapshot: 55,
        entryCount: 55,
        categoryCounts: const {'Cache': 12, 'Temp': 3, 'Media': 40},
      ),
      scanning: false,
      scanProgress: null,
    );

    expect(summary.categories.map((category) => category.name).toList(), [
      'Cache',
      'Temp',
      'Media',
      'Other',
    ]);
    expect(summary.categories.map((category) => category.count).toList(), [
      12,
      3,
      40,
      25,
    ]);
    expect(summary.scannedBytes, 50);
  });

  test('zero tree bytes stay unknown until the scan completes', () {
    final incomplete = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me',
      matchingSnapshot: snapshot(sizeBytes: 0, scanState: 'Walking'),
      scanning: true,
      scanProgress: 0.2,
    );
    final completed = StorageHomeSummary.fromInputs(
      overview: liveOverview,
      targetPath: '/Users/me',
      matchingSnapshot: snapshot(sizeBytes: 0),
      scanning: false,
      scanProgress: null,
    );

    expect(incomplete.scannedBytes, isNull);
    expect(incomplete.categories, isEmpty);
    expect(completed.scannedBytes, 0);
  });

  test('byte formatting remains compatible and scales beyond gigabytes', () {
    expect(formatStorageBytes(null), '—');
    expect(formatStorageBytes(0), '0 B');
    expect(formatStorageBytes(1536), '1.5 KB');
    expect(formatStorageBytes(100 * 1024), '100 KB');
    expect(formatStorageBytes(1024 * 1024 * 1024 * 1024), '1 TB');
  });

  ScanTreeNode candidate(
    String name,
    int bytes, {
    bool isDirectory = false,
    bool scanned = true,
  }) {
    return ScanTreeNode(
      name: name,
      path: '/Users/me/$name',
      isDirectory: isDirectory,
      sizeBytes: bytes,
      subtreeBytes: bytes,
      scanned: scanned,
    );
  }

  group('largestItems', () {
    test('a large file outranks a smaller directory', () {
      final summary = StorageHomeSummary.fromInputs(
        overview: liveOverview,
        targetPath: '/Users/me',
        matchingSnapshot: snapshot(),
        scanning: false,
        scanProgress: null,
        largestItemCandidates: [
          candidate('archive', 8, isDirectory: true),
          candidate('Xcode.dmg', 12),
        ],
      );

      expect(summary.largestItems.map((e) => e.name).toList(), [
        'Xcode.dmg',
        'archive',
      ]);
      expect(summary.largestItems.first.sizeBytes, 12);
      expect(summary.largestItems.first.isDirectory, isFalse);
    });

    test('keeps at most five items', () {
      final summary = StorageHomeSummary.fromInputs(
        overview: liveOverview,
        targetPath: '/Users/me',
        matchingSnapshot: snapshot(),
        scanning: false,
        scanProgress: null,
        largestItemCandidates: [
          for (var i = 0; i < 9; i++) candidate('item$i', 100 - i),
        ],
      );

      expect(summary.largestItems, hasLength(5));
      expect(summary.largestItems.last.sizeBytes, 96);
    });

    test('fewer candidates than the limit are all kept', () {
      final summary = StorageHomeSummary.fromInputs(
        overview: liveOverview,
        targetPath: '/Users/me',
        matchingSnapshot: snapshot(),
        scanning: false,
        scanProgress: null,
        largestItemCandidates: [candidate('only', 5)],
      );

      expect(summary.largestItems, hasLength(1));
    });

    test('a preview snapshot yields no items', () {
      final summary = StorageHomeSummary.fromInputs(
        overview: liveOverview,
        targetPath: '/Users/me',
        matchingSnapshot: snapshot(id: 'preview-1'),
        scanning: false,
        scanProgress: null,
        largestItemCandidates: [candidate('archive', 8, isDirectory: true)],
      );

      expect(summary.largestItems, isEmpty);
    });

    test('no matching snapshot yields no items', () {
      final summary = StorageHomeSummary.fromInputs(
        overview: liveOverview,
        targetPath: '/Users/me',
        scanning: false,
        scanProgress: null,
        largestItemCandidates: [candidate('archive', 8, isDirectory: true)],
      );

      expect(summary.largestItems, isEmpty);
    });

    test('a completed scan of an empty folder is not "never scanned"', () {
      final summary = StorageHomeSummary.fromInputs(
        overview: liveOverview,
        targetPath: '/Users/me',
        matchingSnapshot: snapshot(),
        scanning: false,
        scanProgress: null,
        largestItemCandidates: const [],
      );

      expect(summary.largestItems, isEmpty);
      expect(summary.hasCompletedScan, isTrue);
    });

    test('all-zero sizes still produce items', () {
      final summary = StorageHomeSummary.fromInputs(
        overview: liveOverview,
        targetPath: '/Users/me',
        matchingSnapshot: snapshot(),
        scanning: false,
        scanProgress: null,
        largestItemCandidates: [candidate('a', 0), candidate('b', 0)],
      );

      expect(summary.largestItems, hasLength(2));
      expect(summary.largestItems.every((e) => e.sizeBytes == 0), isTrue);
    });

    test('partial directory sizes carry the scanned flag', () {
      final summary = StorageHomeSummary.fromInputs(
        overview: liveOverview,
        targetPath: '/Users/me',
        matchingSnapshot: snapshot(),
        scanning: false,
        scanProgress: null,
        largestItemCandidates: [
          candidate('partial', 9, isDirectory: true, scanned: false),
        ],
      );

      expect(summary.largestItems.single.scanned, isFalse);
      expect(summary.largestItems.single.path, '/Users/me/partial');
    });

    test('the returned list is unmodifiable', () {
      final summary = StorageHomeSummary.fromInputs(
        overview: liveOverview,
        targetPath: '/Users/me',
        matchingSnapshot: snapshot(),
        scanning: false,
        scanProgress: null,
        largestItemCandidates: [candidate('a', 1)],
      );

      expect(
        () => summary.largestItems.add(
          const StorageHomeItem(
            name: 'x',
            path: '/x',
            sizeBytes: 1,
            isDirectory: false,
            scanned: true,
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
