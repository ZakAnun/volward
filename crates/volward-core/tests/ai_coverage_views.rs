use serde_json::json;
use volward_core::index::SnapshotIndexBuilder;
use volward_core::model::ScanStats;
use volward_core::{
    build_ai_coverage_plan, coverage_group_member_paths, coverage_group_resolution,
    coverage_local_verdict_page, coverage_plan_page, coverage_plan_summary, coverage_tail_page,
    coverage_tree_page, coverage_tree_summary, AiCoveragePlan, AiCoverageRow, AiCoverageRowKind,
    AiTreeNode, AiTreePlan, CoverageFunnelStats, CoverageLocalVerdict, DirectoryRole,
    OsKnowledgeBase,
};

fn empty_kb() -> OsKnowledgeBase {
    OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos").unwrap()
}

fn build_index(
    snapshot_id: &str,
    paths: impl IntoIterator<Item = (String, u64)>,
) -> volward_core::SnapshotIndex {
    let mut builder = SnapshotIndexBuilder::new("/Users/x");
    for (path, size) in paths {
        builder.record_file_size(&path, size);
    }
    builder.finish(
        snapshot_id.to_string(),
        1,
        1,
        "Done".to_string(),
        ScanStats::default(),
    )
}

#[test]
fn summary_and_pages_are_pure_core_views() {
    let index = build_index(
        "summary-snap",
        (0..90).map(|i| (format!("/Users/x/plain/f{i}.bin"), i + 1)),
    );
    let plan = build_ai_coverage_plan(&index, &empty_kb());
    let funnel = CoverageFunnelStats {
        local_safe_files: 3,
        local_keep_files: 4,
        tail_files: 5,
        tree_pending_files: 6,
    };

    let summary = coverage_plan_summary(&plan, funnel);
    assert_eq!(summary.total_unclassified, 90);
    assert_eq!(summary.group_rows, 0);
    assert_eq!(summary.file_rows, 90);
    assert_eq!(summary.estimated_pages, 3);
    assert_eq!(summary.local_safe_files, 3);

    let first = coverage_plan_page(&plan, 0, 2);
    assert_eq!(first.rows.len(), 2);
    assert_eq!(first.next_cursor, Some(2));

    let out_of_range = coverage_plan_page(&plan, 999, 40);
    assert!(out_of_range.rows.is_empty());
    assert_eq!(out_of_range.next_cursor, None);
}

#[test]
fn tree_summary_and_pages_are_pure_core_views() {
    let index = build_index("tree-snap", std::iter::empty());
    let plan = AiTreePlan {
        plan_version: 3,
        snapshot_id: "tree-snap".to_string(),
        root_path: "/Users/x".to_string(),
        seed_nodes: vec![],
        tail_file_paths: vec![("/Users/x/a.bin".to_string(), 10)],
        funnel_stats: CoverageFunnelStats {
            tail_files: 1,
            ..CoverageFunnelStats::default()
        },
        estimated_tree_credits: 0,
        estimated_tail_credits: 1,
    };

    let summary = coverage_tree_summary(&index, &plan);
    assert_eq!(summary.snapshot_id, "tree-snap");
    assert_eq!(summary.total_unclassified, 1);
    assert_eq!(summary.tail_file_count, 1);

    let tree = coverage_tree_page(&plan, 0, 40);
    assert!(tree.nodes.is_empty());
    assert_eq!(tree.next_cursor, None);

    let tail = coverage_tail_page(&plan, 0, 40);
    assert_eq!(tail.rows.len(), 1);
    assert_eq!(tail.rows[0].path, "/Users/x/a.bin");
    assert_eq!(tail.next_cursor, None);
}

#[test]
fn local_verdict_and_group_resolution_views_keep_wire_shape() {
    let verdict = CoverageLocalVerdict {
        path: "/Users/x/a.bin".to_string(),
        size_bytes: 10,
        verdict: "keep".to_string(),
        confidence: "high".to_string(),
        reason: "test".to_string(),
        coverage_source: "local".to_string(),
    };
    let page = coverage_local_verdict_page(vec![verdict], Some(7));
    assert_eq!(page.verdicts.len(), 1);
    assert_eq!(page.next_cursor, Some(7));

    let index = build_index(
        "group-snap",
        (0..90).map(|i| (format!("/Users/x/Library/Caches/cursor/f{i}.bin"), i + 1)),
    );
    let members =
        coverage_group_member_paths(&index, &empty_kb(), "/Users/x/Library/Caches/cursor");
    let group = coverage_group_resolution("group-snap", "/Users/x/Library/Caches/cursor", members);
    assert_eq!(group.members.len(), 90);
    assert_eq!(group.path, "/Users/x/Library/Caches/cursor");
}

