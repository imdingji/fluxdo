# Build Rust DOH Proxy for Android and copy to Flutter jniLibs
# Usage: .\scripts\build_android.ps1 [-Debug]

param(
    [switch]$Debug
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$RustDir = Join-Path $ProjectRoot "core/doh_proxy"
$JniLibsDir = Join-Path $ProjectRoot "android\app\src\main\jniLibs"

if ($Debug) {
    $BuildType = "debug"
    $CargoFlag = ""
} else {
    $BuildType = "release"
    $CargoFlag = "--release"
}

Write-Host "=== Building Rust DOH Proxy for Android ($BuildType) ===" -ForegroundColor Cyan

# Check if cargo-ndk is installed
$cargoNdk = Get-Command cargo-ndk -ErrorAction SilentlyContinue
if (-not $cargoNdk) {
    Write-Host "Installing cargo-ndk..." -ForegroundColor Yellow
    cargo install cargo-ndk
}

# Check and add Android targets
Write-Host "Checking Rust Android targets..." -ForegroundColor Yellow
$targets = @(
    "aarch64-linux-android",
    "armv7-linux-androideabi",
    "x86_64-linux-android",
    "i686-linux-android"
)

$installedTargets = rustup target list --installed
foreach ($target in $targets) {
    if ($installedTargets -notcontains $target) {
        Write-Host "Adding target: $target" -ForegroundColor Yellow
        rustup target add $target
    }
}

# 自动生成证书（如果不存在）
$CaCert = Join-Path $RustDir "certs\ca.crt"
if (-not (Test-Path $CaCert)) {
    Write-Host "Generating CA certificates..." -ForegroundColor Yellow
    Push-Location $RustDir
    try { cargo run --bin gen_ca } finally { Pop-Location }
}

& (Join-Path $ScriptDir "sync_cert_resources.ps1")

# Build for all Android architectures
Write-Host "Building for all Android architectures..." -ForegroundColor Yellow
Push-Location $RustDir
try {
    if ($Debug) {
        cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -t x86 --platform 28 build --features ech
    } else {
        cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -t x86 --platform 28 build --release --features ech
    }
} finally {
    Pop-Location
}

# Create jniLibs directories
Write-Host "Creating jniLibs directories..." -ForegroundColor Yellow
$architectures = @("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
foreach ($arch in $architectures) {
    $dir = Join-Path $JniLibsDir $arch
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Copy libraries
Write-Host "Copying libraries to jniLibs..." -ForegroundColor Yellow

$copyMap = @{
    "aarch64-linux-android" = "arm64-v8a"
    "armv7-linux-androideabi" = "armeabi-v7a"
    "x86_64-linux-android" = "x86_64"
    "i686-linux-android" = "x86"
}

foreach ($rustTarget in $copyMap.Keys) {
    $androidArch = $copyMap[$rustTarget]
    $srcPath = Join-Path $RustDir "target\$rustTarget\$BuildType\libdoh_proxy.so"
    $dstPath = Join-Path $JniLibsDir "$androidArch\libdoh_proxy.so"

    if (Test-Path $srcPath) {
        Copy-Item -Path $srcPath -Destination $dstPath -Force
        Write-Host "  Copied: $androidArch/libdoh_proxy.so" -ForegroundColor Green
    } else {
        Write-Host "  Warning: $srcPath not found" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Build complete! ===" -ForegroundColor Green
Write-Host "Libraries copied to: $JniLibsDir"

# Show file sizes
foreach ($arch in $architectures) {
    $libPath = Join-Path $JniLibsDir "$arch\libdoh_proxy.so"
    if (Test-Path $libPath) {
        $size = (Get-Item $libPath).Length / 1MB
        Write-Host "  $arch/libdoh_proxy.so: $([math]::Round($size, 2)) MB"
    }
}
