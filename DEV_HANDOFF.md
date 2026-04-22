# Firewall Wallet — Developer Handoff

Last updated: 2026-04-22

This document is for onboarding engineers who maintain smart contracts and deployment flow.

## 1. Mission of this repo
- Canonical on-chain enforcement engine.
- Defines policy composition, decision folding, queue scheduling, and automation economics.
- Source of truth for addresses consumed by `firewall-ui`.

## 2. Core contracts and responsibilities
- `packages/contracts/src/FirewallModule.sol`
  - Vault executor, queue, bot reserve/buffer accounting.
- `packages/contracts/src/PolicyRouter.sol`
  - Aggregates policy outcomes using strictness order (`REVERT > DELAY > ALLOW`).
- `packages/contracts/src/FirewallFactory.sol`
  - Vault creation, owner-based latest vault discovery.
- `packages/contracts/src/PolicyPackRegistry.sol`
  - Pack definitions and policy metadata references.

## 3. Critical scripts
- Base deploy: `scripts/deploy-base-mainnet.sh`
- UI address sync: `scripts/sync-ui-addresses-from-manifest.sh`
- Queue relayer runbook: `QUEUE_AUTOMATION.md`
- Bot readiness check: `scripts/check-bot-readiness.sh`

## 4. Quality gates (required)
- `npm run security:static`
- `npm run test:contracts`
- `npm run smoke:contracts`
- `npm run integrity:check`

These must pass before any production deployment.

## 5. Deployment flow (current)
1. Run quality gates.
2. Run deploy flow:
   - `npm run deploy:base`
3. Verify generated deployment outputs.
4. Confirm UI address sync completed in `../firewall-ui/src/contracts/addresses/base.ts`.
5. Push updated repos with sanitized outputs only.

## 6. Bot economics checks per vault
Before enabling automation for a vault:
```bash
BASE_RPC_URL=... \
VAULT_ADDRESS=0x... \
RELAYER_ADDRESS=0x... \
MIN_BOT_GAS_BUFFER_WEI=... \
npm run bot:readiness:check
```

Pass criteria:
- relayer authorized as queue executor,
- gas reserve/refund config non-zero,
- optional minimum buffer satisfied.

## 7. High-risk edit areas
- Queue settlement and reserve accounting in `FirewallModule.sol`.
- Decision folding behavior in `PolicyRouter.sol`.
- Pack metadata and indexes in `PolicyPackRegistry.sol`.
- Factory owner->vault mapping semantics in `FirewallFactory.sol`.

Any change in these files requires smoke test review plus manual reasoning note in PR.

## 8. Cross-repo contract
- `../firewall-ui` consumes addresses and reads runtime metadata.
- `../PROJECT_HOME` stores launch runbook and operations policy.

Contract behavior changes must be documented in all three repositories when user-facing semantics change.
