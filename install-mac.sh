#!/usr/bin/env bash
# Hannah — one-command install for macOS (Apple Silicon or Intel). No admin needed.
#
#   curl -fsSL https://hannah-motion-lab.github.io/site/install-mac.sh | bash
#
# What it does, all inside your home folder:
#   1. tools: Node 22 (private copy), uv (Python 3.12), bun (the agent), Ollama (CLI build)
#   2. Ollama models: qwen2.5:7b (the brain) and moondream (vision)
#   3. clones the Hannah repos into ~/Hannah-Motion
#   4. backend + voice/listening sidecars on the CPU (no CUDA on macOS → no gesture model;
#      the avatar keeps its procedural idle)
#   5. the overlay app from the latest release (unsigned: the quarantine flag is removed)
#   6. a `hannah` command on your PATH: `hannah` brings everything up and opens the window,
#      `hannah stop` shuts it down, `hannah doctor` tells you what is running.
# Needs: git (Xcode Command Line Tools — the ONE thing that may ask an admin) and curl.
set -u

ORG="Hannah-Motion-Lab"
RELEASE_REPO="${ORG}/desktop"
ROOT="${HANNAH_HOME:-$HOME/Hannah-Motion}"
BIN_DIR="$HOME/.local/bin"
TOOLS="$ROOT/.tools"
API="https://api.github.com/repos/${RELEASE_REPO}/releases/latest"
DOCS="https://github.com/${ORG}/workspace/blob/main/SETUP.md#macos-and-windows"
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
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# Everything lives inside main() so a `curl | bash` that gets cut off half-way runs NOTHING.
main() {

# ── platform ──────────────────────────────────────────────────────────────────────────
[ "$(uname -s)" = Darwin ] || die "this installer is for macOS. Linux: install.sh · Windows: install.ps1 (see the site)."
case "$(uname -m)" in
  arm64) ARCH=arm64; NODE_ARCH=darwin-arm64 ;;
  x86_64) ARCH=x64; NODE_ARCH=darwin-x64 ;;
  *) die "unsupported CPU: $(uname -m)" ;;
esac
has curl || die "curl is required."
has git  || die "git is required. Run: xcode-select --install   (Apple's Command Line Tools; this is the one step that may ask for an admin) and re-run."
mkdir -p "$BIN_DIR" "$TOOLS" "$HOME/Applications"
export PATH="$BIN_DIR:$HOME/.bun/bin:$TOOLS/node/bin:$PATH"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fetch() { curl -fL --proto '=https' --tlsv1.2 --progress-bar -o "$2" "$1" || die "download failed: $1"; }
fetch_script() { curl -fsSL --proto '=https' --tlsv1.2 -o "$2" "$1"; }

# ── 1. tools, all in $HOME ────────────────────────────────────────────────────────────
say "tools (in your home folder, no admin)"
node_ok() { has node && [ "$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)" -ge 20 ]; }
if ! node_ok; then
  sub "Node 22 (private copy in $TOOLS/node)"
  tgz="$(curl -fsSL https://nodejs.org/dist/latest-v22.x/ | grep -oE "node-v22\.[0-9.]+-${NODE_ARCH}\.tar\.gz" | head -1)"
  [ -n "$tgz" ] || die "could not find a Node 22 build for ${NODE_ARCH}"
  fetch "https://nodejs.org/dist/latest-v22.x/$tgz" "$tmp/node.tgz"
  rm -rf "$TOOLS/node"; mkdir -p "$TOOLS/node"; tar -xzf "$tmp/node.tgz" -C "$TOOLS/node" --strip-components=1
  for b in node npm npx; do ln -sf "$TOOLS/node/bin/$b" "$BIN_DIR/$b"; done
fi
node_ok || die "Node 20+ still not usable (is $BIN_DIR on your PATH?)"
if ! has uv; then
  sub "uv (Python 3.12 without touching the system)"
  fetch_script "https://astral.sh/uv/install.sh" "$tmp/uv.sh" && sh "$tmp/uv.sh" >/dev/null 2>&1 || die "uv install failed"
fi
if ! has bun; then
  sub "bun (runs the agent)"
  fetch_script "https://bun.sh/install" "$tmp/bun.sh" && bash "$tmp/bun.sh" >/dev/null 2>&1 || warn "bun install failed; the agent will not be available"
fi
if ! has ollama && [ "${HANNAH_BRAIN:-}" != cloud ]; then
  sub "Ollama (CLI build, ~160 MB — the .app is not needed)"
  fetch "https://github.com/ollama/ollama/releases/latest/download/ollama-darwin.tgz" "$tmp/ollama.tgz"
  mkdir -p "$TOOLS/ollama"; tar -xzf "$tmp/ollama.tgz" -C "$TOOLS/ollama"
  bin="$(find "$TOOLS/ollama" -type f -name ollama -perm -u+x | head -1)"; [ -n "$bin" ] || die "ollama binary not found in the archive"
  ln -sf "$bin" "$BIN_DIR/ollama"
