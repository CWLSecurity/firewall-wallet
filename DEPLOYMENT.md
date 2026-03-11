# Firewall Vault Core — Deployment (V2)

## Goal
Deploy V2 core with:
- fixed base packs (`0` Conservative, `1` DeFi),
- curated add-on packs via `PolicyPackRegistry`,
- entitlement hook via `IEntitlementManager`.

## V2 deployment sequence
1. Deploy base policy contracts with existing parameters/behavior.
2. Deploy `PolicyPackRegistry(owner)`.
3. Register base packs in registry:
   - pack `0` type `BASE` (Conservative),
   - pack `1` type `BASE` (DeFi),
   - mark both `active = true`.
4. Deploy entitlement contract:
   - minimal option: `SimpleEntitlementManager(owner)`,
   - or any custom contract implementing `isEntitled(address,uint256)`.
5. Deploy `FirewallFactory(policyPackRegistry, entitlementManager)`.

## Wallet creation
Use:
- `createWallet(owner, recovery, basePackId)`

`basePackId` must point to an active `BASE` pack in registry.
The base pack is fixed in each wallet’s `PolicyRouter` at creation time.

## Add-on packs
1. Register curated add-on pack in `PolicyPackRegistry` with type `ADDON`.
2. Grant entitlement for wallet owner in entitlement manager.
3. Wallet owner calls `PolicyRouter.enableAddonPack(packId)`.

At enable time, add-on policy addresses are snapshotted into that wallet router.
After enablement:
- add-on protection remains active for that wallet,
- entitlement revocation does not disable already-enabled protection,
- registry deactivation only prevents new enablements.
- duplicate policy addresses are rejected:
  - base-pack duplicates at router deployment,
  - add-on duplicates (vs base/already-enabled/within-pack) at enable.

Add-ons can only add checks. Base pack remains active and unchanged.

## Scripts
Updated scripts under `packages/contracts/script`:
- `DeployFactoryBaseMainnet.s.sol`
- `DeployBaseMainnet.s.sol` (legacy path, now V2-compatible)
- `SmokeMvpBase.s.sol`

## Notes
- No billing/subscription logic is included in core.
- Enforcement remains fully on-chain and non-custodial.
- Do not edit generated artifacts under `packages/contracts/{out,cache,broadcast,deployments}`.
