#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/core/doh_proxy"

CERT_CRT="$RUST_DIR/certs/ca.crt"
CERT_DER="$RUST_DIR/certs/ca.der"
ASSETS_DIR="$PROJECT_ROOT/assets/certs"
ANDROID_RAW_DIR="$PROJECT_ROOT/android/app/src/main/res/raw"

if [[ ! -f "$CERT_CRT" || ! -f "$CERT_DER" ]]; then
    echo "CA certificate artifacts not found, skipping resource sync."
    exit 0
fi

mkdir -p "$ASSETS_DIR"
mkdir -p "$ANDROID_RAW_DIR"

cp "$CERT_CRT" "$ASSETS_DIR/proxy_ca.pem"
cp "$CERT_DER" "$ANDROID_RAW_DIR/proxy_ca.der"

echo "Synced CA resources to assets and Android raw directory."
