# Firewall Vault Core

Firewall Vault Core is a non-custodial on-chain transaction firewall.

It enforces deterministic safety decisions before execution, not warning-only simulation.

## 30-second overview
- User actions execute through `FirewallModule` (Vault executor).
- `PolicyRouter` evaluates active policies and returns final outcome.
- Decision priority is fixed: `REVERT > DELAY > ALLOW`.
- Wallets are created with one base pack and can enable optional additive add-ons.

## Product model (current)
- Signer wallet (MetaMask/Rabby) keeps keys.
- Vault (`FirewallModule`) is the protected executor.
- `firewall-ui` is the security console.
- Vault Connector exists as an MVP integration-boundary package (not production-complete).

## Core contracts
- `FirewallModule`
- `PolicyRouter`
- `FirewallFactory`
- `PolicyPackRegistry`
- `SimpleEntitlementManager`
- `ProtocolRegistry`
- `TrustedVaultRegistry`

## Pack model
Base packs:
- Base `0`: Conservative
- Base `1`: DeFi Trader

Add-on packs:
- Add-on `2`: Approval Hardening
- Add-on `3`: New Receiver 24h Delay
- Add-on `4`: Large Transfer 24h Delay

Semantics:
- Base pack is fixed per wallet.
- Add-ons are additive only.
- Enabled add-ons are snapshotted in router state.
- Add-ons remain active once enabled in current router design.

## Current policy lineup
- `InfiniteApprovalPolicy` (strict approvals)
- `DeFiApprovalPolicy` (DeFi approvals)
- `ApprovalToNewSpenderDelayPolicy` (DeFi compensating spender friction)
- `Erc20FirstNewRecipientDelayPolicy` (DeFi compensating ERC20 recipient friction)
- `LargeTransferDelayPolicy` (large transfer delay)
- `NewReceiverDelayPolicy` (strict first receiver delay)
- `NewEOAReceiverDelayPolicy` (first EOA receiver delay)
- `UnknownContractBlockPolicy` (optional, not in default curated packs)

## Security updates reflected in current build
### Phase 1
- `executeScheduled` enforces current policy on execution:
  - current `Revert` => blocked,
  - current `Delay` => must satisfy `max(originalUnlock, createdAt + currentDelay)`,
  - current `Allow` => original unlock still applies.
- Strict approval hardening in strict packs:
  - `approve(0)` allow
  - `approve(non-zero)` revert
  - `increaseAllowance(0)` allow
  - `increaseAllowance(non-zero)` revert
  - `setApprovalForAll(true)` revert
  - permit-like selectors blocked unless policy explicitly allows

### Phase 2
- DeFi pack gained compensating controls:
  - first risky approval spender friction,
  - first ERC20 recipient friction,
  - known-state now scoped by `(vault, token, spender/recipient)` to prevent cross-token priming,
  while preserving normal DeFi contract interaction usability.

### Phase 3A
- `LargeTransferDelayPolicy` hardened:
  - comparator now `>=`
  - separate thresholds:
    - `ETH_THRESHOLD_WEI`
    - `ERC20_THRESHOLD_UNITS`
  - scope remains intentionally limited to:
    - native ETH tx value
    - ERC20 `transfer` / `transferFrom`

## Policy introspection
All admissible policies must expose:
- `policyKey()`
- `policyName()`
- `policyDescription()`
- `policyConfigVersion()`
- `policyConfig()`

Admission is enforced at both:
- `PolicyPackRegistry.registerPack*`
- `PolicyRouter` base/add-on binding paths

Policies missing required introspection methods are rejected.
Policies with empty/invalid metadata shape are rejected.

## Pack reconstructability
On-chain reconstruction is available via:
- `packCount()`
- `packIdAt(index)`
- `getPackMeta(packId)` => `(active, packType, metadataHash, slug, version, policyCount)`
- `getPackPolicies(packId)`

This allows machine reconstruction of canonical pack identity/composition without repository context.

## Monetization foundations
B2C (implemented):
- Premium add-on packs fit one-time permanent upgrade semantics (router snapshots).
- Optional execution fee exists on `executeNow` and `executeScheduled` only.
- `schedule()` does not charge fee (no execution happened yet).
- Fee uses module-measured execution gas (`gasStart - gasleft()`) and `tx.gasprice`:
  - `feeDue = (gasUsed * tx.gasprice * feePpm) / 1_000_000`.
- max fee rate is immutable on-chain: `0.5%` (`MAX_EXECUTION_FEE_CAP_PPM = 5000`).
- Fee config changes are timelocked and on-chain visible:
  - `proposeExecutionFeeConfig(...)`
  - `activateExecutionFeeConfig()`
  - `currentExecutionFeeConfig()`
  - `pendingExecutionFeeConfig()`
- Fee collection is best-effort and non-blocking (execution does not revert if fee transfer fails).

B2B foundations (implemented, billing not implemented):
- `ProtocolRegistry` maps target contracts to protocol ids.
- `FirewallModule` emits protocol interaction events for known protocol targets.
- `TrustedVaultRegistry` provides on-chain recognized vault checks for integrations.
- `FirewallFactory.isFactoryVault(address)` exposes factory-origin vault identity.
- These primitives are operational/analytics hooks, not policy-security decision inputs by default.

Canonical monetization reference:
- [MONETIZATION.md](./MONETIZATION.md)

## Known limitations
- Add-ons are persistent once enabled.
- Registry deactivation/entitlement revocation does not remove enabled add-ons.
- This permanence is compatible with one-time premium packs and incompatible with expiring subscription-style pack validity without core router changes.
- ERC20 large-transfer thresholds are raw-unit based, not price-normalized.
- Large-transfer policy scope is not universal arbitrary-calldata economic coverage.
- `UnknownContractBlockPolicy` allowlist is mapping-based and non-enumerable on-chain; full reconstruction requires indexing `AllowedSet` events.
- `InfiniteApprovalPolicy.approvalLimit` is legacy metadata only in strict mode; enforcement remains strict non-zero block semantics.
- `recovery` is currently a reserved field (required at creation, but no recovery flow is implemented yet).
- MVP/audit status must be checked independently.

## Queue discoverability primitives
- `nextNonce()` returns the next scheduling nonce.
- `scheduledTxIdByNonce(nonce)` returns the tx id recorded for a nonce.
- Off-chain tooling can iterate `nonce in [0, nextNonce)` and inspect each tx via `getScheduled(txId)`.

## Quick start
- `pnpm install`
- `cd packages/contracts && forge build`
- `cd packages/contracts && forge test -vvv`

## Canonical docs
- [SECURITY_MODEL.md](./SECURITY_MODEL.md)
- [PACK_MATRIX.md](./PACK_MATRIX.md)
- [MONETIZATION.md](./MONETIZATION.md)
- [VERIFY_DEPLOYMENT.md](./VERIFY_DEPLOYMENT.md)
- [DEPLOYMENT.md](./DEPLOYMENT.md)
- [DEPLOYMENT_STATUS.md](./DEPLOYMENT_STATUS.md)
