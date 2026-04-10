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

scan_forbidden_pattern() {
  local pattern="$1"
  local label="$2"
  if rg -n -i -S "${pattern}" "${SRC_DIR}" >/dev/null 2>&1; then
    fail "${label}"
    rg -n -i -S "${pattern}" "${SRC_DIR}" || true
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

assembly_count="$(rg -n -S '\bassembly\b' "${SRC_DIR}" | wc -l | tr -d ' ')"
log "assembly occurrences (informational): ${assembly_count}"

if [[ ${failures} -gt 0 ]]; then
  log "failed checks: ${failures}"
  exit 1
fi

log "all static security checks passed"
