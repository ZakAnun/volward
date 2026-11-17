#!/usr/bin/env bash
set -euo pipefail

root_dir="${ARCHITECTURE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
dart_lib="$root_dir/apps/volward/lib"
failures=0

fail() {
  printf 'architecture boundary violation: %s\n' "$*" >&2
  failures=$((failures + 1))
}

check_forbidden_imports() {
  local directory="$1"
  local description="$2"
  local pattern="$3"
  local file

  while IFS= read -r -d '' file; do
    if grep -Eq "$pattern" "$file"; then
      fail "${file#"$root_dir/"}: $description"
    fi
  done < <(find "$directory" -type f -name '*.dart' -print0 2>/dev/null)
}

# Session ownership migration is complete. No feature file may be a part of
# the compatibility facade.
session_part_allowlist=()

is_allowed_session_part() {
  local rel="$1"
  local entry
  if (( ${#session_part_allowlist[@]} == 0 )); then
    return 1
  fi
  for entry in "${session_part_allowlist[@]}"; do
    [[ "$rel" == "$entry" ]] && return 0
  done
  return 1
}

for ui_directory in features widgets shared; do
  check_forbidden_imports \
    "$dart_lib/$ui_directory" \
    'UI or shared code must not import Dart FFI bridge implementations' \
    "^[[:space:]]*(import|export)[[:space:]]+['\"]([^'\"]*/)?(bridge/native_bridge\\.dart|bridge/bindings/)"
done

for ui_file in \
  home_page.dart \
  directory_details_page.dart \
  settings_page.dart \
  storage_overview.dart; do
  file="$dart_lib/$ui_file"
  if [[ -f "$file" ]] && grep -Eq \
    "^[[:space:]]*(import|export)[[:space:]]+['\"]([^'\"]*/)?(bridge/native_bridge\\.dart|bridge/bindings/)" \
    "$file"; then
    fail "${file#"$root_dir/"}: root UI page must not import Dart FFI bridge implementations"
  fi
done

check_forbidden_imports \
  "$dart_lib/shared" \
  'shared code must not import feature, AI, or application-layer implementations' \
  "^[[:space:]]*(import|export)[[:space:]]+['\"]([^'\"]*/)?(features/|ai/|volward_session\\.dart|snapshot_catalog\\.dart|directory_details_page\\.dart|main\\.dart)"

check_forbidden_imports \
  "$dart_lib/core" \
  'core contracts and session logic must not import infrastructure implementations' \
  "^[[:space:]]*(import|export)[[:space:]]+['\"]([^'\"]*/)?infrastructure/"

# Session part ownership. Only the exact allowlisted files may be parts of
# volward_session.dart below features/.
while IFS= read -r -d '' file; do
  rel="${file#"$root_dir/"}"
  if is_allowed_session_part "$rel"; then
    continue
  fi
  if grep -Eq \
    "^[[:space:]]*part[[:space:]]+of[[:space:]]+['\"]([^'\"]*/)?volward_session\\.dart['\"]" \
    "$file"; then
    fail "$rel: feature file must not be a part of volward_session.dart"
  fi
done < <(find "$dart_lib/features" -type f -name '*.dart' -print0 2>/dev/null)

# Singleton tokens below features/, widgets/, and shared/. The allowlisted
# Session parts may still touch VolwardNativeBridge.instance until their
# owners are extracted in later tasks.
for ui_directory in features widgets shared; do
  while IFS= read -r -d '' file; do
    rel="${file#"$root_dir/"}"
    if is_allowed_session_part "$rel"; then
      continue
    fi
    if grep -Eq 'VolwardNativeBridge\.instance|VolwardSession\.instance' "$file"; then
      fail "$rel: feature/widget/shared code must not read infrastructure singletons"
    fi
  done < <(find "$dart_lib/$ui_directory" -type f -name '*.dart' -print0 2>/dev/null)
done

if ((failures > 0)); then
  printf '%d architecture boundary violation(s) found\n' "$failures" >&2
  exit 1
fi

printf 'architecture boundaries: OK\n'
