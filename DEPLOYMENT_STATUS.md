# Firewall Vault — Deployment Status

Last updated: 2026-04-08

## 1) Release Track
- Active release model: Base packs `0`,`1` + add-ons `2`,`3`,`4`.
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
- `factory`: `0x0f1da78A345883E2E1570f772e764fA53A018684`
- `policyRouterDeployer`: `0x0652791573e93268f82CC157dd444f55E9a29B39`
- `policyPackRegistry`: `0xCc68d5dCF2Dcdf8fa948FF255cF21E12D6eBd3Df`
- `entitlementManager`: `0xaFbd4b726164a7D50A43EbCac48680D51fbB4214`

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
cd firewall-wallet/packages/contracts
export DEPLOYER_PK=...
export BASE_RPC_URL=...

# 1) Dry-run (mandatory)
export WRITE_DEPLOYMENT_JSON=false
forge script script/DeployBaseMainnet.s.sol:DeployBaseMainnet \
  --rpc-url "$BASE_RPC_URL" \
  -vvv

# 2) Broadcast (only after successful dry-run)
export WRITE_DEPLOYMENT_JSON=true
export DEPLOYMENT_OUT_PATH=deployments/base-mainnet-manifest.json
forge script script/DeployBaseMainnet.s.sol:DeployBaseMainnet \
  --rpc-url "$BASE_RPC_URL" \
  --broadcast \
  -vvv
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

## 7) Monetization Alignment (Current)
- Premium add-on model matches one-time persistent enable semantics.
- Execution fee model is bounded and timelocked where enabled.
- Canonical wording and constraints: `MONETIZATION.md`.
