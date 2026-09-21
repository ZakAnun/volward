//! AI coverage plan v3 — BFS seed frontier + file tail queue (Phase 2 §5).

use std::collections::HashMap;

use serde::Serialize;

use crate::coverage_funnel::{
    build_coverage_funnel_context, compute_coverage_funnel_stats,
    coverage_funnel_context_for_path, resolve_unclassified_for_coverage, CoverageFileResolution,
    CoverageFunnelContextMap, CoverageFunnelStats,
};
use crate::directory_role::{classify_directory_role, DirectoryRole};
use crate::index::SnapshotIndex;
use crate::os_knowledge::OsKnowledgeBase;

pub const AI_COVERAGE_TREE_PLAN_VERSION: u64 = 3;

const TREE_NODE_BATCH_SIZE: u64 = 80;
const TAIL_FILE_BATCH_SIZE: u64 = 40;

#[derive(Debug, Clone, Serialize)]
pub struct AiTreeNode {
    pub path: String,
    pub size_bytes: u64,
    pub file_count: u64,
    pub subdir_count: u64,
    pub role: DirectoryRole,
    pub markers: Vec<String>,
    pub pruned_flags: u32,
    pub top_extensions: Vec<(String, u32)>,
}

#[derive(Debug, Clone)]
pub struct AiTreePlan {
    pub plan_version: u64,
    pub snapshot_id: String,
    pub root_path: String,
    pub seed_nodes: Vec<AiTreeNode>,
    pub tail_file_paths: Vec<(String, u64)>,
    pub funnel_stats: CoverageFunnelStats,
    pub estimated_tree_credits: u64,
    pub estimated_tail_credits: u64,
}

pub fn build_ai_tree_plan(
    index: &SnapshotIndex,
    kb: &OsKnowledgeBase,
    protected_prefixes: &[String],
    personal_prefixes: &[String],
) -> AiTreePlan {
    let funnel_map = build_coverage_funnel_context(index, kb, protected_prefixes);
    let funnel_stats = compute_coverage_funnel_stats(
        index,
        kb,
        protected_prefixes,
        personal_prefixes,
    );
    let tail_file_paths = collect_tail_queue(
        index,
        kb,
        protected_prefixes,
        personal_prefixes,
        &funnel_map,
    );
    let seed_nodes = build_seed_nodes(
        index,
        kb,
        protected_prefixes,
        personal_prefixes,
        &funnel_map,
    );

    AiTreePlan {
        plan_version: AI_COVERAGE_TREE_PLAN_VERSION,
        snapshot_id: index.snapshot_id.clone(),
        root_path: index.root_path.clone(),
        estimated_tree_credits: seed_nodes.len().div_ceil(TREE_NODE_BATCH_SIZE as usize) as u64,
        estimated_tail_credits: tail_file_paths
            .len()
            .div_ceil(TAIL_FILE_BATCH_SIZE as usize) as u64,
        seed_nodes,
        tail_file_paths,
        funnel_stats,
    }
}

fn collect_tail_queue(
    index: &SnapshotIndex,
    kb: &OsKnowledgeBase,
    protected_prefixes: &[String],
    personal_prefixes: &[String],
    funnel_map: &CoverageFunnelContextMap,
) -> Vec<(String, u64)> {
    let classified = index.classified_paths();
    let mut tail: Vec<(String, u64)> = Vec::new();
    for (path, size_bytes) in index.unclassified_files() {
        if classified.contains(&path) {
            continue;
        }
        let resolution = resolve_file(index, kb, protected_prefixes, personal_prefixes, funnel_map, &path, size_bytes);
        if matches!(
            resolution,
            CoverageFileResolution::TailCandidate { .. }
        ) {
            tail.push((path, size_bytes));
        }
    }
    tail.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    tail
}

