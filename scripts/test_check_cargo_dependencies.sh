#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root_dir/scripts/check_cargo_dependencies.py"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/volward-cargo-dependencies.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

new_package() {
  local root="$1"
  local name="$2"
  mkdir -p "$root/crates/$name/src"
  printf 'fn main() {}\n' >"$root/crates/$name/src/lib.rs"
  printf '[package]\nname = "%s"\nversion = "0.1.0"\nedition = "2021"\n' "$name" \
    >"$root/crates/$name/Cargo.toml"
}

clean_root="$fixture_root/clean"
mkdir -p "$clean_root"
new_package "$clean_root" volward-core
printf '[workspace]\nmembers = ["crates/volward-core"]\nresolver = "2"\n' \
  >"$clean_root/Cargo.toml"
printf '[]\n' >"$fixture_root/empty-edges.json"
if ! python3 "$checker" --root "$clean_root" \
  --expected-edges "$fixture_root/empty-edges.json" >/dev/null; then
  printf 'cargo dependency checker test failed: clean workspace was rejected\n' >&2
  exit 1
fi

multiline_root="$fixture_root/multiline"
mkdir -p "$multiline_root"
new_package "$multiline_root" volward-core
new_package "$multiline_root" volward-facade
printf '[workspace]\nmembers = ["crates/volward-core", "crates/volward-facade"]\nresolver = "2"\n' \
  >"$multiline_root/Cargo.toml"
printf '\n[dependencies]\nvolward-core = {\n  version = "0.1.0",\n  path = "../volward-core",\n}\n' \
  >>"$multiline_root/crates/volward-facade/Cargo.toml"

if python3 "$checker" --root "$multiline_root" \
  --expected-edges "$fixture_root/empty-edges.json" >/dev/null 2>&1; then
  printf 'cargo dependency checker test failed: multiline edge was accepted\n' >&2
  exit 1
fi

printf 'cargo dependency checker tests: OK\n'
