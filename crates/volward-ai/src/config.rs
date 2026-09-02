pub const MODEL: &str = "deepseek-v4-flash";
pub const UPSTREAM_ENDPOINT: &str = "https://api.deepseek.com/chat/completions";
pub const TEMPERATURE: f32 = 0.0;
pub const MAX_OUTPUT_TOKENS: u32 = 8192;
pub const BATCH_SIZE: usize = 40;
/// DeepSeek V4 defaults thinking on; classification must disable it.
pub const THINKING_DISABLED: bool = true;
