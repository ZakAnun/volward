#!/usr/bin/env bash
# Bootstrap a macOS developer machine for Volward:
# toolchains, Flutter/Rust deps, and local Apple Development signing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/volward"
MACOS_DIR="$APP_DIR/macos"
LOCAL_TEAM_FILE="$MACOS_DIR/Runner/Configs/TeamSettings.local.xcconfig"

ASSUME_YES=0
SKIP_BUILD=0
FORCE_TEAM=""

usage() {
  cat <<'EOF'
Usage: bash scripts/setup_macos.sh [options]

Options:
  -y, --yes           Non-interactive; auto-pick only when a single personal Team exists
  --team <TEAM_ID>    Force DEVELOPMENT_TEAM (10-char Apple Team ID)
  --skip-build        Skip compiling libvolward_facade (still runs cargo fetch)
  -h, --help          Show this help

Typical first-time flow:
  1. Open Xcode → Settings → Accounts → sign in with your Apple ID (once)
  2. bash scripts/setup_macos.sh
  3. cd apps/volward && bash scripts/run_macos_debug.sh
EOF
}

log() { printf '==> %s\n' "$*" >&2; }
ok() { printf '    ok: %s\n' "$*" >&2; }
warn() { printf '    warn: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Run a command with a soft timeout (seconds). Returns 124 on timeout.
run_with_timeout() {
  local seconds="$1"
  shift
  perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1; shift ;;
    --team)
      [[ $# -ge 2 ]] || die "--team requires a Team ID"
      FORCE_TEAM="$2"
      shift 2
      ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

# Ensure common tool locations are visible even in non-login shells.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
export PATH="${HOME}/.cargo/bin:${HOME}/.pub-cache/bin:${HOME}/fvm/default/bin:${HOME}/.fvm_flutter/bin:${PATH}"

# Reuse proxy if unset; only default to local 7890 when a gateway appears to be listening.
export http_proxy="${http_proxy:-${HTTP_PROXY:-}}"
export https_proxy="${https_proxy:-${HTTPS_PROXY:-}}"
if [[ -z "${http_proxy}" && -z "${https_proxy}" ]]; then
  if curl -fsS --connect-timeout 1 --max-time 2 "http://127.0.0.1:7890" >/dev/null 2>&1 \
    || nc -z -G 1 127.0.0.1 7890 >/dev/null 2>&1; then
    export http_proxy="http://127.0.0.1:7890"
    export https_proxy="http://127.0.0.1:7890"
  fi
fi
export HTTP_PROXY="${HTTP_PROXY:-$http_proxy}"
export HTTPS_PROXY="${HTTPS_PROXY:-$https_proxy}"

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "this setup script only supports macOS"
}

read_xcode_version() {
  local plist="/Applications/Xcode.app/Contents/Info.plist"
  if [[ -f "$plist" ]]; then
    plutil -extract CFBundleShortVersionString raw "$plist" 2>/dev/null && return 0
  fi
  # Fallback only; xcodebuild can hang while waiting for first-launch UI / license.
  run_with_timeout 8 xcodebuild -version 2>/dev/null | awk 'NR==1{print; exit}'
}

check_xcode() {
  log "Checking Xcode / Command Line Tools"
  if ! xcode-select -p >/dev/null 2>&1; then
    die "Xcode Command Line Tools missing. Run: xcode-select --install"
  fi
  ok "developer dir: $(xcode-select -p)"

  if [[ ! -d /Applications/Xcode.app ]]; then
    die "Xcode.app not found under /Applications. Install Xcode from the App Store, open it once, then re-run setup."
  fi

  local xcode_ver
  xcode_ver="$(read_xcode_version || true)"
  ok "Xcode present (${xcode_ver:-unknown})"

  # Cheap existence check only — avoid a blocking `xcodebuild -version`.
  if [[ ! -x /usr/bin/xcodebuild && ! -x "$(xcode-select -p)/usr/bin/xcodebuild" ]]; then
    die "xcodebuild not found. Open Xcode once to finish installation, then re-run setup."
  fi
}

ensure_brew() {
  if command -v brew >/dev/null 2>&1; then
    ok "Homebrew $(brew --version | head -1)"
    return
  fi
  log "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  command -v brew >/dev/null 2>&1 || die "Homebrew install finished but brew not on PATH"
  ok "Homebrew installed"
}

ensure_brew_pkg() {
  local pkg="$1"
  if [[ "$pkg" == "protobuf" ]] && command -v protoc >/dev/null 2>&1; then
    ok "protoc already on PATH ($(protoc --version 2>/dev/null | head -1))"
    return
  fi
  if brew list --formula "$pkg" >/dev/null 2>&1; then
    ok "brew $pkg already installed"
    return
  fi
  log "Installing brew formula: $pkg"
  brew install "$pkg"
  ok "brew $pkg installed"
}

ensure_rust() {
  log "Checking Rust toolchain"
  if ! command -v rustc >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
    if ! command -v rustup >/dev/null 2>&1; then
      log "Installing rustup (stable)"
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
      # shellcheck disable=SC1091
      [[ -f "${HOME}/.cargo/env" ]] && source "${HOME}/.cargo/env"
    fi
    command -v rustc >/dev/null 2>&1 || die "rustc not found after rustup install"
    command -v cargo >/dev/null 2>&1 || die "cargo not found after rustup install"
  fi

  if command -v rustup >/dev/null 2>&1; then
    if ! rustup show active-toolchain >/dev/null 2>&1; then
      rustup default stable >/dev/null 2>&1 || warn "could not set rustup default stable (network?); using existing rustc"
    fi
  fi

  ok "$(rustc --version)"
  ok "$(cargo --version)"
}

ensure_fvm_flutter() {
  log "Checking FVM + Flutter (stable)"
  if ! command -v fvm >/dev/null 2>&1; then
    local installed=0
    if command -v brew >/dev/null 2>&1; then
      log "Installing FVM via Homebrew"
      if brew install fvm; then
        installed=1
      elif brew tap leoafarias/fvm >/dev/null 2>&1 && brew install fvm; then
        installed=1
      else
        warn "Homebrew FVM install failed; trying other methods"
      fi
    fi
    if [[ "$installed" -eq 0 ]] && command -v dart >/dev/null 2>&1; then
      log "Installing FVM via dart pub global activate"
      dart pub global activate fvm && installed=1 || warn "dart pub global activate fvm failed"
    fi
    if [[ "$installed" -eq 0 ]]; then
      log "Installing FVM via https://fvm.app/install.sh"
      curl -fsSL https://fvm.app/install.sh | bash
      export PATH="${HOME}/fvm/default/bin:${HOME}/.fvm_flutter/bin:${PATH}"
    fi
  fi
  command -v fvm >/dev/null 2>&1 || die "fvm still not on PATH after install. Open a new terminal or add FVM to PATH, then re-run."
  ok "fvm $(fvm --version 2>/dev/null | head -1 || echo present)"

  (
    cd "$APP_DIR"
    fvm install
    fvm use stable
    fvm flutter config --enable-macos-desktop >/dev/null 2>&1 \
      || warn "could not enable macOS desktop via flutter config (continuing)"
    fvm flutter --version
  )
  ok "Flutter stable ready via FVM"
}

fetch_flutter_deps() {
  log "Fetching Flutter packages"
  (
    cd "$APP_DIR"
    fvm flutter pub get
  )
  ok "flutter pub get done"
}

fetch_rust_deps() {
  log "Fetching Rust crates"
  (
    cd "$ROOT_DIR"
    export CARGO_TARGET_DIR="${ROOT_DIR}/target"
    cargo fetch
  )
  ok "cargo fetch done"
}

build_rust_dylib() {
  if [[ "$SKIP_BUILD" -eq 1 ]]; then
    log "Skipping Rust dylib build (--skip-build)"
    return
  fi
  log "Building libvolward_facade (Debug)"
  (
    cd "$MACOS_DIR"
    bash build_rust.sh
  )
  ok "Rust dylib build finished"
}

# Print "TEAM_ID|ORG" lines for Apple Development certificates (unique by Team ID).
list_development_teams() {
  local pem team org subject
  while IFS= read -r -d '' pem; do
    subject="$(
      printf '%s' "$pem" | openssl x509 -noout -subject 2>/dev/null || true
    )"
    [[ -n "$subject" ]] || continue
    team="$(printf '%s\n' "$subject" | sed -n 's/.*OU=\([A-Z0-9]\{10\}\).*/\1/p')"
    org="$(printf '%s\n' "$subject" | sed -n 's/.*O=\([^,]*\).*/\1/p')"
    [[ -n "$team" ]] && printf '%s|%s\n' "$team" "${org:-unknown}"
  done < <(
    security find-certificate -a -c "Apple Development" -p 2>/dev/null |
      awk '
        /-----BEGIN CERTIFICATE-----/ { cert=$0 ORS; in_cert=1; next }
        in_cert { cert=cert $0 ORS }
        /-----END CERTIFICATE-----/ {
          printf "%s%c", cert, 0
          cert=""
          in_cert=0
        }
      '
  ) | awk -F'|' 'NF && !seen[$1]++ {print $0}'
}

# Heuristic: company orgs usually contain Ltd/Inc/Co./Company/Technology.
is_personal_org() {
  local org="$1"
  [[ ! "$org" =~ (Ltd\.?|Inc\.?|LLC|Corp\.?|Company|Technology|Technologies|Co\.) ]]
}

read_existing_team() {
  if [[ -f "$LOCAL_TEAM_FILE" ]] \
    && grep -Eq '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{10}[[:space:]]*$' "$LOCAL_TEAM_FILE"; then
    sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*\([A-Z0-9]\{10\}\)[[:space:]]*$/\1/p' "$LOCAL_TEAM_FILE" | head -1
  fi
}

write_team_file() {
  local team="$1"
  [[ "$team" =~ ^[A-Z0-9]{10}$ ]] || die "invalid Team ID: $team"
  mkdir -p "$(dirname "$LOCAL_TEAM_FILE")"
  cat >"$LOCAL_TEAM_FILE" <<EOF
// Generated by scripts/setup_macos.sh — do not commit.
// Personal/local Apple Development Team ID for Automatic signing.
DEVELOPMENT_TEAM = ${team}
EOF
  ok "wrote $LOCAL_TEAM_FILE (DEVELOPMENT_TEAM = ${team})"
}

setup_signing() {
  log "Configuring macOS Debug signing (TeamSettings.local.xcconfig)"

  if [[ -n "$FORCE_TEAM" ]]; then
    write_team_file "$FORCE_TEAM"
    return
  fi

  local existing
  existing="$(read_existing_team || true)"
  if [[ -n "$existing" ]]; then
    ok "existing DEVELOPMENT_TEAM = $existing (kept)"
    return
  fi

  log "Scanning Keychain for Apple Development certificates…"
  local teams=()
  local orgs=()
  local personal_idxs=()
  local entry team org i
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    team="${entry%%|*}"
    org="${entry#*|}"
    teams+=("$team")
    orgs+=("$org")
    if is_personal_org "$org"; then
      personal_idxs+=("$((${#teams[@]} - 1))")
    fi
  done < <(list_development_teams)

  if [[ ${#teams[@]} -eq 0 ]]; then
    cat >&2 <<EOF
error: no Apple Development certificate found in Keychain.

Do this once, then re-run setup:
  1. Open Xcode → Settings → Accounts
  2. Sign in with your Apple ID
  3. Select the team → Manage Certificates… → (+) Apple Development
  4. bash scripts/setup_macos.sh

Or set the Team ID manually:
  bash scripts/setup_macos.sh --team YOUR_TEAM_ID

Or non-interactive:
  bash scripts/setup_macos.sh --team YOUR_TEAM_ID
EOF
    exit 1
  fi

  if [[ ${#teams[@]} -eq 1 ]]; then
    write_team_file "${teams[0]}"
    return
  fi

  log "Multiple Development Team IDs found:"
  for i in "${!teams[@]}"; do
    printf '  [%d] %s  (%s)\n' "$((i + 1))" "${teams[$i]}" "${orgs[$i]}"
  done

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    if [[ ${#personal_idxs[@]} -eq 1 ]]; then
      i="${personal_idxs[0]}"
      warn "non-interactive: selecting personal team ${teams[$i]} (${orgs[$i]})"
      write_team_file "${teams[$i]}"
      return
    fi
    die "multiple Team IDs found; re-run with --team <TEAM_ID> (see list above). -y will only auto-pick when exactly one personal team is present."
  fi

  local choice
  while true; do
    read -r -p "Select team [1-${#teams[@]}] (prefer your Personal Team): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#teams[@]} )); then
      write_team_file "${teams[$((choice - 1))]}"
      return
    fi
    warn "invalid choice"
  done
}

verify_signing_config() {
  log "Verifying signing config"
  bash "$MACOS_DIR/scripts/verify_debug_signing.sh"
}

print_next_steps() {
  cat <<EOF

Setup complete.

Next:
  cd apps/volward
  bash scripts/run_macos_debug.sh

Notes:
  - TeamSettings.local.xcconfig is gitignored; each machine keeps its own Team ID.
  - If crates.io / pub.dev time out, export http_proxy/https_proxy (see README).
  - Full Disk Access is only needed at runtime for deep Library scans, not for build.
EOF
}

main() {
  require_macos
  log "Volward macOS setup (root: $ROOT_DIR)"
  check_xcode
  # Fail fast on missing Apple ID / cert before long dependency installs.
  setup_signing
  ensure_brew
  ensure_brew_pkg protobuf
  ensure_rust
  ensure_fvm_flutter
  fetch_flutter_deps
  fetch_rust_deps
  build_rust_dylib
  verify_signing_config
  print_next_steps
}

main
