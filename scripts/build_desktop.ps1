# Build Rust DOH Proxy for Desktop (Windows)
# Usage: .\scripts\build_desktop.ps1 [-Debug]

param(
    [switch]$Debug
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$RustDir = Join-Path $ProjectRoot "core/doh_proxy"

if ($Debug) {
    $BuildType = "debug"
    $CargoFlag = ""
} else {
    $BuildType = "release"
    $CargoFlag = "--release"
}

Write-Host "=== Building Rust DOH Proxy for Windows ($BuildType) ===" -ForegroundColor Cyan

# 自动生成证书（如果不存在）
$CaCert = Join-Path $RustDir "certs\ca.crt"
if (-not (Test-Path $CaCert)) {
    Write-Host "Generating CA certificates..." -ForegroundColor Yellow
    Push-Location $RustDir
    try { cargo run --bin gen_ca } finally { Pop-Location }
}

& (Join-Path $ScriptDir "sync_cert_resources.ps1")

# Build
Push-Location $RustDir
try {
    if ($Debug) {
        cargo build
    } else {
        cargo build --release
    }
} finally {
    Pop-Location
}

$exePath = Join-Path $RustDir "target\$BuildType\doh_proxy_bin.exe"

if (Test-Path $exePath) {
    $size = (Get-Item $exePath).Length / 1MB
    Write-Host ""
    Write-Host "=== Build complete! ===" -ForegroundColor Green
    Write-Host "Executable: $exePath"
    Write-Host "Size: $([math]::Round($size, 2)) MB"
} else {
    Write-Host "Build failed: $exePath not found" -ForegroundColor Red
    exit 1
}
