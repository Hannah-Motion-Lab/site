# Hannah: one-command install for Windows 10/11 (x64). No admin needed.
#
#   irm https://hannah-motion-lab.github.io/site/install.ps1 | iex
#
# Everything is installed for YOUR user only, nothing touches Program Files or the registry
# beyond your own PATH:
#   1. tools as portable copies in %USERPROFILE%\Hannah-Motion\.tools: Git (MinGit), Node 22;
#      uv (Python 3.12) and bun (the agent) in your profile
#   2. NOT the brain: on first run Hannah asks where she should think (Ollama here, installed
#      per-user if you say so, or a provider key)
#   3. clones the Hannah repos into %USERPROFILE%\Hannah-Motion
#   4. backend + voice/listening sidecars, the watches (hannah-sense, off by default) and the
#      gesture model (text → motion) on your NVIDIA card if there is one, else on the CPU
#   5. the overlay app from the latest release (per-user install, silent)
#   6. a `hannah` command: `hannah` brings everything up and opens the window,
#      `hannah stop` shuts it down, `hannah doctor` tells you what is running.
# If PowerShell refuses to run scripts:  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

function Install-Hannah {
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  $Org = 'Hannah-Motion-Lab'
  $Root = if ($env:HANNAH_HOME) { $env:HANNAH_HOME } else { Join-Path $env:USERPROFILE 'Hannah-Motion' }
  $Tools = Join-Path $Root '.tools'
  $Api = "https://api.github.com/repos/$Org/desktop/releases/latest"
  $Docs = "https://github.com/$Org/workspace/blob/main/SETUP.md#macos-and-windows"
  $Kokoro = 'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0'

  function Say($m)  { Write-Host "==> $m" -ForegroundColor Green }
  function Sub($m)  { Write-Host "    $m" -ForegroundColor DarkGray }
  function Warn($m) { Write-Host "warning: $m" -ForegroundColor Yellow }
  function Die($m)  { Write-Host "error: $m" -ForegroundColor Red; throw $m }
  function Has($c)  { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
  function Fetch($url, $out) { Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing }
  function Add-UserPath($dir) {
    if (-not (Test-Path $dir)) { return }
    $cur = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($cur -split ';') -notcontains $dir) { [Environment]::SetEnvironmentVariable('Path', "$dir;$cur", 'User') }
    if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$dir;$env:Path" }
  }

  if (-not [Environment]::Is64BitOperatingSystem) { Die 'Hannah needs 64-bit Windows.' }
  New-Item -ItemType Directory -Force -Path $Root, $Tools | Out-Null
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("hannah-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null

  # ── 1. tools, portable, in your profile ──────────────────────────────────────────────
  Say 'tools (portable copies in your profile, no admin)'
  if (-not (Has git)) {
    Sub 'Git (MinGit, portable)'
    $rel = Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest' -UseBasicParsing
    $a = $rel.assets | Where-Object { $_.name -match '^MinGit-[\d.]+-64-bit\.zip$' } | Select-Object -First 1
    if (-not $a) { Die 'could not find a MinGit build' }
    Fetch $a.browser_download_url "$tmp\git.zip"
    Expand-Archive "$tmp\git.zip" -DestinationPath "$Tools\git" -Force
    Add-UserPath "$Tools\git\cmd"
  }
  $nodeOk = (Has node) -and ([int]((node -p 'process.versions.node.split(".")[0]') 2>$null) -ge 20)
  if (-not $nodeOk) {
    Sub 'Node 22 (portable)'
    $idx = Invoke-WebRequest 'https://nodejs.org/dist/latest-v22.x/' -UseBasicParsing
    $zip = ([regex]'node-v22\.[\d.]+-win-x64\.zip').Match($idx.Content).Value
    if (-not $zip) { Die 'could not find a Node 22 build' }
    Fetch "https://nodejs.org/dist/latest-v22.x/$zip" "$tmp\node.zip"
    Expand-Archive "$tmp\node.zip" -DestinationPath "$tmp\node" -Force
    if (Test-Path "$Tools\node") { Remove-Item "$Tools\node" -Recurse -Force }
    Move-Item (Get-ChildItem "$tmp\node" | Select-Object -First 1).FullName "$Tools\node"
    Add-UserPath "$Tools\node"
  }
  if (-not (Has uv)) {
    Sub 'uv (Python 3.12 without touching the system)'
    Fetch 'https://astral.sh/uv/install.ps1' "$tmp\uv.ps1"
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$tmp\uv.ps1" | Out-Null
    Add-UserPath (Join-Path $env:USERPROFILE '.local\bin')
  }
  if (-not (Has bun)) {
    Sub 'bun (runs the agent)'
    try {
      Fetch 'https://bun.sh/install.ps1' "$tmp\bun.ps1"
      & powershell -NoProfile -ExecutionPolicy Bypass -File "$tmp\bun.ps1" | Out-Null
      Add-UserPath (Join-Path $env:USERPROFILE '.bun\bin')
    } catch { Warn 'bun install failed; the agent will not be available' }
  }
  # ── 2. the brain is NOT installed here ─────────────────────────────────────────────
  # Where Hannah thinks (Ollama on this PC, or a provider key) is chosen on the FIRST RUN, in
  # her window: she detects Ollama if you already have it, installs it per-user if you ask,
  # and downloads the models with a progress bar.

  # ── 3. repos ────────────────────────────────────────────────────────────────────────
  Say "code → $Root"
  function Clone($repo, $dir) {
    $d = Join-Path $Root $dir
    if (Test-Path (Join-Path $d '.git')) { Push-Location $d; git pull -q --ff-only 2>$null; Pop-Location; Sub "$dir ✓ (updated)" }
    else { git clone -q "https://github.com/$Org/$repo.git" $d; if ($LASTEXITCODE) { Die "could not clone $Org/$repo" }; Sub "$dir ✓" }
  }
  if (Test-Path (Join-Path $Root '.git')) { Push-Location $Root; git pull -q --ff-only 2>$null; Pop-Location; Sub 'workspace ✓ (updated)' }
  else {
    if (Test-Path "$Root.tmp") { Remove-Item "$Root.tmp" -Recurse -Force }
    git clone -q "https://github.com/$Org/workspace.git" "$Root.tmp"; if ($LASTEXITCODE) { Die "could not clone $Org/workspace" }
    Copy-Item "$Root.tmp\*" $Root -Recurse -Force; Remove-Item "$Root.tmp" -Recurse -Force; Sub 'workspace ✓'
  }
  Clone backend      hannah-backend
  Clone motion-model hannah-motion-lab
  Clone agent        hannah-agent

  # ── 4. backend + sidecars (CPU) ─────────────────────────────────────────────────────
  Say 'backend'
  $back = Join-Path $Root 'hannah-backend'
  Push-Location $back
  if (-not (Test-Path 'node_modules')) { npm install --no-audit --no-fund; if ($LASTEXITCODE) { Pop-Location; Die 'npm install failed in hannah-backend' } }
  if (-not (Test-Path '.env')) {
    $envText = Get-Content '.env.example' -Raw
    $envText = $envText -replace '(?m)^LLM_MODEL=.*$', 'LLM_MODEL=qwen2.5:7b' -replace '(?m)^ASR_PROVIDER=.*$', 'ASR_PROVIDER=local'
    $tok = -join ((1..48) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    $envText = $envText -replace '(?m)^#?\s*HANNAH_AGENT_TOKEN=.*$', "HANNAH_AGENT_TOKEN=$tok"
    Set-Content '.env' $envText -NoNewline
    Sub '.env created (edit it to enable tools/terminal/agent)'
  } else { Sub '.env kept' }
  Sub 'python sidecars (voice, listening), CPU'
  Push-Location 'sidecar'
  if (-not (Test-Path '.venv\Scripts\python.exe')) {
    uv venv .venv --python 3.12 | Out-Null; if ($LASTEXITCODE) { Pop-Location; Pop-Location; Die 'uv could not create the venv' }
    # onnxruntime-gpu needs CUDA libs we do not ship here; the vision (YOLO) extras are not needed
    (Get-Content 'requirements.txt') -replace '^onnxruntime-gpu==.*$', 'onnxruntime' | Where-Object { $_ -notmatch '^(ultralytics|pillow)' } | Set-Content "$tmp\req-win.txt"
    uv pip install -q -p .venv\Scripts\python.exe -r "$tmp\req-win.txt"; if ($LASTEXITCODE) { Pop-Location; Pop-Location; Die 'sidecar dependencies failed' }
  }
  Pop-Location
  Sub 'sidecars ✓'
  # the watches (hannah-sense, :8007): its own venv; on Windows R1/R5 use psutil (no pgrep/ss)
  Push-Location 'sidecar\sense'
  if (-not (Test-Path '.venv\Scripts\python.exe')) {
    uv venv .venv --python 3.12 | Out-Null; if ($LASTEXITCODE) { Pop-Location; Pop-Location; Die 'uv could not create the sense venv' }
    uv pip install -q -p .venv\Scripts\python.exe -r requirements.txt; if ($LASTEXITCODE) { Pop-Location; Pop-Location; Die 'sense dependencies failed' }
  }
  Pop-Location
  Sub 'hannah-sense ✓ (off until SENSE_ENABLED=true)'
  Say 'gesture model (text → motion)'
  $lab = Join-Path $Root 'hannah-motion-lab'
  Push-Location $lab
  if (-not (Test-Path '.venv\Scripts\python.exe')) {
    uv venv .venv --python 3.12 | Out-Null; if ($LASTEXITCODE) { Pop-Location; Die 'uv could not create the motion venv' }
    $nvidia = [bool](Get-Command nvidia-smi -ErrorAction SilentlyContinue)
    if ($nvidia) { Sub 'torch (CUDA 12.8)'; uv pip install -q -p .venv\Scripts\python.exe torch --index-url https://download.pytorch.org/whl/cu128 }
    else { Sub 'torch (CPU)'; uv pip install -q -p .venv\Scripts\python.exe torch --index-url https://download.pytorch.org/whl/cpu }
    if ($LASTEXITCODE) { Pop-Location; Die 'torch install failed' }
    uv pip install -q -p .venv\Scripts\python.exe -r requirements-serve.txt; if ($LASTEXITCODE) { Pop-Location; Die 'motion dependencies failed' }
  }
  Sub 'motion-lab ✓'
  $mrel = Invoke-RestMethod "https://api.github.com/repos/$Org/motion-model/releases/tags/models" -UseBasicParsing
  $msums = $mrel.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1
  $sumText = if ($msums) { (Invoke-WebRequest $msums.browser_download_url -UseBasicParsing).Content } else { '' }
  function Get-Weight($name, $dest) {
    if (Test-Path $dest) { return }
    $a = $mrel.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $a) { Die "the models release has no $name" }
    Sub "gesture model: $name"
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Fetch $a.browser_download_url "$dest.part"
    if ($sumText) {
      $want = (($sumText -split "`n" | Where-Object { $_ -match [regex]::Escape($name) + '$' } | Select-Object -First 1) -split '\s+')[0]
      $got = (Get-FileHash "$dest.part" -Algorithm SHA256).Hash.ToLower()
      if ($want -and $got -ne $want.ToLower()) { Remove-Item "$dest.part"; Die "checksum mismatch for $name" }
    }
    Move-Item -Force "$dest.part" $dest
  }
  Get-Weight 'motion-vae-latest.pt'  (Join-Path $lab 'runs\vae\latest.pt')
  Get-Weight 'motion-flow-latest.pt' (Join-Path $lab 'runs\flow\latest.pt')
  Sub 'gestures ✓'
  Pop-Location
  Say 'voice model'
  $tts = Join-Path $back 'sidecar\tts'
  if (-not (Test-Path "$tts\kokoro-v1.0.onnx")) { Sub 'Kokoro voice model (311 MB)'; Fetch "$Kokoro/kokoro-v1.0.onnx" "$tts\kokoro-v1.0.onnx" }
  if (-not (Test-Path "$tts\voices-v1.0.bin"))  { Sub 'Kokoro voices (27 MB)';       Fetch "$Kokoro/voices-v1.0.bin"  "$tts\voices-v1.0.bin" }
  Sub 'voice ✓'
  Pop-Location

  # ── 5. the hands (agent) ────────────────────────────────────────────────────────────
  Say 'agent (the hands), off until you add an API key'
  if (Has bun) {
    Push-Location (Join-Path $Root 'hannah-agent')
    if (-not (Test-Path 'node_modules')) { bun install 2>$null | Out-Null }
    Pop-Location
    Sub 'agent ✓ (enable it later: AGENT_ENABLED=true + a key, in the ⚙ panel or .env)'
  }

  # ── 6. the overlay app (per-user, silent) ───────────────────────────────────────────
  Say 'overlay app'
  $rel = Invoke-RestMethod $Api -UseBasicParsing
  $asset = $rel.assets | Where-Object { $_.name -like '*-win-x64.exe' } | Select-Object -First 1
  if (-not $asset) { Die 'the latest release has no Windows build.' }
  $appExe = Join-Path $env:LOCALAPPDATA 'Programs\Hannah\Hannah.exe'
  $ver = ($asset.name -replace '^Hannah-([\d.]+)-.*$', '$1')
  $installed = if (Test-Path $appExe) { (Get-Item $appExe).VersionInfo.ProductVersion } else { '' }
  if ($installed -eq $ver) { Sub "Hannah.exe ✓ (already $ver)" }
  else {
    Fetch $asset.browser_download_url "$tmp\HannahSetup.exe"
    $sums = $rel.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1
    if ($sums) {
      $want = ((Invoke-WebRequest $sums.browser_download_url -UseBasicParsing).Content -split "`n" | Where-Object { $_ -match [regex]::Escape($asset.name) + '$' } | Select-Object -First 1) -split '\s+' | Select-Object -First 1
      $got = (Get-FileHash "$tmp\HannahSetup.exe" -Algorithm SHA256).Hash.ToLower()
      if ($want -and $got -ne $want.ToLower()) { Die "checksum mismatch for $($asset.name), nothing was installed" }
    } else { Warn 'no SHA256SUMS: the app was not verified' }
    # NSIS one-click, per-user (no UAC): lands in %LOCALAPPDATA%\Programs\Hannah
    Start-Process -Wait -FilePath "$tmp\HannahSetup.exe" -ArgumentList '/S'
    if (-not (Test-Path $appExe)) { Die "the app did not install to $appExe" }
    Sub "Hannah $ver → $appExe ✓"
  }

  # ── 7. the launcher ─────────────────────────────────────────────────────────────────
  Add-UserPath $Root
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

  Write-Host ''
  Write-Host "  Hannah is installed.   ($Root)" -ForegroundColor Green
  Write-Host ''
  Write-Host '  Open a NEW terminal (so the PATH is fresh) and run her:'
  Write-Host ''
  Write-Host '      hannah' -ForegroundColor Yellow
  Write-Host ''
  Write-Host '  Other commands:   hannah doctor   ·   hannah stop'
  Write-Host ''
  Write-Host '  Nothing else was installed: no Ollama, no language model, that is her first question.'
  Write-Host '  Voice and listening run on the CPU; the gestures on your NVIDIA card if there is one, else on the CPU'
  Write-Host '  (each sentence takes a bit longer to prepare, but she moves while she speaks).'
  Write-Host '  SmartScreen may show "Windows protected your PC" the first time: More info → Run anyway.'
  Write-Host ''
  Write-Host "  Docs: $Docs"
  Write-Host ''
}

Install-Hannah
