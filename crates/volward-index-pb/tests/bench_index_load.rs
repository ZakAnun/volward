//! Measured (release, 20k synthetic entries, 2026-09-08):
//! JSON 5.08 MB / read 13.35 ms — PB 2.60 MB / read 10.42 ms — size −48.8%, decode 1.28×
//!
//! Run: `cargo test -p volward-index-pb bench_index_json_vs_pb -- --nocapture`
//! Optional: `VOLWARD_BENCH_ENTRIES=50000 cargo test -p volward-index-pb bench_index_json_vs_pb -- --nocapture`
//! Real cache: `VOLWARD_CACHE_PATH=/path/to/cache.pb cargo test -p volward-index-pb bench_large_cache_from_env -- --ignored --nocapture`

use std::path::Path;
use std::time::{Duration, Instant};

use volward_core::index::SnapshotIndexBuilder;
use volward_core::model::{
    EntryCategory, RiskLevel, ScanStats, SourceType, StorageEntry,
};
use volward_core::SnapshotIndex;
use volward_index_pb::{decode_snapshot_index, encode_snapshot_index};

const DEFAULT_SYNTHETIC_ENTRIES: usize = 20_000;
const BENCH_ITERATIONS: u32 = 3;

struct FormatBench {
    write_elapsed: Duration,
    read_elapsed: Duration,
    size_bytes: usize,
}

fn build_synthetic_index(entry_count: usize) -> SnapshotIndex {
    let root = "/Users/bench/Home";
    let mut builder = SnapshotIndexBuilder::new(root);

    for i in 0..entry_count {
        let folder = i / 100;
        let path = format!("/Users/bench/Home/Library/Caches/app-{folder}/cache-{i}.bin");
        builder.insert_entry(StorageEntry {
            id: format!("entry-{i}"),
            display_name: format!("cache-{i}.bin"),
            path_or_uri: path,
            size_bytes: 1_024 + (i as u64 * 17),
            category: EntryCategory::Cache,
            risk_level: RiskLevel::Low,
            source_type: SourceType::File,
            deletable: true,
            reason: "synthetic benchmark entry".to_string(),
            modified_at_ms: Some(1_700_000_000_000 + i as i64),
        });
    }

    builder.finish(
        "bench-synthetic".to_string(),
        1_700_000_000_000,
        1,
        "Done".to_string(),
        ScanStats {
            paths_seen: entry_count as u64 + 1,
            dirs_seen: (entry_count / 100 + 1) as u64,
            files_seen: entry_count as u64,
            files_in_snapshot: entry_count as u64,
            paths_skipped: 0,
            truncated: false,
            incomplete_reason: None,
        },
    )
}

fn bench_json_roundtrip(index: &SnapshotIndex, iterations: u32) -> FormatBench {
    let _ = serde_json::to_vec(index).expect("json warm-up");

    let mut json_bytes = Vec::new();
    let write_start = Instant::now();
    for _ in 0..iterations {
        json_bytes = serde_json::to_vec(index).expect("json serialize");
    }
    let write_elapsed = write_start.elapsed();

    let read_start = Instant::now();
    for _ in 0..iterations {
        let _: SnapshotIndex = serde_json::from_slice(&json_bytes).expect("json deserialize");
    }
    let read_elapsed = read_start.elapsed();

    FormatBench {
        write_elapsed,
        read_elapsed,
        size_bytes: json_bytes.len(),
    }
}

fn bench_pb_roundtrip(index: &SnapshotIndex, iterations: u32) -> FormatBench {
    let _ = encode_snapshot_index(index).expect("pb warm-up");

    let mut pb_bytes = Vec::new();
    let write_start = Instant::now();
    for _ in 0..iterations {
        pb_bytes = encode_snapshot_index(index).expect("pb encode");
    }
    let write_elapsed = write_start.elapsed();

    let read_start = Instant::now();
    for _ in 0..iterations {
        let _ = decode_snapshot_index(&pb_bytes).expect("pb decode");
    }
    let read_elapsed = read_start.elapsed();

    FormatBench {
        write_elapsed,
        read_elapsed,
        size_bytes: pb_bytes.len(),
    }
}

fn per_iter_ms(elapsed: Duration, iterations: u32) -> f64 {
    elapsed.as_secs_f64() * 1000.0 / iterations as f64
}

