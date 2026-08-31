class ScanEntryRecord {
  const ScanEntryRecord({
    required this.id,
    required this.displayName,
    required this.pathOrUri,
    required this.sizeBytes,
    required this.category,
    required this.deletable,
    this.modifiedAtMs,
  });

  factory ScanEntryRecord.fromWire(Map<String, dynamic> wire) {
    return ScanEntryRecord(
      id: wire['id']?.toString() ?? '',
      displayName: wire['display_name']?.toString() ?? '',
      pathOrUri: wire['path_or_uri']?.toString() ?? '',
      sizeBytes: (wire['size_bytes'] as num?)?.toInt() ?? 0,
      category: wire['category']?.toString() ?? 'Unknown',
      deletable: wire['deletable'] == true,
      modifiedAtMs: (wire['modified_at_ms'] as num?)?.toInt(),
    );
  }

  final String id;
  final String displayName;
  final String pathOrUri;
  final int sizeBytes;
  final String category;
  final bool deletable;
  /// File modification time in epoch milliseconds; null when the snapshot
  /// did not collect metadata (old snapshots, directories, unknown mtime).
  final int? modifiedAtMs;

  int get categoryBit => categoryMaskFor(category);

  Map<String, dynamic> toWire() {
    return {
      'id': id,
      'display_name': displayName,
      'path_or_uri': pathOrUri,
      'size_bytes': sizeBytes,
      'category': category,
      'deletable': deletable,
      if (modifiedAtMs != null) 'modified_at_ms': modifiedAtMs,
    };
  }

  static int categoryMaskFor(String? category) {
    switch (category) {
      case 'Cache':
        return 1 << 0;
      case 'Temp':
        return 1 << 1;
      case 'Media':
        return 1 << 2;
      case 'System':
        return 1 << 3;
      default:
        return 1 << 4;
    }
  }
}
