// ignore_for_file: prefer_initializing_formals

import 'scan_entry_record.dart';
import 'scan_tree.dart';
import 'snapshot_catalog.dart';
import 'snapshot_query.dart';
import 'widgets/scan_filter_bar.dart';

class ScanSnapshotState {
  ScanSnapshotState({
    required this.snapshotId,
    required this.scannedAtMs,
    required this.stats,
    required this.reclaimableEstimateBytes,
    required this.tree,
    required this.entryCount,
    List<ScanEntryRecord>? flatEntries,
    required this.categoryCounts,
    required this.deletableCategoryCounts,
    required this.deletableCount,
    required this.extraFields,
  }) : _flatEntries = flatEntries;

  factory ScanSnapshotState.fromIndexSummary(Map<String, dynamic> summary) {
    final snapshotId = summary['snapshot_id']?.toString() ?? '';
    final rootPath = normalizeFsPath(summary['root_path']?.toString() ?? '');
    final rootParts = rootPath.split('/').where((s) => s.isNotEmpty).toList();
    final root = ScanTreeNode(
      name: rootParts.isEmpty
          ? (rootPath.isEmpty ? 'root' : rootPath)
          : rootParts.last,
      path: rootPath.isEmpty ? '/' : rootPath,
      isDirectory: true,
      sizeBytes: (summary['root_size_bytes'] as num?)?.toInt() ?? 0,
      scanned: true,
    );
    final categoryCounts = _stringCountMap(summary['category_counts']);
    final deletableCategoryCounts = _stringCountMap(
      summary['deletable_counts'],
    );
    final stats = summary['stats'] is Map
        ? Map<String, dynamic>.from(summary['stats'] as Map)
        : <String, dynamic>{};
    stats['files_in_snapshot'] =
        (stats['files_in_snapshot'] as num?)?.toInt() ??
            (summary['entry_count'] as num?)?.toInt() ??
            0;
    stats['scan_state'] = stats['scan_state']?.toString() ??
        summary['scan_state']?.toString() ??
        'Done';
    final extraFields = Map<String, dynamic>.from(summary)
      ..remove('snapshot_id')
      ..remove('root_path')
      ..remove('root_size_bytes')
      ..remove('scanned_at_ms')
      ..remove('version')
      ..remove('scan_state')
      ..remove('reclaimable_estimate_bytes')
      ..remove('stats')
      ..remove('entry_count')
      ..remove('deletable_count')
      ..remove('category_counts')
      ..remove('deletable_counts');
    return ScanSnapshotState(
      snapshotId: snapshotId,
      scannedAtMs: (summary['scanned_at_ms'] as num?)?.toInt(),
      stats: stats,
      reclaimableEstimateBytes:
          (summary['reclaimable_estimate_bytes'] as num?)?.toInt() ?? 0,
      tree: root,
      entryCount: (summary['entry_count'] as num?)?.toInt() ?? 0,
      categoryCounts: categoryCounts,
      deletableCategoryCounts: deletableCategoryCounts,
      deletableCount: (summary['deletable_count'] as num?)?.toInt() ?? 0,
      extraFields: Map.unmodifiable(extraFields),
    );
  }