fi

# ── 2. Ollama + models ────────────────────────────────────────────────────────────────
# HANNAH_BRAIN=cloud: no Ollama, no local models — the brain is a provider whose key you paste
# in the ⚙ panel; vision and memory recall are off.
CLOUD=""; [ "${HANNAH_BRAIN:-}" = cloud ] && CLOUD=1
if [ -n "$CLOUD" ]; then say "brain: cloud provider (skipping Ollama and the local models)"; else
say "Ollama (the brain)"
if ! curl -sf -m 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  sub "starting ollama serve"
  (nohup ollama serve >"$HOME/.ollama-hannah.log" 2>&1 &)
  for _ in $(seq 1 20); do curl -sf -m 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break; sleep 1; done
  curl -sf -m 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 || die "ollama did not start. Run 'ollama serve' in another terminal and re-run."
fi
for m in qwen2.5:7b nomic-embed-text moondream; do
  if ollama list 2>/dev/null | grep -q "^$m"; then sub "$m ✓"; else sub "pulling $m (this is the long part)"; ollama pull "$m" || die "could not pull $m"; fi
done
fi

# ── 3. repos ──────────────────────────────────────────────────────────────────────────
say "code → $ROOT"
mkdir -p "$ROOT"
clone() {
  if [ -d "$ROOT/$2/.git" ]; then (cd "$ROOT/$2" && git pull -q --ff-only 2>/dev/null || true); sub "$2 ✓ (updated)"
  else git clone -q "https://github.com/${ORG}/$1.git" "$ROOT/$2" || die "could not clone ${ORG}/$1"; sub "$2 ✓"; fi
}
if [ -d "$ROOT/.git" ]; then (cd "$ROOT" && git pull -q --ff-only 2>/dev/null || true); sub "workspace ✓ (updated)"
else
  rm -rf "$ROOT.tmp"; git clone -q "https://github.com/${ORG}/workspace.git" "$ROOT.tmp" || die "could not clone ${ORG}/workspace"
  cp -a "$ROOT.tmp/." "$ROOT/" && rm -rf "$ROOT.tmp"; sub "workspace ✓"
fi
clone backend hannah-backend
clone agent   hannah-agent

# ── 4. backend + sidecars (CPU) ───────────────────────────────────────────────────────
say "backend"
( cd "$ROOT/hannah-backend"
  [ -d node_modules ] || npm install --no-audit --no-fund
  if [ ! -f .env ]; then
    cp .env.example .env
    # local brain + local listening; the gesture model is CUDA-only, so it stays off here
    sed -i '' 's/^LLM_MODEL=.*/LLM_MODEL=qwen2.5:7b/; s/^ASR_PROVIDER=.*/ASR_PROVIDER=local/; s/^MOTION_ENABLED=.*/MOTION_ENABLED=false/' .env
    [ -n "$CLOUD" ] && sed -i '' 's|^LLM_BASE_URL=.*|LLM_BASE_URL=https://api.groq.com/openai/v1|; s/^LLM_API_KEY=.*/LLM_API_KEY=/; s/^LLM_MODEL=.*/LLM_MODEL=llama-3.3-70b-versatile/; s/^VISION_PROVIDER=.*/VISION_PROVIDER=off/; s/^#\{0,1\}[[:space:]]*MEMORY_RECALL=.*/MEMORY_RECALL=false/' .env
    tok="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    sed -i '' "s|^#\{0,1\}[[:space:]]*HANNAH_AGENT_TOKEN=.*|HANNAH_AGENT_TOKEN=$tok|" .env
    chmod 600 .env
    sub ".env created (edit it to enable tools/terminal/agent)"
  else sub ".env kept"; fi
  sub "python sidecars (voice, listening) — CPU"
  cd sidecar
  if [ ! -x .venv/bin/python ]; then
    uv venv .venv --python 3.12 >/dev/null || die "uv could not create the venv"
    # onnxruntime-gpu has no macOS wheel; the vision (YOLO) extras are not needed here
    sed -e 's/^onnxruntime-gpu==.*/onnxruntime/' -e '/^ultralytics/d' -e '/^pillow/d' requirements.txt > "$tmp/req-mac.txt"
    uv pip install -q -p .venv/bin/python -r "$tmp/req-mac.txt" || die "sidecar dependencies failed"
  fi
  sub "sidecars ✓" )