fn build_seed_nodes(
    index: &SnapshotIndex,
    kb: &OsKnowledgeBase,
    protected_prefixes: &[String],
    personal_prefixes: &[String],
    funnel_map: &CoverageFunnelContextMap,
) -> Vec<AiTreeNode> {
    let root_query = index.query_directory(&index.root_path, None, false, "name");
    let mut nodes: Vec<AiTreeNode> = Vec::new();
    for child in root_query.direct_children {
        if !child.is_directory {
            continue;
        }
        let dir_path = child.path;
        let (role, markers) = classify_directory_role(index, &dir_path);
        if matches!(
            role,
            DirectoryRole::ProjectRoot | DirectoryRole::ProjectLike
        ) {
            continue;
        }
        if !subtree_has_tree_or_tail_pending(
            index,
            kb,
            protected_prefixes,
            personal_prefixes,
            funnel_map,
            &dir_path,
        ) {
            continue;
        }
        if subtree_all_local_resolved(
            index,
            kb,
            protected_prefixes,
            personal_prefixes,
            funnel_map,
            &dir_path,
        ) {
            continue;
        }
        nodes.push(build_tree_node(index, &dir_path, role, markers));
    }
    nodes.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes).then(a.path.cmp(&b.path)));
    nodes
}

fn build_tree_node(
    index: &SnapshotIndex,
    dir_path: &str,
    role: DirectoryRole,
    markers: Vec<String>,
) -> AiTreeNode {
    let (file_count, subdir_count, ext_counts) = subtree_unclassified_stats(index, dir_path);
    let top_extensions = top_n_extensions(&ext_counts, 3);
    let size_bytes = index
        .directory_record(dir_path)
        .map(|d| d.size_bytes)
        .unwrap_or(0);
    let pruned_flags = index.directory_pruned_child_flags(dir_path);

    AiTreeNode {
        path: dir_path.to_string(),
        size_bytes,
        file_count,
        subdir_count,
        role,
        markers,
        pruned_flags,
        top_extensions,
    }
}

fn subtree_has_tree_or_tail_pending(
    index: &SnapshotIndex,
    kb: &OsKnowledgeBase,
    protected_prefixes: &[String],
    personal_prefixes: &[String],
    funnel_map: &CoverageFunnelContextMap,
    dir_path: &str,
) -> bool {
    let classified = index.classified_paths();
    for (path, size_bytes) in index.unclassified_files() {
        if classified.contains(&path) {
            continue;
        }
        if !path_is_at_or_under(&path, dir_path) {
            continue;
        }
        let resolution = resolve_file(
            index,
            kb,
            protected_prefixes,
            personal_prefixes,
            funnel_map,
            &path,
            size_bytes,
        );
        if matches!(
            resolution,
            CoverageFileResolution::TreeCandidate | CoverageFileResolution::TailCandidate { .. }
        ) {
            return true;
        }
    }
    false
}

fn subtree_all_local_resolved(
    index: &SnapshotIndex,
    kb: &OsKnowledgeBase,
    protected_prefixes: &[String],
    personal_prefixes: &[String],
    funnel_map: &CoverageFunnelContextMap,
    dir_path: &str,
) -> bool {
    let classified = index.classified_paths();
    let mut saw_any = false;
    for (path, size_bytes) in index.unclassified_files() {
        if classified.contains(&path) {
            continue;
        }
        if !path_is_at_or_under(&path, dir_path) {
            continue;
        }
        saw_any = true;
        let resolution = resolve_file(
            index,
            kb,
            protected_prefixes,
            personal_prefixes,
            funnel_map,
            &path,
            size_bytes,
        );
        if !matches!(
            resolution,
            CoverageFileResolution::LocalSafe(_) | CoverageFileResolution::LocalKeep { .. }
        ) {
            return false;
        }
    }
    saw_any
}

fn subtree_unclassified_stats(
    index: &SnapshotIndex,
    dir_path: &str,
) -> (u64, u64, HashMap<String, u32>) {
    let classified = index.classified_paths();
    let mut file_count = 0u64;
    let mut ext_counts: HashMap<String, u32> = HashMap::new();
    for (path, size_bytes) in index.unclassified_files() {
        if classified.contains(&path) {
            continue;
        }
        if !path_is_at_or_under(&path, dir_path) {
            continue;
        }
        let _ = size_bytes;
        file_count += 1;
        if let Some(ext) = extension_token(&path) {
            *ext_counts.entry(ext).or_default() += 1;
        }
    }
    let subdir_count = count_subdirs(index, dir_path);
    (file_count, subdir_count, ext_counts)
}

fn count_subdirs(index: &SnapshotIndex, dir_path: &str) -> u64 {
    let mut stack = vec![dir_path.to_string()];
    let mut count = 0u64;
    while let Some(dir) = stack.pop() {
        let query = index.query_directory(&dir, None, false, "name");
        for child in query.direct_children {
            if child.is_directory {
                count += 1;
                stack.push(child.path);
            }
        }
    }
    count
}

