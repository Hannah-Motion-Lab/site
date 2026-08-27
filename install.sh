#!/usr/bin/env bash
# Hannah installer — the WHOLE companion, not just the window.
#
#   curl -fsSL https://hannah-motion-lab.github.io/site/install.sh | bash
#
# What it sets up, in order (each step is skipped if already done, so re-running is safe):
#   1. system packages (git, node, python, uv, unzip) via your distro's package manager
#   2. Ollama + the three models Hannah uses (brain, memory embeddings, vision)
#   3. the five repos under ~/Hannah-Motion (workspace, backend, frontend, motion-lab, agent)
#   4. Node deps for backend/frontend, Python venvs for the sidecars and the gesture model
#   5. the weights that are not in git: Kokoro voice (from upstream) and the trained
#      text→motion model (from Hannah's GitHub release)
#   6. bun + the agent (the "hands"), off by default until you add an API key
#   7. the overlay AppImage, and the `hannah` launcher on your PATH
#
# Why not a single package: the stack is ~20 GB of Python/CUDA environments and models that
# must be built and downloaded on YOUR machine (GPU-specific wheels, non-redistributable
# models). The AppImage alone is only the window — it needs all of this behind it.
set -euo pipefail

ORG="Hannah-Motion-Lab"
RELEASE_REPO="${ORG}/desktop"
ROOT="${HANNAH_HOME:-$HOME/Hannah-Motion}"
BIN_DIR="$HOME/.local/bin"
API="https://api.github.com/repos/${RELEASE_REPO}/releases/latest"
SITE="https://hannah-motion-lab.github.io/site"
DOCS="https://github.com/${ORG}/workspace#readme"
KOKORO="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"

if [ -t 1 ]; then
  C_INFO=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_INFO=""; C_WARN=""; C_ERR=""; C_DIM=""; C_OFF=""
fi
say()  { printf '%s\n' "${C_DIM}==>${C_OFF} ${C_INFO}$*${C_OFF}"; }
sub()  { printf '%s\n' "    ${C_DIM}$*${C_OFF}"; }
warn() { printf '%s\n' "${C_WARN}warning:${C_OFF} $*" >&2; }
die()  { printf '%s\n' "${C_ERR}error:${C_OFF} $*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# ── platform ──────────────────────────────────────────────────────────────────────────
case "$(uname -s -m)" in
  "Linux x86_64") ;;
  "Linux aarch64"|"Linux arm64") die "only x86_64 is supported right now (got $(uname -m))." ;;
  Darwin*) die "this installer supports Linux only. macOS: see ${DOCS}" ;;
  CYGWIN*|MINGW*|MSYS*) die "this installer supports Linux only. Windows: see ${DOCS}" ;;
  *) die "unsupported platform: $(uname -s -m)." ;;
esac

# ── 1. system packages ────────────────────────────────────────────────────────────────
say "system packages"
if has pacman; then
  PKG="sudo pacman -S --needed --noconfirm"; PKGS="git nodejs npm python python-pip uv unzip curl"
elif has apt-get; then
  PKG="sudo apt-get install -y"; PKGS="git nodejs npm python3 python3-pip python3-venv unzip curl"
elif has dnf; then
  PKG="sudo dnf install -y"; PKGS="git nodejs npm python3 python3-pip unzip curl"
else
  warn "unknown package manager: make sure git, node 20+, python 3.12+, unzip and curl are installed"; PKG=""; PKGS=""
fi
missing=""
for c in git node npm python3 unzip curl; do has "$c" || missing="$missing $c"; done
if [ -n "$missing" ] && [ -n "$PKG" ]; then
  sub "installing:$missing (needs sudo)"
  $PKG $PKGS
fi
has node || die "node is required (20+)."
node -e 'process.exit(parseInt(process.versions.node) >= 20 ? 0 : 1)' || die "node 20+ is required (found $(node -v))."
has python3 || die "python3 is required (3.12+)."
# uv creates the venvs far faster than pip; install it to the user if the distro has none.
if ! has uv; then
  sub "installing uv (fast Python installer) into ~/.local/bin"
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || warn "uv install failed; falling back to pip (slower)"
  export PATH="$HOME/.local/bin:$PATH"
fi
NVIDIA=""
if has nvidia-smi && nvidia-smi >/dev/null 2>&1; then NVIDIA=1; sub "NVIDIA GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
else warn "no NVIDIA GPU detected: the voice and gesture models will run on CPU (slower)."; fi

# ── 2. Ollama + models ────────────────────────────────────────────────────────────────
say "Ollama (the brain)"
if ! has ollama; then
  sub "installing Ollama"
  curl -fsSL https://ollama.com/install.sh | sh
