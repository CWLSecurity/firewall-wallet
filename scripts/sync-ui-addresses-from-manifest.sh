#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH="${1:-${ROOT_DIR}/packages/contracts/deployments/base-mainnet-manifest.json}"
UI_BASE_FILE="${2:-${ROOT_DIR}/../firewall-ui/src/contracts/addresses/base.ts}"
UI_ROOT_DIR="$(cd "$(dirname "${UI_BASE_FILE}")/../../.." && pwd)"
SOURCE_LABEL="$(realpath --relative-to="${ROOT_DIR}" "${MANIFEST_PATH}" 2>/dev/null || echo "packages/contracts/deployments/base-mainnet-manifest.json")"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[sync-ui-addresses][fail] missing command: ${cmd}" >&2
    exit 1
  fi
}

require_cmd jq

if [[ ! -f "${MANIFEST_PATH}" ]]; then
  echo "[sync-ui-addresses][fail] manifest not found: ${MANIFEST_PATH}" >&2
  exit 1
fi

if [[ ! -d "${UI_ROOT_DIR}" ]]; then
  echo "[sync-ui-addresses][fail] UI root not found: ${UI_ROOT_DIR}" >&2
  exit 1
fi

read_json() {
  local key="$1"
  jq -r "${key}" "${MANIFEST_PATH}"
}

FACTORY_ADDRESS="$(read_json '.factory')"
POLICY_PACK_REGISTRY_ADDRESS="$(read_json '.policyPackRegistry')"
SIMPLE_ENTITLEMENT_MANAGER_ADDRESS="$(read_json '.entitlementManager')"

BASE_PACK_CONSERVATIVE_ID="$(read_json '.basePackConservative')"
BASE_PACK_DEFI_ID="$(read_json '.basePackDefi')"

POLICY_INFINITE_APPROVAL_CONSERVATIVE_ADDRESS="$(read_json '.policy_infiniteApproval_conservative')"
POLICY_INFINITE_APPROVAL_DEFI_ADDRESS="$(read_json '.policy_approval_defi')"
POLICY_APPROVAL_TO_NEW_SPENDER_DELAY_ADDRESS="$(read_json '.policy_approvalToNewSpenderDelay_defi')"
POLICY_ERC20_FIRST_NEW_RECIPIENT_DELAY_ADDRESS="$(read_json '.policy_erc20FirstNewRecipientDelay_defi')"
POLICY_INFINITE_APPROVAL_ADDON_HARDENING_ADDRESS="$(read_json '.policy_infiniteApproval_addonApprovalHardening')"
POLICY_LARGE_TRANSFER_DELAY_ADDRESS="$(read_json '.policy_largeTransferDelay_conservative')"
POLICY_LARGE_TRANSFER_DELAY_DEFI_ADDRESS="$(read_json '.policy_largeTransferDelay_defi')"
POLICY_LARGE_TRANSFER_DELAY_ADDON_ADDRESS="$(read_json '.policy_largeTransferDelay_addonLargeTransfer24h')"
POLICY_NEW_RECEIVER_DELAY_ADDRESS="$(read_json '.policy_newReceiverDelay_conservative')"
POLICY_NEW_EOA_RECEIVER_DELAY_ADDRESS="$(read_json '.policy_newReceiverDelay_defi')"
POLICY_NEW_RECEIVER_DELAY_ADDON_ADDRESS="$(read_json '.policy_newReceiverDelay_addonNewReceiver24h')"

cat > "${UI_BASE_FILE}" <<EOF
import type { Address } from 'viem'

export const BASE_CHAIN_ID = 8453

// Source: generated from firewall-wallet/${SOURCE_LABEL}
export const FACTORY_ADDRESS: Address = '${FACTORY_ADDRESS}'
export const POLICY_PACK_REGISTRY_ADDRESS: Address = '${POLICY_PACK_REGISTRY_ADDRESS}'
export const SIMPLE_ENTITLEMENT_MANAGER_ADDRESS: Address = '${SIMPLE_ENTITLEMENT_MANAGER_ADDRESS}'

export const BASE_PACK_CONSERVATIVE_ID = ${BASE_PACK_CONSERVATIVE_ID}
export const BASE_PACK_DEFI_ID = ${BASE_PACK_DEFI_ID}

