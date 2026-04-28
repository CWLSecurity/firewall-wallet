# Firewall Vault — Deployment Status

Last updated: 2026-04-28

## 1) Release Track
- Active release model: Base packs `0`,`1` + add-ons `2`,`3`.
- Current status: latest Base deployment artifacts and manifest are present in-repo.
- MVP launch path uses this wallet deployment line together with `firewall-ui`.
- Connector rollout remains a separate post-MVP track.

## 2) Canonical Manifest
- File: `packages/contracts/deployments/base-mainnet-manifest.json`
- Contains:
  - chain id
  - compiler version
  - deployment tx hashes
  - curated pack IDs and metadata
  - deployed addresses mirrored from broadcast artifacts

## 2A) Latest Base Mainnet addresses
- `factory`: `0xc0943B763Bbc1D1b3E568488Bad56356aEe99D1C`
- `policyRouterDeployer`: `0x3cfDdb4F361dF757979331488c2b1742775EB671`
- `policyPackRegistry`: `0x917FDBa1830633604F00C3D87B89ec47B2e3e92b`
- `entitlementManager`: `0xD9574281f79Ac0962654ef8e0072A0415dF26f28`

## 3) Build/Tooling Assumptions
- Foundry config: `packages/contracts/foundry.toml`
- Solidity toolchain expected for reproducibility: `0.8.30`

Quick checks:
```bash
solc --version
forge --version
```

## 4) Deployment Path (Current Scripts)
Deployment policy (required):
- Always run `dry-run` first.
- Run `--broadcast` only after dry-run succeeds with expected output.

```bash
cd firewall-wallet
export DEPLOYER_PK=...
export BASE_RPC_URL=...
export DEPLOYMENT_OUT_PATH=deployments/base-mainnet-manifest.json

# Runs quality/security gates + dry-run + broadcast + UI address sync
npm run deploy:base
```

## 5) Verification Path
Use `forge verify-contract` for all deployed core contracts and policies with constructor args from broadcast outputs.

Primary references:
- `DEPLOYMENT.md`
- `VERIFY_DEPLOYMENT.md`

## 6) Operational Notes
- Pack semantics are additive and deterministic.
- Enabled add-ons remain active in current router line.
- UI and docs should align with these constraints to avoid overclaiming feature behavior.
- Factory now enforces owner-authenticated creation (`msg.sender == owner`).
- New vaults now default `feeConfigAdmin` to wallet owner.
- Module line supports safe NFT receive hooks (`ERC721` / `ERC1155`).
- DeFi line includes unknown-selector hardening for first-time EOAs and first-time `(contract target, selector)` pairs.

## 8) CI / Integrity Automation
- `npm run test:contracts`
- `npm run smoke:contracts`
- `npm run integrity:check`
- `npm run security:static`
- `npm run sync:ui-addresses`