  factory ScanSnapshotState.fromWire(Map<String, dynamic> wire) {
    final treeWire = wire['tree'];
    final keepFlatEntries = treeWire is! Map;
    final flatEntries = keepFlatEntries ? <ScanEntryRecord>[] : null;
    final entriesById = <String, ScanEntryRecord>{};
    final categoryCounts = <String, int>{};
    final deletableCategoryCounts = <String, int>{};
    var deletableCount = 0;
    final entriesWire = wire['entries'];
    if (entriesWire is List) {
      for (final rawEntry in entriesWire) {
        if (rawEntry is! Map) continue;
        final entry = ScanEntryRecord.fromWire(
          rawEntry is Map<String, dynamic>
              ? rawEntry
              : Map<String, dynamic>.from(rawEntry),
        );
        entriesById[entry.id] = entry;
        flatEntries?.add(entry);
      }
    }

    ScanTreeNode? tree;
    if (treeWire is Map) {
      tree = ScanTreeNode.fromSnapshotJson(
        treeWire is Map<String, dynamic>
            ? treeWire
            : Map<String, dynamic>.from(treeWire),
        entriesById: entriesById,
      );
    }
    final summary = summarizeSnapshotEntries(
      tree: tree,
      flatEntries: flatEntries,
      categoryCounts: categoryCounts,
      deletableCategoryCounts: deletableCategoryCounts,
      deletableCount: deletableCount,
    );

    final stats = wire['stats'] is Map
        ? Map<String, dynamic>.from(wire['stats'] as Map)
        : <String, dynamic>{};
    final extraFields = Map<String, dynamic>.from(wire)
      ..remove('snapshot_id')
      ..remove('scanned_at_ms')
      ..remove('reclaimable_estimate_bytes')
      ..remove('entries')
      ..remove('tree')
      ..remove('stats');

    return ScanSnapshotState(
      snapshotId: wire['snapshot_id']?.toString() ?? '',
      scannedAtMs: (wire['scanned_at_ms'] as num?)?.toInt(),
      stats: stats,
      reclaimableEstimateBytes:
          (wire['reclaimable_estimate_bytes'] as num?)?.toInt() ?? 0,
      tree: tree,
      entryCount: summary.entryCount,
      flatEntries: flatEntries,
      categoryCounts: summary.categoryCounts,
      deletableCategoryCounts: summary.deletableCategoryCounts,
      deletableCount: summary.deletableCount,
      extraFields: Map.unmodifiable(extraFields),
    );
  }

  final String snapshotId;
  final int? scannedAtMs;
  final Map<String, dynamic> stats;
  final int reclaimableEstimateBytes;
  final ScanTreeNode? tree;
  final int entryCount;
  final List<ScanEntryRecord>? _flatEntries;
  final Map<String, int> categoryCounts;
  final Map<String, int> deletableCategoryCounts;
  final int deletableCount;
  final Map<String, dynamic> extraFields;

  late final SnapshotCatalog catalog = SnapshotCatalog(this);

  int get filesInSnapshot =>
      (stats['files_in_snapshot'] as num?)?.toInt() ?? entryCount;

  bool get hasFlatEntries => _flatEntries != null && _flatEntries.isNotEmpty;

  List<ScanEntryRecord> materializeEntries() {
    final flat = _flatEntries;
    if (flat != null) return flat;
    final out = <ScanEntryRecord>[];
    void visit(String path) {
      final result = catalog.query(
        SnapshotQueryKey(
          snapshotId: snapshotId,
          version: 0,
          path: path,
          categoryFilter: null,
          deletableOnly: false,
          sortMode: ScanSortMode.nameAsc,
        ),
      );
      out.addAll(result.directEntries);
      for (final child in result.directChildren) {
        visit(child.path);
      }
    }

    final root = tree;
    if (root != null) visit(root.path);
    return out;
  }

