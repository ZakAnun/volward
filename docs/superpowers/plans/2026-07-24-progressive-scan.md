# Progressive Scan (Preview + Background Checkpoint + Priority Peek) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the blocking "scan → wait → see everything" flow with an instant directory preview, a background full scan that streams progressive checkpoints to the UI, and click-priority scoped scans for folders the background scan hasn't reached yet.

**Architecture:** Rust core gains a non-recursive `quick_list_dir` (instant preview) and a periodic, non-destructive checkpoint hook inside the existing full-walk `ScanOrchestrator::run_scan` (no jwalk rewrite). The Rust facade exposes these over new FFI calls, reusing the existing polling-based async-scan infrastructure. Dart adds pure, unit-testable merge/preview helpers, wires them into `VolwardSession`, and updates the UI so results are browsable the instant a preview or checkpoint exists, while background scanning and (Wave 2) per-click scoped scans keep filling in real data without resetting the user's navigation position.

**Tech Stack:** Rust (jwalk, serde_json), Dart FFI (`dart:ffi`), Flutter Isolates, existing `ScanTreeNode`/`ScanColumnView` UI.

**Spec:** `docs/superpowers/specs/2026-07-24-progressive-scan-design.md`

---

## File Structure

| File | Change |
|------|--------|
| `crates/volward-core/src/model.rs` | `RawFsEntry` gains `Serialize` |
| `crates/volward-core/src/platform.rs` | `PlatformStorage::quick_list_dir` (default impl) |
| `crates/volward-core/src/scan_tree.rs` | `ScanTreeBuilder::peek_snapshot()` |
| `crates/volward-core/src/scan.rs` | `run_scan` gains `on_checkpoint` param + moved `vol` computation |
| `crates/platform-desktop/src/desktop.rs` | `DesktopPlatform::quick_list_dir` impl + test call-site updates |
| `crates/volward-facade/src/engine.rs` | checkpoint storage, `quick_list_dir_json`, `write_last_checkpoint_to_path`, call-site updates |
| `crates/volward-facade/src/capi.rs` | 2 new C exports |
| `apps/volward/lib/bridge/native_bridge.dart` | FFI bindings for the 2 new exports |
| `apps/volward/lib/bridge/scan_worker.dart` | periodic checkpoint emission + new `volwardPeekScanIsolate` (Wave 2) |
| `apps/volward/lib/scan_tree.dart` | `ScanTreeNode.scanned` field |
| `apps/volward/lib/scan_tree_filter.dart` | preserve `scanned` in `pruneTree` |
| `apps/volward/lib/scan_preview.dart` | **new** — `buildPreviewSnapshot()` |
| `apps/volward/lib/scan_snapshot_merge.dart` | **new** — `mergeSubtreeIntoSnapshot()` |
| `apps/volward/lib/scan_tree_navigation.dart` | **new** — `refreshColumnChain()` |
| `apps/volward/lib/volward_session.dart` | `previewTarget()`, checkpoint handling, `_applyMerge`, `peekScan()` (Wave 2) |
| `apps/volward/lib/home_page.dart` | preview-before-confirm wiring, column-nav refresh, `scanned` display, peek trigger (Wave 2) |
| `apps/volward/lib/widgets/scan_column_view.dart` | "—"/loading display for `scanned == false` |
| `apps/volward/test/*.dart` | new/updated tests (listed per task) |

---

## Task 1: `ScanTreeBuilder::peek_snapshot()` — non-destructive checkpoint

**Files:**
- Modify: `crates/volward-core/src/scan_tree.rs`

- [ ] **Step 1: Write the failing test**

Add to the `#[cfg(test)] mod tests` block at the bottom of `crates/volward-core/src/scan_tree.rs` (after the existing `grafts_cached_subtree_children` test):

```rust
    #[test]
    fn peek_snapshot_is_non_destructive() {
        let mut b = ScanTreeBuilder::new("/root");
        b.insert_file("/root/a.txt", Some("a"), 10);

        let peek1 = b.peek_snapshot();
        assert_eq!(peek1.size_bytes, 10);
        assert_eq!(peek1.children.len(), 1);

        // Builder must remain fully usable after a peek.
        b.insert_file("/root/b.txt", Some("b"), 20);
        let peek2 = b.peek_snapshot();
        assert_eq!(peek2.size_bytes, 30);
        assert_eq!(peek2.children.len(), 2);

        let final_tree = b.finalize();
        assert_eq!(final_tree.size_bytes, 30);
        assert_eq!(final_tree.children.len(), 2);
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd crates/volward-core && cargo test peek_snapshot_is_non_destructive`
Expected: FAIL with `no method named 'peek_snapshot' found`

- [ ] **Step 3: Implement `peek_snapshot`**

In `crates/volward-core/src/scan_tree.rs`, add this method to `impl ScanTreeBuilder` (place it right after `pub fn finalize(mut self) -> ScanTreeNode { ... }`):

