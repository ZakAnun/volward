use super::VolwardEngine;

impl VolwardEngine {
    /// Query direct children of `path` with optional filter/sort.
    /// Pure in-memory — no file-system scan triggered.
    pub fn query_directory_json(
        &self,
        path: &str,
        category_filter: Option<&str>,
        deletable_only: bool,
        sort_mode: &str,
    ) -> Result<String, String> {
        let guard = self.last_index.lock().map_err(|e| format!("lock: {e}"))?;
        let index = guard
            .as_ref()
            .ok_or_else(|| "error:no index loaded".to_string())?;
        index.query_directory_json(path, category_filter, deletable_only, sort_mode)
    }
}
