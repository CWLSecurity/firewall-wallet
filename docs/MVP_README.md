# Firewall Vault MVP (Current v1 / v1.5)

## Product summary
Firewall Vault is a non-custodial on-chain execution firewall.

A signer wallet authorizes owner actions, while `FirewallModule` executes through `PolicyRouter` under deterministic policy enforcement.

## Core model
- `FirewallFactory` creates wallet + router bound to base pack.
- `FirewallModule` supports:
  - `executeNow`
  - `schedule`
  - `executeScheduled`
  - `cancelScheduled`
  - `getScheduled`
- `PolicyRouter` folds policy outcomes as:
  - `REVERT > DELAY > ALLOW`

## Current pack lineup
Base packs:
- Base `0` Conservative
- Base `1` DeFi Trader

Add-ons:
- Add-on `2` Approval Hardening
- Add-on `3` New Receiver 24h Delay
- Add-on `4` Large Transfer 24h Delay

## Base 0 — Conservative
Policies:
- `InfiniteApprovalPolicy(allowPermit=false)`
- `LargeTransferDelayPolicy(...)`
- `NewReceiverDelayPolicy(...)`

Behavior summary:
- strict non-zero approval/increaseAllowance blocking,
- strict operator enable block,
- first receiver delays for EOAs/contracts,
- large transfer delays.

## Base 1 — DeFi Trader
Policies:
- `DeFiApprovalPolicy(...)`
- `ApprovalToNewSpenderDelayPolicy(...)`
- `Erc20FirstNewRecipientDelayPolicy(...)`
- `LargeTransferDelayPolicy(...)`
- `NewEOAReceiverDelayPolicy(...)`

Behavior summary:
- normal contract interaction remains generally usable,
- first non-zero approval to new contract spender delayed,
- non-zero approval to EOA spender blocked,
- first ERC20 recipient delayed,
- first new EOA transfer delayed,
- `setApprovalForAll(true)` blocked.

## Add-on 2 — Approval Hardening
- `InfiniteApprovalPolicy(approvalLimit=max, allowPermit=false)`
- Strict approval protection. Blocks risky token approval patterns including permit-style approvals.

## Add-on 3 — New Receiver 24h Delay
- `NewReceiverDelayPolicy(delay=86400s)`
- Delays the first transfer to any new receiver by 24 hours.

## Add-on 4 — Large Transfer 24h Delay
- `LargeTransferDelayPolicy(ETH=1 ether, ERC20=1 unit, delay=86400s)`
- Delays large ETH and ERC20 transfers by 24 hours.
Policies:
- `InfiniteApprovalPolicy(allowPermit=false)`
- `LargeTransferDelayPolicy(...)`
- `NewReceiverDelayPolicy(...)`

Behavior summary:
- adds stricter approval and delay controls on top of selected base pack.

## Security updates included
### Phase 1
- scheduled execution now enforces current policy at execution time:
  - current `Revert` => block,
  - current `Delay` => must satisfy `max(originalUnlockTime, createdAt + currentDelaySeconds)`,
  - current `Allow` => original unlock still applies,
- strict approval hardening applied.

### Phase 2
- DeFi compensating spender/recipient delay controls added.
- known spender/recipient state is token-scoped to prevent cross-token priming bypass.

### Phase 3A
- large transfer comparator hardened to `>=`,
- split ETH/ERC20 threshold configuration.

## Large transfer policy caveat
`LargeTransferDelayPolicy` covers only:
- native ETH tx value,
- ERC20 `transfer`,
- ERC20 `transferFrom`.

ERC20 threshold is raw-unit based (`ERC20_THRESHOLD_UNITS`), not economically normalized.

## Queue behavior
Delay flow:
1. `schedule(...)` stores delayed tx with unlock time.
2. `executeScheduled(txId)` re-checks current policy before execution.
3. Execution requires:
   - current decision is not `Revert`,
   - and if current decision is `Delay`, current time is at least
     `max(originalUnlockTime, createdAt + currentDelaySeconds)`.
4. `cancelScheduled(txId)` removes queued tx.

Queue discoverability helpers:
- `nextNonce()`
- `scheduledTxIdByNonce(nonce)`

## Monetization foundations
B2C:
- add-on packs are one-time permanent snapshots once enabled.
- optional execution fee is supported on:
  - `executeNow`
  - `executeScheduled`
- `schedule` does not charge execution fee.
- fee uses module-measured gas and `tx.gasprice`:
  - `feeDue = (gasUsed * tx.gasprice * feePpm) / 1_000_000`,
  - `gasUsed = gasStart - gasleft()`.
- fee updates are timelocked and publicly introspectable.
- immutable fee-rate hard cap is `0.5%` of gas cost.
- fee collection is best-effort and does not revert protected execution if transfer fails.

B2B:
- `ProtocolRegistry` supports protocol id <-> target mapping.
- `FirewallModule` emits protocol interaction events for known protocol targets.
- `TrustedVaultRegistry` supports recognized vault checks.
- `FirewallFactory.isFactoryVault(address)` supports factory-origin vault checks.
- no live on-chain protocol billing is implemented yet.
- protocol/trusted-vault/factory-origin primitives are not policy/security boundaries by default.

## Metadata and pack reconstruction (current)
Policy metadata required for admission:
- `policyKey`
- `policyName`
- `policyDescription`
- `policyConfigVersion`
- `policyConfig`

Pack reconstruction primitives:
- `packCount()` / `packIdAt(index)`
- `getPackMeta(packId)` => `active`, `packType`, `metadata`, `slug`, `version`, `policyCount`
- `getPackPolicies(packId)`

`UnknownContractBlockPolicy` caveat:
- allowlist mapping is non-enumerable on-chain;
- full allowlist reconstruction requires indexing `AllowedSet` events.

## Canonical references
- `README.md`
- `SECURITY_MODEL.md`
- `PACK_MATRIX.md`
- `MONETIZATION.md`
- `VERIFY_DEPLOYMENT.md`
- `DEPLOYMENT.md`
- `DEPLOYMENT_STATUS.md`
