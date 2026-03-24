# Firewall Vault — Deployment Status

Last updated: 2026-03-24

## 1) Release Track
- Active release model: Base packs `0`,`1` + add-ons `2`,`3`,`4`.
- Current status: latest Base deployment artifacts and manifest are present in-repo.

## 2) Canonical Manifest
- File: `packages/contracts/deployments/base-mainnet-manifest.json`
- Contains:
  - chain id
  - compiler version
  - deployment tx hashes
  - curated pack IDs and metadata
  - deployed addresses mirrored from broadcast artifacts

## 3) Build/Tooling Assumptions
- Foundry config: `packages/contracts/foundry.toml`
- Solidity toolchain expected for reproducibility: `0.8.30`

Quick checks:
```bash
solc --version
forge --version
```

## 4) Deployment Path (Current Scripts)
```bash
cd firewall-wallet/packages/contracts
export DEPLOYER_PK=...
export BASE_RPC_URL=...
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
- Module line supports safe NFT receive hooks (`ERC721` / `ERC1155`).
- DeFi line includes first unknown-selector contract-target delay hardening.

## 8) CI / Integrity Automation
- `npm run test:contracts`
- `npm run smoke:contracts`
- `npm run integrity:check`

## 7) Monetization Alignment (Current)
- Premium add-on model matches one-time persistent enable semantics.
- Execution fee model is bounded and timelocked where enabled.
- Canonical wording and constraints: `MONETIZATION.md`.
