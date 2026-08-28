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
# the gesture model's weights (~400 MB, used by the Python motion server, not by the app):
# a release of their own so the app release only lists apps
MODELS_API="https://api.github.com/repos/${ORG}/motion-model/releases/tags/models"
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

# Everything below lives inside main() so a `curl | bash` that gets cut off half-way runs
# NOTHING: bash only executes the function once its closing brace has arrived.
main() {

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
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# third-party installers: to a file first, then run — never `curl | sh` (a cut-off download
# would otherwise run half a script). Their content is whatever the vendor serves today.
fetch_script() { curl -fsSL --proto '=https' --tlsv1.2 -o "$2" "$1"; }
# uv creates the venvs far faster than pip; install it to the user if the distro has none.
if ! has uv; then
  sub "installing uv (fast Python installer) into ~/.local/bin"
  fetch_script "https://astral.sh/uv/install.sh" "$tmp/uv-install.sh" && sh "$tmp/uv-install.sh" >/dev/null 2>&1 \
    || warn "uv install failed; falling back to pip (slower)"
  export PATH="$HOME/.local/bin:$PATH"
fi
NVIDIA=""
if has nvidia-smi && nvidia-smi >/dev/null 2>&1; then NVIDIA=1; sub "NVIDIA GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
else warn "no NVIDIA GPU detected: the voice and gesture models will run on CPU (slower)."; fi

# ── 2. Ollama + models ────────────────────────────────────────────────────────────────
# HANNAH_BRAIN=cloud: no Ollama, no local models — the brain is a provider (Groq/OpenAI/
# Anthropic/OpenRouter) whose key you paste in the ⚙ panel; vision and memory recall are off.
CLOUD=""; [ "${HANNAH_BRAIN:-}" = cloud ] && CLOUD=1
if [ -n "$CLOUD" ]; then say "brain: cloud provider (skipping Ollama and the local models)"; else
say "Ollama (the brain)"
if ! has ollama; then
  sub "installing Ollama"
  if [ "${PKG%% *}" = "sudo" ] && [ "$(echo "$PKG" | awk '{print $2}')" = "pacman" ]; then $PKG ollama
  else fetch_script "https://ollama.com/install.sh" "$tmp/ollama-install.sh" && sh "$tmp/ollama-install.sh"; fi
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
fi

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
# the workspace repo IS the root (launcher + docs); the others are its subfolders
if [ -d "$ROOT/.git" ]; then (cd "$ROOT" && git pull -q --ff-only 2>/dev/null || true); sub "workspace ✓ (updated)"
else
  rm -rf "$ROOT.tmp"   # a previous run that died mid-clone leaves this behind
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
    # cloud brain: Groq's OpenAI-compatible endpoint as the placeholder (switch provider + paste
    # the key in the ⚙ panel → Brain); no vision model and no local embeddings
    [ -n "$CLOUD" ] && sed -i 's|^LLM_BASE_URL=.*|LLM_BASE_URL=https://api.groq.com/openai/v1|; s/^LLM_API_KEY=.*/LLM_API_KEY=/; s/^LLM_MODEL=.*/LLM_MODEL=llama-3.3-70b-versatile/; s/^VISION_PROVIDER=.*/VISION_PROVIDER=off/; s/^#\{0,1\}[[:space:]]*MEMORY_RECALL=.*/MEMORY_RECALL=false/' .env
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
# download to a temp file, verify against SHA256SUMS when the release ships one, then move into
# place — a half-written file never gets the final name, and a tampered one never gets used.
dl() {
  local part="$2.part"
  curl -fL --proto '=https' --tlsv1.2 --progress-bar -o "$part" "$1" || { rm -f "$part"; die "download failed: $1"; }
  if [ -s "$tmp/SHA256SUMS" ]; then
    local want; want="$(grep -E " [*]?$(basename "$1")\$" "$tmp/SHA256SUMS" | awk '{print $1}' | head -1)"
    if [ -n "$want" ]; then
      local got; got="$(sha256sum "$part" | awk '{print $1}')"
      [ "$got" = "$want" ] || { rm -f "$part"; die "checksum mismatch for $(basename "$1") — the download is corrupt or tampered; nothing was installed"; }
    else warn "$(basename "$1") is not listed in SHA256SUMS: installed unverified"; fi
  fi
  mv -f "$part" "$2"
}
( cd "$ROOT/hannah-backend/sidecar/tts"
  [ -f kokoro-v1.0.onnx ] || { sub "Kokoro voice model (311 MB)"; dl "$KOKORO/kokoro-v1.0.onnx" kokoro-v1.0.onnx; }
  [ -f voices-v1.0.bin ]  || { sub "Kokoro voices (27 MB)";       dl "$KOKORO/voices-v1.0.bin"  voices-v1.0.bin; }
  sub "voice ✓" )
say "looking up the latest Hannah release"
code="$(curl -fsSL -o "$tmp/release.json" -w '%{http_code}' "$API" 2>/dev/null)" || true
[ "${code:-000}" = "200" ] || die "could not read the latest release (HTTP ${code:-network error}). https://github.com/${RELEASE_REPO}/releases"
asset() { grep -o "\"browser_download_url\": *\"[^\"]*$1\"" "$tmp/release.json" | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/'; }
sums="$(asset SHA256SUMS)"
if [ -n "$sums" ]; then curl -fsSL --proto '=https' --tlsv1.2 -o "$tmp/SHA256SUMS" "$sums" || warn "could not fetch SHA256SUMS: downloads will not be verified"
else warn "this release ships no SHA256SUMS: downloads will not be verified"; fi
say "gesture model (weights)"
code="$(curl -fsSL -o "$tmp/models.json" -w '%{http_code}' "$MODELS_API" 2>/dev/null)" || true
[ "${code:-000}" = "200" ] || die "could not read the models release (HTTP ${code:-network error}). https://github.com/${ORG}/motion-model/releases"
masset() { grep -o "\"browser_download_url\": *\"[^\"]*$1\"" "$tmp/models.json" | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/'; }
# swap in the models release's own checksums for these downloads
mv -f "$tmp/SHA256SUMS" "$tmp/SHA256SUMS.app" 2>/dev/null || true
msums="$(masset SHA256SUMS)"; [ -n "$msums" ] && curl -fsSL -o "$tmp/SHA256SUMS" "$msums" || warn "the models release ships no SHA256SUMS: weights will not be verified"
( cd "$ROOT/hannah-motion-lab"
  mkdir -p runs/vae runs/flow
  [ -f runs/vae/latest.pt ]  || { sub "gesture model: vae (174 MB)";  dl "$(masset motion-vae-latest.pt)"  runs/vae/latest.pt; }
  [ -f runs/flow/latest.pt ] || { sub "gesture model: flow (213 MB)"; dl "$(masset motion-flow-latest.pt)" runs/flow/latest.pt; }
  sub "gestures ✓" )
[ -f "$tmp/SHA256SUMS.app" ] && mv -f "$tmp/SHA256SUMS.app" "$tmp/SHA256SUMS"

# ── 6. the hands (agent) ──────────────────────────────────────────────────────────────
say "agent (the hands) — off until you add an API key"
export BUN_INSTALL="$HOME/.bun"; export PATH="$BUN_INSTALL/bin:$PATH"
if ! has bun; then sub "installing bun"; fetch_script "https://bun.sh/install" "$tmp/bun-install.sh" && bash "$tmp/bun-install.sh" >/dev/null 2>&1 || warn "bun install failed; the agent will not be available"; fi
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

$( [ -n "$CLOUD" ] && printf '  %sCloud brain:%s open the ⚙ panel → Brain, pick your provider and paste the API key. Nothing works until then.\n' "$C_WARN" "$C_OFF" )
  Optional, in ${ROOT}/hannah-backend/.env (or the ⚙ panel in the overlay):
      TOOLS_ENABLED=true          let her act (internet, open apps, commands)
      TOOLS_SYSTEM_CONTROL=true   a REAL terminal — read the security note first
      AGENT_ENABLED=true          multi-step tasks; needs an OpenRouter key with credits

  Docs: ${DOCS}
  Overlay won't stay on top / FUSE error? see the README, or run once with:
      ${BIN_DIR}/Hannah.AppImage --appimage-extract-and-run

EOF
}

main "$@"
