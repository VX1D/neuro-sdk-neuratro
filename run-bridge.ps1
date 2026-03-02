if ($null -eq $env:NEURO_SDK_WS_URL -or $env:NEURO_SDK_WS_URL -eq "") {
  $env:NEURO_SDK_WS_URL = "ws://127.0.0.1:8000"
}

$modRoot = Join-Path $env:APPDATA "Balatro\Mods\neuro-game"

if ($null -eq $env:NEURO_IPC_DIR -or $env:NEURO_IPC_DIR -eq "") {
  if (Test-Path -LiteralPath $modRoot) {
    $env:NEURO_IPC_DIR = Join-Path $modRoot "ipc"
  } else {
    Write-Host "ERROR: neuro-game mod not found at $modRoot"
    Write-Host "Copy the neuro-game folder to $modRoot first"
    exit 1
  }
}

Write-Host "Bridge using IPC directory: $env:NEURO_IPC_DIR"
Write-Host "Bridge connecting to: $env:NEURO_SDK_WS_URL"

if (!(Test-Path $env:NEURO_IPC_DIR)) {
  New-Item -ItemType Directory -Force -Path $env:NEURO_IPC_DIR | Out-Null
}

Set-Location (Join-Path $PSScriptRoot "neuro-bridge-rs")
cargo run --release
