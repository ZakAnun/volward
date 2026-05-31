#!/bin/bash
set -euo pipefail

# Resolve volward workspace from this script (macos/build_rust.sh → ../../..)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
export http_proxy="${http_proxy:-http://127.0.0.1:7890}"
export https_proxy="${https_proxy:-http://127.0.0.1:7890}"
export HTTP_PROXY="${HTTP_PROXY:-$http_proxy}"
export HTTPS_PROXY="${HTTPS_PROXY:-$https_proxy}"
export PATH="${HOME}/.cargo/bin:${PATH}"

cd "${WORKSPACE_ROOT}"
export CARGO_TARGET_DIR="${WORKSPACE_ROOT}/target"
if [ "${CONFIGURATION:-}" = "Debug" ]; then
  cargo build -p volward-facade
  DYLIB_SRC="${WORKSPACE_ROOT}/target/debug/libvolward_facade.dylib"
else
  cargo build --release -p volward-facade
  DYLIB_SRC="${WORKSPACE_ROOT}/target/release/libvolward_facade.dylib"
fi
FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
mkdir -p "${FRAMEWORKS_DIR}"
cp -f "${DYLIB_SRC}" "${FRAMEWORKS_DIR}/libvolward_facade.dylib"
install_name_tool -id "@rpath/libvolward_facade.dylib" "${FRAMEWORKS_DIR}/libvolward_facade.dylib" 2>/dev/null || true

echo "Volward Rust: copied ${DYLIB_SRC} -> ${FRAMEWORKS_DIR}"
