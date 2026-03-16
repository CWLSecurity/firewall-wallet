# Firewall Vault Core — Deployment (Current v1 / v1.5)

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
6. Deploy `FirewallFactory(policyPackRegistry, entitlementManager)`.

## Wallet creation
Use:
- `createWallet(owner, recovery, basePackId)`

`recovery` is currently reserved metadata only (no recovery authorization flow yet).

## DeFi base pack wiring (current)
Base pack `1` includes:
- `DeFiApprovalPolicy`
- `ApprovalToNewSpenderDelayPolicy`
- `Erc20FirstNewRecipientDelayPolicy`
- `LargeTransferDelayPolicy`
- `NewEOAReceiverDelayPolicy`

## Large transfer policy config shape (current)
`LargeTransferDelayPolicy` expects:
- `ETH_THRESHOLD_WEI`
- `ERC20_THRESHOLD_UNITS`
- `DELAY_SECONDS`

Scope intentionally limited to:
- native ETH tx value,
- ERC20 `transfer(address,uint256)`,
- ERC20 `transferFrom(address,address,uint256)`.

## Add-on behavior
- Add-ons are enabled via `PolicyRouter.enableAddonPack(packId)`.
- On enable, policy addresses are snapshotted in wallet router.
- Enabled add-ons remain active even if entitlement is later revoked or registry deactivates pack.
- Current router has no add-on disable path.

## Policy address validation
- Registry registration rejects zero-address and non-contract policy addresses.
- Router constructor/add-on enable path also rejects non-contract policy addresses.
- Registry/router also require policy introspection metadata at admission:
  - `policyKey`
  - `policyName`
  - `policyDescription`
  - `policyConfigVersion`
  - `policyConfig`

## Pack metadata registration shape
Curated scripts use `registerPackDetailed` with:
- `packId`
- `packType`
- `metadata` hash
- `slug`
- `version`
- `active`
- `policies`

## Queue discoverability
- `FirewallModule.nextNonce()` exposes the next queue nonce.
- `FirewallModule.scheduledTxIdByNonce(nonce)` provides deterministic tx id lookup by nonce.
- `getScheduled(txId)` remains the source for per-tx status/details.

## Execution fee configuration
- Fee applies to successful `executeNow` / `executeScheduled` only.
- No fee is charged at `schedule(...)`.
- Runtime fee basis in module:
  - `gasUsed = gasStart - gasleft()`
  - `feeDue = (gasUsed * tx.gasprice * feePpm) / 1_000_000`
- Immutable max fee cap is on-chain (`MAX_EXECUTION_FEE_CAP_PPM`, equivalent `MAX_EXECUTION_FEE_CAP()` view).
- Configure fee via timelocked flow:
  - `proposeExecutionFeeConfig(feePpm, feeReceiver)`
  - wait timelock
  - `activateExecutionFeeConfig()`
- Collection is best-effort: insufficient balance or failed fee transfer does not revert protected execution.

## B2B foundation contracts
- `ProtocolRegistry` for protocol id <-> target contract mapping.
- `TrustedVaultRegistry` for recognized vault checks.
- `FirewallFactory.isFactoryVault(address)` as factory-origin vault primitive.
- These are extensibility primitives; they do not alter policy/security decisions.

## Reproducibility and verification
- Canonical deployment status and verification commands live in `DEPLOYMENT_STATUS.md`.
- Script-level artifacts are emitted under `packages/contracts/broadcast/*`.

## Notes
- Add-on snapshot permanence supports one-time premium pack sales.
- Expiring pack subscriptions are not supported by current router semantics without core behavior changes.
- See `MONETIZATION.md` for canonical monetization semantics and trust boundaries.
- Do not edit generated artifacts under `packages/contracts/{out,cache,broadcast,deployments}`.
