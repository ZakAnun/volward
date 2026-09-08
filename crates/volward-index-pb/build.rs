fn main() {
    println!("cargo:rerun-if-changed=../../proto/volward.proto");
    prost_build::compile_protos(&["../../proto/volward.proto"], &["../../proto"])
        .expect("failed to compile proto/volward.proto (is protoc installed?)");
}