fn top_n_extensions(counts: &HashMap<String, u32>, n: usize) -> Vec<(String, u32)> {
    let mut items: Vec<(String, u32)> = counts.iter().map(|(k, v)| (k.clone(), *v)).collect();
    items.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    items.truncate(n);
    items
}

fn extension_token(path: &str) -> Option<String> {
    let name = path.rsplit('/').next()?;
    let ext = name.rsplit('.').next()?;
    if ext == name || ext.is_empty() {
        return None;
    }
    Some(format!(".{ext}"))
}

fn resolve_file(
    index: &SnapshotIndex,
    kb: &OsKnowledgeBase,
    protected_prefixes: &[String],
    personal_prefixes: &[String],
    funnel_map: &CoverageFunnelContextMap,
    path: &str,
    size_bytes: u64,
) -> CoverageFileResolution {
    let project_ancestor = funnel_map.get(path).cloned().flatten();
    let ctx = coverage_funnel_context_for_path(
        project_ancestor,
        index,
        protected_prefixes,
        personal_prefixes,
    );
    resolve_unclassified_for_coverage(path, size_bytes, kb, &ctx)
}

fn path_is_at_or_under(path: &str, root: &str) -> bool {
    let path = normalize_path(path);
    let root = normalize_path(root);
    if root.is_empty() {
        return false;
    }
    path == root || (path.starts_with(&root) && path.as_bytes().get(root.len()) == Some(&b'/'))
}

fn normalize_path(path: &str) -> String {
    let normalized = path.replace('\\', "/");
    if normalized.len() > 1 && normalized.ends_with('/') {
        normalized[..normalized.len() - 1].to_string()
    } else {
        normalized
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::index::SnapshotIndexBuilder;
    use crate::model::ScanStats;

    fn kb_empty() -> OsKnowledgeBase {
        OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
            .unwrap()
    }

    fn finish(builder: SnapshotIndexBuilder) -> SnapshotIndex {
        builder.finish(
            "snap-tree".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        )
    }

    #[test]
    fn ai_tree_plan_fixture_project_tail_and_seed_nodes() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/proj/src");
        builder.ensure_dir("/root/proj/llm-output");
        builder.ensure_dir("/root/unknown_storage");
        builder.record_file_size("/root/proj/Cargo.toml", 10);
        builder.record_file_size("/root/proj/src/main.rs", 200);
        builder.record_file_size("/root/proj/llm-output/out.md", 50);
        builder.record_file_size("/root/unknown_storage/misc.dat", 500);
        let index = finish(builder);
        let kb = kb_empty();

        let plan = build_ai_tree_plan(&index, &kb, &[], &[]);

        assert_eq!(plan.plan_version, AI_COVERAGE_TREE_PLAN_VERSION);
        assert_eq!(plan.plan_version, 3);

        let tail_paths: Vec<&str> = plan
            .tail_file_paths
            .iter()
            .map(|(p, _)| p.as_str())
            .collect();
        assert!(
            tail_paths.contains(&"/root/proj/llm-output/out.md"),
            "ai output should be in tail: {tail_paths:?}"
        );
        assert!(
            !tail_paths.iter().any(|p| p.ends_with("main.rs")),
            "project source should not be in tail: {tail_paths:?}"
        );

        let seed_paths: Vec<&str> = plan.seed_nodes.iter().map(|n| n.path.as_str()).collect();
        assert!(
            !seed_paths.iter().any(|p| *p == "/root/proj"),
            "project subtree excluded from seed frontier: {seed_paths:?}"
        );
        assert!(
            seed_paths.contains(&"/root/unknown_storage"),
            "storage-like top-level dir with tree mass should be seeded: {seed_paths:?}"
        );

        let stats = &plan.funnel_stats;
        assert!(stats.local_keep_files >= 2, "project files → local keep: {stats:?}");
        assert_eq!(stats.tail_files, 1, "{stats:?}");
        assert_eq!(stats.tree_pending_files, 1, "{stats:?}");

        let unclassified = index.unclassified_files().len() as u64;
        assert_eq!(
            stats.local_safe_files
                + stats.local_keep_files
                + stats.tail_files
                + stats.tree_pending_files,
            unclassified
        );

        assert_eq!(plan.estimated_tree_credits, 1);
        assert_eq!(plan.estimated_tail_credits, 1);
    }
}
