# Firewall Vault Queue Automation

Last updated: 2026-04-22

## Goal
Automate delayed-transaction execution without storing owner key in bot runtime.

## Current model
- Owner can always execute manually via `executeScheduled(txId)`.
- Owner can authorize/revoke relayer on-chain via `setQueueExecutor(executor, enabled)`.
- Authorized relayer executes unlocked actions via `executeScheduledByExecutor(txId)`.

## Gas model
### 1) Bot gas pool funding
- Vault bot gas pool lives inside `FirewallModule` accounting.
- Pool can be funded at create time:
  - `FirewallFactory.createWallet(...)` is `payable` and forwards `msg.value` into `FirewallModule.init(...)`.
- Pool can be topped up later by owner:
  - `fundBotGasBuffer()` (`payable`).

### 2) Reserve allocation
- `schedule(...)` auto-reserves from bot pool.
- Default auto-reserve target per tx:
  - `DEFAULT_BOT_AUTO_RESERVE_WEI = 0.00003 ETH`.
- Optional explicit reserve paths still exist:
  - `scheduleWithReserve(...)` (`payable`)
  - `topUpScheduledReserve(txId)` (`payable`)

### 3) Relayer execution and refund
- Relayer is tx sender and pays gas up-front.
- Vault refunds from tx reserve inside `executeScheduledByExecutor(...)`.
- Refund is capped by bot config:
  - `refundMaxGasPriceWei`
  - `refundMaxGasUsed`
- If owner executes manually, bot-origin reserve for that tx is returned to pool.
- If relayer executes, paid refund is deducted from bot-origin reserve and only remainder returns to pool.

### 4) Script behavior
- `RunQueueRelayer` now skips queued actions with zero reserve.
- This prevents bot from paying gas for unreserved actions.

## Relevant `FirewallModule` APIs
- `schedule(address to, uint256 value, bytes data)`
- `scheduleWithReserve(address to, uint256 value, bytes data)` (`payable`)
- `topUpScheduledReserve(bytes32 txId)` (`payable`)
- `executeScheduled(bytes32 txId)`
- `executeScheduledByExecutor(bytes32 txId)`
- `setQueueExecutor(address executor, bool enabled)`
- `isQueueExecutor(address executor)`
- `fundBotGasBuffer()` (`payable`)
- `botGasBuffer() -> uint256`
- `botGasConfig() -> (autoReserveWei, refundMaxGasPriceWei, refundMaxGasUsed)`
- `setBotGasConfig(uint256 autoReserveWei, uint256 refundMaxGasPriceWei, uint256 refundMaxGasUsed)`
- `scheduledReserve(bytes32 txId) -> uint256`
- `scheduledBotPoolReserve(bytes32 txId) -> uint256`

## Relayer script
- `packages/contracts/script/RunQueueRelayer.s.sol`

NPM shortcuts:
- `npm run bot:queue:once`
- `npm run bot:queue:loop`
- `RELAYER_ADDRESS=<0x...> VAULT_ADDRESS=<0x...> npm run bot:readiness:check`

Required env:
- `BASE_RPC_URL`
- `VAULT_ADDRESS`
- `RELAYER_PRIVATE_KEY` (fallback: `DEPLOYER_PK`)

Optional env:
- `QUEUE_SCAN_LIMIT` (default `128`)
- `MIN_BOT_GAS_BUFFER_WEI` (optional threshold for `bot:readiness:check`)

## Runbook
1. Dry run (simulation, no broadcast):
   - `cd packages/contracts && forge script script/RunQueueRelayer.s.sol:RunQueueRelayer --rpc-url "$BASE_RPC_URL" -vv`
2. Enable relayer executor on vault (owner action):
   - call `setQueueExecutor(<RELAYER_ADDRESS>, true)`
3. Readiness preflight:
   - `RELAYER_ADDRESS=<RELAYER_ADDRESS> VAULT_ADDRESS=<VAULT_ADDRESS> npm run bot:readiness:check`
4. Execute once:
   - `npm run bot:queue:once`
5. Run continuously:
   - `npm run bot:queue:loop`

## Security properties
- Bot runtime does not require owner private key.
- Unauthorized relayer calls revert (`Firewall_QueueExecutorUnauthorized`).
- Early execution reverts (`Firewall_NotUnlocked`).
- Queue execution still passes full policy re-check before transfer.
