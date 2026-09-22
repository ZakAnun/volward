use crate::config::{
    BATCH_SIZE, MAX_OUTPUT_TOKENS, MODEL, TEMPERATURE, THINKING_DISABLED, TREE_BATCH_SIZE,
    TREE_MAX_OUTPUT_TOKENS,
};
use crate::prompt::{SYSTEM_PROMPT, TREE_SYSTEM_PROMPT};
use crate::types::{AnalyzeCandidate, AnalyzeTreeNode};

/// Split candidates into batches of [`BATCH_SIZE`].
pub fn split_batches(items: Vec<AnalyzeCandidate>) -> Vec<Vec<AnalyzeCandidate>> {
    if items.is_empty() {
        return vec![];
    }
    items.chunks(BATCH_SIZE).map(|c| c.to_vec()).collect()
}

/// Split tree directory nodes into batches of [`TREE_BATCH_SIZE`].
pub fn split_tree_batches(items: Vec<AnalyzeTreeNode>) -> Vec<Vec<AnalyzeTreeNode>> {
    if items.is_empty() {
        return vec![];
    }
    items
        .chunks(TREE_BATCH_SIZE)
        .map(|c| c.to_vec())
        .collect()
}

/// Build DeepSeek Chat Completions request body for one batch.
pub fn build_request_body(batch: &[AnalyzeCandidate]) -> String {
    let user_content = batch
        .iter()
        .map(|c| {
            let type_label = if c.is_dir { "dir" } else { "file" };
            let extra = c
                .child_count
                .map(|n| format!(", {n} files"))
                .unwrap_or_default();
            let cleanup = match (&c.cleanup_source, &c.cleanup_hint, c.retention_days) {
                (Some(source), Some(hint), Some(days)) => {
                    format!(", source: {source}, stale_after: {days} days, hint: {hint}")
                }
                (Some(source), Some(hint), None) => {
                    format!(", source: {source}, hint: {hint}")
                }
                (Some(source), None, Some(days)) => {
                    format!(", source: {source}, stale_after: {days} days")
                }
                (Some(source), None, None) => format!(", source: {source}"),
                _ => String::new(),
            };
            format!(
                "{} [{type_label}{extra}, {}{}]",
                c.path,
                human_size(c.size_bytes),
                cleanup
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    let thinking = if THINKING_DISABLED {
        serde_json::json!({ "type": "disabled" })
    } else {
        serde_json::json!({ "type": "enabled" })
    };

    let body = serde_json::json!({
        "model": MODEL,
        "temperature": TEMPERATURE,
        "max_tokens": MAX_OUTPUT_TOKENS,
        "thinking": thinking,
        "messages": [
            { "role": "system", "content": SYSTEM_PROMPT },
            { "role": "user", "content": user_content },
        ],
    });
    serde_json::to_string(&body).unwrap_or_else(|_| "{}".to_string())
}

/// Build DeepSeek Chat Completions request body for one tree directory batch.
pub fn build_tree_request_body(batch: &[AnalyzeTreeNode]) -> String {
    let user_content = batch
        .iter()
        .map(format_tree_node_line)
        .collect::<Vec<_>>()
        .join("\n");

    let thinking = if THINKING_DISABLED {
        serde_json::json!({ "type": "disabled" })
    } else {
        serde_json::json!({ "type": "enabled" })
    };

    let body = serde_json::json!({
        "model": MODEL,
        "temperature": TEMPERATURE,
        "max_tokens": TREE_MAX_OUTPUT_TOKENS,
        "thinking": thinking,
        "messages": [
            { "role": "system", "content": TREE_SYSTEM_PROMPT },
            { "role": "user", "content": user_content },
        ],
    });
    serde_json::to_string(&body).unwrap_or_else(|_| "{}".to_string())
}

fn format_tree_node_line(node: &AnalyzeTreeNode) -> String {
    let markers = if node.markers.is_empty() {
        "-".to_string()
    } else {
        node.markers.join("|")
    };
    let top_ext = if node.top_extensions.is_empty() {
        "-".to_string()
    } else {
        node.top_extensions
            .iter()
            .map(|(ext, count)| format!("{ext}:{count}"))
            .collect::<Vec<_>>()
            .join(", ")
    };
    format!(
        "{} [dir, {}, files={}, subdirs={}, role={}, markers={}, pruned_flags={}, top_ext={}]",
        node.path,
        human_size(node.size_bytes),
        node.file_count,
        node.subdir_count,
        node.role,
        markers,
        node.pruned_flags,
        top_ext
    )
}

fn human_size(bytes: u64) -> String {
    if bytes < 1024 {
        return format!("{bytes}B");
    }
    if bytes < 1024 * 1024 {
        return format!("{:.1}KB", bytes as f64 / 1024.0);
    }
    if bytes < 1024 * 1024 * 1024 {
        return format!("{:.1}MB", bytes as f64 / (1024.0 * 1024.0));
    }
    format!("{:.1}GB", bytes as f64 / (1024.0 * 1024.0 * 1024.0))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn split_batches_respects_batch_size() {
        let items: Vec<_> = (0..85)
            .map(|i| AnalyzeCandidate {
                path: format!("/f{i}"),
                size_bytes: 1,
                is_dir: false,
                child_count: None,
                extension: None,
                cleanup_source: None,
                cleanup_hint: None,
                retention_days: None,
            })
            .collect();
        let batches = split_batches(items);
        assert_eq!(batches.len(), 3);
        assert_eq!(batches[0].len(), 40);
        assert_eq!(batches[2].len(), 5);
    }

    #[test]
    fn request_body_has_thinking_disabled_and_model() {
        let batch = vec![AnalyzeCandidate {
            path: "/a".into(),
            size_bytes: 1,
            is_dir: false,
            child_count: None,
            extension: None,
            cleanup_source: Some("ai_tool_cache".into()),
            cleanup_hint: Some("AI/editor cache".into()),
            retention_days: Some(30),
        }];
        let raw = build_request_body(&batch);
        let body: serde_json::Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(body["model"], MODEL);
        assert_eq!(body["thinking"]["type"], "disabled");
        assert_eq!(body["max_tokens"], MAX_OUTPUT_TOKENS);
        assert!(body["messages"].as_array().unwrap().len() >= 2);
        let user = body["messages"][1]["content"].as_str().unwrap();
        assert!(user.contains("source: ai_tool_cache"));
        assert!(user.contains("stale_after: 30 days"));
    }

    #[test]
    fn split_tree_batches_respects_tree_batch_size() {
        let items: Vec<_> = (0..165)
            .map(|i| AnalyzeTreeNode {
                path: format!("/d{i}"),
                size_bytes: 1,
                file_count: 0,
                subdir_count: 0,
                role: "unknown".into(),
                markers: vec![],
                pruned_flags: 0,
                top_extensions: vec![],
            })
            .collect();
        let batches = split_tree_batches(items);
        assert_eq!(batches.len(), 3);
        assert_eq!(batches[0].len(), 80);
        assert_eq!(batches[2].len(), 5);
    }

    #[test]
    fn tree_request_body_uses_tree_prompt_and_max_tokens() {
        let batch = vec![AnalyzeTreeNode {
            path: "/storage".into(),
            size_bytes: 1024 * 1024,
            file_count: 10,
            subdir_count: 2,
            role: "storage_like".into(),
            markers: vec!["large_unknown".into()],
            pruned_flags: 1,
            top_extensions: vec![(".tmp".into(), 5)],
        }];
        let raw = build_tree_request_body(&batch);
        let body: serde_json::Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(body["max_tokens"], TREE_MAX_OUTPUT_TOKENS);
        let system = body["messages"][0]["content"].as_str().unwrap();
        assert!(system.contains("drill_down"));
        let user = body["messages"][1]["content"].as_str().unwrap();
        assert!(user.contains("role=storage_like"));
        assert!(user.contains("markers=large_unknown"));
        assert!(user.contains("pruned_flags=1"));
        assert!(user.contains("top_ext=.tmp:5"));
    }
}
