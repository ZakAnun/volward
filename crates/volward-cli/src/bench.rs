use std::time::{Duration, Instant};

use volward_core::model::{
    CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SourceType, StorageEntry,
    StorageSnapshot,
};

const DEFAULT_SYNTHETIC_ENTRIES: usize = 1_000;
const DEFAULT_ITERATIONS: u32 = 10;

pub struct BenchResult {
    pub label: &'static str,
    pub elapsed: Duration,
    pub size_bytes: usize,
}

pub fn parse_scan_bench_args(args: &[String]) -> ScanBenchOptions {
    let mut root: Option<String> = None;
    let mut entries = DEFAULT_SYNTHETIC_ENTRIES;
    let mut iterations = DEFAULT_ITERATIONS;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--root" => {
                i += 1;
                root = Some(args.get(i).expect("--root requires a path").clone());
            }
            "--entries" => {
                i += 1;
                entries = args
                    .get(i)
                    .expect("--entries requires a number")
                    .parse()
                    .expect("--entries must be a positive integer");
            }
            "--iterations" | "-n" => {
                i += 1;
                iterations = args
                    .get(i)
                    .expect("--iterations requires a number")
                    .parse()
                    .expect("--iterations must be a positive integer");
            }
            other => panic!("unknown scan-bench argument: {other}"),
        }
        i += 1;
    }

    ScanBenchOptions {
        root,
        entries,
        iterations,
    }
}

pub struct ScanBenchOptions {
    pub root: Option<String>,
    pub entries: usize,
    pub iterations: u32,
}

pub fn build_synthetic_snapshot(entry_count: usize) -> StorageSnapshot {
    let mut entries = Vec::with_capacity(entry_count);
    let mut tree_children = Vec::with_capacity(entry_count);

    for i in 0..entry_count {
        let folder = i / 100;
        let path = format!("/Users/example/Library/Caches/app-{folder}/cache-{i}.bin");
        let id = format!("entry-{i}");
        entries.push(StorageEntry {
            id: id.clone(),
            display_name: format!("cache-{i}.bin"),
            path_or_uri: path.clone(),
            size_bytes: 1_024 + (i as u64 * 17),
            category: EntryCategory::Cache,
            risk_level: RiskLevel::Low,
            source_type: SourceType::File,
            deletable: true,
            reason: "synthetic benchmark entry".to_string(),
            modified_at_ms: None,
        });
        tree_children.push(ScanTreeNode {
            name: format!("cache-{i}.bin"),
            path,
            is_dir: false,
            size_bytes: 1_024 + (i as u64 * 17),
            entry_id: Some(id),
            children: vec![],
        });
    }

    StorageSnapshot {
        snapshot_id: "bench-synthetic".to_string(),
        scanned_at_ms: 1_700_000_000_000,
        capability: CapabilityLevel::FullPath,
        volume_total_bytes: 512 * 1024 * 1024 * 1024,
        volume_used_bytes: 256 * 1024 * 1024 * 1024,
        reclaimable_estimate_bytes: entries.iter().map(|e| e.size_bytes).sum(),
        entries,
        tree: ScanTreeNode {
            name: "Library".to_string(),
            path: "/Users/example/Library".to_string(),
            is_dir: true,
            size_bytes: tree_children.iter().map(|n| n.size_bytes).sum(),
            entry_id: None,
            children: tree_children,
        },
        stats: ScanStats {
            paths_seen: entry_count as u64 + 1,
            dirs_seen: 1,
            files_seen: entry_count as u64,
            files_in_snapshot: entry_count as u64,
            paths_skipped: 0,
            truncated: false,
            incomplete_reason: None,
        },
        warnings: vec!["synthetic snapshot for serialize benchmark".to_string()],
    }
}

pub fn bench_json_to_string(snapshot: &StorageSnapshot, iterations: u32) -> BenchResult {
    let mut last_size = 0;
    let start = Instant::now();
    for _ in 0..iterations {
        let json = serde_json::to_string(snapshot).expect("json serialize");
        last_size = json.len();
    }
    BenchResult {
        label: "serde_json::to_string",
        elapsed: start.elapsed(),
        size_bytes: last_size,
    }
}

pub fn bench_json_to_writer(snapshot: &StorageSnapshot, iterations: u32) -> BenchResult {
    let mut last_size = 0;
    let start = Instant::now();
    for _ in 0..iterations {
        let mut buf = Vec::new();
        serde_json::to_writer(&mut buf, snapshot).expect("json to_writer");
        last_size = buf.len();
    }
    BenchResult {
        label: "serde_json::to_writer",
        elapsed: start.elapsed(),
        size_bytes: last_size,
    }
}

