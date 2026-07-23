mod bench;

use platform_desktop::DesktopPlatform;
use volward_core::classify::Classifier;
use volward_core::scan::ScanOrchestrator;
use volward_core::PlatformStorage;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        None | Some("smoke") => run_smoke(),
        Some("scan-bench") => bench::run_scan_bench_cli(&args[2..]),
        Some(cmd) => {
            eprintln!("Unknown command: {cmd}");
            eprintln!("Usage:");
            eprintln!("  volward-cli [smoke]");
            eprintln!("  volward-cli scan-bench [--root PATH] [--entries N] [--iterations N]");
            std::process::exit(1);
        }
    }
}

fn run_smoke() {
    let platform = DesktopPlatform::new();
    let caps = platform.probe_capabilities();
    println!("Volward CLI smoke");
    println!("capability: {:?}", caps.level);
    println!("deep_scan_ready: {}", platform.is_deep_scan_ready());
    for hint in &caps.permission_hints {
        println!("hint: {hint}");
    }

    let cancel = std::sync::atomic::AtomicBool::new(false);
    let classifier = Classifier::new(platform.protected_prefixes().to_vec());
    let orchestrator = ScanOrchestrator::new(&platform, classifier);
    let snapshot = orchestrator
        .run_scan("cli-smoke".to_string(), vec![], false, &cancel, |_p| {})
        .expect("scan should complete");

    println!("snapshot_id: {}", snapshot.snapshot_id);
    println!("entries: {}", snapshot.entries.len());
    println!(
        "reclaimable_estimate_bytes: {}",
        snapshot.reclaimable_estimate_bytes
    );
    if let Some(first) = snapshot.entries.first() {
        println!(
            "largest: {} ({} bytes)",
            first.path_or_uri, first.size_bytes
        );
    }
}
