# Firewall Vault Core — Deployment (Current v2)

Last updated: 2026-04-22

## Goal
Deploy core with:
- base packs (`0` Conservative, `1` DeFi Trader),
- curated add-on packs via `PolicyPackRegistry`,
- entitlement hook via `IEntitlementManager`.

## Deployment sequence
1. Deploy policy contracts.
2. Deploy `PolicyPackRegistry(owner)`.
3. Register base packs:
   - pack `0` type `BASE` (Conservative)
   - pack `1` type `BASE` (DeFi Trader)
4. Register add-on packs:
   - pack `2` type `ADDON` (New Receiver 24h Delay)
   - pack `3` type `ADDON` (Large Transfer 24h Delay)
5. Deploy entitlement contract (`SimpleEntitlementManager` or compatible implementation).
6. Deploy `PolicyRouterDeployer`.
7. Deploy `FirewallFactory(policyPackRegistry, entitlementManager, policyRouterDeployer)`.

## Mandatory deploy policy
For any deploy/upgrade script run:
1. Run dry-run first (no broadcast).
2. Check logs/artifacts.
3. Run broadcast only after dry-run succeeds.

Canonical local operator command:
- `npm run deploy:base`

This command enforces:
- wallet quality/security gates (`integrity`, `security:static`, contracts tests, smoke tests),
- dry-run before broadcast,
- post-deploy auto-sync of addresses to `../firewall-ui/src/contracts/addresses/base.ts`,
- auto-refresh of `firewall-ui` integrity manifest.

Launch e2e smoke coverage:
- `packages/contracts/test/smoke/V2EndToEndLaunchFlows.t.sol`

## Wallet creation
Use:
- `createWallet(owner, recovery, basePackId)` (`payable`)

Creation semantics:
- caller must equal `owner` (`msg.sender == owner`)
- delegated creation by third party is rejected
- new vaults set `feeConfigAdmin = owner`
- `msg.value` is forwarded to module init and seeds Vault bot gas pool

`recovery` is currently reserved metadata only.

## Current large-transfer defaults
Current deploy scripts set Vault large-transfer thresholds to `10 ETH` (native and 18-decimal ERC20 units):
- base Vault delay: `1 hour`
- add-on delay: `24 hours`

## Queue discoverability
- `nextNonce()` returns queue nonce upper-bound.
- `scheduledTxIdByNonce(nonce)` maps nonce to tx id.
- `getScheduled(txId)` is canonical per-tx read.

## Queue automation (current)
Owner/manual path remains:
- `executeScheduled(txId)`

Automation path:
- owner authorizes relayer: `setQueueExecutor(executor, enabled)`
- relayer executes unlocked tx: `executeScheduledByExecutor(txId)`

Gas reserve flow:
- `schedule(...)` auto-reserves from bot pool.
- optional explicit reserve funding still supported:
  - `scheduleWithReserve(...)` (`payable`)
  - `topUpScheduledReserve(txId)` (`payable`)
- `RunQueueRelayer` skips tx with zero reserve.

Bot gas controls:
- `fundBotGasBuffer()`
- `botGasBuffer()`
- `botGasConfig()`
- `setBotGasConfig(...)`
- `scheduledBotPoolReserve(txId)`

Relayer script:
- `packages/contracts/script/RunQueueRelayer.s.sol`

Deployment manifest now also records:
- `policyRouterDeployer`

Run order:
1. Dry-run relayer script (no broadcast):
   - `cd packages/contracts && forge script script/RunQueueRelayer.s.sol:RunQueueRelayer --rpc-url "$BASE_RPC_URL" -vv`
2. Enable relayer executor on vault (owner action):
   - call `setQueueExecutor(<RELAYER_ADDRESS>, true)`
3. Readiness preflight (recommended before enabling continuous loop):
   - `RELAYER_ADDRESS=<RELAYER_ADDRESS> VAULT_ADDRESS=<VAULT_ADDRESS> npm run bot:readiness:check`
   - optional floor: `MIN_BOT_GAS_BUFFER_WEI=<wei>`
4. Run once:
   - `npm run bot:queue:once`
5. Run loop:
   - `npm run bot:queue:loop`
6. UI/server mode:
   - start server: `cd ../firewall-ui && npm run bot:server`
   - enable/disable per-Vault automation from Queue modal.

Required env:
- `BASE_RPC_URL`
- `VAULT_ADDRESS`
- `RELAYER_PRIVATE_KEY` (fallback: `DEPLOYER_PK`)

Optional env:
- `QUEUE_SCAN_LIMIT`

## Execution fee configuration
- Fee applies to successful `executeNow` / `executeScheduled`.
- No fee is charged at `schedule(...)`.
- Runtime basis:
  - `gasUsed = gasStart - gasleft()`
  - `feeDue = (gasUsed * tx.gasprice * feePpm) / 1_000_000`
- Max fee cap is on-chain (`MAX_EXECUTION_FEE_CAP_PPM`, view `MAX_EXECUTION_FEE_CAP()`).
- Timelocked update flow:
  - `proposeExecutionFeeConfig(feePpm, feeReceiver)`
  - wait timelock
  - `activateExecutionFeeConfig()`
- Collection is best-effort and does not revert protected execution.

## B2B foundation contracts
- `ProtocolRegistry`
- `TrustedVaultRegistry`
- `FirewallFactory.isFactoryVault(address)`
- `FirewallFactory.latestWalletOfOwner(address)`

## Reproducibility and verification
- Canonical status/commands: `DEPLOYMENT_STATUS.md`.
- Script artifacts: `packages/contracts/broadcast/*`.
- Do not edit generated artifacts under `packages/contracts/{out,cache,broadcast,deployments}`.
