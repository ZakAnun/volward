use crate::types::{AiVerdict, AnalyzeCandidate, AnalyzeTreeNode};

/// Parse an OpenAI-compatible DeepSeek chat completion body into verdicts.
///
/// Truncation (`finish_reason == length`), missing choices, or JSON failure
/// degrade the **whole** batch to `review_needed`.
pub fn parse_response(body: &str, batch: &[AnalyzeCandidate]) -> Vec<AiVerdict> {
    match parse_verdicts_from_completion(body) {
        Ok(list) if !list.is_empty() || batch.is_empty() => list,
        Ok(_) => unparsed_file_batch(batch, "AI response could not be parsed"),
        Err(reason) => unparsed_file_batch(batch, reason),
    }
}

/// Parse a tree batch completion; accepts `drill_down` and other tree verdict strings.
pub fn parse_tree_response(body: &str, batch: &[AnalyzeTreeNode]) -> Vec<AiVerdict> {
    match parse_verdicts_from_completion(body) {
        Ok(list) if !list.is_empty() || batch.is_empty() => list,
        Ok(_) => unparsed_tree_batch(batch, "AI response could not be parsed"),
        Err(reason) => unparsed_tree_batch(batch, reason),
    }
}

fn parse_verdicts_from_completion(body: &str) -> Result<Vec<AiVerdict>, &'static str> {
    let decoded = serde_json::from_str::<serde_json::Value>(body)
        .map_err(|_| "AI response is not a JSON object")?;
    let choices = decoded
        .get("choices")
        .and_then(|c| c.as_array())
        .filter(|c| !c.is_empty())
        .ok_or("AI response missing choices")?;
    let choice = choices.first().ok_or("AI response missing choices")?;
    if choice.get("finish_reason").and_then(|v| v.as_str()) == Some("length") {
        return Err("AI response was truncated");
    }
    let text = choice
        .get("message")
        .and_then(|m| m.get("content"))
        .and_then(|c| c.as_str())
        .ok_or("AI response missing message")?;
    let stripped = strip_markdown_fence(text);
    serde_json::from_str::<Vec<AiVerdict>>(&stripped).map_err(|_| "AI response could not be parsed")
}

fn strip_markdown_fence(text: &str) -> String {
    let trimmed = text.trim();
    if !trimmed.starts_with("```") {
        return trimmed.to_string();
    }
    let lines: Vec<&str> = trimmed.split('\n').collect();
    if lines.len() < 3 {
        return trimmed.to_string();
    }
    let end = if lines.last().is_some_and(|l| l.trim() == "```") {
        lines.len() - 1
    } else {
        lines.len()
    };
    lines[1..end].join("\n").trim().to_string()
}

fn unparsed_file_batch(batch: &[AnalyzeCandidate], reason: &str) -> Vec<AiVerdict> {
    batch
        .iter()
        .map(|c| AiVerdict {
            path: c.path.clone(),
            verdict: "review_needed".into(),
            confidence: "low".into(),
            reason: reason.into(),
        })
        .collect()
}

fn unparsed_tree_batch(batch: &[AnalyzeTreeNode], reason: &str) -> Vec<AiVerdict> {
    batch
        .iter()
        .map(|c| AiVerdict {
            path: c.path.clone(),
            verdict: "review_needed".into(),
            confidence: "low".into(),
            reason: reason.into(),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn length_finish_reason_degrades_whole_batch() {
        let batch = vec![AnalyzeCandidate {
            path: "/a".into(),
            size_bytes: 1,
            is_dir: false,
            child_count: None,
            extension: None,
            cleanup_source: None,
            cleanup_hint: None,
            retention_days: None,
        }];
        let body = r#"{"choices":[{"finish_reason":"length","message":{"content":"["}}]}"#;
        let out = parse_response(body, &batch);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].verdict, "review_needed");
    }

    #[test]
    fn strips_markdown_fence() {
        let batch = vec![AnalyzeCandidate {
            path: "/a".into(),
            size_bytes: 1,
            is_dir: false,
            child_count: None,
            extension: None,
            cleanup_source: None,
            cleanup_hint: None,
            retention_days: None,
        }];
        let inner = r#"[{"path":"/a","verdict":"keep","confidence":"high","reason":"x"}]"#;
        let fenced = format!("```json\n{inner}\n```");
        let body = serde_json::json!({
            "choices": [{
                "finish_reason": "stop",
                "message": { "content": fenced },
            }],
        })
        .to_string();
        let out = parse_response(&body, &batch);
        assert_eq!(out[0].verdict, "keep");
    }

    #[test]
    fn tree_response_parses_drill_down_verdict() {
        let batch = vec![AnalyzeTreeNode {
            path: "/storage".into(),
            size_bytes: 1,
            file_count: 0,
            subdir_count: 3,
            role: "storage_like".into(),
            markers: vec![],
            pruned_flags: 0,
            top_extensions: vec![],
        }];
        let inner = r#"[{"path":"/storage","verdict":"drill_down","confidence":"medium","reason":"need children"}]"#;
        let body = serde_json::json!({
            "choices": [{
                "finish_reason": "stop",
                "message": { "content": inner },
            }],
        })
        .to_string();
        let out = parse_tree_response(&body, &batch);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].verdict, "drill_down");
        assert_eq!(out[0].path, "/storage");
    }
}