  void forEachEntry(void Function(ScanEntryRecord entry) visit) {
    final flat = _flatEntries;
    if (flat != null) {
      for (final entry in flat) {
        visit(entry);
      }
      return;
    }

    void walk(ScanTreeNode node) {
      if (!node.isDirectory) {
        final entry = node.toEntryRecord();
        if (entry != null) visit(entry);
        return;
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    final root = tree;
    if (root != null) walk(root);
  }

  int selectedBytes(Set<String> selectedIds) {
    if (selectedIds.isEmpty) return 0;
    final flat = _flatEntries;
    if (flat != null) {
      var total = 0;
      for (final entry in flat) {
        if (selectedIds.contains(entry.id)) total += entry.sizeBytes;
      }
      return total;
    }
    final root = tree;
    if (root == null) return 0;
    var total = 0;
    void walk(ScanTreeNode node) {
      if (!node.isDirectory) {
        final id = node.entryId ?? node.path;
        if (id.isNotEmpty && selectedIds.contains(id)) {
          total += node.sizeBytes;
        }
        return;
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(root);
    return total;
  }

  int matchingEntryCount(
    String? categoryFilter, {
    required bool deletableOnly,
  }) {
    if (categoryFilter == null) {
      return deletableOnly ? deletableCount : entryCount;
    }
    return deletableOnly
        ? (deletableCategoryCounts[categoryFilter] ?? 0)
        : (categoryCounts[categoryFilter] ?? 0);
  }

  Map<String, dynamic> toWire({bool includeEntries = true}) {
    return {
      'snapshot_id': snapshotId,
      if (scannedAtMs != null) 'scanned_at_ms': scannedAtMs,
      'reclaimable_estimate_bytes': reclaimableEstimateBytes,
      if (includeEntries)
        'entries':
            materializeEntries().map((e) => e.toWire()).toList(growable: false),
      'tree': tree?.toWire(),
      'stats': Map<String, dynamic>.from(stats),
      ...extraFields,
    };
  }
}

Map<String, int> _stringCountMap(Object? wire) {
  final out = <String, int>{};
  if (wire is Map) {
    for (final entry in wire.entries) {
      out[entry.key.toString()] = (entry.value as num?)?.toInt() ?? 0;
    }
  }
  return Map.unmodifiable(out);
}

class ScanSnapshotSummary {
  const ScanSnapshotSummary({
    required this.entryCount,
    required this.categoryCounts,
    required this.deletableCategoryCounts,
    required this.deletableCount,
  });

  final int entryCount;
  final Map<String, int> categoryCounts;
  final Map<String, int> deletableCategoryCounts;
  final int deletableCount;
}

ScanSnapshotSummary summarizeSnapshotEntries({
  required ScanTreeNode? tree,
  required List<ScanEntryRecord>? flatEntries,
  required Map<String, int> categoryCounts,
  required Map<String, int> deletableCategoryCounts,
  required int deletableCount,
}) {
  if (tree != null && tree.scanned) {
    return summarizeSnapshotTree(tree);
  }
  if (flatEntries != null) {
    for (final entry in flatEntries) {
      categoryCounts[entry.category] =
          (categoryCounts[entry.category] ?? 0) + 1;
      if (entry.deletable) {
        deletableCount++;
        deletableCategoryCounts[entry.category] =
            (deletableCategoryCounts[entry.category] ?? 0) + 1;
      }
    }
    return ScanSnapshotSummary(
      entryCount: flatEntries.length,
      categoryCounts: Map.unmodifiable(categoryCounts),
      deletableCategoryCounts: Map.unmodifiable(deletableCategoryCounts),
      deletableCount: deletableCount,
    );
  }
  return const ScanSnapshotSummary(
    entryCount: 0,
    categoryCounts: <String, int>{},
    deletableCategoryCounts: <String, int>{},
    deletableCount: 0,
  );
}

ScanSnapshotSummary summarizeSnapshotTree(ScanTreeNode root) {
  final categoryCounts = <String, int>{};
  final deletableCategoryCounts = <String, int>{};
  var entryCount = 0;
  var deletableCount = 0;

  void walk(ScanTreeNode node) {
    if (!node.isDirectory) {
      entryCount++;
      categoryCounts[node.category] = (categoryCounts[node.category] ?? 0) + 1;
      if (node.deletable) {
        deletableCount++;
        deletableCategoryCounts[node.category] =
            (deletableCategoryCounts[node.category] ?? 0) + 1;
      }
      return;
    }
    for (final child in node.children) {
      walk(child);
    }
  }

  walk(root);
  return ScanSnapshotSummary(
    entryCount: entryCount,
    categoryCounts: Map.unmodifiable(categoryCounts),
    deletableCategoryCounts: Map.unmodifiable(deletableCategoryCounts),
    deletableCount: deletableCount,
  );
}
