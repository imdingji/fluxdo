#!/usr/bin/env bash

set -euo pipefail

BUNDLE_DIR="${1:-}"

if [[ -z "${BUNDLE_DIR}" || ! -d "${BUNDLE_DIR}" ]]; then
  echo "Usage: $0 <bundle-dir>" >&2
  exit 1
fi

BUNDLE_LIB_DIR="${BUNDLE_DIR}/lib"
PLUGIN_LIB="${BUNDLE_LIB_DIR}/libflutter_inappwebview_linux_plugin.so"

if [[ ! -f "${PLUGIN_LIB}" ]]; then
  echo "No flutter_inappwebview Linux plugin found at ${PLUGIN_LIB}, skipping WPE bundling"
  exit 0
fi

declare -A SEEN=()
declare -a QUEUE=("${PLUGIN_LIB}")

while [[ "${#QUEUE[@]}" -gt 0 ]]; do
  CURRENT="${QUEUE[0]}"
  QUEUE=("${QUEUE[@]:1}")

  while read -r resolved_path; do
    [[ -n "${resolved_path}" ]] || continue

    base_name="$(basename "${resolved_path}")"

    if [[ ! "${base_name}" =~ ^lib(WPE|wpe) ]]; then
      continue
    fi

    if [[ -n "${SEEN[${resolved_path}]:-}" ]]; then
      continue
    fi

    SEEN["${resolved_path}"]=1
    echo "==> Copying ${resolved_path}"
    cp -L -n "${resolved_path}" "${BUNDLE_LIB_DIR}/"
    QUEUE+=("${resolved_path}")
  done < <(ldd "${CURRENT}" | awk '/=> \// { print $3 }')
done
