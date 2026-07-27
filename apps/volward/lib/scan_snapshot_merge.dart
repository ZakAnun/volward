/// Splices [subtreeTree] (already in the wire "ScanTreeNode json" shape)
/// into [snapshot]'s `tree` at [targetPath], replacing that node's
/// `size_bytes`/`scanned`, and merging its `children`. Also merges
/// [subtreeEntries] into `snapshot['entries']`, overwriting any existing
/// entry with the same `id`, and recomputes `reclaimable_estimate_bytes`
/// locally from the merged entries (rather than trusting a possibly-stale
/// value carried over from an earlier partial result).
///
/// [replacementIsAuthoritative] distinguishes two very different callers:
/// - `false` (default) — [subtreeTree] is a snapshot of the *still-running*
///   background scan (a checkpoint). It may be less complete than what's
///   already displayed for parts of the tree it hasn't caught up to yet, so
///   children are upserted by path via [_mergeChildrenByPath] (see there),
///   and entries are only ever added/overwritten by id, never removed.
/// - `true` — [subtreeTree] is the result of a completed, scoped Wave-2
///   peek scan of exactly [targetPath]: a fresh, complete listing of that
///   directory. It is trusted wholesale (including a child's *absence*,
///   e.g. a file deleted since the last checkpoint), rather than compared
///   size-for-size against old data — otherwise a real deletion could be
///   masked indefinitely by the old, larger, now-stale size. For the same
///   reason, any existing entry whose `path_or_uri` falls under
///   [targetPath] but is absent from [subtreeEntries] is dropped too —
///   otherwise a deleted file's stale entry would keep inflating
///   `reclaimable_estimate_bytes` until the whole scan finishes.
///
/// Pure function: [snapshot] is never mutated; a new map is returned.
Map<String, dynamic> mergeSubtreeIntoSnapshot({
  required Map<String, dynamic> snapshot,
  required String targetPath,
  required Map<String, dynamic> subtreeTree,
  required List<Map<String, dynamic>> subtreeEntries,
  bool replacementIsAuthoritative = false,
}) {
  // Background checkpoints never carry a `scanned` field (Rust doesn't
  // serialize one). Stamp directories the walk has already rediscovered as
  // `scanned: true` so preview spinners clear per-directory as soon as
  // that path appears in a checkpoint — instead of lingering until the
  // final Done snapshot replaces the whole tree.
  final incomingTree = replacementIsAuthoritative
      ? subtreeTree
      : _markDiscoveredDirsScanned(subtreeTree);

  final tree = snapshot['tree'];
  final mergedTree = tree is Map
      ? _replaceNodeAtPath(
          Map<String, dynamic>.from(tree),
          targetPath,
          incomingTree,
          replacementIsAuthoritative: replacementIsAuthoritative,
        )
      : incomingTree;

  final existingEntries = (snapshot['entries'] is List)
      ? (snapshot['entries'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
      : <Map<String, dynamic>>[];
  final byId = <String, Map<String, dynamic>>{
    for (final e in existingEntries)
      if (e['id'] != null) e['id'].toString(): e,
  };
  for (final e in subtreeEntries) {
    final id = e['id']?.toString();
    if (id != null) byId[id] = e;
  }
  if (replacementIsAuthoritative) {
    final prefix = targetPath.endsWith('/') ? targetPath : '$targetPath/';
    final freshIds = subtreeEntries
        .map((e) => e['id']?.toString())
        .whereType<String>()
        .toSet();
    byId.removeWhere((id, e) {
      final entryPath = e['path_or_uri']?.toString();
      if (entryPath == null) return false;
      final underTarget = entryPath == targetPath || entryPath.startsWith(prefix);
      return underTarget && !freshIds.contains(id);
    });
  }
  final mergedEntries = byId.values.toList();

  final reclaimable = mergedEntries
      .where((e) => e['deletable'] == true)
      .fold<int>(0, (sum, e) => sum + ((e['size_bytes'] as num?)?.toInt() ?? 0));

  return {
    ...snapshot,
    'tree': mergedTree,
    'entries': mergedEntries,
    'reclaimable_estimate_bytes': reclaimable,
  };
}

Map<String, dynamic> _replaceNodeAtPath(
  Map<String, dynamic> node,
  String targetPath,
  Map<String, dynamic> replacement, {
  required bool replacementIsAuthoritative,
}) {
  if (node['path']?.toString() == targetPath) {
    return {
      ...node,
      'size_bytes': replacement['size_bytes'],
      'scanned': replacement['scanned'] ?? true,
      // Mark authoritative (peek) results so _pickMoreComplete can distinguish
      // them from checkpoint-stamped dirs (which only carry scanned:true).
      if (replacementIsAuthoritative) 'peekScanned': true,
      'children': replacementIsAuthoritative
          ? _childList(replacement)
          : _mergeChildrenByPath(_childList(node), _childList(replacement)),
    };
  }

  final children = node['children'];
  if (children is! List) return node;

  final newChildren = <dynamic>[];
  var found = false;
  for (final child in children) {
    final childPath = (child is Map) ? child['path']?.toString() ?? '' : '';
    final isOnPath = child is Map &&
        childPath.isNotEmpty &&
        (targetPath == childPath ||
            targetPath.startsWith(
              childPath.endsWith('/') ? childPath : '$childPath/',
            ));
    if (isOnPath) {
      newChildren.add(
        _replaceNodeAtPath(
          Map<String, dynamic>.from(child),
          targetPath,
          replacement,
          replacementIsAuthoritative: replacementIsAuthoritative,
        ),
      );
      found = true;
    } else {
      newChildren.add(child);
    }
  }

  if (!found) return node;
  return {...node, 'children': newChildren};
}

List<Map<String, dynamic>> _childList(Map<String, dynamic> node) {
  final children = node['children'];
  if (children is! List) return const [];
  return children
      .whereType<Map>()
      .map((c) => Map<String, dynamic>.from(c))
      .toList();
}

/// Upserts [newChildren] into [oldChildren] by `path` instead of blindly
/// replacing the whole list.
///
/// This matters because a periodic background-scan checkpoint's view of a
/// subtree can temporarily be *less* complete than what's already being
/// displayed — e.g. a directory a Wave-2 peek scan already fully resolved,
/// but the (slower) main background scan hasn't rediscovered yet in this
/// checkpoint. Wholesale-replacing `children` with the checkpoint's list
/// would silently drop that already-resolved data (or any not-yet
/// rediscovered preview/peek entry) and briefly regress the UI back to an
/// unscanned/emptier state until the main scan eventually catches back up.
///
/// - A child present in both is resolved via [_pickMoreComplete].
/// - A child present only in [oldChildren] (not yet rediscovered by this
///   merge) is kept as-is.
/// - A child present only in [newChildren] is a new discovery and is added.
List<Map<String, dynamic>> _mergeChildrenByPath(
  List<Map<String, dynamic>> oldChildren,
  List<Map<String, dynamic>> newChildren,
) {
  final oldByPath = <String, Map<String, dynamic>>{
    for (final c in oldChildren)
      if (c['path'] != null) c['path'].toString(): c,
  };

  final merged = <Map<String, dynamic>>[];
  final seenPaths = <String>{};
  for (final newChild in newChildren) {
    final path = newChild['path']?.toString();
    if (path == null) {
      merged.add(newChild);
      continue;
    }
    seenPaths.add(path);
    final oldChild = oldByPath[path];
    merged.add(oldChild == null ? newChild : _pickMoreComplete(oldChild, newChild));
  }
  for (final entry in oldByPath.entries) {
    if (!seenPaths.contains(entry.key)) merged.add(entry.value);
  }
  return merged;
}

/// Marks every directory in a checkpoint fragment as `scanned: true`.
///
/// Preview nodes start as `scanned: false` (spinner). Once the background
/// walk rediscovers a path in a checkpoint, that directory's contents are
/// at least partially known and the spinner should clear immediately for
/// that row — not wait for the full scan to finish.
Map<String, dynamic> _markDiscoveredDirsScanned(Map<String, dynamic> node) {
  if (node['is_dir'] != true) return node;
  return {
    ...node,
    'scanned': true,
    'children': [
      for (final child in _childList(node)) _markDiscoveredDirsScanned(child),
    ],
  };
}

/// Keeps whichever side of a duplicate-path child looks more complete.
///
/// Only used for non-authoritative (checkpoint) merges — see
/// [mergeSubtreeIntoSnapshot]. Uses aggregated `size_bytes` as a
/// monotonic-enough proxy: a directory's size usually only grows as more of
/// its subtree is discovered by a given scan pass, so a smaller size on the
/// incoming side — while the existing side came from a completed Wave-2
/// peek (`peekScanned: true`) — is treated as a regression rather than
/// new information, and is ignored in favor of the peek data.
///
/// **Peek vs. checkpoint distinction**: [_replaceNodeAtPath] writes
/// `peekScanned: true` on the *target* node of every authoritative merge.
/// Checkpoint-stamped dirs only carry `scanned: true` (from
/// [_markDiscoveredDirsScanned]), never `peekScanned`. Using a separate
/// sentinel keeps the deep-merge logic scoped to actual peek results and
/// avoids O(overlap × children) deep-merges on every checkpoint after the
/// first one (checkpoint-stamped dirs no longer falsely appear
/// "peek-authoritative" to this function).
///
/// Known limitation: if a file is genuinely deleted between two checkpoints
/// of the *same* still-running background scan (not a peek), and the
/// existing side was previously from a peek, this proxy cannot distinguish
/// "smaller because incomplete" from "smaller because something was deleted"
/// and will keep the stale larger size until the scan finishes. A completed
/// peek scan (`replacementIsAuthoritative: true`) does not have this
/// limitation, since its result is trusted wholesale.
Map<String, dynamic> _pickMoreComplete(
  Map<String, dynamic> oldChild,
  Map<String, dynamic> newChild,
) {
  // Only a completed peek can veto a smaller incoming checkpoint.
  // Checkpoint-stamped dirs (scanned:true but NOT peekScanned) must still
  // accept newer checkpoint data even when the incoming size is temporarily
  // smaller — the checkpoint may not have finished counting yet.
  final oldPeeked = oldChild['peekScanned'] == true;
  final oldSize = (oldChild['size_bytes'] as num?)?.toInt() ?? 0;
  final newSize = (newChild['size_bytes'] as num?)?.toInt() ?? 0;
  if (oldPeeked && oldSize > newSize) return oldChild;

  // Directory: stamp scanned so preview spinners clear.
  // Deep-merge children whenever the old side has *any* known content
  // (whether from a peek or a prior checkpoint) so that children the new
  // checkpoint hasn't re-listed yet are not silently dropped. Only take new
  // children wholesale for dirs that were still unscanned (preview-only).
  if (newChild['is_dir'] == true) {
    final oldScanned = oldPeeked || oldChild['scanned'] == true;
    return {
      ...newChild,
      'scanned': true,
      'children': oldScanned
          ? _mergeChildrenByPath(_childList(oldChild), _childList(newChild))
          : _childList(newChild),
    };
  }
  return newChild;
}
