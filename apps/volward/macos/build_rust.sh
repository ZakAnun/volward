#!/bin/bash
set -euo pipefail

# Resolve volward workspace from this script (macos/build_rust.sh → ../../..)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Honor explicit proxy env; otherwise only default to local 7890 if it looks alive.
# (Forcing a dead 127.0.0.1:7890 breaks cargo for contributors without a local proxy.)
if [[ -z "${http_proxy:-${HTTP_PROXY:-}}" && -z "${https_proxy:-${HTTPS_PROXY:-}}" ]]; then
  if curl -fsS --connect-timeout 1 "http://127.0.0.1:7890" >/dev/null 2>&1 \
    || nc -z -G 1 127.0.0.1 7890 >/dev/null 2>&1; then
    export http_proxy="http://127.0.0.1:7890"
    export https_proxy="http://127.0.0.1:7890"
  fi
else
  export http_proxy="${http_proxy:-${HTTP_PROXY:-}}"
  export https_proxy="${https_proxy:-${HTTPS_PROXY:-}}"
fi
export HTTP_PROXY="${HTTP_PROXY:-${http_proxy:-}}"
export HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy:-}}"
export PATH="${HOME}/.cargo/bin:${PATH}"

cd "${WORKSPACE_ROOT}"
export CARGO_TARGET_DIR="${WORKSPACE_ROOT}/target"
if [ "${CONFIGURATION:-Debug}" = "Debug" ]; then
  cargo build -p volward-facade
  DYLIB_SRC="${WORKSPACE_ROOT}/target/debug/libvolward_facade.dylib"
else
  cargo build --release -p volward-facade
  DYLIB_SRC="${WORKSPACE_ROOT}/target/release/libvolward_facade.dylib"
fi

copy_dylib() {
  local dest_dir="$1"
  mkdir -p "${dest_dir}"
  cp -f "${DYLIB_SRC}" "${dest_dir}/libvolward_facade.dylib"
  install_name_tool -id "@rpath/libvolward_facade.dylib" "${dest_dir}/libvolward_facade.dylib" 2>/dev/null || true
  # install_name_tool invalidates any code signature. Ad-hoc sign so Xcode can
  # embed the dylib (CI Intel runners fail CodeSign on unsigned nested binaries).
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --timestamp=none --sign - "${dest_dir}/libvolward_facade.dylib"
  fi
  echo "Volward Rust: copied ${DYLIB_SRC} -> ${dest_dir}/libvolward_facade.dylib"
}

if [ -n "${BUILT_PRODUCTS_DIR:-}" ] && [ -n "${FRAMEWORKS_FOLDER_PATH:-}" ]; then
  copy_dylib "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
else
  # Standalone (e.g. manual run after `flutter run` without Xcode env vars).
  FLUTTER_APP_ROOT="${SCRIPT_DIR}/../build/macos/Build/Products"
  copied=0
  for config in Debug Release; do
    dest="${FLUTTER_APP_ROOT}/${config}/volward.app/Contents/Frameworks"
    if [ -d "${FLUTTER_APP_ROOT}/${config}/volward.app" ]; then
      copy_dylib "${dest}"
      copied=1
    fi
  done
  if [ "${copied}" -eq 0 ]; then
    echo "Volward Rust: built ${DYLIB_SRC} (no .app bundle found — run a full macOS build next)"
  fi
fi

if [ -n "${DERIVED_FILE_DIR:-}" ]; then
  mkdir -p "${DERIVED_FILE_DIR}"
  touch "${DERIVED_FILE_DIR}/volward_rust_build.stamp"
fi
