#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS_DIR="${ROOT_DIR}/packages/contracts"
MANIFEST_REL_PATH="${DEPLOYMENT_OUT_PATH:-deployments/base-mainnet-manifest.json}"
MANIFEST_PATH="${CONTRACTS_DIR}/${MANIFEST_REL_PATH}"
RUN_BROADCAST="${RUN_BROADCAST:-1}"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "[wallet-release][fail] missing env: ${name}" >&2
    exit 1
  fi
}

require_env BASE_RPC_URL
require_env DEPLOYER_PK

echo "[wallet-release] quality/security gates"
(cd "${ROOT_DIR}" && npm run integrity:check && npm run security:static && npm run test:contracts && npm run smoke:contracts)

echo "[wallet-release] deploy dry-run (required)"
(
  cd "${CONTRACTS_DIR}"
  export WRITE_DEPLOYMENT_JSON=false
  forge script script/DeployBaseMainnet.s.sol:DeployBaseMainnet --rpc-url "${BASE_RPC_URL}" -vvv
)

if [[ "${RUN_BROADCAST}" != "1" ]]; then
  echo "[wallet-release] RUN_BROADCAST=${RUN_BROADCAST}, stopping after dry-run"
  exit 0
fi

echo "[wallet-release] deploy broadcast"
(
  cd "${CONTRACTS_DIR}"
  export WRITE_DEPLOYMENT_JSON=true
  export DEPLOYMENT_OUT_PATH="${MANIFEST_REL_PATH}"
  forge script script/DeployBaseMainnet.s.sol:DeployBaseMainnet --rpc-url "${BASE_RPC_URL}" --broadcast -vvv
)

echo "[wallet-release] sync UI addresses from manifest"
bash "${ROOT_DIR}/scripts/sync-ui-addresses-from-manifest.sh" "${MANIFEST_PATH}"

echo "[wallet-release] completed"
