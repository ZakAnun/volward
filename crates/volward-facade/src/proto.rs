//! Generated protobuf types for the snapshot wire format.
//!
//! `build.rs` compiles `proto/volward.proto` into `$OUT_DIR/volward.rs`; this
//! module simply includes it. See `pb_convert.rs` for model <-> proto mapping.

#![allow(clippy::all)]
include!(concat!(env!("OUT_DIR"), "/volward.rs"));
