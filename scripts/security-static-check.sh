#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/packages/contracts/src"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "[security-static][fail] missing source dir: ${SRC_DIR}" >&2
  exit 1
fi

failures=0

log() {
  printf '[security-static] %s\n' "$*"
}

fail() {
  failures=$((failures + 1))
  printf '[security-static][fail] %s\n' "$*" >&2
}

ok() {
  printf '[security-static][ok] %s\n' "$*"
}

has_rg=0
if command -v rg >/dev/null 2>&1; then
  has_rg=1
fi

search_matches() {
  local pattern="$1"
  if [[ ${has_rg} -eq 1 ]]; then
    rg -n -i -S "${pattern}" "${SRC_DIR}"
  else
    grep -RInP "${pattern}" "${SRC_DIR}"
  fi
}

scan_forbidden_pattern() {
  local pattern="$1"
  local label="$2"
  if search_matches "${pattern}" >/dev/null 2>&1; then
    fail "${label}"
    search_matches "${pattern}" || true
  else
    ok "${label}"
  fi
}

scan_forbidden_pattern '\bdelegatecall\b' "no delegatecall in contracts/src"
scan_forbidden_pattern '\bselfdestruct\b' "no selfdestruct in contracts/src"
scan_forbidden_pattern '\btx\.origin\b' "no tx.origin auth path in contracts/src"

backup_files="$(
  find "${SRC_DIR}" -type f \( -name '*.save' -o -name '*.bak' -o -name '*~' \) | sed "s#${ROOT_DIR}/##" || true
)"
if [[ -n "${backup_files}" ]]; then
  fail "no backup artifacts in contracts/src"
  printf '%s\n' "${backup_files}" >&2
else
  ok "no backup artifacts in contracts/src"
fi

if [[ ${has_rg} -eq 1 ]]; then
  assembly_count="$({ rg -n -S '\bassembly\b' "${SRC_DIR}" || true; } | wc -l | tr -d ' ')"
else
  assembly_count="$({ grep -RInP '\bassembly\b' "${SRC_DIR}" || true; } | wc -l | tr -d ' ')"
fi
log "assembly occurrences (informational): ${assembly_count}"

if [[ ${failures} -gt 0 ]]; then
  log "failed checks: ${failures}"
  exit 1
fi

log "all static security checks passed"
