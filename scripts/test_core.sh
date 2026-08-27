#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-all}"

run_rust() {
  cd "$root_dir"
  cargo test -p volward-core snapshot_catalog_round_trips_as_compact_json
  cargo test -p volward-core compact_index_roundtrips_and_accepts_older_format_versions
  cargo test -p volward-core full_scan_indexes_every_file_without_cap
  cargo test -p volward-core index_scan_builds_catalog_without_snapshot_tree
  cargo test -p volward-core delete_trashes_deletable_paths
  cargo test -p volward-core node_modules_matches_all_platforms
  cargo test -p volward-core tier2_classifies_node_modules_when_tier1_misses
  cargo test -p volward-core aggregate_folds_large_directory
  cargo test -p volward-core from_unclassified_files_aggregate_folds_siblings
  cargo test -p volward-core cap_top_n_keeps_largest_and_flags_truncation
  cargo test -p volward-core every_macos_yaml_rule_compiles
  cargo test -p volward-core save_and_load_round_trip
  cargo test -p volward-ai
  cargo test -p volward-platform-api
}

run_flutter() {
  cd "$root_dir/apps/volward"
  local flutter_cmd
  if command -v fvm >/dev/null 2>&1; then
    flutter_cmd=(fvm flutter)
  elif command -v flutter >/dev/null 2>&1; then
    flutter_cmd=(flutter)
  else
    echo "error: fvm or flutter is required" >&2
    return 1
  fi
  local tests=(
    test/home_page_startup_test.dart
    test/scan_preview_test.dart
    test/scan_worker_test.dart
    test/settings_update_section_test.dart
    test/home_page_content_mode_test.dart
    test/ai_analysis_workspace_test.dart
    test/platform_ai_provider_test.dart
    test/byok_ai_provider_test.dart
    test/ai_settings_store_test.dart
  )
  for test_file in "${tests[@]}"; do
    "${flutter_cmd[@]}" test "$test_file"
  done
}

case "$mode" in
  rust)
    run_rust
    ;;
  flutter)
    run_flutter
    ;;
  all)
    run_rust
    run_flutter
    ;;
  *)
    echo "usage: $0 [all|rust|flutter]" >&2
    exit 1
    ;;
esac
