//! Shared DeepSeek analyze contract for BYOK (via FFI) and the Platform server.

pub mod config;
pub mod prompt;
pub mod request;
pub mod response;
pub mod types;

pub use config::{
    BATCH_SIZE, MAX_OUTPUT_TOKENS, MODEL, TEMPERATURE, THINKING_DISABLED, UPSTREAM_ENDPOINT,
};
pub use prompt::SYSTEM_PROMPT;
pub use request::{build_request_body, split_batches};
pub use response::parse_response;
pub use types::{AiVerdict, AnalyzeCandidate};
