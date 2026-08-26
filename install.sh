#!/usr/bin/env bash
set -euo pipefail

REPO="Hannah-Motion-Lab/desktop"
APP="Hannah.AppImage"
BIN_DIR="$HOME/.local/bin"
API="https://api.github.com/repos/${REPO}/releases/latest"
SITE="https://hannah-motion-lab.github.io/site"
DOCS="https://github.com/Hannah-Motion-Lab/workspace#readme"

if [ -t 1 ]; then
  C_INFO=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_INFO=""; C_WARN=""; C_ERR=""; C_DIM=""; C_OFF=""
fi

say()  { printf '%s\n' "${C_DIM}==>${C_OFF} ${C_INFO}$*${C_OFF}"; }
warn() { printf '%s\n' "${C_WARN}warning:${C_OFF} $*" >&2; }
die()  { printf '%s\n' "${C_ERR}error:${C_OFF} $*" >&2; exit 1; }

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<EOF
Hannah installer

Downloads the latest Hannah AppImage from ${REPO}
releases and installs it to ${BIN_DIR}/${APP}.

Usage: curl -fsSL ${SITE}/install.sh | bash
EOF
  exit 0
fi

command -v curl >/dev/null 2>&1 || die "curl is required. Install it with your package manager and try again."

case "$(uname -s -m)" in
  "Linux x86_64") ;;
  "Linux aarch64"|"Linux arm64") die "only x86_64 builds are packaged right now (got $(uname -m))." ;;
  Darwin*) die "this installer supports Linux only. macOS builds are on the way." ;;
  CYGWIN*|MINGW*|MSYS*) die "this installer supports Linux only. Windows builds are on the way." ;;
  *) die "unsupported platform: $(uname -s -m)." ;;
esac

say "looking for the latest release..."
json="$(curl -fsSL "$API")" || die "could not reach GitHub. Check your connection and try again."
url="$(printf '%s' "$json" \
  | grep -o '"browser_download_url": *"[^"]*\.AppImage"' \
  | head -n1 \
  | sed 's/.*"\(https[^"]*\)"/\1/')"
[ -n "$url" ] || die "no release published yet. Watch ${SITE} or https://github.com/${REPO}/releases for v1.0.0."

say "found $(basename "$url")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "downloading..."
curl -fL --progress-bar -o "$tmp/$APP" "$url" || die "download failed. Try again or grab it directly from https://github.com/${REPO}/releases"

mkdir -p "$BIN_DIR"
mv -f "$tmp/$APP" "$BIN_DIR/$APP"
chmod +x "$BIN_DIR/$APP"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    warn "$BIN_DIR is not in your PATH. Add it with:"
    printf '       %s\n' "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
    ;;
esac

cat <<EOF

  ${C_INFO}Hannah is installed.${C_OFF}

  Run her:

      ${C_WARN}${BIN_DIR}/${APP}${C_OFF}

  Notes:
   - The app is the floating overlay (it forces XWayland so it can stay on top).
     The full companion stack (LLM brain, voice, memory) still runs locally:
     see ${DOCS}
   - If it complains about FUSE, install libfuse2, or run once with:
         ${BIN_DIR}/${APP} --appimage-extract-and-run

EOF