fn format_bytes(bytes: usize) -> String {
    const KB: f64 = 1024.0;
    const MB: f64 = KB * 1024.0;
    const GB: f64 = MB * 1024.0;
    let b = bytes as f64;
    if b >= GB {
        format!("{:.2} GB", b / GB)
    } else if b >= MB {
        format!("{:.2} MB", b / MB)
    } else if b >= KB {
        format!("{:.2} KB", b / KB)
    } else {
        format!("{bytes} B")
    }
}

/// Printed by both synthetic and real-cache benches; keep in sync with spec Success Criteria.
fn print_bench_report(
    label: &str,
    entry_count: usize,
    iterations: u32,
    json: &FormatBench,
    pb: &FormatBench,
) -> BenchSummary {
    let json_write_ms = per_iter_ms(json.write_elapsed, iterations);
    let json_read_ms = per_iter_ms(json.read_elapsed, iterations);
    let pb_write_ms = per_iter_ms(pb.write_elapsed, iterations);
    let pb_read_ms = per_iter_ms(pb.read_elapsed, iterations);
    let size_reduction_pct =
        (1.0 - pb.size_bytes as f64 / json.size_bytes.max(1) as f64) * 100.0;
    let decode_speedup = json_read_ms / pb_read_ms.max(f64::EPSILON);
    let write_speedup = json_write_ms / pb_write_ms.max(f64::EPSILON);
    let gate_pass = decode_speedup >= 3.0 || size_reduction_pct >= 40.0;

    println!("\n=== SnapshotIndex JSON vs Protobuf ({label}) ===");
    println!("entries: {entry_count}, iterations: {iterations}");
    println!(
        "JSON:  write {json_write_ms:.2} ms/iter, read {json_read_ms:.2} ms/iter, size {} ({})",
        json.size_bytes,
        format_bytes(json.size_bytes)
    );
    println!(
        "PB:    write {pb_write_ms:.2} ms/iter, read {pb_read_ms:.2} ms/iter, size {} ({})",
        pb.size_bytes,
        format_bytes(pb.size_bytes)
    );
    println!("size reduction: {size_reduction_pct:.1}%");
    println!("decode speedup: {decode_speedup:.2}x");
    println!("write speedup: {write_speedup:.2}x");
    println!("gate (>=3x decode OR >=40% size): {gate_pass}");

    BenchSummary {
        entry_count,
        json_size_bytes: json.size_bytes,
        pb_size_bytes: pb.size_bytes,
        json_read_ms,
        pb_read_ms,
        json_write_ms,
        pb_write_ms,
        size_reduction_pct,
        decode_speedup,
        write_speedup,
        gate_pass,
    }
}

#[derive(Debug, Clone, Copy)]
#[allow(dead_code)]
struct BenchSummary {
    pub entry_count: usize,
    pub json_size_bytes: usize,
    pub pb_size_bytes: usize,
    pub json_read_ms: f64,
    pub pb_read_ms: f64,
    pub json_write_ms: f64,
    pub pb_write_ms: f64,
    pub size_reduction_pct: f64,
    pub decode_speedup: f64,
    pub write_speedup: f64,
    pub gate_pass: bool,
}

fn bench_env_usize(name: &str, default: usize) -> usize {
    std::env::var(name)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(default)
}

fn bench_env_u32(name: &str, default: u32) -> u32 {
    std::env::var(name)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(default)
}

fn bench_file_roundtrip_json(bytes: &[u8], iterations: u32) -> (Duration, SnapshotIndex) {
    let read_start = Instant::now();
    let index = serde_json::from_slice(bytes).expect("json deserialize from file");
    for _ in 1..iterations {
        let _: SnapshotIndex = serde_json::from_slice(bytes).expect("json deserialize from file");
    }
    (read_start.elapsed(), index)
}

fn bench_file_roundtrip_pb(bytes: &[u8], iterations: u32) -> (Duration, SnapshotIndex) {
    let read_start = Instant::now();
    let index = decode_snapshot_index(bytes).expect("pb decode from file");
    for _ in 1..iterations {
        let _ = decode_snapshot_index(bytes).expect("pb decode from file");
    }
    (read_start.elapsed(), index)
}

#[test]
fn bench_index_json_vs_pb_synthetic() {
    let entry_count = bench_env_usize("VOLWARD_BENCH_ENTRIES", DEFAULT_SYNTHETIC_ENTRIES);
    let iterations = bench_env_u32("VOLWARD_BENCH_ITERATIONS", BENCH_ITERATIONS);

    let index = build_synthetic_index(entry_count);
    assert_eq!(index.summary().entry_count, entry_count as u64);

    let json = bench_json_roundtrip(&index, iterations);
    let pb = bench_pb_roundtrip(&index, iterations);
    let summary = print_bench_report("synthetic", entry_count, iterations, &json, &pb);

    assert!(
        summary.gate_pass,
        "benchmark gate failed: decode speedup {:.2}x, size reduction {:.1}%",
        summary.decode_speedup,
        summary.size_reduction_pct
    );
}