fi
# Ollama is a SYSTEM service, not part of Hannah: it is never bundled, and this script never
# enrolls it with sudo. If it is already answering (however you run it) it is left alone; if
# not, it is started for this session only and you are told how to make that permanent.
if ! curl -sf -m 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  sub "starting ollama for this session (no sudo, no service enrolled)"
  (nohup ollama serve >/dev/null 2>&1 &) || true
  for _ in $(seq 1 20); do curl -sf -m 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break; sleep 1; done
  curl -sf -m 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 || die "ollama did not start. Run 'ollama serve' in another terminal and re-run this installer."
  warn "to have Ollama start at boot: systemctl --user enable --now ollama   (or: sudo systemctl enable --now ollama)"
else
  sub "ollama already running ✓ (left as is)"
fi
for m in qwen2.5:7b nomic-embed-text moondream; do
  if ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$m" ; then sub "$m ✓"
  else sub "pulling $m"; ollama pull "$m"; fi
done

# ── 3. repos ──────────────────────────────────────────────────────────────────────────
say "repos → $ROOT"
mkdir -p "$ROOT"
# git must never prompt for a password in a piped install: fail fast with a clear message.
export GIT_TERMINAL_PROMPT=0
clone() {  # clone <repo> <dir>
  if [ -d "$ROOT/$2/.git" ]; then (cd "$ROOT/$2" && git pull -q --ff-only 2>/dev/null || true); sub "$2 ✓ (updated)"
  else
    git clone -q "https://github.com/${ORG}/$1.git" "$ROOT/$2" 2>"$tmp/git.err" \
      || die "could not clone ${ORG}/$1: $(tail -1 "$tmp/git.err"). If the repo is private you need access; otherwise check your connection."
    sub "$2 ✓"
  fi
}
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# the workspace repo IS the root (launcher + docs); the others are its subfolders
if [ -d "$ROOT/.git" ]; then (cd "$ROOT" && git pull -q --ff-only 2>/dev/null || true); sub "workspace ✓ (updated)"
else
  git clone -q "https://github.com/${ORG}/workspace.git" "$ROOT.tmp" 2>"$tmp/git.err" \
    || die "could not clone ${ORG}/workspace: $(tail -1 "$tmp/git.err"). If the repo is private you need access; otherwise check your connection."
  cp -a "$ROOT.tmp/." "$ROOT/" && rm -rf "$ROOT.tmp"; sub "workspace ✓"
fi
clone backend      hannah-backend
clone frontend     hannah-frontend
clone motion-model hannah-motion-lab
clone agent        hannah-agent
clone desktop      hannah-desktop

# ── 4. dependencies ───────────────────────────────────────────────────────────────────
say "backend"
( cd "$ROOT/hannah-backend"
  [ -d node_modules ] || npm install --no-audit --no-fund
  if [ ! -f .env ]; then
    cp .env.example .env
    # defaults that make it work on the first try: the brain that is best at actions, and
    # the local ASR (the example points at the cloud, which needs an OpenAI key)
    sed -i 's/^LLM_MODEL=.*/LLM_MODEL=qwen2.5:7b/; s/^ASR_PROVIDER=.*/ASR_PROVIDER=local/' .env
    # the backend<->agent bearer: generated now so the agent is never reachable without it
    tok="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    sed -i "s|^#\?[[:space:]]*HANNAH_AGENT_TOKEN=.*|HANNAH_AGENT_TOKEN=$tok|" .env
    chmod 600 .env
    sub ".env created (edit it to enable tools/terminal/agent)"
  else sub ".env kept"; fi
  sub "python sidecars (voice, listening, vision)"
  cd sidecar
  if [ ! -x .venv/bin/python ]; then
    if has uv; then uv venv .venv --python 3.12 >/dev/null 2>&1 || uv venv .venv >/dev/null; uv pip install -q -r requirements.txt
    else python3 -m venv .venv && .venv/bin/pip install -q -r requirements.txt; fi
  fi
  sub "sidecars ✓"
)
say "frontend"
( cd "$ROOT/hannah-frontend"
  [ -d node_modules ] || npm install --legacy-peer-deps --no-audit --no-fund   # the flag is NOT optional
  sub "frontend ✓" )
say "gesture model (text → motion)"
( cd "$ROOT/hannah-motion-lab"
  if [ ! -x .venv/bin/python ]; then
    if has uv; then
      uv venv .venv --python 3.12 >/dev/null 2>&1 || uv venv .venv >/dev/null
      # torch must come from the CUDA 12.8 index (RTX 50xx needs it; older GPUs work too)
      if [ -n "$NVIDIA" ]; then uv pip install -q torch --index-url https://download.pytorch.org/whl/cu128
      else uv pip install -q torch --index-url https://download.pytorch.org/whl/cpu; fi
      uv pip install -q -r requirements.txt
    else
      python3 -m venv .venv
      if [ -n "$NVIDIA" ]; then .venv/bin/pip install -q torch --index-url https://download.pytorch.org/whl/cu128
      else .venv/bin/pip install -q torch --index-url https://download.pytorch.org/whl/cpu; fi
      .venv/bin/pip install -q -r requirements.txt
    fi
  fi
  sub "motion-lab ✓" )