say "voice model"
( cd "$ROOT/hannah-backend/sidecar/tts"
  [ -f kokoro-v1.0.onnx ] || { sub "Kokoro voice model (311 MB)"; fetch "$KOKORO/kokoro-v1.0.onnx" kokoro-v1.0.onnx; }
  [ -f voices-v1.0.bin ]  || { sub "Kokoro voices (27 MB)";       fetch "$KOKORO/voices-v1.0.bin"  voices-v1.0.bin; }
  sub "voice ✓" )

# ── 5. the hands (agent) ──────────────────────────────────────────────────────────────
say "agent (the hands) — off until you add an API key"
if has bun; then
  ( cd "$ROOT/hannah-agent"
    [ -d node_modules ] || bun install >/dev/null 2>&1
    [ -f "$HOME/.config/hannah-agent/hannah-agent.jsonc" ] || scripts/install-profile.sh --openrouter >/dev/null 2>&1 || true
    sub "agent ✓ (enable it later: AGENT_ENABLED=true + a key, in the ⚙ panel or .env)" )
fi

# ── 6. the overlay app ────────────────────────────────────────────────────────────────
say "overlay app (macOS $ARCH)"
code="$(curl -fsSL -o "$tmp/release.json" -w '%{http_code}' "$API" 2>/dev/null)" || true
[ "${code:-000}" = "200" ] || die "could not read the latest release (HTTP ${code:-network error}). https://github.com/${RELEASE_REPO}/releases"
asset() { grep -o "\"browser_download_url\": *\"[^\"]*$1\"" "$tmp/release.json" | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/'; }
url="$(asset "-mac-${ARCH}.dmg")"; [ -n "$url" ] || die "the latest release has no macOS ($ARCH) build."
sums="$(asset SHA256SUMS)"
if [ -d "$HOME/Applications/Hannah.app" ] && [ "$(defaults read "$HOME/Applications/Hannah.app/Contents/Info" CFBundleShortVersionString 2>/dev/null)" = "$(basename "$url" | sed -E 's/^Hannah-([0-9.]+)-.*/\1/')" ]; then
  sub "Hannah.app ✓ (already this version)"
else
  fetch "$url" "$tmp/Hannah.dmg"
  if [ -n "$sums" ] && curl -fsSL -o "$tmp/SHA256SUMS" "$sums"; then
    want="$(grep -E " [*]?$(basename "$url")\$" "$tmp/SHA256SUMS" | awk '{print $1}' | head -1)"
    got="$(shasum -a 256 "$tmp/Hannah.dmg" | awk '{print $1}')"
    [ -z "$want" ] || [ "$got" = "$want" ] || die "checksum mismatch for $(basename "$url") — nothing was installed"
  else warn "no SHA256SUMS: the app was not verified"; fi
  mnt="$tmp/dmg"; mkdir -p "$mnt"
  hdiutil attach -nobrowse -quiet -mountpoint "$mnt" "$tmp/Hannah.dmg" || die "could not mount the dmg"
  rm -rf "$HOME/Applications/Hannah.app"
  cp -R "$mnt/Hannah.app" "$HOME/Applications/Hannah.app" || { hdiutil detach -quiet "$mnt"; die "could not copy Hannah.app"; }
  hdiutil detach -quiet "$mnt" || true
  # unsigned build: without this macOS says the app "is damaged"/"can't be opened"
  xattr -dr com.apple.quarantine "$HOME/Applications/Hannah.app" 2>/dev/null || true
  sub "Hannah.app → ~/Applications ✓"
fi

# ── 7. the launcher ───────────────────────────────────────────────────────────────────
chmod +x "$ROOT/hannah-mac"
ln -sf "$ROOT/hannah-mac" "$BIN_DIR/hannah"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not in your PATH. Add it with:"
     printf '       %s\n' "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" ;;
esac

cat <<EOF

  ${C_INFO}Hannah is installed.${C_OFF}   ${C_DIM}($ROOT)${C_OFF}

  Run her (brings up the brain, voice and the overlay):

      ${C_WARN}hannah${C_OFF}

  Other commands:
      hannah doctor     what is running
      hannah stop       shut everything down

  On macOS the voice runs on the CPU (a second or two per sentence) and there is no gesture
  model (CUDA only): the avatar breathes and looks around, but does not gesture while speaking.

$( [ -n "$CLOUD" ] && printf '  %sCloud brain:%s open the ⚙ panel → Brain, pick your provider and paste the API key. Nothing works until then.\n' "$C_WARN" "$C_OFF" )
  Optional, in ${ROOT}/hannah-backend/.env (or the ⚙ panel in the overlay):
      TOOLS_ENABLED=true          let her act (internet, open apps, commands)
      AGENT_ENABLED=true          multi-step tasks; needs an API key with credits

  Docs: ${DOCS}

EOF
}

main "$@"
