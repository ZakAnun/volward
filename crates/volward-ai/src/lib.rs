//! Shared DeepSeek analyze contract for BYOK (via FFI) and the Platform server.

pub mod config;
pub mod prompt;
pub mod request;
pub mod response;
pub mod types;

pub use config::{
    BATCH_SIZE, MAX_OUTPUT_TOKENS, MODEL, TEMPERATURE, THINKING_DISABLED, TREE_BATCH_SIZE,
    TREE_MAX_OUTPUT_TOKENS, UPSTREAM_ENDPOINT,
};
pub use prompt::{SYSTEM_PROMPT, TREE_SYSTEM_PROMPT};
pub use request::{build_request_body, build_tree_request_body, split_batches, split_tree_batches};
pub use response::{parse_response, parse_tree_response};
pub use types::{AiVerdict, AnalyzeCandidate, AnalyzeTreeNode};
