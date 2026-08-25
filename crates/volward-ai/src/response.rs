use crate::types::{AiVerdict, AnalyzeCandidate};

/// Parse an OpenAI-compatible DeepSeek chat completion body into verdicts.
///
/// Truncation (`finish_reason == length`), missing choices, or JSON failure
/// degrade the **whole** batch to `review_needed`.
pub fn parse_response(body: &str, batch: &[AnalyzeCandidate]) -> Vec<AiVerdict> {
    let Ok(decoded) = serde_json::from_str::<serde_json::Value>(body) else {
        return unparsed_batch(batch, "AI response is not a JSON object");
    };
    let Some(choices) = decoded.get("choices").and_then(|c| c.as_array()) else {
        return unparsed_batch(batch, "AI response missing choices");
    };
    if choices.is_empty() {
        return unparsed_batch(batch, "AI response missing choices");
    }
    let Some(choice) = choices.first() else {
        return unparsed_batch(batch, "AI response missing choices");
    };
    if choice.get("finish_reason").and_then(|v| v.as_str()) == Some("length") {
        return unparsed_batch(batch, "AI response was truncated");
    }
    let Some(text) = choice
        .get("message")
        .and_then(|m| m.get("content"))
        .and_then(|c| c.as_str())
    else {
        return unparsed_batch(batch, "AI response missing message");
    };
    let stripped = strip_markdown_fence(text);
    match serde_json::from_str::<Vec<AiVerdict>>(&stripped) {
        Ok(list) if !list.is_empty() || batch.is_empty() => list,
        Ok(_) | Err(_) => unparsed_batch(batch, "AI response could not be parsed"),
    }
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

fn unparsed_batch(batch: &[AnalyzeCandidate], reason: &str) -> Vec<AiVerdict> {
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
}
