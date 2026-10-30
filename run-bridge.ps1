if ($null -eq $env:NEURO_SDK_WS_URL -or $env:NEURO_SDK_WS_URL -eq "") {
  $env:NEURO_SDK_WS_URL = "ws://127.0.0.1:8000"
}

function Get-WebSocketUrlInfo {
  param([AllowEmptyString()][string]$Raw)

  $invalid = "<invalid websocket URL>"
  $result = [pscustomobject]@{ Valid = $false; Safe = $invalid; Reason = "invalid URL" }
  if ([string]::IsNullOrWhiteSpace($Raw) -or $Raw -match '[\s\p{Cc}]') {
    $result.Reason = "URL is empty or contains whitespace/control characters"
    return $result
  }
  $parsed = $null
  if (![Uri]::TryCreate($Raw, [UriKind]::Absolute, [ref]$parsed)
      -or $null -eq $parsed
      -or $parsed.Scheme -notin @("ws", "wss")
      -or [string]::IsNullOrEmpty($parsed.Host)
      -or $parsed.Fragment -ne "") {
    $result.Reason = "URL must be an absolute ws:// or wss:// URL without a fragment"
    return $result
  }
  $port = $parsed.Port
  if ($port -eq -1) {
    # ws/wss have defined default ports even when System.Uri reports none.
    $port = if ($parsed.Scheme -eq "ws") { 80 } else { 443 }
  }
  if ($port -lt 1 -or $port -gt 65535) {
    $result.Reason = "URL port is outside 1..65535"
    return $result
  }
  # Authority excludes path/query/fragment; remove userinfo without relying on
  # scheme casing so credentials never reach launcher logs.
  $authority = $parsed.Authority
  $at = $authority.LastIndexOf("@")
  if ($at -ge 0) {
    $authority = $authority.Substring($at + 1)
  }
  if ([string]::IsNullOrEmpty($authority)) {
    $result.Reason = "URL authority is empty"
    return $result
  }
  $result.Valid = $true
  $result.Safe = "$($parsed.Scheme.ToLowerInvariant())://$authority"
  $result.Reason = ""
  return $result
}

$wsInfo = Get-WebSocketUrlInfo -Raw $env:NEURO_SDK_WS_URL
if (!$wsInfo.Valid) {
  Write-Host "FATAL: invalid NEURO_SDK_WS_URL ($($wsInfo.Reason))." -ForegroundColor Red
  exit 1
}
$safeWsUrl = $wsInfo.Safe

# Relative IPC paths cannot identify the same directory from launcher,
# direct-relay, and installed-mod processes. Require one absolute root.
$stableRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
function Resolve-IpcPath {
  param([string]$Value)
  if (![System.IO.Path]::IsPathRooted($Value)) {
    throw "IPC path must be absolute"
  }
  return [System.IO.Path]::GetFullPath($Value)
}

function Try-PrepareIpcDirectory {
  param([AllowEmptyString()][string]$Candidate, [string]$Source)

  $value = if ($null -ne $Candidate) { $Candidate.Trim() } else { "" }
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $null
  }
  if ($value -match '[\x00-\x1F"\x60$;|&<>]') {
    Write-Warning "Could not prepare $Source IPC directory '$value': unsafe path"
    return $null
  }
  try {
    $resolved = Resolve-IpcPath $value
    if (!(Test-Path -LiteralPath $resolved -PathType Container)) {
      New-Item -ItemType Directory -Force -ErrorAction Stop -LiteralPath $resolved | Out-Null
    }
    if (!(Test-Path -LiteralPath $resolved -PathType Container)) {
      throw "path is not a directory"
    }
    return $resolved
  } catch {
    Write-Warning "Could not prepare $Source IPC directory '$value': $($_.Exception.Message)"
    return $null
  }
}


$ipcDir = $null
$envCandidate = if ($null -ne $env:NEURO_IPC_DIR) { $env:NEURO_IPC_DIR.Trim() } else { "" }
if (![string]::IsNullOrWhiteSpace($envCandidate)) {
  $ipcDir = Try-PrepareIpcDirectory $envCandidate "NEURO_IPC_DIR"
  if ($null -eq $ipcDir) {
    Write-Host "FATAL: NEURO_IPC_DIR must be one canonical absolute path." -ForegroundColor Red
    exit 1
  }
}

function Get-MarkerIpcDirectory {
  param([string]$Root)
  $marker = Join-Path $Root "neuro_ipc_dir.txt"
  if (!(Test-Path -LiteralPath $marker -PathType Leaf)) {
    $legacy = "$marker.txt"
    if (!(Test-Path -LiteralPath $legacy -PathType Leaf)) {
      return $null
    }
    $marker = $legacy
  }
  $configured = Get-Content -Raw -ErrorAction Stop -LiteralPath $marker
  if ([string]::IsNullOrWhiteSpace($configured)) {
    return $null
  }
  $prepared = Try-PrepareIpcDirectory $configured "IPC marker"
  if ($null -eq $prepared) {
    throw "IPC marker must contain one canonical absolute path: $marker"
  }
  return $prepared
}

function Add-MarkerRoot {
  param([string]$Root)
  $found = Get-MarkerIpcDirectory $Root
  if ($null -eq $found) {
    return
  }
  if ($null -eq $script:ipcDir) {
    $script:ipcDir = $found
  } elseif ($script:ipcDir -ne $found) {
    throw "conflicting IPC markers; set NEURO_IPC_DIR explicitly"
  }
}

if ($null -eq $ipcDir) {
  $appDataForMarker = if ($null -ne $env:APPDATA) { $env:APPDATA.Trim() } else { "" }
  if ($appDataForMarker -ne "" -and [System.IO.Path]::IsPathRooted($appDataForMarker)) {
    Add-MarkerRoot (Join-Path $appDataForMarker "Balatro\Mods\neuro-game")
    Add-MarkerRoot (Join-Path $appDataForMarker "Balatro\Mods\neuro_game")
  }
}

if ($null -eq $ipcDir) {
  $appData = if ($null -ne $env:APPDATA) { $env:APPDATA.Trim() } else { "" }
  if ($appData -eq "") {
    Write-Host "FATAL: no canonical IPC directory; set NEURO_IPC_DIR or create an absolute marker." -ForegroundColor Red
    exit 1
  }
  if (![System.IO.Path]::IsPathRooted($appData)) {
    Write-Host "FATAL: APPDATA is not an absolute path; set NEURO_IPC_DIR." -ForegroundColor Red
    exit 1
  }
  $ipcDir = Try-PrepareIpcDirectory (Join-Path $appData "Balatro\neuro-ipc") "APPDATA default"
  if ($null -eq $ipcDir) {
    Write-Host "FATAL: could not prepare APPDATA IPC directory." -ForegroundColor Red
    exit 1
  }
}

$env:NEURO_IPC_DIR = $ipcDir

Write-Host "Bridge using IPC directory: $env:NEURO_IPC_DIR"
Write-Host "Bridge connecting to: $safeWsUrl"
$released = Get-ChildItem -Path $stableRoot -Filter "neuro-bridge-*-windows-x86_64.exe" -File -ErrorAction SilentlyContinue |
  Sort-Object Name | Select-Object -Last 1
if ($null -ne $released) {
  Write-Host "Running released bridge: $($released.Name)"
  & $released.FullName
  exit $LASTEXITCODE
}

Set-Location -Path (Join-Path $stableRoot "neuro-bridge-rs") -ErrorAction Stop


$bin = ".\target\release\neuro-bridge.exe"

# Cargo fingerprinting is authoritative; build failures must not run stale binaries.
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