# ── 5. weights that are not in git ────────────────────────────────────────────────────
say "model weights"
dl() { curl -fL --progress-bar -o "$2" "$1" || die "download failed: $1"; }
( cd "$ROOT/hannah-backend/sidecar/tts"
  [ -f kokoro-v1.0.onnx ] || { sub "Kokoro voice model (311 MB)"; dl "$KOKORO/kokoro-v1.0.onnx" kokoro-v1.0.onnx; }
  [ -f voices-v1.0.bin ]  || { sub "Kokoro voices (27 MB)";       dl "$KOKORO/voices-v1.0.bin"  voices-v1.0.bin; }
  sub "voice ✓" )
say "looking up the latest Hannah release"
code="$(curl -fsSL -o "$tmp/release.json" -w '%{http_code}' "$API" 2>/dev/null)" || true
[ "${code:-000}" = "200" ] || die "could not read the latest release (HTTP ${code:-network error}). https://github.com/${RELEASE_REPO}/releases"
asset() { grep -o "\"browser_download_url\": *\"[^\"]*$1\"" "$tmp/release.json" | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/'; }
( cd "$ROOT/hannah-motion-lab"
  mkdir -p runs/vae runs/flow
  [ -f runs/vae/latest.pt ]  || { sub "gesture model: vae (174 MB)";  dl "$(asset motion-vae-latest.pt)"  runs/vae/latest.pt; }
  [ -f runs/flow/latest.pt ] || { sub "gesture model: flow (213 MB)"; dl "$(asset motion-flow-latest.pt)" runs/flow/latest.pt; }
  sub "gestures ✓" )

# ── 6. the hands (agent) ──────────────────────────────────────────────────────────────
say "agent (the hands) — off until you add an API key"
export BUN_INSTALL="$HOME/.bun"; export PATH="$BUN_INSTALL/bin:$PATH"
if ! has bun; then sub "installing bun"; curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1 || warn "bun install failed; the agent will not be available"; fi
if has bun; then
  ( cd "$ROOT/hannah-agent"
    [ -d node_modules ] || bun install >/dev/null 2>&1
    [ -f "$HOME/.config/hannah-agent/hannah-agent.jsonc" ] || scripts/install-profile.sh --openrouter >/dev/null 2>&1 || true
    sub "agent ✓ (enable it later: AGENT_ENABLED=true + an OpenRouter key, in the ⚙ panel or .env)" )
fi

# ── 7. the overlay + launcher on PATH ─────────────────────────────────────────────────
say "overlay (AppImage)"
url="$(asset '.AppImage')"; [ -n "$url" ] || die "the latest release has no AppImage."
mkdir -p "$BIN_DIR"
if [ ! -x "$BIN_DIR/Hannah.AppImage" ]; then
  dl "$url" "$tmp/Hannah.AppImage"; mv -f "$tmp/Hannah.AppImage" "$BIN_DIR/Hannah.AppImage"; chmod +x "$BIN_DIR/Hannah.AppImage"
fi
sub "AppImage ✓"
# the launcher: `hannah` from anywhere brings up the stack and opens the overlay
chmod +x "$ROOT/hannah"
ln -sf "$ROOT/hannah" "$BIN_DIR/hannah"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not in your PATH. Add it with:"
     printf '       %s\n' "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc" ;;
esac

cat <<EOF

  ${C_INFO}Hannah is installed.${C_OFF}   ${C_DIM}($ROOT)${C_OFF}

  Run her (brings up the brain, voice, gestures and the overlay):

      ${C_WARN}hannah${C_OFF}

  Other commands:
      hannah doctor     what works on this desktop and what is missing
      hannah stop       shut everything down and free the GPU

  Optional, in ${ROOT}/hannah-backend/.env (or the ⚙ panel in the overlay):
      TOOLS_ENABLED=true          let her act (internet, open apps, commands)
      TOOLS_SYSTEM_CONTROL=true   a REAL terminal — read the security note first
      AGENT_ENABLED=true          multi-step tasks; needs an OpenRouter key with credits

  Docs: ${DOCS}
  Overlay won't stay on top / FUSE error? see the README, or run once with:
      ${BIN_DIR}/Hannah.AppImage --appimage-extract-and-run

EOF
