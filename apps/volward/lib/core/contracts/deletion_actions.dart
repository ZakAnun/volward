/// Delete and trash operations for the currently active snapshot.
abstract interface class DeletionActions {
  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    String? expectedSnapshotId,
    bool dryRun = false,
    bool rescanAfterDelete = false,
    String? refreshPath,
    Map<String, String>? targetPathById,
  });

  Future<Map<String, dynamic>> emptyTrash({bool rescanAfterEmpty = true});
}