export const POLICY_INFINITE_APPROVAL_CONSERVATIVE_ADDRESS: Address =
  '${POLICY_INFINITE_APPROVAL_CONSERVATIVE_ADDRESS}'
export const POLICY_INFINITE_APPROVAL_DEFI_ADDRESS: Address =
  '${POLICY_INFINITE_APPROVAL_DEFI_ADDRESS}'
export const POLICY_APPROVAL_TO_NEW_SPENDER_DELAY_ADDRESS: Address =
  '${POLICY_APPROVAL_TO_NEW_SPENDER_DELAY_ADDRESS}'
export const POLICY_ERC20_FIRST_NEW_RECIPIENT_DELAY_ADDRESS: Address =
  '${POLICY_ERC20_FIRST_NEW_RECIPIENT_DELAY_ADDRESS}'
export const POLICY_INFINITE_APPROVAL_ADDON_HARDENING_ADDRESS: Address =
  '${POLICY_INFINITE_APPROVAL_ADDON_HARDENING_ADDRESS}'
export const POLICY_LARGE_TRANSFER_DELAY_ADDRESS: Address =
  '${POLICY_LARGE_TRANSFER_DELAY_ADDRESS}'
export const POLICY_LARGE_TRANSFER_DELAY_DEFI_ADDRESS: Address =
  '${POLICY_LARGE_TRANSFER_DELAY_DEFI_ADDRESS}'
export const POLICY_LARGE_TRANSFER_DELAY_ADDON_ADDRESS: Address =
  '${POLICY_LARGE_TRANSFER_DELAY_ADDON_ADDRESS}'
export const POLICY_NEW_RECEIVER_DELAY_ADDRESS: Address =
  '${POLICY_NEW_RECEIVER_DELAY_ADDRESS}'
export const POLICY_NEW_EOA_RECEIVER_DELAY_ADDRESS: Address =
  '${POLICY_NEW_EOA_RECEIVER_DELAY_ADDRESS}'
export const POLICY_NEW_RECEIVER_DELAY_ADDON_ADDRESS: Address =
  '${POLICY_NEW_RECEIVER_DELAY_ADDON_ADDRESS}'

export const KNOWN_POLICY_LABELS: Record<string, string> = {
  [POLICY_INFINITE_APPROVAL_CONSERVATIVE_ADDRESS.toLowerCase()]: 'Infinite Approval Guard (Conservative)',
  [POLICY_INFINITE_APPROVAL_DEFI_ADDRESS.toLowerCase()]: 'DeFi Approval Guard',
  [POLICY_APPROVAL_TO_NEW_SPENDER_DELAY_ADDRESS.toLowerCase()]: 'Approval To New Spender Delay',
  [POLICY_ERC20_FIRST_NEW_RECIPIENT_DELAY_ADDRESS.toLowerCase()]: 'ERC20 First New Recipient Delay',
  [POLICY_INFINITE_APPROVAL_ADDON_HARDENING_ADDRESS.toLowerCase()]: 'Infinite Approval Guard (Add-on)',
  [POLICY_LARGE_TRANSFER_DELAY_ADDRESS.toLowerCase()]: 'Large Transfer Delay (Conservative)',
  [POLICY_LARGE_TRANSFER_DELAY_DEFI_ADDRESS.toLowerCase()]: 'Large Transfer Delay (DeFi)',
  [POLICY_LARGE_TRANSFER_DELAY_ADDON_ADDRESS.toLowerCase()]: 'Large Transfer Delay (Add-on)',
  [POLICY_NEW_RECEIVER_DELAY_ADDRESS.toLowerCase()]: 'New Receiver Delay (Conservative)',
  [POLICY_NEW_EOA_RECEIVER_DELAY_ADDRESS.toLowerCase()]: 'New EOA Receiver Delay',
  [POLICY_NEW_RECEIVER_DELAY_ADDON_ADDRESS.toLowerCase()]: 'New Receiver Delay (Add-on)',
}
EOF

echo "[sync-ui-addresses] updated ${UI_BASE_FILE}"

if [[ "${UPDATE_UI_INTEGRITY:-1}" == "1" ]]; then
  (
    cd "${UI_ROOT_DIR}"
    ./scripts/integrity.sh update
    ./scripts/integrity.sh check
  )
  echo "[sync-ui-addresses] refreshed firewall-ui integrity manifest"
fi
