#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root_dir/scripts/check_architecture.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/volward-architecture-check.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

new_fixture() {
  local fixture="$1"
  mkdir -p \
    "$fixture/apps/volward/lib/features" \
    "$fixture/apps/volward/lib/core" \
    "$fixture/apps/volward/lib/shared" \
    "$fixture/apps/volward/lib/widgets"
}

expect_failure() {
  local name="$1"
  local fixture="$2"

  if ARCHITECTURE_ROOT="$fixture" bash "$checker" >/dev/null 2>&1; then
    printf 'architecture checker test failed: %s was accepted\n' "$name" >&2
    exit 1
  fi
}

clean_case="$fixture_root/clean"
new_fixture "$clean_case"
printf "const value = 'clean';\n" >"$clean_case/apps/volward/lib/features/example.dart"

if ! ARCHITECTURE_ROOT="$clean_case" bash "$checker" >/dev/null; then
  printf 'architecture checker test failed: clean fixture was rejected\n' >&2
  exit 1
fi

feature_ffi_case="$fixture_root/feature_ffi"
new_fixture "$feature_ffi_case"
printf "import '../../bridge/native_bridge.dart';\n" \
  >"$feature_ffi_case/apps/volward/lib/features/example.dart"
expect_failure 'feature to FFI' "$feature_ffi_case"

root_page_ffi_case="$fixture_root/root_page_ffi"
new_fixture "$root_page_ffi_case"
printf "import 'bridge/native_bridge.dart';\n" \
  >"$root_page_ffi_case/apps/volward/lib/home_page.dart"
expect_failure 'root page to FFI' "$root_page_ffi_case"

shared_feature_case="$fixture_root/shared_feature"
new_fixture "$shared_feature_case"
printf "import '../features/browse/catalog_reader.dart';\n" \
  >"$shared_feature_case/apps/volward/lib/shared/example.dart"
expect_failure 'shared to feature' "$shared_feature_case"

core_infrastructure_case="$fixture_root/core_infrastructure"
new_fixture "$core_infrastructure_case"
printf "import '../../infrastructure/bridge/scan_bridge.dart';\n" \
  >"$core_infrastructure_case/apps/volward/lib/core/leak.dart"
expect_failure 'core to infrastructure' "$core_infrastructure_case"

part_only_case="$fixture_root/part_only"
new_fixture "$part_only_case"
printf "part of '../volward_session.dart';\n" \
  >"$part_only_case/apps/volward/lib/features/part_owner.dart"
expect_failure 'feature part ownership' "$part_only_case"

part_ffi_case="$fixture_root/part_ffi"
new_fixture "$part_ffi_case"
printf "part of '../volward_session.dart';\nfinal bridge = VolwardNativeBridge.instance;\n" \
  >"$part_ffi_case/apps/volward/lib/features/part_owner.dart"
expect_failure 'feature part to FFI singleton' "$part_ffi_case"

feature_session_case="$fixture_root/feature_session"
new_fixture "$feature_session_case"
printf "const session = VolwardSession.instance;\n" \
  >"$feature_session_case/apps/volward/lib/features/session_use.dart"
expect_failure 'feature to Session singleton' "$feature_session_case"

widget_singleton_case="$fixture_root/widget_singleton"
new_fixture "$widget_singleton_case"
printf "final bridge = VolwardNativeBridge.instance;\n" \
  >"$widget_singleton_case/apps/volward/lib/widgets/bridge_use.dart"
expect_failure 'widget to bridge singleton' "$widget_singleton_case"

printf 'architecture checker tests: OK\n'