#[test]
fn summary_plan_and_tree_views_serialize_exact_json_shape() {
    let plan = AiCoveragePlan {
        plan_version: 2,
        snapshot_id: "wire-snap".to_string(),
        root_path: "/Users/x".to_string(),
        root_size_bytes: 10,
        scanned_at_ms: 7,
        stats: ScanStats::default(),
        total_unclassified: 1,
        pre_classified_count: 2,
        group_rows: 0,
        file_rows: 1,
        rows: vec![AiCoverageRow {
            row_index: 0,
            kind: AiCoverageRowKind::File,
            path: "/Users/x/a.bin".to_string(),
            size_bytes: 10,
            member_count: None,
            cleanup_source: None,
            cleanup_hint: None,
            retention_days: None,
        }],
    };
    let summary = coverage_plan_summary(
        &plan,
        CoverageFunnelStats {
            local_safe_files: 1,
            local_keep_files: 2,
            tail_files: 3,
            tree_pending_files: 4,
        },
    );
    assert_eq!(
        serde_json::to_value(summary).unwrap(),
        json!({
            "snapshot_id": "wire-snap",
            "plan_version": 2,
            "root_path": "/Users/x",
            "root_size_bytes": 10,
            "scanned_at_ms": 7,
            "stats": {
                "paths_seen": 0,
                "dirs_seen": 0,
                "files_seen": 0,
                "files_in_snapshot": 0,
                "paths_skipped": 0,
                "truncated": false,
                "incomplete_reason": null
            },
            "total_unclassified": 1,
            "pre_classified_count": 2,
            "group_rows": 0,
            "file_rows": 1,
            "estimated_pages": 1,
            "local_safe_files": 1,
            "local_keep_files": 2,
            "tail_files": 3,
            "tree_pending_files": 4
        })
    );

    assert_eq!(
        serde_json::to_value(coverage_plan_page(&plan, 0, 1)).unwrap(),
        json!({
            "snapshot_id": "wire-snap",
            "plan_version": 2,
            "next_cursor": null,
            "rows": [{
                "row_index": 0,
                "kind": "file",
                "path": "/Users/x/a.bin",
                "size_bytes": 10
            }]
        })
    );

    let index = build_index("wire-tree", [("/Users/x/a.bin".to_string(), 10)]);
    let tree_plan = AiTreePlan {
        plan_version: 3,
        snapshot_id: "wire-tree".to_string(),
        root_path: "/Users/x".to_string(),
        seed_nodes: vec![AiTreeNode {
            path: "/Users/x/Cache".to_string(),
            size_bytes: 10,
            file_count: 1,
            subdir_count: 0,
            role: DirectoryRole::CacheLike,
            markers: vec!["cache".to_string()],
            pruned_flags: 0,
            top_extensions: vec![("bin".to_string(), 1)],
        }],
        tail_file_paths: vec![("/Users/x/a.bin".to_string(), 10)],
        funnel_stats: CoverageFunnelStats {
            local_safe_files: 1,
            local_keep_files: 2,
            tail_files: 3,
            tree_pending_files: 4,
        },
        estimated_tree_credits: 5,
        estimated_tail_credits: 6,
    };
    assert_eq!(
        serde_json::to_value(coverage_tree_summary(&index, &tree_plan)).unwrap(),
        json!({
            "snapshot_id": "wire-tree",
            "plan_version": 3,
            "root_path": "/Users/x",
            "root_size_bytes": 10,
            "scanned_at_ms": 1,
            "total_unclassified": 10,
            "seed_node_count": 1,
            "tail_file_count": 1,
            "local_safe_files": 1,
            "local_keep_files": 2,
            "tail_files": 3,
            "tree_pending_files": 4,
            "estimated_tree_credits": 5,
            "estimated_tail_credits": 6
        })
    );
    assert_eq!(
        serde_json::to_value(coverage_tree_page(&tree_plan, 0, 1)).unwrap(),
        json!({
            "snapshot_id": "wire-tree",
            "plan_version": 3,
            "next_cursor": null,
            "nodes": [{
                "path": "/Users/x/Cache",
                "size_bytes": 10,
                "file_count": 1,
                "subdir_count": 0,
                "role": "cache_like",
                "markers": ["cache"],
                "pruned_flags": 0,
                "top_extensions": [["bin", 1]]
            }]
        })
    );
    assert_eq!(
        serde_json::to_value(coverage_tail_page(&tree_plan, 0, 1)).unwrap(),
        json!({
            "snapshot_id": "wire-tree",
            "plan_version": 3,
            "next_cursor": null,
            "rows": [{
                "path": "/Users/x/a.bin",
                "size_bytes": 10
            }]
        })
    );
}

#[test]
fn local_verdict_and_group_views_serialize_exact_json_shape() {
    let verdict = CoverageLocalVerdict {
        path: "/Users/x/a.bin".to_string(),
        size_bytes: 10,
        verdict: "keep".to_string(),
        confidence: "high".to_string(),
        reason: "test".to_string(),
        coverage_source: "local".to_string(),
    };
    assert_eq!(
        serde_json::to_value(coverage_local_verdict_page(vec![verdict], Some(7))).unwrap(),
        json!({
            "verdicts": [{
                "path": "/Users/x/a.bin",
                "size_bytes": 10,
                "verdict": "keep",
                "confidence": "high",
                "reason": "test",
                "coverage_source": "local"
            }],
            "next_cursor": 7
        })
    );

    assert_eq!(
        serde_json::to_value(coverage_group_resolution(
            "wire-group",
            "/Users/x/Cache",
            vec![("/Users/x/Cache/a.bin".to_string(), 10)],
        ))
        .unwrap(),
        json!({
            "snapshot_id": "wire-group",
            "path": "/Users/x/Cache",
            "members": [{
                "path": "/Users/x/Cache/a.bin",
                "size_bytes": 10
            }]
        })
    );
}
