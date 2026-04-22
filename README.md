# Firewall Vault Core

Last updated: 2026-04-22

`firewall-wallet` contains canonical on-chain contracts for Firewall Vault.

## What This Repo Delivers
- Deterministic policy enforcement before execution.
- Vault execution model (`FirewallModule`) with router-driven decisions.
- Pack-based protection composition (base + additive add-ons).
- Delayed queue with owner fallback and optional relayer automation.

## MVP Scope for Contracts
In MVP:
- Base Mainnet contract line for `firewall-ui` core flows.
- Curated base/add-on packs and queue semantics used by current UI journey.

After MVP:
- Connector-native discovery/integration rollout.
- Multi-chain deployment tracks.

## Core Runtime Model
- Signer wallet keeps private keys.
- Vault (`FirewallModule`) is the protected executor.
- `PolicyRouter` returns final decision by strict priority:
  - `REVERT > DELAY > ALLOW`
- Base pack is selected at wallet creation.
- Add-ons can be enabled later and are additive snapshots.

## Main Contracts
- `FirewallModule`
- `PolicyRouter`
- `PolicyRouterDeployer`
- `FirewallFactory`
- `PolicyPackRegistry`
- `SimpleEntitlementManager`
- `ProtocolRegistry`
- `TrustedVaultRegistry`

## Current Pack Surface
Base packs:
- Base `0`: Conservative (`Vault Safe` in UI)
- Base `1`: DeFi Trader

Add-on packs:
- Add-on `2`: Approval Hardening
- Add-on `3`: New Receiver 24h Delay
- Add-on `4`: Large Transfer 24h Delay

## Creation and Bot Gas Buffer
- `FirewallFactory.createWallet(owner, recovery, basePackId)` is `payable`.
- Creation is owner-authenticated (`msg.sender == owner`).
- `msg.value` is forwarded to `FirewallModule.init(...)` and credited into Vault bot gas pool.
- `recovery` is currently reserved metadata only (no recovery authorization flow).

## Queue Automation (Current)
Owner/manual path remains available:
- `executeScheduled(txId)`

Automation path is additive:
- owner authorizes relayer via `setQueueExecutor(executor, enabled)`
- relayer executes unlocked tx via `executeScheduledByExecutor(txId)`
- owner key is never required in bot runtime

Gas reserve model:
- `schedule(...)` auto-reserves from Vault bot gas pool.
- default auto-reserve target: `0.00003 ETH` per scheduled tx (`DEFAULT_BOT_AUTO_RESERVE_WEI`).
- `scheduleWithReserve(...)` and `topUpScheduledReserve(...)` are still available for explicit reserve funding.
- relayer script skips tx without reserve (`scheduledReserve(txId) == 0`).

Refund model:
- relayer pays network gas up-front as tx sender.
- vault refunds relayer from tx reserve, with caps from `botGasConfig()`:
  - `refundMaxGasPriceWei`
  - `refundMaxGasUsed`
- if owner executes manually, bot-origin reserve returns to bot pool.
- if relayer executes, paid refund is deducted from bot-origin reserve and only remainder returns to pool.

Bot gas management views/actions:
- `fundBotGasBuffer()`
- `botGasBuffer()`
- `botGasConfig()`
- `setBotGasConfig(autoReserveWei, refundMaxGasPriceWei, refundMaxGasUsed)`
- `scheduledBotPoolReserve(txId)`

## Security Semantics (Current)
- Router folding is deterministic and policy-order independent for strictness outcome.
- Scheduled execution re-checks current policy state at execution time.
- Add-ons are additive only and currently persistent once enabled.
- Large transfer delay logic uses explicit ETH/ERC20 thresholds and `>=` comparator semantics.
- Factory tracks deterministic owner->vault discovery:
  - `latestWalletOfOwner(owner)`
  - (historical full-list path moved off factory to keep deployment bytecode under EIP-170 limit)
- New vaults default `feeConfigAdmin` to vault owner.
- `FirewallModule` supports inbound safe NFT transfers (`ERC721` / `ERC1155` receiver hooks).
- Reserved queue gas is isolated from normal execution spending:
  - `executeNow(...)` enforces unreserved balance checks,
  - fee charging respects reserved-balance floor.

## Queue Relayer Commands
```bash
npm run bot:queue:once
npm run bot:queue:loop
RELAYER_ADDRESS=<0x...> VAULT_ADDRESS=<0x...> npm run bot:readiness:check
```

Required env:
- `BASE_RPC_URL`
- `VAULT_ADDRESS`
- `RELAYER_PRIVATE_KEY` (fallback: `DEPLOYER_PK`)

Optional env:
- `QUEUE_SCAN_LIMIT`
- `MIN_BOT_GAS_BUFFER_WEI` (only for `bot:readiness:check`)

## Build and Test
```bash
pnpm install
cd packages/contracts
forge build
forge test -vvv
```

CI/local parity shortcuts:
```bash
npm run test:contracts
npm run smoke:contracts
npm run integrity:check
npm run security:static
npm run sync:ui-addresses
npm run deploy:base
```

Launch-critical smoke flow coverage includes:
- `packages/contracts/test/smoke/V2EndToEndLaunchFlows.t.sol`

`npm run deploy:base` flow:
- runs wallet quality/security gates first,
- executes mandatory deploy dry-run,
- broadcasts to Base Mainnet,
- auto-syncs deployed addresses to `../firewall-ui/src/contracts/addresses/base.ts`,
- auto-refreshes `firewall-ui/integrity/manifest.sha256`.

## Documentation Index
- `PACK_MATRIX.md`
- `SECURITY_MODEL.md`
- `VERIFY_DEPLOYMENT.md`
- `DEPLOYMENT.md`
- `QUEUE_AUTOMATION.md`
- `DEPLOYMENT_STATUS.md`
- `MONETIZATION.md`
- `DEV_HANDOFF.md`
- `../PROJECT_HOME/MARKETING_BRIEF.md`

## Product Surface Repos
- `../firewall-ui` (security console)
- `../firewall-connector` (EIP-1193 connector boundary)
- `../PROJECT_HOME` (cross-repo docs and launch messaging)
