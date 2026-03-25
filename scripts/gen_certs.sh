#!/bin/bash
# 生成 CA 证书（如果不存在）
# 用于本地开发：运行此脚本确保证书文件存在
# CI 中由 build.yaml 直接调用 cargo run --bin gen_ca
#
# Usage: ./scripts/gen_certs.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/core/doh_proxy"

if [ -f "$RUST_DIR/certs/ca.crt" ] && [ -f "$RUST_DIR/certs/ca.key" ] && [ -f "$RUST_DIR/certs/ca.der" ]; then
    echo "CA certificates already exist, skipping generation."
    exit 0
fi

echo "Generating CA certificates..."
(cd "$RUST_DIR" && cargo run --bin gen_ca)
"$SCRIPT_DIR/sync_cert_resources.sh"
echo "CA certificates generated successfully."
