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
if (!(Test-Path $bin)) {
  Write-Host "Bridge binary not found at $bin, building..."
  cargo build --release
}
& $bin
