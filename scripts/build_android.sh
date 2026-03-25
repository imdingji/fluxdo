#!/bin/bash
# Build Rust DOH Proxy for Android and copy to Flutter jniLibs
# Usage: ./scripts/build_android.sh [--release]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/core/doh_proxy"
JNILIBS_DIR="$PROJECT_ROOT/android/app/src/main/jniLibs"

# Default to release build
BUILD_TYPE="release"
CARGO_FLAG="--release"

if [ "$1" == "--debug" ]; then
    BUILD_TYPE="debug"
    CARGO_FLAG=""
fi

echo "=== Building Rust DOH Proxy for Android ($BUILD_TYPE) ==="

# Check if cargo-ndk is installed
if ! command -v cargo-ndk &> /dev/null; then
    echo "Installing cargo-ndk..."
    cargo install cargo-ndk
fi

# Check if Android targets are installed
echo "Checking Rust Android targets..."
for target in aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android; do
    if ! rustup target list --installed | grep -q "$target"; then
        echo "Adding target: $target"
        rustup target add "$target"
    fi
done

# 自动生成证书（如果不存在）
if [ ! -f "$RUST_DIR/certs/ca.crt" ]; then
    echo "Generating CA certificates..."
    (cd "$RUST_DIR" && cargo run --bin gen_ca)
fi

"$SCRIPT_DIR/sync_cert_resources.sh"

# Build for all Android architectures
echo "Building for all Android architectures..."
cd "$RUST_DIR"
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -t x86 --platform 28 build $CARGO_FLAG --features ech

# Create jniLibs directories
echo "Creating jniLibs directories..."
mkdir -p "$JNILIBS_DIR/arm64-v8a"
mkdir -p "$JNILIBS_DIR/armeabi-v7a"
mkdir -p "$JNILIBS_DIR/x86_64"
mkdir -p "$JNILIBS_DIR/x86"

# Copy libraries
echo "Copying libraries to jniLibs..."
cp "$RUST_DIR/target/aarch64-linux-android/$BUILD_TYPE/libdoh_proxy.so" "$JNILIBS_DIR/arm64-v8a/"
cp "$RUST_DIR/target/armv7-linux-androideabi/$BUILD_TYPE/libdoh_proxy.so" "$JNILIBS_DIR/armeabi-v7a/"
cp "$RUST_DIR/target/x86_64-linux-android/$BUILD_TYPE/libdoh_proxy.so" "$JNILIBS_DIR/x86_64/"
cp "$RUST_DIR/target/i686-linux-android/$BUILD_TYPE/libdoh_proxy.so" "$JNILIBS_DIR/x86/"

echo ""
echo "=== Build complete! ==="
echo "Libraries copied to: $JNILIBS_DIR"
ls -la "$JNILIBS_DIR"/*/libdoh_proxy.so