pub fn bench_postcard(snapshot: &StorageSnapshot, iterations: u32) -> BenchResult {
    let mut last_size = 0;
    let start = Instant::now();
    for _ in 0..iterations {
        let bytes = postcard::to_allocvec(snapshot).expect("postcard serialize");
        last_size = bytes.len();
    }
    BenchResult {
        label: "postcard::to_allocvec",
        elapsed: start.elapsed(),
        size_bytes: last_size,
    }
}

pub fn run_snapshot_bench(snapshot: &StorageSnapshot, iterations: u32) -> Vec<BenchResult> {
    // Warm up allocators and caches.
    let _ = serde_json::to_string(snapshot);
    let _ = postcard::to_allocvec(snapshot);

    vec![
        bench_json_to_string(snapshot, iterations),
        bench_json_to_writer(snapshot, iterations),
        bench_postcard(snapshot, iterations),
    ]
}

pub fn print_bench_report(snapshot: &StorageSnapshot, iterations: u32, results: &[BenchResult]) {
    let baseline_size = results.first().map(|r| r.size_bytes).unwrap_or(1).max(1);

    println!("Volward snapshot serialize benchmark (F0)");
    println!("snapshot_id: {}", snapshot.snapshot_id);
    println!("entries: {}", snapshot.entries.len());
    println!("tree children: {}", snapshot.tree.children.len());
    println!("iterations: {iterations}");
    println!();
    println!(
        "{:<28} {:>12} {:>14} {:>12}",
        "Format", "Total (ms)", "Size (bytes)", "Size ratio"
    );
    println!("{}", "-".repeat(70));

    for result in results {
        let total_ms = result.elapsed.as_secs_f64() * 1000.0;
        let per_iter_ms = total_ms / iterations as f64;
        let size_ratio = result.size_bytes as f64 / baseline_size as f64;
        println!(
            "{:<28} {:>8.2} avg {:>10} {:>11.2}x",
            result.label,
            per_iter_ms,
            format_size(result.size_bytes),
            size_ratio
        );
    }
    println!();
    println!(
        "Note: per-iteration averages; lower time and size are better for on-disk snapshot I/O."
    );
}

fn format_size(bytes: usize) -> String {
    bytes
        .to_string()
        .as_bytes()
        .rchunks(3)
        .rev()
        .map(std::str::from_utf8)
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
        .join(",")
}

pub fn run_scan_bench_cli(args: &[String]) {
    let options = parse_scan_bench_args(args);
    let snapshot = if let Some(root) = options.root {
        load_snapshot_from_scan(&root)
    } else {
        build_synthetic_snapshot(options.entries)
    };

    let results = run_snapshot_bench(&snapshot, options.iterations);
    print_bench_report(&snapshot, options.iterations, &results);
}

fn load_snapshot_from_scan(root: &str) -> StorageSnapshot {
    use platform_desktop::DesktopPlatform;
    use std::sync::atomic::AtomicBool;
    use volward_core::classify::Classifier;
    use volward_core::scan::ScanOrchestrator;

    eprintln!("scan-bench: scanning {root} ...");
    let platform = DesktopPlatform::new();
    let cancel = AtomicBool::new(false);
    let classifier = Classifier::new(platform.protected_prefixes().to_vec());
    let orchestrator = ScanOrchestrator::new(&platform, classifier);
    orchestrator
        .run_scan(
            "scan-bench".to_string(),
            vec![root.to_string()],
            false,
            &cancel,
            |_| {},
            |_snapshot| {},
        )
        .expect("scan should complete")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn synthetic_snapshot_bench_runs() {
        let snapshot = build_synthetic_snapshot(32);
        let results = run_snapshot_bench(&snapshot, 2);
        assert_eq!(results.len(), 3);
        for result in &results {
            assert!(result.size_bytes > 0);
            assert!(result.elapsed > Duration::ZERO);
        }
    }

    #[test]
    fn json_and_postcard_sizes_differ() {
        let snapshot = build_synthetic_snapshot(64);
        let json = serde_json::to_string(&snapshot).unwrap();
        let bin = postcard::to_allocvec(&snapshot).unwrap();
        assert_ne!(json.len(), bin.len());
    }
}
