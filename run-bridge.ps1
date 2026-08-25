if ($null -eq $env:NEURO_SDK_WS_URL -or $env:NEURO_SDK_WS_URL -eq "") {
  $env:NEURO_SDK_WS_URL = "ws://127.0.0.1:8000"
}

if ($null -eq $env:NEURO_IPC_DIR -or $env:NEURO_IPC_DIR -eq "") {
  $env:NEURO_IPC_DIR = Join-Path $env:APPDATA "Balatro\neuro-ipc"
}

Write-Host "Bridge using IPC directory: $env:NEURO_IPC_DIR"
Write-Host "Bridge connecting to: $env:NEURO_SDK_WS_URL"

if (!(Test-Path $env:NEURO_IPC_DIR)) {
  New-Item -ItemType Directory -Force -Path $env:NEURO_IPC_DIR | Out-Null
}

Set-Location (Join-Path $PSScriptRoot "neuro-bridge-rs")

$bin = "target\release\neuro-bridge.exe"

# Always invoke cargo: its own fingerprinting (mtimes, Cargo.toml, deps, env) is the
# authoritative "does this need a rebuild" check, not a hand-rolled file comparison.
# A stale binary must never run silently, so build failure here is fatal.
$buildOutput = cargo build --release 2>&1 | Tee-Object -Variable buildOutputVar
if ($LASTEXITCODE -ne 0) {
  Write-Host "FATAL: cargo build failed; refusing to run a possibly stale binary." -ForegroundColor Red
  exit 1
}
if ($buildOutputVar -match "Compiling neuro-bridge ") {
  Write-Host "rebuilt: source was newer than the binary."
} else {
  Write-Host "skipped rebuild: binary already up to date with source (cargo fingerprint match)."
}

if (!(Test-Path $bin)) {
  Write-Host "FATAL: build reported success but binary is missing at $bin" -ForegroundColor Red
  exit 1
}
& $bin
