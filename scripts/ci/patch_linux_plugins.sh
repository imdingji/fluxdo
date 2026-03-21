#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"
PATCHED=0

declare -a SEARCH_ROOTS=()

if [[ -d "${PUB_CACHE_DIR}" ]]; then
  SEARCH_ROOTS+=("${PUB_CACHE_DIR}")
fi

if [[ -d "${PROJECT_ROOT}/.pub-cache" ]]; then
  SEARCH_ROOTS+=("${PROJECT_ROOT}/.pub-cache")
fi

if [[ "${#SEARCH_ROOTS[@]}" -eq 0 ]]; then
  echo "==> No pub cache directory found, skipping flutter_secure_storage_linux patch"
  exit 0
fi

mapfile -t JSON_HEADERS < <(find "${SEARCH_ROOTS[@]}" -path '*flutter_secure_storage_linux-*/linux/include/json.hpp' 2>/dev/null | sort -u)

for header in "${JSON_HEADERS[@]}"; do
  if grep -q 'operator "" _json' "${header}"; then
    echo "==> Patching ${header}"
    sed -i \
      -e 's/operator "" _json/operator""_json/g' \
      -e 's/operator "" _json_pointer/operator""_json_pointer/g' \
      "${header}"
    PATCHED=1
  fi
done

if [[ "${PATCHED}" -eq 0 ]]; then
  echo "==> No flutter_secure_storage_linux json.hpp patch needed"
fi
