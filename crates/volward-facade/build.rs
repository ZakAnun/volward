//! Compiles `proto/volward.proto` (repo root) into Rust via prost.
//!
//! Requires `protoc` on PATH at build time (macOS: `brew install protobuf`).
//! The Flutter client needs `protoc` + `protoc_plugin` for its own codegen, so
//! this is a shared prerequisite, not a new one.
//!
//! Output lands in `$OUT_DIR/volward.rs` (named after the proto `package`) and
//! is pulled in by `src/proto.rs`.

fn main() {
    println!("cargo:rerun-if-changed=../../proto/volward.proto");
    println!("cargo:rerun-if-changed=../../proto/volward_ai.proto");
    prost_build::compile_protos(
        &["../../proto/volward.proto", "../../proto/volward_ai.proto"],
        &["../../proto"],
    )
    .expect("failed to compile volward protos (is protoc installed?)");
}
