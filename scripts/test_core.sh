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
}

run_flutter() {
  cd "$root_dir/apps/volward"
  local flutter_cmd=(flutter)
  if ! command -v flutter >/dev/null 2>&1 && command -v fvm >/dev/null 2>&1; then
    flutter_cmd=(fvm flutter)
  fi
  local tests=(
    test/home_page_startup_test.dart
    test/scan_preview_test.dart
    test/scan_worker_test.dart
    test/settings_update_section_test.dart
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
