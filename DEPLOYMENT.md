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
   - pack `2` type `ADDON` (Approval Hardening)
   - pack `3` type `ADDON` (New Receiver 24h Delay)
   - pack `4` type `ADDON` (Large Transfer 24h Delay)
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

## Wallet creation
Use:
- `createWallet(owner, recovery, basePackId)` (`payable`)

Creation semantics:
- caller must equal `owner` (`msg.sender == owner`)
- delegated creation by third party is rejected
- new vaults set `feeConfigAdmin = owner`
- `msg.value` is forwarded to module init and seeds Vault bot gas pool

`recovery` is currently reserved metadata only.

## Current large-transfer test defaults
Current deploy scripts keep conservative large-transfer thresholds at `0` for test stage.
Production target is to restore `0.05 ETH` thresholds when launch policy switches to production mode.

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
3. Run once:
   - `npm run bot:queue:once`
4. Run loop:
   - `npm run bot:queue:loop`
5. UI/server mode:
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
