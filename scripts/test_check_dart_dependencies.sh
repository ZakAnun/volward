#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root_dir/scripts/check_dart_dependencies.dart"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/volward-dart-dependencies.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

if ! command -v dart >/dev/null 2>&1; then
  printf 'dart dependency checker test failed: dart is required\n' >&2
  exit 1
fi

new_fixture() {
  local fixture="$1"
  mkdir -p "$fixture/apps/volward/lib"
}

expect_failure() {
  local name="$1"
  local fixture="$2"

  if dart "$checker" --root "$fixture" \
    --accepted-cycles "$fixture_root/empty-cycles.json" --check >/dev/null 2>&1; then
    printf 'dart dependency checker test failed: %s was accepted\n' "$name" >&2
    exit 1
  fi
}

printf '[]\n' >"$fixture_root/empty-cycles.json"

clean_graph_case="$fixture_root/clean_graph"
new_fixture "$clean_graph_case"
printf "import 'child.dart';\nconst parent = true;\n" \
  >"$clean_graph_case/apps/volward/lib/parent.dart"
printf "const child = true;\n" \
  >"$clean_graph_case/apps/volward/lib/child.dart"
if ! dart "$checker" --root "$clean_graph_case" \
  --accepted-cycles "$fixture_root/empty-cycles.json" --check >/dev/null; then
  printf 'dart dependency checker test failed: acyclic fixture was rejected\n' >&2
  exit 1
fi

dependency_cycle_case="$fixture_root/dependency_cycle"
new_fixture "$dependency_cycle_case"
printf "import 'cycle_b.dart';\n" \
  >"$dependency_cycle_case/apps/volward/lib/cycle_a.dart"
printf "import 'cycle_a.dart';\n" \
  >"$dependency_cycle_case/apps/volward/lib/cycle_b.dart"
expect_failure 'unapproved dependency cycle' "$dependency_cycle_case"

multiline_cycle_case="$fixture_root/multiline_cycle"
new_fixture "$multiline_cycle_case"
printf "import\n  'cycle_b.dart'\n  as child;\n" \
  >"$multiline_cycle_case/apps/volward/lib/cycle_a.dart"
printf "import\n  'cycle_a.dart'\n  as child;\n" \
  >"$multiline_cycle_case/apps/volward/lib/cycle_b.dart"
expect_failure 'multiline dependency cycle' "$multiline_cycle_case"

accepted_cycle_case="$fixture_root/accepted_cycle"
new_fixture "$accepted_cycle_case"
printf "import 'cycle_b.dart';\n" \
  >"$accepted_cycle_case/apps/volward/lib/cycle_a.dart"
printf "import 'cycle_a.dart';\n" \
  >"$accepted_cycle_case/apps/volward/lib/cycle_b.dart"
printf '[["cycle_a.dart","cycle_b.dart"]]\n' >"$fixture_root/accepted-cycle.json"
if ! dart "$checker" --root "$accepted_cycle_case" \
  --accepted-cycles "$fixture_root/accepted-cycle.json" --check >/dev/null; then
  printf 'dart dependency checker test failed: approved cycle was rejected\n' >&2
  exit 1
fi

unresolved_import_case="$fixture_root/unresolved_import"
new_fixture "$unresolved_import_case"
printf "import 'missing.dart';\n" \
  >"$unresolved_import_case/apps/volward/lib/example.dart"
expect_failure 'unresolved local import' "$unresolved_import_case"

printf 'dart dependency checker tests: OK\n'
