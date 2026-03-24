#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILES_LIST="${ROOT_DIR}/integrity/files.txt"
MANIFEST_PATH="${ROOT_DIR}/integrity/manifest.sha256"
MODE="${1:-check}"

if [[ ! -f "${FILES_LIST}" ]]; then
  echo "Missing integrity file list: ${FILES_LIST}" >&2
  exit 1
fi

generate_manifest() {
  local rel
  while IFS= read -r rel || [[ -n "${rel}" ]]; do
    if [[ -z "${rel}" || "${rel}" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    local abs="${ROOT_DIR}/${rel}"
    if [[ ! -f "${abs}" ]]; then
      echo "Missing tracked file: ${rel}" >&2
      exit 1
    fi

    sha256sum "${abs}" | sed "s#${ROOT_DIR}/##"
  done < "${FILES_LIST}"
}

case "${MODE}" in
  update)
    generate_manifest > "${MANIFEST_PATH}"
    echo "Updated integrity manifest: ${MANIFEST_PATH}"
    ;;
  check)
    if [[ ! -f "${MANIFEST_PATH}" ]]; then
      echo "Missing integrity manifest: ${MANIFEST_PATH}" >&2
      exit 1
    fi
    tmp_file="$(mktemp)"
    trap 'rm -f "${tmp_file}"' EXIT
    generate_manifest > "${tmp_file}"
    if ! diff -u "${MANIFEST_PATH}" "${tmp_file}"; then
      echo "Integrity check failed. Run: ./scripts/integrity.sh update" >&2
      exit 1
    fi
    echo "Integrity check passed."
    ;;
  *)
    echo "Usage: ./scripts/integrity.sh [check|update]" >&2
    exit 2
    ;;
esac
