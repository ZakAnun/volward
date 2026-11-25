use async_trait::async_trait;
use std::sync::Arc;

use volward_ai::{
    build_conclusion_synthesis_body, build_request_body, build_tree_request_body,
    parse_completion_text, parse_response, parse_tree_response, split_batches, split_tree_batches,
    AiVerdict, AnalyzeCandidate, AnalyzeTreeNode, MODEL, UPSTREAM_ENDPOINT,
};

use crate::error::AppError;

#[async_trait]
pub trait UpstreamClient: Send + Sync {
    async fn complete(&self, request_body: String) -> Result<String, AppError>;
}

pub struct HttpUpstream {
    client: reqwest::Client,
    api_key: String,
}

impl HttpUpstream {
    pub fn new(api_key: String) -> Self {
        Self {
            client: reqwest::Client::new(),
            api_key,
        }
    }
}

#[async_trait]
impl UpstreamClient for HttpUpstream {
    async fn complete(&self, request_body: String) -> Result<String, AppError> {
        let res = self
            .client
            .post(UPSTREAM_ENDPOINT)
            .bearer_auth(&self.api_key)
            .header("Content-Type", "application/json")
            .body(request_body)
            .send()
            .await
            .map_err(|_| AppError::BadGateway)?;
        if !res.status().is_success() {
            return Err(AppError::BadGateway);
        }
        res.text().await.map_err(|_| AppError::BadGateway)
    }
}

pub use crate::billing::{debit_one_credit, refund_one_credit};

pub async fn run_conclusion_upstream(
    upstream: &Arc<dyn UpstreamClient>,
    user_json: &str,
) -> Result<String, AppError> {
    let body = build_conclusion_synthesis_body(user_json);
    let resp = upstream.complete(body).await?;
    parse_completion_text(&resp).map_err(|_| AppError::BadGateway)
}

pub async fn run_upstream(
    upstream: &Arc<dyn UpstreamClient>,
    candidates: &[AnalyzeCandidate],
) -> Result<Vec<AiVerdict>, AppError> {
    let mut out = Vec::new();
    for batch in split_batches(candidates.to_vec()) {
        let body = build_request_body(&batch);
        let resp = upstream.complete(body).await?;
        out.extend(parse_response(&resp, &batch));
    }
    Ok(out)
}

pub async fn run_tree_upstream(
    upstream: &Arc<dyn UpstreamClient>,
    nodes: &[AnalyzeTreeNode],
) -> Result<Vec<AiVerdict>, AppError> {
    let mut out = Vec::new();
    for batch in split_tree_batches(nodes.to_vec()) {
        let body = build_tree_request_body(&batch);
        let resp = upstream.complete(body).await?;
        out.extend(parse_tree_response(&resp, &batch));
    }
    Ok(out)
}

pub fn model_name() -> &'static str {
    MODEL
}
