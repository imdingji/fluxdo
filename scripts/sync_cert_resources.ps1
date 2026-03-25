param()

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$RustDir = Join-Path $ProjectRoot "core/doh_proxy"

$certCrt = Join-Path $RustDir "certs\ca.crt"
$certDer = Join-Path $RustDir "certs\ca.der"
$assetsDir = Join-Path $ProjectRoot "assets\certs"
$androidRawDir = Join-Path $ProjectRoot "android\app\src\main\res\raw"

if (-not (Test-Path $certCrt) -or -not (Test-Path $certDer)) {
    Write-Host "CA certificate artifacts not found, skipping resource sync." -ForegroundColor Yellow
    exit 0
}

New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null
New-Item -ItemType Directory -Force -Path $androidRawDir | Out-Null

Copy-Item -Path $certCrt -Destination (Join-Path $assetsDir "proxy_ca.pem") -Force
Copy-Item -Path $certDer -Destination (Join-Path $androidRawDir "proxy_ca.der") -Force

Write-Host "Synced CA resources to assets and Android raw directory." -ForegroundColor Green