#[test]
#[ignore = "requires VOLWARD_CACHE_PATH pointing to a real index cache (.json or .pb)"]
fn bench_large_cache_from_env() {
    let path = std::env::var("VOLWARD_CACHE_PATH")
        .expect("set VOLWARD_CACHE_PATH to a .json or .pb index cache file");
    let iterations = bench_env_u32("VOLWARD_BENCH_ITERATIONS", 1);
    let cache_path = Path::new(&path);
    assert!(
        cache_path.is_file(),
        "VOLWARD_CACHE_PATH is not a file: {path}"
    );

    let bytes = std::fs::read(cache_path).expect("read cache file");
    let ext = cache_path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("");

    let sibling = |suffix: &str| {
        cache_path.with_extension(suffix.strip_prefix('.').unwrap_or(suffix))
    };

    match ext {
        "pb" => {
            let (pb_read, index) = bench_file_roundtrip_pb(&bytes, iterations);
            let entry_count = index.summary().entry_count as usize;
            let pb_read_ms = per_iter_ms(pb_read, iterations);
            println!("\n=== Real cache decode (PB) ===");
            println!("path: {path}");
            println!("entries: {entry_count}");
            println!("file size: {} ({})", bytes.len(), format_bytes(bytes.len()));
            println!("PB read: {pb_read_ms:.2} ms/iter");

            if sibling("json").is_file() {
                let json_bytes = std::fs::read(sibling("json")).expect("read json sibling");
                let json_start = Instant::now();
                for _ in 0..iterations {
                    let _: SnapshotIndex =
                        serde_json::from_slice(&json_bytes).expect("json deserialize");
                }
                let json_read_ms = per_iter_ms(json_start.elapsed(), iterations);
                let size_reduction =
                    (1.0 - bytes.len() as f64 / json_bytes.len().max(1) as f64) * 100.0;
                let decode_speedup = json_read_ms / pb_read_ms.max(f64::EPSILON);
                println!("JSON sibling size: {} ({})", json_bytes.len(), format_bytes(json_bytes.len()));
                println!("JSON read: {json_read_ms:.2} ms/iter");
                println!("size reduction (on disk): {size_reduction:.1}%");
                println!("decode speedup: {decode_speedup:.2}x");
            }
        }
        "json" => {
            let (json_read, index) = bench_file_roundtrip_json(&bytes, iterations);
            let entry_count = index.summary().entry_count as usize;
            let json_read_ms = per_iter_ms(json_read, iterations);
            println!("\n=== Real cache decode (JSON) ===");
            println!("path: {path}");
            println!("entries: {entry_count}");
            println!("file size: {} ({})", bytes.len(), format_bytes(bytes.len()));
            println!("JSON read: {json_read_ms:.2} ms/iter");

            if sibling("pb").is_file() {
                let pb_bytes = std::fs::read(sibling("pb")).expect("read pb sibling");
                let pb_start = Instant::now();
                for _ in 0..iterations {
                    let _ = decode_snapshot_index(&pb_bytes).expect("pb decode");
                }
                let pb_read_ms = per_iter_ms(pb_start.elapsed(), iterations);
                let size_reduction =
                    (1.0 - pb_bytes.len() as f64 / bytes.len().max(1) as f64) * 100.0;
                let decode_speedup = json_read_ms / pb_read_ms.max(f64::EPSILON);
                println!("PB sibling size: {} ({})", pb_bytes.len(), format_bytes(pb_bytes.len()));
                println!("PB read: {pb_read_ms:.2} ms/iter");
                println!("size reduction (on disk): {size_reduction:.1}%");
                println!("decode speedup: {decode_speedup:.2}x");
            } else {
                // Re-encode to PB in memory for apples-to-apples size/latency comparison.
                let pb = bench_pb_roundtrip(&index, iterations);
                let json = FormatBench {
                    write_elapsed: Duration::ZERO,
                    read_elapsed: json_read,
                    size_bytes: bytes.len(),
                };
                let _ = print_bench_report("real-cache", entry_count, iterations, &json, &pb);
            }
        }
        other => panic!("unsupported cache extension: {other} (expected .json or .pb)"),
    }
}