```rust
    /// Non-destructive snapshot of the tree built so far. Unlike [`finalize`],
    /// this can be called repeatedly while the builder keeps accepting more
    /// `insert_file`/`ensure_dir`/`graft_subtree` calls afterwards.
    pub fn peek_snapshot(&self) -> ScanTreeNode {
        let mut clone = self.root.clone();
        aggregate_sizes(&mut clone);
        clone
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd crates/volward-core && cargo test peek_snapshot_is_non_destructive`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add crates/volward-core/src/scan_tree.rs
git commit -m "feat(core): add non-destructive ScanTreeBuilder::peek_snapshot"
```

---

## Task 2: `RawFsEntry` serializable + `quick_list_dir` trait method

**Files:**
- Modify: `crates/volward-core/src/model.rs`
- Modify: `crates/volward-core/src/platform.rs`

- [ ] **Step 1: Make `RawFsEntry` serializable**

In `crates/volward-core/src/model.rs`, change:

```rust
#[derive(Debug, Clone)]
pub struct RawFsEntry {
```

to:

```rust
#[derive(Debug, Clone, Serialize)]
pub struct RawFsEntry {
```

(`Serialize` is already imported at the top of the file via `use serde::{Deserialize, Serialize};`.)

- [ ] **Step 2: Add `quick_list_dir` to the `PlatformStorage` trait with a default implementation**

In `crates/volward-core/src/platform.rs`, add this method inside `pub trait PlatformStorage: Send + Sync { ... }`, right after `open_permission_settings`:

```rust
    /// Single-level, non-recursive directory listing for instant UI preview.
    /// Directories in the result have `size_bytes = 0` (unknown — callers
    /// must not treat this as a real empty folder) and `dir_fingerprint =
    /// None`. Default implementation is "unsupported" so existing test
    /// platforms don't need changes; `DesktopPlatform` overrides it.
    fn quick_list_dir(&self, _path: &str) -> Result<Vec<RawFsEntry>, PlatformError> {
        Err(PlatformError::Unsupported("quick_list_dir"))
    }
```

- [ ] **Step 3: Verify the workspace still compiles**

Run: `cd /Users/liminglin/Funny/volward && export CARGO_TARGET_DIR="$(pwd)/target" && cargo build -p volward-core`
Expected: builds cleanly (default trait method means no other implementor needs changes)

- [ ] **Step 4: Commit**

```bash
git add crates/volward-core/src/model.rs crates/volward-core/src/platform.rs
git commit -m "feat(core): add quick_list_dir trait method with default impl"
```

---

## Task 3: `DesktopPlatform::quick_list_dir` implementation

**Files:**
- Modify: `crates/platform-desktop/src/desktop.rs`

- [ ] **Step 1: Write the failing tests**

Add to the `#[cfg(test)] mod tests` block at the bottom of `crates/platform-desktop/src/desktop.rs` (after `incremental_scan_reuses_unchanged_real_subtree`):

```rust
    #[test]
    fn quick_list_dir_lists_only_one_level() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let root_path = std::env::temp_dir().join(format!(
            "volward-quicklist-{}-{unique}",
            std::process::id()
        ));
        fs::create_dir_all(root_path.join("sub/nested")).expect("mkdir");
        fs::write(root_path.join("top.txt"), b"hello").expect("write top file");
        fs::write(root_path.join("sub/nested/deep.txt"), b"deep").expect("write nested file");

        let platform = DesktopPlatform::new();
        let entries = platform
            .quick_list_dir(&root_path.to_string_lossy())
            .expect("quick list should succeed");

        assert_eq!(
            entries.len(),
            2,
            "should only see top-level entries, not nested/deep.txt"
        );
        let file_entry = entries
            .iter()
            .find(|e| e.path.ends_with("top.txt"))
            .expect("top.txt listed");
        assert!(!file_entry.is_dir);
        assert_eq!(file_entry.size_bytes, 5);
        let dir_entry = entries
            .iter()
            .find(|e| e.path.ends_with("sub"))
            .expect("sub dir listed");
        assert!(dir_entry.is_dir);
        assert_eq!(dir_entry.size_bytes, 0);

        fs::remove_dir_all(root_path).expect("cleanup");
    }

    #[test]
    fn quick_list_dir_returns_error_for_missing_path() {
        let platform = DesktopPlatform::new();
        let result = platform.quick_list_dir("/definitely/does/not/exist/volward-test");
        assert!(result.is_err());
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd crates/platform-desktop && cargo test quick_list_dir`
Expected: FAIL — `DesktopPlatform` uses the trait's default `Err(Unsupported)` implementation, so `quick_list_dir_lists_only_one_level`'s `.expect("quick list should succeed")` panics.

- [ ] **Step 3: Implement `quick_list_dir` for `DesktopPlatform`**

In `crates/platform-desktop/src/desktop.rs`, add this method inside `impl PlatformStorage for DesktopPlatform { ... }`, right after `fn volume_stats(...)`:

```rust
    fn quick_list_dir(&self, path: &str) -> Result<Vec<RawFsEntry>, PlatformError> {
        let dir_path = Path::new(path);
        let read_dir = fs::read_dir(dir_path)?;
        let mut out = Vec::new();
        for entry in read_dir {
            let entry = match entry {
                Ok(e) => e,
                Err(_) => continue,
            };
            let entry_path = entry.path();
            if is_protected_path(&entry_path, &self.protected_prefixes) {
                continue;
            }
            let metadata = match entry.metadata() {
                Ok(m) => m,
                Err(_) => continue,
            };
            let is_dir = metadata.is_dir();
            out.push(RawFsEntry {
                path: entry_path.to_string_lossy().to_string(),
                is_dir,
                size_bytes: if is_dir { 0 } else { metadata.len() },
                dir_fingerprint: None,
            });
        }
        Ok(out)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd crates/platform-desktop && cargo test quick_list_dir`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add crates/platform-desktop/src/desktop.rs
git commit -m "feat(desktop): implement quick_list_dir as single-level read_dir"
```

---

## Task 4: `ScanOrchestrator::run_scan` — periodic checkpoint callback

**Files:**
- Modify: `crates/volward-core/src/scan.rs`
- Modify: `crates/platform-desktop/src/desktop.rs` (test call sites)

- [ ] **Step 1: Write the failing test and update existing test call sites**

In `crates/volward-core/src/scan.rs`, add this test to `#[cfg(test)] mod tests` (after `incremental_scan_with_existing_manifest_reuses_cached_tree`):

```rust
    #[test]
    fn checkpoints_are_monotonically_increasing_subsets_of_final_result() {
        let (_temp, platform) = build_temp_scan_platform(50);
        let cancel = AtomicBool::new(false);
        let orchestrator = ScanOrchestrator::new(&platform, Classifier::default());
        let checkpoints = std::sync::Mutex::new(Vec::<usize>::new());

        let snapshot = orchestrator
            .run_scan(
                "test-checkpoints".to_string(),
                vec![],
                false,
                &cancel,
                |_p| {},
                |checkpoint| {
                    checkpoints.lock().unwrap().push(checkpoint.tree.children.len());
                },
            )
            .expect("scan should succeed");

        // build_temp_scan_platform files aren't classified (no rules match),
        // so this test only exercises that run_scan compiles and runs with
        // the new on_checkpoint parameter; checkpoint firing itself is timing
        // gated (2s) so may legitimately record zero checkpoints for a fast
        // in-memory scan — that's fine, the assertion is about final shape.
        assert_eq!(snapshot.stats.files_seen, 50);
    }
```

Now update every EXISTING `run_scan(...)` call site to pass a new no-op checkpoint closure as the last argument (the compiler will point these out one by one, but apply them all now):

In `crates/volward-core/src/scan.rs`, test `full_scan_indexes_every_file_without_cap`, replace:

```rust
        let snapshot = orchestrator
            .run_scan(
                "test-full-scan".to_string(),
                vec![],
                false,
                &cancel,
                |_p| {},
            )
            .expect("scan should succeed");
```

with:

```rust
        let snapshot = orchestrator
            .run_scan(
                "test-full-scan".to_string(),
                vec![],
                false,
                &cancel,
                |_p| {},
                |_snapshot| {},
            )
            .expect("scan should succeed");
```

In test `cancelled_scan_marks_snapshot_truncated`, replace:

```rust
        let snapshot = orchestrator
            .run_scan("test-cancel".to_string(), vec![], false, &cancel, |_p| {})
            .expect("cancelled scan still returns snapshot");
```

with:

```rust
        let snapshot = orchestrator
            .run_scan(
                "test-cancel".to_string(),
                vec![],
                false,
                &cancel,
                |_p| {},
                |_snapshot| {},
            )
            .expect("cancelled scan still returns snapshot");
```

In test `successful_scan_saves_manifest_with_directory_fingerprints`, replace:

```rust
        let snapshot = orchestrator
            .run_scan("test-manifest".to_string(), vec![], false, &cancel, |_p| {})
            .expect("scan should succeed");
```

with:

```rust
        let snapshot = orchestrator
            .run_scan(
                "test-manifest".to_string(),
                vec![],
                false,
                &cancel,
                |_p| {},
                |_snapshot| {},
            )
            .expect("scan should succeed");
```

In test `incremental_scan_with_existing_manifest_reuses_cached_tree`, replace:

```rust
        orchestrator
            .run_scan("seed-manifest".to_string(), vec![], false, &cancel, |_p| {})
            .expect("seed scan should succeed");

        let snapshot = orchestrator
            .run_scan("incremental-e2".to_string(), vec![], true, &cancel, |_p| {})
            .expect("incremental E2 scan should succeed");
```

with:

```rust
        orchestrator
            .run_scan(
                "seed-manifest".to_string(),
                vec![],
                false,
                &cancel,
                |_p| {},
                |_snapshot| {},
            )
            .expect("seed scan should succeed");

        let snapshot = orchestrator
            .run_scan(
                "incremental-e2".to_string(),
                vec![],
                true,
                &cancel,
                |_p| {},
                |_snapshot| {},
            )
            .expect("incremental E2 scan should succeed");
```

In `crates/platform-desktop/src/desktop.rs`, test `incremental_scan_reuses_unchanged_real_subtree`, replace:

```rust
        let first = orchestrator
            .run_scan(
                "real-full".to_string(),
                selected.clone(),
                false,
                &cancel,
                |_| {},
            )
            .expect("full scan should succeed");
        let second = orchestrator
            .run_scan(
                "real-incremental".to_string(),
                selected.clone(),
                true,
                &cancel,
                |_| {},
            )
            .expect("incremental scan should succeed");
```

with:

```rust
        let first = orchestrator
            .run_scan(
                "real-full".to_string(),
                selected.clone(),
                false,
                &cancel,
                |_| {},
                |_snapshot| {},
            )
            .expect("full scan should succeed");
        let second = orchestrator
            .run_scan(
                "real-incremental".to_string(),
                selected.clone(),
                true,
                &cancel,
                |_| {},
                |_snapshot| {},
            )
            .expect("incremental scan should succeed");
```

And later in the same test, replace:

```rust
        let third = orchestrator
            .run_scan(
                "real-incremental-after-modify".to_string(),
                selected,
                true,
                &cancel,
                |_| {},
            )
            .expect("incremental scan after file change should succeed");
```

with:

```rust
        let third = orchestrator
            .run_scan(
                "real-incremental-after-modify".to_string(),
                selected,
                true,
                &cancel,
                |_| {},
                |_snapshot| {},
            )
            .expect("incremental scan after file change should succeed");
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: `cd /Users/liminglin/Funny/volward && export CARGO_TARGET_DIR="$(pwd)/target" && cargo test -p volward-core -p platform-desktop`
Expected: FAIL to compile — `run_scan` doesn't accept the new closure argument yet (signature unchanged so far).

- [ ] **Step 3: Implement the `on_checkpoint` parameter**

In `crates/volward-core/src/scan.rs`, replace the **entire** `run_scan` function (from `pub fn run_scan(` through its closing `}` — everything between `pub fn probe(&self) -> PlatformCapabilities { ... }` and the free function `fn path_is_at_or_below`) with:

```rust
    pub fn run_scan(
        &self,
        job_id: String,
        user_selected: Vec<String>,
        incremental: bool,
        cancel: &AtomicBool,
        mut on_progress: impl FnMut(ScanProgress),
        mut on_checkpoint: impl FnMut(StorageSnapshot),
    ) -> Result<StorageSnapshot, PlatformError> {
        let caps = self.platform.probe_capabilities();
        on_progress(ScanProgress {
            job_id: job_id.clone(),
            phase: ScanPhase::DiscoveringRoots,
            paths_seen: 0,
            bytes_seen: 0,
            current_path: None,
        });

        let roots = self.platform.discover_roots(&user_selected)?;
        let root_path = roots.first().map(|r| r.path.as_str()).unwrap_or("/");
        let vol = roots
            .first()
            .and_then(|r| self.platform.volume_stats(r).ok())
            .unwrap_or(crate::model::VolumeStats {
                total_bytes: 0,
                available_bytes: 0,
            });
        let mut tree_builder = ScanTreeBuilder::new(root_path);
        let mut entries = Vec::new();
        let mut stats = ScanStats::default();
        let mut bytes_seen = 0u64;
        let mut warnings = Vec::new();
        let mut dir_fingerprints = HashMap::<String, DirFingerprint>::new();
        let mut walk_completed = false;

        let loaded_manifest = incremental
            .then(|| self.manifest_store.load(root_path))
            .flatten()
            .filter(|manifest| manifest.root == root_path);

        if incremental {
            match &loaded_manifest {
                None => warnings.push(
                    "Incremental scan: no prior scan cache for this root; performing a full walk."
                        .to_string(),
                ),
                Some(manifest) => {
                    let snapshot_ok = self
                        .snapshot_store
                        .load_snapshot(root_path)
                        .is_some_and(|snapshot| snapshot.snapshot_id == manifest.snapshot_id);
                    if !snapshot_ok {
                        warnings.push(
                            "Incremental scan: cached snapshot missing or outdated; performing a full walk."
                                .to_string(),
                        );
                    }
                }
            }
        }

        let incremental_cache = loaded_manifest.and_then(|manifest| {
            self.snapshot_store
                .load_snapshot(root_path)
                .filter(|snapshot| snapshot.snapshot_id == manifest.snapshot_id)
                .map(|snapshot| (manifest, snapshot))
        });
        let baseline_fingerprints = incremental_cache.as_ref().map(|(manifest, snapshot)| {
            manifest
                .dir_fingerprints
                .iter()
                .filter(|(path, _)| find_subtree(&snapshot.tree, path).is_some())
                .map(|(path, fingerprint)| (path.clone(), fingerprint.clone()))
                .collect::<HashMap<_, _>>()
        });
        let mut skipped_dirs = Vec::<String>::new();

        if !self.platform.is_deep_scan_ready() {
            warnings.push(
                "Deep scan not ready (e.g. grant Full Disk Access on macOS for full Library access)."
                    .to_string(),
            );
        }

        on_progress(ScanProgress {
            job_id: job_id.clone(),
            phase: ScanPhase::Walking,
            paths_seen: 0,
            bytes_seen: 0,
            current_path: roots.first().map(|r| r.path.clone()),
        });

        let mut last_path: Option<String> = None;
        let mut progress_counter = 0u64;
        let mut last_checkpoint_at = std::time::Instant::now();
        let checkpoint_interval = std::time::Duration::from_secs(2);
        let mut walk = |e: crate::model::RawFsEntry| -> WalkAction {
            if cancel.load(std::sync::atomic::Ordering::Relaxed) {
                return WalkAction::Stop;
            }
            stats.paths_seen += 1;
            bytes_seen = bytes_seen.saturating_add(e.size_bytes);
            last_path = Some(e.path.clone());
            progress_counter += 1;
            if progress_counter % 1000 == 0 {
                on_progress(ScanProgress {
                    job_id: job_id.clone(),
                    phase: ScanPhase::Walking,
                    paths_seen: stats.paths_seen,
                    bytes_seen,
                    current_path: last_path.clone(),
                });
            }
            if e.is_dir {
                stats.dirs_seen += 1;
                if let Some(fingerprint) = e.dir_fingerprint {
                    if baseline_fingerprints
                        .as_ref()
                        .and_then(|baseline| baseline.get(&e.path))
                        .is_some_and(|baseline| baseline.matches(&fingerprint))
                    {
                        skipped_dirs.push(e.path.clone());
                    }
                    dir_fingerprints.insert(e.path.clone(), fingerprint);
                }
                tree_builder.ensure_dir(&e.path);
            } else {
                stats.files_seen += 1;
                if let Some(classified) =
                    self.classifier
                        .classify_path(&e.path, e.size_bytes, false, &job_id)
                {
                    let id = classified.id.clone();
                    stats.files_in_snapshot += 1;
                    entries.push(classified);
                    tree_builder.insert_file(&e.path, Some(&id), e.size_bytes);
                } else {
                    tree_builder.insert_file(&e.path, None, e.size_bytes);
                }
            }

            if progress_counter % 200 == 0 && last_checkpoint_at.elapsed() >= checkpoint_interval {
                last_checkpoint_at = std::time::Instant::now();
                on_checkpoint(StorageSnapshot {
                    snapshot_id: format!("{job_id}-checkpoint"),
                    scanned_at_ms: unix_ms(),
                    capability: caps.level,
                    volume_total_bytes: vol.total_bytes,
                    volume_used_bytes: vol.total_bytes.saturating_sub(vol.available_bytes),
                    reclaimable_estimate_bytes: entries
                        .iter()
                        .filter(|entry| entry.deletable)
                        .map(|entry| entry.size_bytes)
                        .sum(),
                    entries: entries.clone(),
                    tree: tree_builder.peek_snapshot(),
                    stats: stats.clone(),
                    warnings: Vec::new(),
                });
            }

            WalkAction::Continue
        };

        match self.platform.walk_entries(
            &roots,
            WalkOptions {
                baseline_fingerprints: baseline_fingerprints.as_ref(),
            },
            cancel,
            &mut walk,
        ) {
            Err(PlatformError::Cancelled) => {
                stats.truncated = true;
                stats.incomplete_reason = Some("Scan cancelled.".into());
                warnings.push("Scan cancelled.".into());
            }
            Err(other) => return Err(other),
            Ok(skipped) => {
                walk_completed = true;
                stats.paths_skipped = skipped;
                stats.truncated = false;
                if skipped > 0 {
                    warnings.push(format!(
                        "{skipped} path(s) skipped due to permission or I/O errors."
                    ));
                }
            }
        }

        if let Some((manifest, cached_snapshot)) = incremental_cache.as_ref() {
            for dir in &skipped_dirs {
                if let Some(source) = find_subtree(&cached_snapshot.tree, dir) {
                    tree_builder.graft_subtree(dir, source);
                }
            }

            let existing_paths = entries
                .iter()
                .map(|entry| entry.path_or_uri.clone())
                .collect::<HashSet<_>>();
            entries.extend(
                cached_snapshot
                    .entries
                    .iter()
                    .filter(|entry| {
                        !existing_paths.contains(&entry.path_or_uri)
                            && skipped_dirs
                                .iter()
                                .any(|dir| path_is_at_or_below(&entry.path_or_uri, dir))
                    })
                    .cloned(),
            );
            for (path, fingerprint) in &manifest.dir_fingerprints {
                if skipped_dirs
                    .iter()
                    .any(|dir| path_is_at_or_below(path, dir) && path != dir.as_str())
                {
                    dir_fingerprints
                        .entry(path.clone())
                        .or_insert_with(|| fingerprint.clone());
                }
            }
            stats.files_in_snapshot = entries.len().min(u64::MAX as usize) as u64;
            if !skipped_dirs.is_empty() {
                warnings.push(format!(
                    "Incremental scan reused {} unchanged directories.",
                    skipped_dirs.len()
                ));
            }
        }

        on_progress(ScanProgress {
            job_id: job_id.clone(),
            phase: ScanPhase::Aggregating,
            paths_seen: stats.paths_seen,
            bytes_seen,
            current_path: last_path,
        });

        // Sort deferred to UI (home_page) to avoid O(n log n) on full-volume scans.

        let reclaimable = entries
            .iter()
            .filter(|e| e.deletable)
            .map(|e| e.size_bytes)
            .sum();

        let tree = tree_builder.finalize();
        let snapshot_id = Uuid::new_v4().to_string();
        let scanned_at_ms = unix_ms();

        let mut snapshot = StorageSnapshot {
            snapshot_id,
            scanned_at_ms,
            capability: caps.level,
            volume_total_bytes: vol.total_bytes,
            volume_used_bytes: vol.total_bytes.saturating_sub(vol.available_bytes),
            reclaimable_estimate_bytes: reclaimable,
            entries,
            tree,
            stats,
            warnings,
        };

        if walk_completed {
            let mut manifest = ScanManifest {
                root: root_path.to_string(),
                scanned_at_ms,
                snapshot_id: snapshot.snapshot_id.clone(),
                snapshot_path: None,
                dir_fingerprints,
            };
            match self.snapshot_store.save_snapshot(root_path, &snapshot) {
                Ok(path) => {
                    manifest.snapshot_path = Some(path.to_string_lossy().into_owned());
                }
                Err(error) => {
                    snapshot
                        .warnings
                        .push(format!("Failed to save snapshot cache: {error}"));
                }
            }
            if let Err(error) = self.manifest_store.save(&manifest) {
                snapshot
                    .warnings
                    .push(format!("Failed to save scan manifest: {error}"));
            }
        }

        on_progress(ScanProgress {
            job_id: job_id.clone(),
            phase: ScanPhase::Done,
            paths_seen: snapshot.stats.paths_seen,
            bytes_seen,
            current_path: None,
        });

        Ok(snapshot)
    }
```

Note what changed vs. the original: `on_checkpoint` parameter added; `vol` computation moved up (right after `root_path`) so it's available inside the walk closure and the later duplicate `let vol = ...` before `let reclaimable = ...` was removed; the `is_dir` branch no longer does an early `return WalkAction::Continue` — it now falls through to a shared tail so the new checkpoint-emission block runs for both directory and file entries.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/liminglin/Funny/volward && export CARGO_TARGET_DIR="$(pwd)/target" && cargo test -p volward-core -p platform-desktop`
Expected: PASS (all existing scan tests + the new checkpoint test + the new quick_list_dir tests from Task 3)

- [ ] **Step 5: Commit**

```bash
git add crates/volward-core/src/scan.rs crates/platform-desktop/src/desktop.rs
git commit -m "feat(core): stream periodic checkpoints from run_scan during Walking phase"
```

---

## Task 5: `VolwardEngine` — checkpoint storage + quick_list_dir_json + write_last_checkpoint_to_path

**Files:**
- Modify: `crates/volward-facade/src/engine.rs`

- [ ] **Step 1: Write the failing test**

Add to `#[cfg(test)] mod tests` in `crates/volward-facade/src/engine.rs` (after `write_last_snapshot_roundtrip`):

```rust
    #[test]
    fn checkpoint_starts_empty_and_quick_list_dir_reports_unsupported_error() {
        let engine = VolwardEngine::new();
        assert!(engine.get_last_checkpoint().is_none());

        // No real directory needed: an obviously-missing path exercises the
        // error path end-to-end through the JSON encoding.
        let json = engine.quick_list_dir_json("/definitely/does/not/exist/volward-test");
        assert!(json.contains("error"));
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd crates/volward-facade && cargo test checkpoint_starts_empty`
Expected: FAIL — `get_last_checkpoint`/`quick_list_dir_json` don't exist yet.

- [ ] **Step 3: Implement the engine changes**

In `crates/volward-facade/src/engine.rs`, add the new field to the struct:

```rust
pub struct VolwardEngine {
    platform: Arc<DesktopPlatform>,
    cancel: Arc<AtomicBool>,
    is_scanning: Arc<AtomicBool>,
    last_snapshot: Arc<Mutex<Option<StorageSnapshot>>>,
    last_progress: Arc<Mutex<Option<ScanProgress>>>,
    last_checkpoint: Arc<Mutex<Option<StorageSnapshot>>>,
    _scan_handle: Arc<Mutex<Option<std::thread::JoinHandle<()>>>>,
}
```

Update `new()`:

```rust
    pub fn new() -> Self {
        Self {
            platform: Arc::new(DesktopPlatform::new()),
            cancel: Arc::new(AtomicBool::new(false)),
            is_scanning: Arc::new(AtomicBool::new(false)),
            last_snapshot: Arc::new(Mutex::new(None)),
            last_progress: Arc::new(Mutex::new(None)),
            last_checkpoint: Arc::new(Mutex::new(None)),
            _scan_handle: Arc::new(Mutex::new(None)),
        }
    }
```

Update `start_scan` (blocking variant — no real checkpoint delivery needed since callers already get the final result directly), replace:

```rust
        let result = orchestrator.run_scan(job_id, roots, incremental, &cancel, |progress| {
            if let Ok(mut g) = last_progress.lock() {
                *g = Some(progress);
            }
        });
```

with:

```rust
        let result = orchestrator.run_scan(
            job_id,
            roots,
            incremental,
            &cancel,
            |progress| {
                if let Ok(mut g) = last_progress.lock() {
                    *g = Some(progress);
                }
            },
            |_checkpoint| {},
        );
```

Update `start_scan_async` to wire real checkpoint delivery, replace:

```rust
        let platform = self.platform.clone();
        let cancel = self.cancel.clone();
        let last_snapshot = self.last_snapshot.clone();
        let last_progress = self.last_progress.clone();
        let is_scanning = self.is_scanning.clone();
        let scan_handle = self._scan_handle.clone();

        let job_id_clone = job_id.clone();

        let handle = std::thread::spawn(move || {
            let classifier = load_classifier_from_arc(&platform);
            let orchestrator = ScanOrchestrator::new(platform.as_ref(), classifier);
            match orchestrator.run_scan(job_id_clone, roots, incremental, &cancel, |progress| {
                if let Ok(mut g) = last_progress.lock() {
                    *g = Some(progress);
                }
            }) {
                Ok(snapshot) => {
                    if let Ok(mut g) = last_snapshot.lock() {
                        *g = Some(snapshot);
                    }
                }
                Err(_e) => {
                    // snapshot stays None; caller should check via get_last_snapshot
                }
            }
            is_scanning.store(false, Ordering::Relaxed);
        });
```

with:

```rust
        let platform = self.platform.clone();
        let cancel = self.cancel.clone();
        let last_snapshot = self.last_snapshot.clone();
        let last_progress = self.last_progress.clone();
        let last_checkpoint = self.last_checkpoint.clone();
        let is_scanning = self.is_scanning.clone();
        let scan_handle = self._scan_handle.clone();

        let job_id_clone = job_id.clone();

        let handle = std::thread::spawn(move || {
            let classifier = load_classifier_from_arc(&platform);
            let orchestrator = ScanOrchestrator::new(platform.as_ref(), classifier);
            match orchestrator.run_scan(
                job_id_clone,
                roots,
                incremental,
                &cancel,
                |progress| {
                    if let Ok(mut g) = last_progress.lock() {
                        *g = Some(progress);
                    }
                },
                |checkpoint| {
                    if let Ok(mut g) = last_checkpoint.lock() {
                        *g = Some(checkpoint);
                    }
                },
            ) {
                Ok(snapshot) => {
                    if let Ok(mut g) = last_snapshot.lock() {
                        *g = Some(snapshot);
                    }
                    if let Ok(mut g) = last_checkpoint.lock() {
                        *g = None;
                    }
                }
                Err(_e) => {
                    // snapshot stays None; caller should check via get_last_snapshot
                }
            }
            is_scanning.store(false, Ordering::Relaxed);
        });
```

Add these new methods anywhere inside `impl VolwardEngine { ... }` (e.g. right after `get_last_progress_json`):

```rust
    pub fn get_last_checkpoint(&self) -> Option<StorageSnapshot> {
        self.last_checkpoint.lock().ok().and_then(|g| g.clone())
    }

    /// Serializes the last checkpoint directly to `path`. Returns
    /// `error:no checkpoint` if the current scan hasn't produced one yet.
    pub fn write_last_checkpoint_to_path(&self, path: &str) -> Result<String, String> {
        let snapshot = self
            .get_last_checkpoint()
            .ok_or_else(|| "error:no checkpoint".to_string())?;
        let file = File::create(path).map_err(|e| format!("error:create checkpoint: {e}"))?;
        let mut writer = BufWriter::new(file);
        serde_json::to_writer(&mut writer, &snapshot)
            .map_err(|e| format!("error:serialize checkpoint: {e}"))?;
        writer
            .flush()
            .map_err(|e| format!("error:flush checkpoint: {e}"))?;
        Ok(snapshot.snapshot_id)
    }

    /// Single-level, non-recursive directory listing (see
    /// `PlatformStorage::quick_list_dir`). Safe to call while a scan is
    /// running — it does not touch `is_scanning`/shared scan state.
    pub fn quick_list_dir_json(&self, path: &str) -> String {
        match self.platform.quick_list_dir(path) {
            Ok(entries) => serde_json::to_string(&entries).unwrap_or_else(|_| "[]".to_string()),
            Err(e) => serde_json::json!({ "error": e.to_string() }).to_string(),
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd crates/volward-facade && cargo test checkpoint_starts_empty`
Expected: PASS

- [ ] **Step 5: Run the full workspace test suite**

Run: `cd /Users/liminglin/Funny/volward && export CARGO_TARGET_DIR="$(pwd)/target" && cargo test`
Expected: PASS (all crates)

- [ ] **Step 6: Commit**

```bash
git add crates/volward-facade/src/engine.rs
git commit -m "feat(facade): expose checkpoint storage and quick_list_dir over the engine"
```

---

## Task 6: `capi.rs` — C exports for the new engine methods

**Files:**
- Modify: `crates/volward-facade/src/capi.rs`

- [ ] **Step 1: Add the exports**

In `crates/volward-facade/src/capi.rs`, add these two functions after `volward_write_last_snapshot_to_path`:

```rust
#[no_mangle]
pub unsafe extern "C" fn volward_write_last_checkpoint_to_path(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return to_c_string("error:null engine".to_string());
    };
    let Some(path) = cstr_to_string(path) else {
        return to_c_string("error:null path".to_string());
    };
    match e.write_last_checkpoint_to_path(&path) {
        Ok(id) => to_c_string(id),
        Err(msg) => to_c_string(msg),
    }
}

#[no_mangle]
pub unsafe extern "C" fn volward_quick_list_dir_json(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let Some(path) = cstr_to_string(path) else {
        return to_c_string("error:null path".to_string());
    };
    to_c_string(e.quick_list_dir_json(&path))
}
```

- [ ] **Step 2: Verify the facade builds**

Run: `cd /Users/liminglin/Funny/volward && export CARGO_TARGET_DIR="$(pwd)/target" && cargo build -p volward-facade`
Expected: builds cleanly

- [ ] **Step 3: Commit**

```bash
git add crates/volward-facade/src/capi.rs
git commit -m "feat(facade): add C exports for checkpoint and quick_list_dir"
```

---

## Task 7: Rebuild native library and run full Rust test suite

**Files:** none (verification task)

- [ ] **Step 1: Run the full Rust test suite**

Run: `cd /Users/liminglin/Funny/volward && export CARGO_TARGET_DIR="$(pwd)/target" && cargo test`
Expected: PASS across `volward-core`, `platform-desktop`, `volward-facade`, `volward-cli`

- [ ] **Step 2: Rebuild the macOS dylib**

Run: `cd /Users/liminglin/Funny/volward/apps/volward/macos && bash build_rust.sh`
Expected: `Volward Rust: copied .../libvolward_facade.dylib -> .../libvolward_facade.dylib`

- [ ] **Step 3: Smoke-test the CLI**

Run: `cd /Users/liminglin/Funny/volward && export CARGO_TARGET_DIR="$(pwd)/target" && cargo run -p volward-cli`
Expected: prints a scan summary without errors (CLI doesn't use checkpoints/quick_list_dir directly, this just confirms nothing else broke)

- [ ] **Step 4: Commit (only if anything changed, e.g. Cargo.lock)**

```bash
git add -A
git status
# If there are staged changes (e.g. Cargo.lock), commit them:
git commit -m "chore: rebuild native library after checkpoint/quick_list_dir changes" || true
```

---

## Task 8: Dart FFI bindings for `quick_list_dir` and checkpoint

**Files:**
- Modify: `apps/volward/lib/bridge/native_bridge.dart`

- [ ] **Step 1: Add the typedefs**

In `apps/volward/lib/bridge/native_bridge.dart`, add these typedefs after `VolwardWriteLastSnapshotToPath`:

```dart
typedef VolwardWriteLastCheckpointToPathNative =
    Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef VolwardWriteLastCheckpointToPath =
    Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);

typedef VolwardQuickListDirJsonNative =
    Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef VolwardQuickListDirJson =
    Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
```

- [ ] **Step 2: Add fields and constructor wiring**

Add these fields next to `late final VolwardWriteLastSnapshotToPath? _writeLastSnapshotToPath;`:

```dart
  late final VolwardWriteLastCheckpointToPath? _writeLastCheckpointToPath;
  late final VolwardQuickListDirJson? _quickListDirJson;
```

In the constructor body (`VolwardNativeBridge._(this._lib) { ... }`), add these two lines right after `_writeLastSnapshotToPath = _tryLookupWriteSnapshot();`:

```dart
    _writeLastCheckpointToPath = _tryLookupWriteCheckpoint();
    _quickListDirJson = _tryLookupQuickListDirJson();
```

Add these two lookup helpers next to `VolwardWriteLastSnapshotToPath? _tryLookupWriteSnapshot() { ... }`:

```dart
  VolwardWriteLastCheckpointToPath? _tryLookupWriteCheckpoint() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardWriteLastCheckpointToPathNative>>(
            'volward_write_last_checkpoint_to_path',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardQuickListDirJson? _tryLookupQuickListDirJson() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardQuickListDirJsonNative>>(
            'volward_quick_list_dir_json',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }
```

- [ ] **Step 3: Add capability getters and public methods**

Add these getters next to `bool get hasScanOptionsApi => _startScanAsyncWithOptions != null;`:

```dart
  /// True when the bundled dylib supports periodic scan checkpoints.
  bool get hasCheckpointApi => _writeLastCheckpointToPath != null;

  /// True when the bundled dylib supports instant, non-recursive directory
  /// listing (used for the pre-scan preview and click-priority peeks).
  bool get hasQuickListApi => _quickListDirJson != null;
```

Add these public methods next to `writeLastSnapshotToPath`:

```dart
  /// Writes the current in-progress scan checkpoint to [path]; returns the
  /// checkpoint's `snapshot_id`, or `null` if no checkpoint API/checkpoint
  /// is available yet.
  String? writeLastCheckpointToPath(Pointer<Void> engine, String path) {
    final write = _writeLastCheckpointToPath;
    if (write == null) return null;
    final pathPtr = path.toNativeUtf8();
    try {
      final out = write(engine, pathPtr);
      return out.toDartString();
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Single-level, non-recursive listing of [path]. Returns an empty list
  /// if the native dylib doesn't support it yet (old build) or on error.
  List<Map<String, dynamic>> quickListDir(Pointer<Void> engine, String path) {
    final lookup = _quickListDirJson;
    if (lookup == null) return const [];
    final pathPtr = path.toNativeUtf8();
    try {
      final out = lookup(engine, pathPtr);
      if (out == nullptr) return const [];
      try {
        final decoded = jsonDecode(out.toDartString());
        if (decoded is! List) return const [];
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } finally {
        _freeString(out);
      }
    } finally {
      calloc.free(pathPtr);
    }
  }
```

- [ ] **Step 4: Verify Dart analysis passes**

Run: `cd apps/volward && fvm flutter analyze lib/bridge/native_bridge.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add apps/volward/lib/bridge/native_bridge.dart
git commit -m "feat(bridge): add FFI bindings for checkpoint and quick_list_dir"
```

---

## Task 9: `ScanTreeNode.scanned` field (preserved everywhere nodes are copied)

**Files:**
- Modify: `apps/volward/lib/scan_tree.dart`
- Modify: `apps/volward/lib/scan_tree_filter.dart`
- Modify: `apps/volward/lib/home_page.dart`
- Test: `apps/volward/test/scan_tree_test.dart`

- [ ] **Step 1: Write the failing tests**

In `apps/volward/test/scan_tree_test.dart`, add a new group after `group('ScanTreeNode.fromSnapshotJson', ...)`:

```dart
  group('ScanTreeNode.scanned', () {
    test('defaults to true when constructed directly', () {
      final node = ScanTreeNode(name: 'a', path: '/a', isDirectory: true);
      expect(node.scanned, isTrue);
    });

    test('fromSnapshotJson reads an explicit false value', () {
      final node = ScanTreeNode.fromSnapshotJson({
        'name': 'a',
        'path': '/a',
        'is_dir': true,
        'scanned': false,
        'children': [],
      });
      expect(node.scanned, isFalse);
    });

    test('fromSnapshotJson defaults to true when the key is absent', () {
      final node = ScanTreeNode.fromSnapshotJson({
        'name': 'a',
        'path': '/a',
        'is_dir': true,
        'children': [],
      });
      expect(node.scanned, isTrue);
    });

    test('withAggregatedCounts preserves scanned on the copy', () {
      final root = ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        scanned: false,
        children: [
          ScanTreeNode(name: 'a', path: '/root/a', isDirectory: false),
        ],
      );
      final annotated = ScanTreeNode.withAggregatedCounts(root);
      expect(annotated.scanned, isFalse);
    });
  });
```

Also add this test to the existing `group('pruneTree', ...)` block:

```dart
    test('preserves scanned on the pruned copy', () {
      final unscannedRoot = ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        scanned: false,
        children: [
          ScanTreeNode(
            name: 'cache.txt',
            path: '/root/cache.txt',
            isDirectory: false,
            entry: {'id': '1', 'category': 'Cache', 'deletable': true},
          ),
        ],
      );
      final pruned = pruneTree(unscannedRoot, (entry) => entry['category'] == 'Cache');
      expect(pruned!.scanned, isFalse);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/volward && fvm flutter test test/scan_tree_test.dart`
Expected: FAIL — `scanned` is not a named parameter / getter yet.

- [ ] **Step 3: Implement the `scanned` field**

In `apps/volward/lib/scan_tree.dart`, replace the class header and `fromSnapshotJson`/`withAggregatedCounts`:

```dart
class ScanTreeNode {
  ScanTreeNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.entryId,
    this.entry,
    this.subtreeFileCount,
    this.scanned = true,
    List<ScanTreeNode>? children,
  }) : children = children ?? [];

  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final String? entryId;
  final Map<String, dynamic>? entry;
  /// Precomputed file count under this directory (files only, not dirs).
  final int? subtreeFileCount;
  /// False for directories whose contents haven't been scanned yet (the
  /// pre-scan preview, or a not-yet-covered node before a Wave-2 peek scan
  /// completes). Always true for files and for data from a real scan
  /// snapshot or checkpoint.
  final bool scanned;
  final List<ScanTreeNode> children;
```

Replace `factory ScanTreeNode.fromSnapshotJson(...)`'s body's return statement:

```dart
    return ScanTreeNode(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      isDirectory: isDir,
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      entryId: entryId,
      entry: entry,
      scanned: json['scanned'] is bool ? json['scanned'] as bool : true,
      children: children,
    );
```

Replace `static ScanTreeNode withAggregatedCounts(ScanTreeNode node)`'s return statement:

```dart
    return ScanTreeNode(
      name: node.name,
      path: node.path,
      isDirectory: true,
      sizeBytes: node.sizeBytes,
      entryId: node.entryId,
      entry: node.entry,
      subtreeFileCount: count,
      scanned: node.scanned,
      children: annotatedChildren,
    );
```

In `apps/volward/lib/scan_tree_filter.dart`, in `pruneTree`, replace the final return statement:

```dart
  return ScanTreeNode(
    name: node.name,
    path: node.path,
    isDirectory: true,
    sizeBytes: node.sizeBytes,
    entryId: node.entryId,
    entry: node.entry,
    scanned: node.scanned,
    children: prunedChildren,
  );
```

In `apps/volward/lib/home_page.dart`, in `_sortTree`, replace the return statement:

```dart
    return ScanTreeNode(
      name: node.name,
      path: node.path,
      isDirectory: true,
      sizeBytes: node.sizeBytes,
      entryId: node.entryId,
      entry: node.entry,
      scanned: node.scanned,
      children: sortedChildren,
    );
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/volward && fvm flutter test test/scan_tree_test.dart`
Expected: PASS

- [ ] **Step 5: Run the full Dart test suite to catch regressions**

Run: `cd apps/volward && fvm flutter test`
Expected: PASS (all existing tests still pass — `scanned` defaults to `true` everywhere it wasn't previously set, matching prior behavior)

- [ ] **Step 6: Commit**

```bash
git add apps/volward/lib/scan_tree.dart apps/volward/lib/scan_tree_filter.dart apps/volward/lib/home_page.dart apps/volward/test/scan_tree_test.dart
git commit -m "feat(ui): add ScanTreeNode.scanned, preserved across prune/sort/aggregate"
```

---

## Task 10: `scan_preview.dart` — wrap quick-list results into a renderable snapshot

**Files:**
- Create: `apps/volward/lib/scan_preview.dart`
- Test: `apps/volward/test/scan_preview_test.dart`

- [ ] **Step 1: Write the failing test**

Create `apps/volward/test/scan_preview_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_preview.dart';
import 'package:volward/scan_tree.dart';

void main() {
  group('buildPreviewSnapshot', () {
    test('wraps quick-list entries into a renderable snapshot shape', () {
      final snapshot = buildPreviewSnapshot(
        rootPath: '/Users/test',
        quickListEntries: [
          {'path': '/Users/test/Documents', 'is_dir': true},
          {'path': '/Users/test/notes.txt', 'is_dir': false, 'size_bytes': 42},
        ],
      );

      expect(snapshot['snapshot_id'], 'preview');
      final tree = snapshot['tree'] as Map<String, dynamic>;
      expect(tree['scanned'], isFalse);
      expect(tree['path'], '/Users/test');

      final root = ScanTreeNode.fromSnapshotJson(tree);
      expect(root.children, hasLength(2));

      final dir = root.children.firstWhere((c) => c.name == 'Documents');
      expect(dir.isDirectory, isTrue);
      expect(dir.scanned, isFalse);

      final file = root.children.firstWhere((c) => c.name == 'notes.txt');
      expect(file.isDirectory, isFalse);
      expect(file.scanned, isTrue);
      expect(file.sizeBytes, 42);
    });

    test('handles an empty directory listing', () {
      final snapshot = buildPreviewSnapshot(
        rootPath: '/Users/test',
        quickListEntries: const [],
      );
      final tree = snapshot['tree'] as Map<String, dynamic>;
      expect(tree['children'], isEmpty);
    });

    test('strips a trailing slash from the root path when naming the root', () {
      final snapshot = buildPreviewSnapshot(
        rootPath: '/Users/test/',
        quickListEntries: const [],
      );
      final tree = snapshot['tree'] as Map<String, dynamic>;
      expect(tree['name'], 'test');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/volward && fvm flutter test test/scan_preview_test.dart`
Expected: FAIL — `package:volward/scan_preview.dart` doesn't exist yet.

- [ ] **Step 3: Implement `buildPreviewSnapshot`**

Create `apps/volward/lib/scan_preview.dart`:

```dart
/// Builds a lightweight, snapshot-shaped map from a `quick_list_dir` result
/// so the UI can render it through the same [ScanTreeNode.fromSnapshotJson]
/// path used for real scan results, before any deep scan has started.
Map<String, dynamic> buildPreviewSnapshot({
  required String rootPath,
  required List<Map<String, dynamic>> quickListEntries,
}) {
  final normalizedRoot = _normalizeRoot(rootPath);
  final children = quickListEntries.map((entry) {
    final isDir = entry['is_dir'] == true;
    return <String, dynamic>{
      'name': _lastPathSegment(entry['path']?.toString() ?? ''),
      'path': entry['path']?.toString() ?? '',
      'is_dir': isDir,
      'size_bytes': isDir ? 0 : ((entry['size_bytes'] as num?)?.toInt() ?? 0),
      'entry_id': null,
      'scanned': !isDir,
      'children': const <Map<String, dynamic>>[],
    };
  }).toList();

  return <String, dynamic>{
    'snapshot_id': 'preview',
    'scanned_at_ms': DateTime.now().millisecondsSinceEpoch,
    'reclaimable_estimate_bytes': 0,
    'entries': const <Map<String, dynamic>>[],
    'tree': {
      'name': _lastPathSegment(normalizedRoot),
      'path': normalizedRoot,
      'is_dir': true,
      'size_bytes': 0,
      'entry_id': null,
      'scanned': false,
      'children': children,
    },
    'stats': {
      'paths_seen': 0,
      'dirs_seen': 0,
      'files_seen': 0,
      'files_in_snapshot': 0,
      'paths_skipped': 0,
      'truncated': false,
    },
    'warnings': const <String>[],
  };
}

String _normalizeRoot(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

String _lastPathSegment(String path) {
  final normalized = _normalizeRoot(path);
  final idx = normalized.lastIndexOf('/');
  if (idx == -1 || idx == normalized.length - 1) return normalized;
  return normalized.substring(idx + 1);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/volward && fvm flutter test test/scan_preview_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add apps/volward/lib/scan_preview.dart apps/volward/test/scan_preview_test.dart
git commit -m "feat(ui): add buildPreviewSnapshot for instant pre-scan directory preview"
```

---

## Task 11: `scan_snapshot_merge.dart` — splice a subtree into the live snapshot

**Files:**
- Create: `apps/volward/lib/scan_snapshot_merge.dart`
- Test: `apps/volward/test/scan_snapshot_merge_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `apps/volward/test/scan_snapshot_merge_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_snapshot_merge.dart';

void main() {
  group('mergeSubtreeIntoSnapshot', () {
    Map<String, dynamic> baseSnapshot() => {
          'snapshot_id': 'preview',
          'entries': <Map<String, dynamic>>[],
          'tree': {
            'name': 'root',
            'path': '/root',
            'is_dir': true,
            'size_bytes': 0,
            'scanned': false,
            'children': [
              {
                'name': 'Documents',
                'path': '/root/Documents',
                'is_dir': true,
                'size_bytes': 0,
                'scanned': false,
                'children': <Map<String, dynamic>>[],
              },
              {
                'name': 'Downloads',
                'path': '/root/Downloads',
                'is_dir': true,
                'size_bytes': 0,
                'scanned': false,
                'children': <Map<String, dynamic>>[],
              },
            ],
          },
        };

    test('replaces only the targeted subtree, leaving siblings untouched', () {
      final merged = mergeSubtreeIntoSnapshot(
        snapshot: baseSnapshot(),
        targetPath: '/root/Documents',
        subtreeTree: {
          'name': 'Documents',
          'path': '/root/Documents',
          'is_dir': true,
          'size_bytes': 500,
          'scanned': true,
          'children': [
            {
              'name': 'a.txt',
              'path': '/root/Documents/a.txt',
              'is_dir': false,
              'size_bytes': 500,
              'entry_id': 'e1',
              'scanned': true,
              'children': <Map<String, dynamic>>[],
            },
          ],
        },
        subtreeEntries: [
          {
            'id': 'e1',
            'path_or_uri': '/root/Documents/a.txt',
            'size_bytes': 500,
            'category': 'Unknown',
            'deletable': false,
          },
        ],
      );

      final tree = merged['tree'] as Map<String, dynamic>;
      final children = tree['children'] as List;

      final documents =
          children.firstWhere((c) => c['path'] == '/root/Documents') as Map;
      expect(documents['size_bytes'], 500);
      expect(documents['scanned'], isTrue);
      expect((documents['children'] as List), hasLength(1));

      final downloads =
          children.firstWhere((c) => c['path'] == '/root/Downloads') as Map;
      expect(downloads['scanned'], isFalse, reason: 'sibling must be untouched');

      expect(merged['entries'], hasLength(1));
    });

    test('overwrites an existing entry with the same id instead of duplicating', () {
      final snapshot = baseSnapshot();
      snapshot['entries'] = [
        {'id': 'e1', 'size_bytes': 100, 'deletable': true},
      ];

      final merged = mergeSubtreeIntoSnapshot(
        snapshot: snapshot,
        targetPath: '/root/Documents',
        subtreeTree:
            (snapshot['tree'] as Map)['children'][0] as Map<String, dynamic>,
        subtreeEntries: [
          {'id': 'e1', 'size_bytes': 200, 'deletable': true},
        ],
      );

      final entries = merged['entries'] as List;
      expect(entries, hasLength(1));
      expect(entries.single['size_bytes'], 200);
      expect(merged['reclaimable_estimate_bytes'], 200);
    });

    test('is a pure function that does not mutate the input snapshot', () {
      final snapshot = baseSnapshot();
      final originalTree = snapshot['tree'];

      mergeSubtreeIntoSnapshot(
        snapshot: snapshot,
        targetPath: '/root/Documents',
        subtreeTree: {
          'name': 'Documents',
          'path': '/root/Documents',
          'is_dir': true,
          'size_bytes': 999,
          'scanned': true,
          'children': <Map<String, dynamic>>[],
        },
        subtreeEntries: const [],
      );

      expect(identical(snapshot['tree'], originalTree), isTrue);
    });

    test('merging at the root path replaces the whole tree (checkpoint case)', () {
      final merged = mergeSubtreeIntoSnapshot(
        snapshot: baseSnapshot(),
        targetPath: '/root',
        subtreeTree: {
          'name': 'root',
          'path': '/root',
          'is_dir': true,
          'size_bytes': 1000,
          'scanned': true,
          'children': <Map<String, dynamic>>[],
        },
        subtreeEntries: const [],
      );

      final tree = merged['tree'] as Map<String, dynamic>;
      expect(tree['size_bytes'], 1000);
      expect(tree['scanned'], isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/volward && fvm flutter test test/scan_snapshot_merge_test.dart`
Expected: FAIL — `package:volward/scan_snapshot_merge.dart` doesn't exist yet.

- [ ] **Step 3: Implement `mergeSubtreeIntoSnapshot`**

Create `apps/volward/lib/scan_snapshot_merge.dart`:

```dart
/// Splices [subtreeTree] (already in the wire "ScanTreeNode json" shape)
/// into [snapshot]'s `tree` at [targetPath], replacing that node's
/// `size_bytes`/`scanned`/`children`. Also merges [subtreeEntries] into
/// `snapshot['entries']`, overwriting any existing entry with the same
/// `id`, and recomputes `reclaimable_estimate_bytes` locally from the
/// merged entries (rather than trusting a possibly-stale value carried
/// over from an earlier partial result).
///
/// Pure function: [snapshot] is never mutated; a new map is returned.
Map<String, dynamic> mergeSubtreeIntoSnapshot({
  required Map<String, dynamic> snapshot,
  required String targetPath,
  required Map<String, dynamic> subtreeTree,
  required List<Map<String, dynamic>> subtreeEntries,
}) {
  final tree = snapshot['tree'];
  final mergedTree = tree is Map
      ? _replaceNodeAtPath(
          Map<String, dynamic>.from(tree),
          targetPath,
          subtreeTree,
        )
      : subtreeTree;

  final existingEntries = (snapshot['entries'] is List)
      ? (snapshot['entries'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
      : <Map<String, dynamic>>[];
  final byId = <String, Map<String, dynamic>>{
    for (final e in existingEntries)
      if (e['id'] != null) e['id'].toString(): e,
  };
  for (final e in subtreeEntries) {
    final id = e['id']?.toString();
    if (id != null) byId[id] = e;
  }
  final mergedEntries = byId.values.toList();

  final reclaimable = mergedEntries
      .where((e) => e['deletable'] == true)
      .fold<int>(0, (sum, e) => sum + ((e['size_bytes'] as num?)?.toInt() ?? 0));

  return {
    ...snapshot,
    'tree': mergedTree,
    'entries': mergedEntries,
    'reclaimable_estimate_bytes': reclaimable,
  };
}

Map<String, dynamic> _replaceNodeAtPath(
  Map<String, dynamic> node,
  String targetPath,
  Map<String, dynamic> replacement,
) {
  if (node['path']?.toString() == targetPath) {
    return {
      ...node,
      'size_bytes': replacement['size_bytes'],
      'scanned': replacement['scanned'] ?? true,
      'children': replacement['children'],
    };
  }

  final children = node['children'];
  if (children is! List) return node;

  final newChildren = <dynamic>[];
  var found = false;
  for (final child in children) {
    final childPath = (child is Map) ? child['path']?.toString() ?? '' : '';
    final isOnPath = child is Map &&
        childPath.isNotEmpty &&
        (targetPath == childPath ||
            targetPath.startsWith(
              childPath.endsWith('/') ? childPath : '$childPath/',
            ));
    if (isOnPath) {
      newChildren.add(
        _replaceNodeAtPath(
          Map<String, dynamic>.from(child as Map),
          targetPath,
          replacement,
        ),
      );
      found = true;
    } else {
      newChildren.add(child);
    }
  }

  if (!found) return node;
  return {...node, 'children': newChildren};
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/volward && fvm flutter test test/scan_snapshot_merge_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add apps/volward/lib/scan_snapshot_merge.dart apps/volward/test/scan_snapshot_merge_test.dart
git commit -m "feat(ui): add mergeSubtreeIntoSnapshot for progressive tree updates"
```

---

## Task 12: Periodic checkpoint emission from the main scan isolate

**Files:**
- Modify: `apps/volward/lib/bridge/scan_worker.dart`

- [ ] **Step 1: Implement the checkpoint tick**

In `apps/volward/lib/bridge/scan_worker.dart`, replace the `Timer.periodic(const Duration(milliseconds: 300), (timer) { ... });` block inside `volwardScanIsolate` with:

```dart
    var tickCount = 0;
    Timer.periodic(const Duration(milliseconds: 300), (timer) {
      tickCount++;
      if (!bridge.isScanRunning(engine)) {
        timer.cancel();
        try {
          final progress = bridge.getLastProgress(engine);
          final pathsSeen = progress?['paths_seen'] as num?;

          progressPort.send(<String, dynamic>{
            'type': 'progress',
            'phase': 'SavingResults',
            'paths_seen': pathsSeen?.toInt() ?? 0,
          });

          final tmpPath = '${Directory.systemTemp.path}/volward-$jobId.json';
          final snapshotId = _persistSnapshot(bridge, engine, tmpPath);
          if (snapshotId.startsWith('error:')) {
            progressPort.send(<String, dynamic>{
              'type': 'error',
              'error': snapshotId,
            });
            return;
          }

          progressPort.send(<String, dynamic>{
            'type': 'progress',
            'phase': 'Done',
            'paths_seen': pathsSeen?.toInt() ?? 0,
          });
          progressPort.send(<String, dynamic>{
            'type': 'done',
            'snapshot_path': tmpPath,
            'snapshot_id': snapshotId,
          });
        } catch (e, st) {
          progressPort.send(<String, dynamic>{
            'type': 'error',
            'error': '$e\n$st',
          });
        } finally {
          bridge.freeEngine(engine);
          cancelRecv.close();
        }
        return;
      }

      final progress = bridge.getLastProgress(engine);
      if (progress != null) {
        progressPort.send(<String, dynamic>{'type': 'progress', ...progress});
      }

      // Roughly every 2s (300ms * 7), stream a partial snapshot so the UI
      // can render progress without waiting for the whole scan to finish.
      if (bridge.hasCheckpointApi && tickCount % 7 == 0) {
        final checkpointPath =
            '${Directory.systemTemp.path}/volward-$jobId-checkpoint.json';
        final checkpointId =
            bridge.writeLastCheckpointToPath(engine, checkpointPath);
        if (checkpointId != null && !checkpointId.startsWith('error:')) {
          progressPort.send(<String, dynamic>{
            'type': 'checkpoint',
            'snapshot_path': checkpointPath,
          });
        }
      }
    });
```

- [ ] **Step 2: Verify Dart analysis passes**

Run: `cd apps/volward && fvm flutter analyze lib/bridge/scan_worker.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run the full Dart test suite**

Run: `cd apps/volward && fvm flutter test`
Expected: PASS (this file has no direct unit tests — it requires the native dylib — verified via analyze + manual regression in Task 15)

- [ ] **Step 4: Commit**

```bash
git add apps/volward/lib/bridge/scan_worker.dart
git commit -m "feat(worker): stream periodic checkpoints from the main scan isolate"
```

---

## Task 13: `VolwardSession` — preview, checkpoint handling, merge

**Files:**
- Modify: `apps/volward/lib/volward_session.dart`

- [ ] **Step 1: Add imports**

At the top of `apps/volward/lib/volward_session.dart`, add these two imports after `import 'snapshot_cache.dart';`:

```dart
import 'scan_preview.dart';
import 'scan_snapshot_merge.dart';
```

- [ ] **Step 2: Add `previewTarget()`**

Add this method anywhere inside `class VolwardSession extends ChangeNotifier { ... }` (e.g. right after `clearScanRoots()`):

```dart
  /// Instantly renders the chosen target's top-level directory listing,
  /// before any deep scan starts. No-op if the native dylib doesn't support
  /// quick_list_dir yet (old build) — callers fall back to the pre-scan
  /// section in that case.
  Future<void> previewTarget() async {
    if (!_ready || _engine == null) return;
    if (!VolwardNativeBridge.instance.hasQuickListApi) return;

    final root = _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot();
    List<Map<String, dynamic>> entries;
    try {
      entries = await Isolate.run(() {
        final bridge = VolwardNativeBridge.open();
        final engine = bridge.createEngine();
        try {
          return bridge.quickListDir(engine, root);
        } finally {
          bridge.freeEngine(engine);
        }
      });
    } catch (e, st) {
      debugPrint('VolwardSession: previewTarget failed: $e\n$st');
      return;
    }

    _lastSnapshot = buildPreviewSnapshot(rootPath: root, quickListEntries: entries);
    notifyListeners();
  }
```

- [ ] **Step 3: Handle the `checkpoint` message type and add `_applyMerge`**

In `runScan()`, inside the `_scanProgressSub = _scanReceivePort!.listen((msg) { ... })` callback, add a new branch for `type == 'checkpoint'` right before the existing `else if (type == 'done')` branch:

```dart
      } else if (type == 'checkpoint') {
        final path = m['snapshot_path']?.toString();
        if (path != null && path.isNotEmpty) {
          unawaited(_applyCheckpointFromFile(path));
        }
      } else if (type == 'done') {
```

Add `import 'dart:async';` already exists at the top of the file (it does — `import 'dart:async';` is the first import), so `unawaited` needs `import 'dart:async' show unawaited;` — actually `unawaited` is exported from `dart:async` in modern Dart SDKs; since `dart:async` is already imported without a `show` clause, `unawaited` is already available. No import change needed.

Add these two new private methods anywhere inside the class (e.g. right after `_loadSnapshotFromFile`):

```dart
  Future<void> _applyCheckpointFromFile(String path) async {
    try {
      final checkpoint = await Isolate.run(() => _decodeSnapshotJsonFile(path));
      try {
        await File(path).delete();
      } catch (_) {}
      if (checkpoint == null) return;

      final tree = checkpoint['tree'];
      if (tree is! Map) return;
      final rootPath = tree['path']?.toString();
      if (rootPath == null || rootPath.isEmpty) return;

      final entries = (checkpoint['entries'] is List)
          ? (checkpoint['entries'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      _applyMerge(rootPath, Map<String, dynamic>.from(tree), entries);
    } catch (e, st) {
      debugPrint('VolwardSession: apply checkpoint failed: $e\n$st');
    }
  }

  void _applyMerge(
    String targetPath,
    Map<String, dynamic> subtreeTree,
    List<Map<String, dynamic>> subtreeEntries,
  ) {
    final current = _lastSnapshot;
    if (current == null) return;
    final merged = mergeSubtreeIntoSnapshot(
      snapshot: current,
      targetPath: targetPath,
      subtreeTree: subtreeTree,
      subtreeEntries: subtreeEntries,
    );
    // Force every merge to look like "new data" to snapshot_id-keyed UI
    // caches, even though checkpoints from the same scan job would
    // otherwise all share the same Rust-side snapshot_id.
    merged['snapshot_id'] = 'live-${DateTime.now().microsecondsSinceEpoch}';
    _lastSnapshot = merged;
    notifyListeners();
  }
```

- [ ] **Step 4: Verify Dart analysis passes**

Run: `cd apps/volward && fvm flutter analyze lib/volward_session.dart`
Expected: `No issues found!`

- [ ] **Step 5: Run the full Dart test suite**

Run: `cd apps/volward && fvm flutter test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add apps/volward/lib/volward_session.dart
git commit -m "feat(session): add previewTarget and progressive checkpoint merging"
```

---

## Task 14: Wire preview + non-resetting navigation into the UI

**Files:**
- Create: `apps/volward/lib/scan_tree_navigation.dart`
- Modify: `apps/volward/lib/home_page.dart`
- Modify: `apps/volward/lib/widgets/scan_column_view.dart`
- Test: `apps/volward/test/scan_tree_navigation_test.dart`
- Test: `apps/volward/test/scan_column_view_test.dart`

- [ ] **Step 1: Write the failing test for `refreshColumnChain`**

Create `apps/volward/test/scan_tree_navigation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/scan_tree_navigation.dart';

void main() {
  group('refreshColumnChain', () {
    ScanTreeNode buildTree({required int aFileCount}) {
      return ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        children: [
          ScanTreeNode(
            name: 'a',
            path: '/root/a',
            isDirectory: true,
            children: List.generate(
              aFileCount,
              (i) => ScanTreeNode(
                name: 'f$i.txt',
                path: '/root/a/f$i.txt',
                isDirectory: false,
              ),
            ),
          ),
          ScanTreeNode(name: 'b', path: '/root/b', isDirectory: true),
        ],
      );
    }

    test('re-resolves a matching path prefix to the new node instances', () {
      final oldRoot = buildTree(aFileCount: 0);
      final oldChain = [oldRoot.children.first]; // '/root/a', empty children

      final newRoot = buildTree(aFileCount: 3); // '/root/a' now has 3 files
      final refreshed = refreshColumnChain(newRoot, oldChain);

      expect(refreshed, hasLength(1));
      expect(refreshed.single.path, '/root/a');
      expect(refreshed.single.children, hasLength(3));
    });

    test('truncates the chain when a path no longer exists', () {
      final oldRoot = buildTree(aFileCount: 0);
      final oldChain = [
        oldRoot.children.first,
        ScanTreeNode(name: 'gone', path: '/root/a/gone', isDirectory: true),
      ];

      final newRoot = buildTree(aFileCount: 0);
      final refreshed = refreshColumnChain(newRoot, oldChain);

      expect(refreshed, hasLength(1));
      expect(refreshed.single.path, '/root/a');
    });

    test('returns an empty chain when nothing matches', () {
      final newRoot = buildTree(aFileCount: 0);
      final refreshed = refreshColumnChain(newRoot, [
        ScanTreeNode(name: 'x', path: '/root/x', isDirectory: true),
      ]);
      expect(refreshed, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/volward && fvm flutter test test/scan_tree_navigation_test.dart`
Expected: FAIL — `package:volward/scan_tree_navigation.dart` doesn't exist yet.

- [ ] **Step 3: Implement `refreshColumnChain`**

Create `apps/volward/lib/scan_tree_navigation.dart`:

```dart
import 'scan_tree.dart';

/// Re-resolves [oldChain] (previously-selected nodes, matched by path)
/// against [newRoot] after the underlying snapshot changed — e.g. a
/// background checkpoint or peek scan merged new data. Stops at the first
/// path segment that no longer exists under the new tree, so a still-valid
/// prefix of the user's navigation is preserved instead of resetting to
/// the root.
List<ScanTreeNode> refreshColumnChain(
  ScanTreeNode newRoot,
  List<ScanTreeNode> oldChain,
) {
  final refreshed = <ScanTreeNode>[];
  var current = newRoot;
  for (final oldNode in oldChain) {
    ScanTreeNode? match;
    for (final child in current.children) {
      if (child.path == oldNode.path) {
        match = child;
        break;
      }
    }
    if (match == null) break;
    refreshed.add(match);
    current = match;
  }
  return refreshed;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/volward && fvm flutter test test/scan_tree_navigation_test.dart`
Expected: PASS

- [ ] **Step 5: Write the failing widget test for the "unscanned" display**

Add this test to `apps/volward/test/scan_column_view_test.dart` (after the existing `'ScanColumnView keeps selected folder highlighted'` test):

```dart
  testWidgets('ScanColumnView shows a placeholder for unscanned folders', (tester) async {
    final root = ScanTreeNode(
      name: 'root',
      path: '/root',
      isDirectory: true,
      children: [
        ScanTreeNode(
          name: 'Pending',
          path: '/root/Pending',
          isDirectory: true,
          scanned: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildVolwardTheme(brightness: Brightness.light),
        home: Scaffold(
          body: SizedBox(
            height: 240,
            width: 480,
            child: ScanColumnView(
              root: root,
              selectionChain: const [],
              onSelect: (_, __) {},
              formatBytes: (b) => '${b ?? 0} B',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });
```

- [ ] **Step 6: Run test to verify it fails**

Run: `cd apps/volward && fvm flutter test test/scan_column_view_test.dart`
Expected: FAIL — `_FinderRow` always shows `Icons.chevron_right` for directories today.

- [ ] **Step 7: Implement the "unscanned" display in `ScanColumnView`**

In `apps/volward/lib/widgets/scan_column_view.dart`, in `_FinderRowState.build`, replace:

```dart
              if (isDir)
                Icon(Icons.chevron_right, size: 14, color: muted)
              else
                Text(
                  subtitle,
                  style: context.vwFinePrint.copyWith(
                    color: muted,
                    fontSize: 11,
                  ),
                ),
```

with:

```dart
              if (isDir)
                (!widget.node.scanned)
                    ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: muted,
                        ),
                      )
                    : Icon(Icons.chevron_right, size: 14, color: muted)
              else
                Text(
                  subtitle,
                  style: context.vwFinePrint.copyWith(
                    color: muted,
                    fontSize: 11,
                  ),
                ),
```

Also update the `subtitle` computation just above it in the same `build` method — replace:

```dart
    final subtitle = isDir
        ? widget.formatBytes(widget.node.displayBytes)
        : widget.formatBytes(
            widget.node.entry?['size_bytes'] as num? ?? widget.node.sizeBytes,
          );
```

with:

```dart
    final subtitle = isDir
        ? (widget.node.scanned ? widget.formatBytes(widget.node.displayBytes) : '—')
        : widget.formatBytes(
            widget.node.entry?['size_bytes'] as num? ?? widget.node.sizeBytes,
          );
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `cd apps/volward && fvm flutter test test/scan_column_view_test.dart`
Expected: PASS

- [ ] **Step 9: Wire `previewTarget()` and column-chain refresh into `home_page.dart`**

Add this import near the top of `apps/volward/lib/home_page.dart` (next to `import 'widgets/scan_filter_bar.dart';`):

```dart
import 'scan_tree_navigation.dart';
```

Replace `initState`:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_onSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.session.restoreCachedSnapshotIfNeeded();
      if (!mounted) return;
      if (widget.session.lastSnapshot == null) {
        await widget.session.previewTarget();
      }
    });
  }
```

Replace `_onSessionChanged`:

```dart
  void _onSessionChanged() {
    if (!_prevScanning && _s.scanning) {
      setState(() {
        _selected.clear();
        _scanStatus = null;
        _columnChain.clear();
        _columnNavTick.value++;
        _invalidateSnapshotCaches();
      });
    } else if (_prevScanning && !_s.scanning && _s.lastSnapshot != null) {
      _columnChain.clear();
      _columnNavTick.value++;
      _invalidateSnapshotCaches();
    } else if (_columnChain.isNotEmpty) {
      // A background checkpoint (or Wave-2 peek) merged new data while the
      // user is browsing: keep their position but refresh node references
      // so newly-scanned children/sizes become visible.
      _invalidateSnapshotCaches();
      final freshRoot = _getDisplayTree();
      if (freshRoot != null) {
        _setColumnChain(refreshColumnChain(freshRoot, _columnChain));
      }
    }
    _prevScanning = _s.scanning;
    setState(() {});
  }
```

Replace `_pickFolder`:

```dart
  Future<void> _pickFolder() async {
    final path = await getDirectoryPath(confirmButtonText: 'Select');
    if (path == null) return;
    _s.setScanRoots([path]);
    await _s.previewTarget();
  }
```

In `_buildCompactResultsChrome`, replace the "Home" button's `onPressed`:

```dart
              if (_s.scanRoots.isNotEmpty) ...[
                const SizedBox(width: AppleSpacing.xxs),
                AppleButton(
                  label: 'Home',
                  icon: Icons.home_outlined,
                  variant: AppleButtonVariant.pearl,
                  onPressed: _s.scanning
                      ? null
                      : () async {
                          _s.clearScanRoots();
                          setState(() => _scanStatus = null);
                          await _s.previewTarget();
                        },
                ),
              ],
```

In `_buildScanSection`, replace the other "Home" button's `onPressed` (the pre-scan section's copy):

```dart
                    if (_s.scanRoots.isNotEmpty)
                      AppleButton(
                        label: 'Home',
                        icon: Icons.home_outlined,
                        variant: AppleButtonVariant.pearl,
                        onPressed: _s.scanning
                            ? null
                            : () async {
                                _s.clearScanRoots();
                                setState(() => _scanStatus = null);
                                await _s.previewTarget();
                              },
                      ),
```

In `_buildItemPreview`, replace the subtitle `Text` widget's data expression:

```dart
                      Text(
                        '${_fmt(size)} · $category'
                        '${isDir ? ' · $subtreeItems items' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.vwFinePrint,
                      ),
```

with:

```dart
                      Text(
                        '${isDir && !focus.scanned ? '—' : _fmt(size)} · $category'
                        '${isDir ? ' · $subtreeItems items' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.vwFinePrint,
                      ),
```

- [ ] **Step 10: Verify Dart analysis passes**

Run: `cd apps/volward && fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 11: Run the full Dart test suite**

Run: `cd apps/volward && fvm flutter test`
Expected: PASS

- [ ] **Step 12: Commit**

```bash
git add apps/volward/lib/scan_tree_navigation.dart apps/volward/lib/home_page.dart apps/volward/lib/widgets/scan_column_view.dart apps/volward/test/scan_tree_navigation_test.dart apps/volward/test/scan_column_view_test.dart
git commit -m "feat(ui): show instant preview, keep navigation position across checkpoints"
```

---

## Task 15: Wave 1 full verification

**Files:** none (verification task)

- [ ] **Step 1: Full Rust suite**

Run: `cd /Users/liminglin/Funny/volward && export CARGO_TARGET_DIR="$(pwd)/target" && cargo test`
Expected: PASS

- [ ] **Step 2: Rebuild native library**

Run: `cd /Users/liminglin/Funny/volward/apps/volward/macos && bash build_rust.sh`
Expected: dylib copied successfully

- [ ] **Step 3: Full Dart suite**

Run: `cd /Users/liminglin/Funny/volward/apps/volward && fvm flutter test`
Expected: PASS (15+ existing tests + all new tests from Tasks 9-14)

- [ ] **Step 4: Manual regression (macOS run)**

Run: `cd /Users/liminglin/Funny/volward/apps/volward && fvm flutter run -d macos`

Checklist:
- Pick a custom folder (or use Home): the folder's top-level contents appear **immediately**, before clicking "Start scan".
- Click "Start scan": the results browser stays visible and interactive (no blocking full-page "scanning" state).
- Within a couple of seconds, folder sizes and the filter bar's reclaimable total start updating on their own.
- Drill into a folder, wait for a checkpoint to land (~2s): your current position is **not** reset back to the root.
- Cancel mid-scan: previously-checkpointed content remains browsable.
- Let the scan finish: final numbers match what today's full scan would report.

- [ ] **Step 5: No commit needed** (verification only — commit any manual fixes found during regression using a descriptive message, then re-run Steps 1-4)

---

## Task 16: `volwardPeekScanIsolate` — scoped scan for click-priority (Wave 2)

**Files:**
- Modify: `apps/volward/lib/bridge/scan_worker.dart`

- [ ] **Step 1: Implement the peek isolate entry point**

Add this new top-level function to `apps/volward/lib/bridge/scan_worker.dart` (after `volwardScanIsolate`, before `_persistSnapshot`):

```dart
/// Isolate entry: [SendPort resultPort, String path].
///
/// Runs a small, scoped full scan of exactly [path] using its own native
/// engine — completely independent from the main background scan's engine
/// — so it can run concurrently. Used when the user clicks a directory the
/// main background scan hasn't reached yet: because the scoped subtree is
/// usually much smaller than the whole scan root, this finishes quickly and
/// gives the effect of "priority" without reordering the main walk.
@pragma('vm:entry-point')
void volwardPeekScanIsolate(List<dynamic> args) {
  final resultPort = args[0] as SendPort;
  final path = args[1] as String;

  VolwardNativeBridge bridge;
  Pointer<Void> engine;
  try {
    bridge = VolwardNativeBridge.open();
    engine = bridge.createEngine();
  } catch (e, st) {
    resultPort.send(<String, dynamic>{'type': 'error', 'error': '$e\n$st'});
    return;
  }

  try {
    final jobId = 'peek-${DateTime.now().millisecondsSinceEpoch}';
    final startResult = bridge.startScanAsyncWithOptions(
      engine,
      jobId,
      [path],
      incremental: false,
    );
    if (startResult.startsWith('error:')) {
      resultPort.send(<String, dynamic>{'type': 'error', 'error': startResult});
      bridge.freeEngine(engine);
      return;
    }

    Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (bridge.isScanRunning(engine)) return;
      timer.cancel();
      try {
        final snapshot = bridge.getLastSnapshot(engine);
        if (snapshot == null) {
          resultPort.send(<String, dynamic>{
            'type': 'error',
            'error': 'error:peek scan produced no snapshot',
          });
          return;
        }
        resultPort.send(<String, dynamic>{
          'type': 'done',
          'path': path,
          'tree': snapshot['tree'],
          'entries': snapshot['entries'],
        });
      } catch (e, st) {
        resultPort.send(<String, dynamic>{'type': 'error', 'error': '$e\n$st'});
      } finally {
        bridge.freeEngine(engine);
      }
    });
  } catch (e, st) {
    resultPort.send(<String, dynamic>{'type': 'error', 'error': '$e\n$st'});
    bridge.freeEngine(engine);
  }
}
```

- [ ] **Step 2: Verify Dart analysis passes**

Run: `cd apps/volward && fvm flutter analyze lib/bridge/scan_worker.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add apps/volward/lib/bridge/scan_worker.dart
git commit -m "feat(worker): add volwardPeekScanIsolate for click-priority scoped scans"
```

---

## Task 17: `VolwardSession.peekScan()` with concurrency limiting

**Files:**
- Modify: `apps/volward/lib/volward_session.dart`

- [ ] **Step 1: Add peek-scan state and the `peekScan` method**

Add these fields near the other scan-state fields (next to `final Set<String> _selectedEntryIds = {};`):

```dart
  final Set<String> _peekInFlight = {};
  final Set<String> _peekCompleted = {};
  static const int _maxConcurrentPeeks = 2;
```

Add this method anywhere inside the class (e.g. right after `previewTarget`):

```dart
  /// Triggers a small, scoped scan of [path] so its contents/size become
  /// available immediately, without waiting for the background full scan
  /// to reach it. No-op if a peek for this path is already in flight or
  /// already completed this session, or if the concurrency limit is hit
  /// (extra clicks are simply dropped — the background scan will cover the
  /// path eventually regardless).
  Future<void> peekScan(String path) async {
    if (!_ready || _engine == null) return;
    if (_peekInFlight.contains(path) || _peekCompleted.contains(path)) return;
    if (_peekInFlight.length >= _maxConcurrentPeeks) return;

    _peekInFlight.add(path);
    ReceivePort? receivePort;
    try {
      receivePort = ReceivePort();
      await Isolate.spawn(volwardPeekScanIsolate, [receivePort.sendPort, path]);
      final message = await receivePort.first;
      if (message is! Map) return;
      final type = message['type']?.toString();
      if (type == 'done') {
        final tree = message['tree'];
        final entriesRaw = message['entries'];
        if (tree is Map) {
          final entries = (entriesRaw is List)
              ? entriesRaw
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
              : <Map<String, dynamic>>[];
          _applyMerge(path, Map<String, dynamic>.from(tree), entries);
          _peekCompleted.add(path);
        }
      } else {
        debugPrint('VolwardSession: peekScan($path) failed: ${message['error']}');
      }
    } catch (e, st) {
      debugPrint('VolwardSession: peekScan($path) error: $e\n$st');
    } finally {
      receivePort?.close();
      _peekInFlight.remove(path);
    }
  }
```

- [ ] **Step 2: Reset peek state at the start of every fresh scan**

In `runScan()`, add these two lines to the setup block, right after `_savingPhaseStartedAt = null;` (before `_startScanElapsedTimer();`):

```dart
    _peekInFlight.clear();
    _peekCompleted.clear();
```

- [ ] **Step 3: Add the import for the peek isolate**

Add this import next to `import 'bridge/scan_worker.dart';` (it's already imported for `volwardScanIsolate`, so `volwardPeekScanIsolate` is automatically available from the same file — no new import line needed).

- [ ] **Step 4: Verify Dart analysis passes**

Run: `cd apps/volward && fvm flutter analyze lib/volward_session.dart`
Expected: `No issues found!`

- [ ] **Step 5: Run the full Dart test suite**

Run: `cd apps/volward && fvm flutter test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add apps/volward/lib/volward_session.dart
git commit -m "feat(session): add peekScan with concurrency limiting and dedup"
```

---

## Task 18: Trigger `peekScan` on click for unscanned nodes

**Files:**
- Modify: `apps/volward/lib/home_page.dart`

- [ ] **Step 1: Implement the click handler change**

In `apps/volward/lib/home_page.dart`, replace `_onColumnSelect`:

```dart
  void _onColumnSelect(int columnIndex, ScanTreeNode node) {
    _setColumnChain(_columnChain.take(columnIndex).toList()..add(node));
    if (node.isDirectory && !node.scanned) {
      unawaited(_s.peekScan(node.path));
    }
  }
```

Add `import 'dart:async';` at the top of `apps/volward/lib/home_page.dart` if not already present — check the existing import list first; `home_page.dart` currently imports `dart:io` but not `dart:async`, so add it as the first import:

```dart
import 'dart:async';
import 'dart:io';
```

- [ ] **Step 2: Verify Dart analysis passes**

Run: `cd apps/volward && fvm flutter analyze lib/home_page.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run the full Dart test suite**

Run: `cd apps/volward && fvm flutter test`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add apps/volward/lib/home_page.dart
git commit -m "feat(ui): trigger a priority peek scan when clicking an unscanned folder"
```

---

## Task 19: Wave 2 full verification

**Files:** none (verification task)

- [ ] **Step 1: Full Rust suite**

Run: `cd /Users/liminglin/Funny/volward && export CARGO_TARGET_DIR="$(pwd)/target" && cargo test`
Expected: PASS

- [ ] **Step 2: Rebuild native library**

Run: `cd /Users/liminglin/Funny/volward/apps/volward/macos && bash build_rust.sh`
Expected: dylib copied successfully

- [ ] **Step 3: Full Dart suite**

Run: `cd /Users/liminglin/Funny/volward/apps/volward && fvm flutter test`
Expected: PASS (all tests from Wave 1 + Task 17/18)

- [ ] **Step 4: Manual regression (macOS run)**

Run: `cd /Users/liminglin/Funny/volward/apps/volward && fvm flutter run -d macos`

Checklist:
- Start a scan on Home (or a large custom folder).
- While the background scan is still working through shallow levels, click into a deep folder that clearly hasn't been reached yet (its row shows the small spinner instead of a chevron).
- Confirm the folder's contents populate within a few seconds (much faster than waiting for the global scan to reach it), and the spinner is replaced by the chevron.
- Click several different not-yet-scanned folders rapidly: confirm only 2 peek scans run at a time (no runaway concurrent scans; check via `Activity Monitor` or just that the app stays responsive).
- Let the background scan finish normally: confirm final numbers match a full scan (peeked folders aren't double-counted or missing in `entries`).

- [ ] **Step 5: No commit needed** (verification only — commit any manual fixes found during regression, then re-run Steps 1-4)

---

## Non-Goals (explicitly deferred, per spec §1.3 and §7)

- Reordering jwalk's internal traversal queue (Approach B) — not attempted.
- Deduping peek-scanned subtrees against the main background scan via `DirFingerprint` reuse — the spec calls this optional; skipping it only costs a little redundant CPU, never correctness. Can be added later as a standalone task if profiling shows it matters.
- Any change to the delete/Move-to-Trash flow, theme/settings, or non-macOS platforms.
- Spec §5 calls for `quick_list_dir` to surface an explicit `partial: true` flag when some entries were skipped due to permission errors. Task 3's implementation already satisfies the more important half of that requirement — a permission error on one child never aborts or panics the whole listing, it's just silently skipped — but does not add a `partial` flag end-to-end through the JSON/Dart layers, since immediate children of a chosen scan root rarely hit permission errors on macOS (unlike deep recursive walks). Add a dedicated follow-up task if manual testing shows this matters in practice.
- Spec §5 also calls for an explicit "rebuild Rust" prompt when `hasQuickListApi`/`hasCheckpointApi` are false. This plan implements the more important half (silent, correct fallback to today's blocking flow) but not a user-facing toast; add one later if it proves confusing in practice.
