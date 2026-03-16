# Firewall Vault v1 Security Model (Current)

## 1. Scope
This document describes the current security model implemented in this repository.

## 2. Security objective
Reduce wallet-drain impact by enforcing deterministic policy checks before execution.

## 3. Deterministic decision model
`PolicyRouter` evaluates active policies and folds decisions as:
- any `Revert` => final `Revert`
- else any `Delay` => final `Delay` (max delay)
- else => final `Allow`

Priority is fixed: `REVERT > DELAY > ALLOW`.

## 4. Pack model security properties
- One base pack per wallet (fixed at creation).
- Optional add-on packs can be enabled later.
- Add-ons are additive only.
- Enabled add-ons are snapshotted and persistent in current router behavior.

Current curated pack IDs:
- Base `0`: Conservative
- Base `1`: DeFi Trader
- Add-on `2`: Vault Protection

## 5. Implemented hardening
### Phase 1
- Scheduled execution guard:
  - `executeScheduled` re-evaluates policy state,
  - blocks if current decision is `Revert`,
  - and if current decision is `Delay`, requires
    `max(originalUnlockTime, createdAt + currentDelaySeconds)`.
- Strict approval hardening:
  - `approve(0)` allow
  - `approve(non-zero)` revert
  - `increaseAllowance(0)` allow
  - `increaseAllowance(non-zero)` revert
  - `setApprovalForAll(true)` revert
  - permit-like selectors blocked unless policy config explicitly allows.

### Phase 2
- DeFi compensating controls:
  - `ApprovalToNewSpenderDelayPolicy`
  - `Erc20FirstNewRecipientDelayPolicy`

These add friction to first risky spender/recipient paths while keeping normal DeFi contract interactions usable.
State is scoped by `(vault, token, spender/recipient)` to avoid cross-token priming bypass.

### Phase 3A
- `LargeTransferDelayPolicy` hardening:
  - delay on `>=` threshold,
  - split ETH and ERC20 thresholds,
  - narrow explicit selector scope preserved.

## 6. Policy coverage summary
Strict controls:
- strict approval/operator protections in conservative-style packs.

Delay controls:
- large transfer delay,
- first receiver delay (strict mode),
- first EOA receiver delay (DeFi-oriented),
- first risky spender/recipient delays in DeFi compensating policies,
- scheduled execution re-check with current-delay enforcement.

## 7. Execution fee model (B2C foundation)
- Fee charging applies on successful `executeNow` and `executeScheduled`.
- `schedule` does not charge an execution fee.
- Fee basis is module-measured execution gas:
  - `gasUsed = gasStart - gasleft()`
  - `feeDue = (gasUsed * tx.gasprice * feePpm) / 1_000_000`
- Immutable hard cap: max fee rate is `0.5%` of gas cost (`MAX_EXECUTION_FEE_CAP_PPM = 5000`).
- Fee config updates are timelocked (`EXECUTION_FEE_CONFIG_TIMELOCK`) and publicly visible:
  - pending config
  - activation timestamp
  - current config
- Fee collection is best-effort and non-blocking:
  - fee may be partially collected (or zero) if vault balance is insufficient or fee transfer fails,
  - execution is not reverted by fee-transfer failure.
- Therefore fee should not be treated as guaranteed-revenue accounting.
- Fee governance is independent from policy evaluation semantics and does not modify policy outcomes.

## 8. Metadata trust model
Minimum metadata guaranteed for every admitted policy:
- `policyKey()`
- `policyName()`
- `policyDescription()`
- `policyConfigVersion()`
- `policyConfig()`

Admission enforcement:
- `PolicyPackRegistry.registerPack` / `registerPackDetailed` reject policies without required metadata.
- `PolicyRouter` rejects base/add-on policy addresses without required metadata.
- Empty/invalid metadata shape (for example empty description/config) is rejected at admission.

`InfiniteApprovalPolicy` note:
- strict enforcement blocks non-zero approve/increaseAllowance regardless of `approvalLimit`.
- metadata marks this explicitly via `approval_limit_functional=false`; `approvalLimit` is legacy metadata only.

## 9. Pack reconstructability model
On-chain APIs support pack reconstruction:
- `packCount()` + `packIdAt(index)` for canonical pack ID enumeration.
- `getPackMeta(packId)` for pack state and self-description:
  - `active`
  - `packType`
  - `metadata` hash
  - `slug`
  - `version`
  - `policyCount`
- `getPackPolicies(packId)` for policy address list.

Limits:
- `UnknownContractBlockPolicy` allowlist is mapping-based and not enumerable from state alone.
- Full allowlist reconstruction requires indexing `AllowedSet(target, allowed)` events.

## 10. B2B foundations (non-billing)
- `ProtocolRegistry` enables on-chain target->protocol identification.
- `FirewallModule` emits protocol interaction events for known protocol targets.
- `TrustedVaultRegistry` enables on-chain recognized-vault checks for integrations.
- `FirewallFactory.isFactoryVault(address)` provides factory-origin vault identity checks.
- No live on-chain B2B billing or entitlement gating is implemented.
- Protocol registry/trusted-vault/factory-origin data are not policy/security boundaries by default.

For canonical monetization positioning and limits, see `MONETIZATION.md`.

## 11. Known limitations and tradeoffs
- Add-on disable path does not exist in current router.
- Registry/entitlement changes do not remove already-enabled add-ons.
- Add-on permanence is incompatible with expiring subscription-style pack validity unless router semantics change.
- ERC20 thresholds are raw-unit based (not price-aware).
- Large-transfer policy only covers ETH value + ERC20 `transfer` / `transferFrom` shapes.
- Delay is review time, not absolute prevention if owner later executes malicious intent.
- Endpoint/device/signing-environment compromise remains out of protocol control.
- `recovery` is reserved metadata only; no recovery authorization path is active.

## 12. Trust boundaries
Users still trust:
- signer wallet integrity,
- frontend integrity,
- RPC read integrity,
- deployed contract correctness,
- governance/operations around registry and entitlement lifecycle.
