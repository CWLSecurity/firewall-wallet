# Firewall Vault — Deployment Status (Authoritative)

Last updated: 2026-03-16

## 1) Current release status
- Target release model: Base `0` + Base `1` + Add-on `2` (current pack matrix).
- Current status: **no finalized in-repo mainnet manifest for the exact current release build**.
- Release requirement: run the current deployment script and publish a fresh manifest + verification transcript before soft launch.

## 2) Canonical manifest format and location
- Canonical manifest file: `packages/contracts/deployments/base-mainnet-manifest.json`
- Current file status: `legacy_snapshot_not_current_release`
- Includes:
  - chain id
  - compiler version
  - create tx hashes
  - pack-registration tx hashes
  - curated pack ids (`0`,`1`,`2`) with slug/version metadata
  - deployed addresses captured from script broadcast artifact

## 3) Compiler and tool assumptions
- Foundry profile uses: `packages/contracts/foundry.toml`
- Compiler binary: `/usr/bin/solc`
- Compiler version expected for reproducibility:
  - `solc, Version: 0.8.30+commit.73712a01.Linux.g++`

Check locally before deploy/verify:
```bash
solc --version
forge --version
```

## 4) Exact deployment command (current scripts)
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

## 5) Exact verification command set
Use this after deployment with the addresses in the new manifest:
```bash
cd firewall-wallet/packages/contracts
export BASESCAN_API_KEY=...
export CHAIN_ID=8453

# FirewallFactory
forge verify-contract \
  --chain-id "$CHAIN_ID" \
  --watch \
  --compiler-version "v0.8.30+commit.73712a01" \
  <FACTORY_ADDRESS> \
  src/FirewallFactory.sol:FirewallFactory

# PolicyPackRegistry
forge verify-contract \
  --chain-id "$CHAIN_ID" \
  --watch \
  --compiler-version "v0.8.30+commit.73712a01" \
  <REGISTRY_ADDRESS> \
  src/PolicyPackRegistry.sol:PolicyPackRegistry

# SimpleEntitlementManager
forge verify-contract \
  --chain-id "$CHAIN_ID" \
  --watch \
  --compiler-version "v0.8.30+commit.73712a01" \
  <ENTITLEMENT_ADDRESS> \
  src/SimpleEntitlementManager.sol:SimpleEntitlementManager
```

For policy contracts with constructor args, use `--constructor-args` with values from the deployment broadcast artifact (`packages/contracts/broadcast/.../run-latest.json`) or manifest extension fields.

## 6) Legacy snapshot currently in repo
The latest recorded Base run artifact is:
- `packages/contracts/broadcast/DeployBaseMainnet.s.sol/8453/run-latest.json`

Its extracted addresses/tx hashes are mirrored in:
- `packages/contracts/deployments/base-mainnet-manifest.json`

Do not treat this legacy snapshot as a finalized manifest for the current release until re-deployed from current sources and re-verified.

## 7) Monetization status alignment (current)
- B2C premium pack model: one-time permanent add-on snapshots (not subscription validity).
- B2C execution fee:
  - enabled on `executeNow` / `executeScheduled`,
  - hard-capped at `0.5%` rate (`MAX_EXECUTION_FEE_CAP_PPM = 5000`),
  - timelocked config updates,
  - best-effort collection.
- B2B:
  - primitives implemented (`ProtocolRegistry`, protocol interaction event, `TrustedVaultRegistry`, `isFactoryVault`),
  - live on-chain B2B billing is not implemented.

Canonical source: `MONETIZATION.md`.
