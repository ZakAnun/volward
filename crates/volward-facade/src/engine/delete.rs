use super::*;

impl VolwardEngine {
    pub fn delete_entries(
        &self,
        snapshot_id: &str,
        entry_ids: Vec<String>,
        dry_run: bool,
    ) -> Result<DeleteReport, String> {
        {
            let guard = self.last_index.lock().map_err(|e| format!("lock: {e}"))?;
            if let Some(index) = guard.as_ref() {
                if index.snapshot_id != snapshot_id {
                    return Err("Snapshot expired or mismatch".to_string());
                }
                let mut paths = Vec::new();
                for target in &entry_ids {
                    if ai_aggregate_path_from_delete_target(target).is_some() {
                        paths.extend(resolve_index_ai_aggregate_paths(index, target)?);
                        continue;
                    }
                    let resolved_entries = index.entries_for_ids(std::slice::from_ref(target));
                    if let Some(entry) = resolved_entries.first() {
                        paths.push((entry.path.clone(), entry.size_bytes));
                        continue;
                    }
                    if let Some(dir) = index.directory_record(target) {
                        paths.push((dir.path, dir.size_bytes));
                        continue;
                    }
                    if let Some((path, size_bytes)) = index_target_path_size(index, target.as_str())
                    {
                        paths.push((path, size_bytes));
                    }
                }
                return DeleteOrchestrator::delete_explicit_paths(
                    paths,
                    Some(&index.root_path),
                    dry_run,
                    &*self.platform,
                )
                .map_err(|e| e.to_string());
            }
        }

        let snapshot = self
            .get_last_snapshot()
            .ok_or_else(|| "No snapshot loaded".to_string())?;
        if snapshot.snapshot_id != snapshot_id {
            return Err("Snapshot expired or mismatch".to_string());
        }
        let mut paths = Vec::new();
        for target in &entry_ids {
            if ai_aggregate_path_from_delete_target(target).is_some() {
                paths.extend(resolve_snapshot_ai_aggregate_paths(&snapshot, target)?);
                continue;
            }
            if let Some((path, size_bytes)) =
                snapshot_target_path_size(&snapshot.tree, &snapshot.entries, target)
            {
                paths.push((path, size_bytes));
            }
        }
        DeleteOrchestrator::delete_explicit_paths(
            paths,
            Some(&snapshot.tree.path),
            dry_run,
            &*self.platform,
        )
        .map_err(|e| e.to_string())
    }

    pub fn empty_trash(&self) -> Result<TrashEmptyReport, String> {
        DeleteOrchestrator::empty_trash(&*self.platform).map_err(|e| e.to_string())
    }

}
