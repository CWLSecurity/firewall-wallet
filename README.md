# Firewall Vault Core

Last updated: 2026-03-24

`firewall-wallet` contains the canonical on-chain contracts for Firewall Vault.

## What This Repo Delivers
- Deterministic policy enforcement before execution.
- Vault execution model (`FirewallModule`) with router-driven decisions.
- Pack-based protection composition (base + additive add-ons).
- Queue semantics for delayed actions.

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

## Policy Introspection Contract Requirement
Admissible policies expose:
- `policyKey()`
- `policyName()`
- `policyDescription()`
- `policyConfigVersion()`
- `policyConfig()`

These metadata fields are used by UI/runtime tooling for canonical policy identity and parameter reads.

## Security Semantics (Current)
- Router folding is deterministic and policy-order independent for strictness outcome.
- Scheduled execution re-checks current policy state at execution time.
- Add-ons are additive only and currently persistent once enabled.
- Large transfer delay logic uses explicit ETH/ERC20 thresholds and `>=` comparator semantics.
- Factory wallet creation is owner-authenticated (`msg.sender == owner`).
- `FirewallModule` supports inbound safe NFT transfers (`ERC721` / `ERC1155` receiver hooks).
- DeFi base line delays first unknown-selector calls to new contract targets.

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
```

## Documentation Index
- `PACK_MATRIX.md`
- `SECURITY_MODEL.md`
- `VERIFY_DEPLOYMENT.md`
- `DEPLOYMENT.md`
- `DEPLOYMENT_STATUS.md`
- `MONETIZATION.md`
- `MARKETING_BRIEF.md`

## Product Surface Repos
- `../firewall-ui` (security console)
- `../firewall-connector` (EIP-1193 connector boundary)
- `../PROJECT_HOME` (cross-repo docs and launch messaging)
