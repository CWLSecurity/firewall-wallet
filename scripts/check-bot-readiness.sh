#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "[bot-readiness][fail] missing env: ${name}" >&2
    exit 1
  fi
}

to_dec() {
  local raw="$1"
  local token
  token="$(echo "${raw}" | awk '{print $1}' | tr -d '(),')"
  if [[ "${token}" == 0x* || "${token}" == 0X* ]]; then
    cast to-dec "${token}"
  else
    echo "${token}"
  fi
}

require_env BASE_RPC_URL
require_env VAULT_ADDRESS
require_env RELAYER_ADDRESS

if ! command -v cast >/dev/null 2>&1; then
  echo "[bot-readiness][fail] cast is required" >&2
  exit 1
fi

MIN_BOT_GAS_BUFFER_WEI="${MIN_BOT_GAS_BUFFER_WEI:-0}"

executor_enabled_raw="$(
  cast call "${VAULT_ADDRESS}" "isQueueExecutor(address)(bool)" "${RELAYER_ADDRESS}" --rpc-url "${BASE_RPC_URL}"
)"
executor_enabled="$(echo "${executor_enabled_raw}" | tr -d '[:space:]')"
if [[ "${executor_enabled}" != "true" ]]; then
  echo "[bot-readiness][fail] relayer is not enabled for vault: ${RELAYER_ADDRESS}" >&2
  exit 1
fi

cfg_raw="$(
  cast call "${VAULT_ADDRESS}" "botGasConfig()(uint256,uint256,uint256)" --rpc-url "${BASE_RPC_URL}"
)"
cfg_clean="${cfg_raw#\(}"
cfg_clean="${cfg_clean%\)}"
IFS=',' read -r auto_raw refund_price_raw refund_gas_raw <<<"${cfg_clean}"

auto_reserve_wei="$(to_dec "${auto_raw}")"
refund_max_gas_price_wei="$(to_dec "${refund_price_raw}")"
refund_max_gas_used="$(to_dec "${refund_gas_raw}")"

bot_gas_buffer_wei_raw="$(
  cast call "${VAULT_ADDRESS}" "botGasBuffer()(uint256)" --rpc-url "${BASE_RPC_URL}"
)"
bot_gas_buffer_wei="$(to_dec "${bot_gas_buffer_wei_raw}")"

echo "[bot-readiness] vault=${VAULT_ADDRESS}"
echo "[bot-readiness] relayer=${RELAYER_ADDRESS}"
echo "[bot-readiness] autoReserveWei=${auto_reserve_wei}"
echo "[bot-readiness] refundMaxGasPriceWei=${refund_max_gas_price_wei}"
echo "[bot-readiness] refundMaxGasUsed=${refund_max_gas_used}"
echo "[bot-readiness] botGasBufferWei=${bot_gas_buffer_wei}"

if (( auto_reserve_wei <= 0 )); then
  echo "[bot-readiness][fail] autoReserveWei must be > 0" >&2
  exit 1
fi
if (( refund_max_gas_price_wei <= 0 )); then
  echo "[bot-readiness][fail] refundMaxGasPriceWei must be > 0" >&2
  exit 1
fi
if (( refund_max_gas_used <= 0 )); then
  echo "[bot-readiness][fail] refundMaxGasUsed must be > 0" >&2
  exit 1
fi

if (( MIN_BOT_GAS_BUFFER_WEI > 0 && bot_gas_buffer_wei < MIN_BOT_GAS_BUFFER_WEI )); then
  echo "[bot-readiness][fail] botGasBufferWei (${bot_gas_buffer_wei}) < MIN_BOT_GAS_BUFFER_WEI (${MIN_BOT_GAS_BUFFER_WEI})" >&2
  exit 1
fi

echo "[bot-readiness] readiness check passed"
