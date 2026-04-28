# Firewall Vault Security Model (Current)

Last updated: 2026-04-28

## 1. Scope
This document describes the security model implemented in `firewall-wallet`.

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
- Add-on `2`: New Receiver 24h Delay
- Add-on `3`: Large Transfer 24h Delay

## 5. Implemented hardening
### Phase 1
- Scheduled execution guard:
  - `executeScheduled` re-evaluates policy state,
  - blocks if current decision is `Revert`,
  - and for `Delay` requires `max(originalUnlockTime, createdAt + currentDelaySeconds)`.
- Approval policy hardening primitives exist in codebase and can be composed in curated packs.

### Phase 2
- DeFi compensating controls:
  - `ApprovalToNewSpenderDelayPolicy`
  - `Erc20FirstNewRecipientDelayPolicy`

### Phase 3A
- `LargeTransferDelayPolicy` hardening:
  - delay on `>=` threshold,
  - split ETH and ERC20 thresholds,
  - narrow explicit selector scope preserved.

### Phase 3B
- Factory creation hardening:
  - `createWallet(owner, ...)` requires `msg.sender == owner`.
- New vaults default fee role:
  - vault owner becomes `feeConfigAdmin`.
- DeFi receiver hardening:
  - first unknown-selector call to new EOA is delayed,
  - first unknown-selector `(contract target, selector)` is delayed,
  - approval-like selectors excluded from receiver-delay classification.
- NFT receive baseline:
  - `FirewallModule` implements `IERC721Receiver`, `IERC1155Receiver`, and `IERC165`.

### Phase 4 (queue automation hardening)
- Owner/manual path remains available:
  - `executeScheduled(txId)`.
- Owner-controlled relayer authorization:
  - `setQueueExecutor(executor, enabled)`.
- Authorized relayer path:
  - `executeScheduledByExecutor(txId)`.
- Owner key isolation:
  - bot runtime uses relayer key only.

Queue gas reserve hardening:
- Vault has bot gas pool accounting (`botGasPoolWei`).
- Pool can be funded at creation (`createWallet` payable) and via `fundBotGasBuffer()`.
- `schedule(...)` auto-reserves from bot pool (default target `0.00003 ETH` per tx).
- Reserve is tracked per tx and excluded from unreserved-spend checks.
- Relayer refund is capped by bot-config gas limits.
- If owner executes manually/cancels, bot-origin reserve returns to bot pool.

## 6. Policy coverage summary
Strict controls:
- DeFi approval guardrails (`DeFiApprovalPolicy` with operator-wide approval block).

Delay controls:
- large transfer delay,
- first receiver delay,
- first EOA receiver delay (DeFi-oriented),
- first risky spender/recipient delays in DeFi compensating policies,
- scheduled execution re-check with current-delay enforcement.

## 6A. Current test coverage
Current on-chain suite (`246` tests) covers:
- wallet creation and initial state,
- base-pack behavior and add-on enablement,
- delayed transfer and queue lifecycle paths,
- threshold boundaries around large-transfer triggers,
- mixed multi-queue interleaving stress,
- router behavior when policy `evaluate()` reverts,
- factory owner-auth restriction,
- safe ERC721/ERC1155 inbound transfer hooks,
- unknown-selector hardening for DeFi receiver paths,
- schedule reserve lifecycle (`scheduleWithReserve` / `topUp` / `cancel` release),
- queue-executor relayer execution with unlock gating,
- bot gas pool auto-reserve + refund + manual-return flows.

## 6B. Policy evaluation failure semantics
- if any policy `evaluate()` reverts, router evaluation reverts (fail-closed).
- This avoids fail-open bypass but introduces availability risk when a policy is faulty.

## 7. Execution fee model (B2C foundation)
- Fee charging applies on successful `executeNow` and `executeScheduled`.
- `schedule` does not charge execution fee.
- Fee basis:
  - `gasUsed = gasStart - gasleft()`
  - `feeDue = (gasUsed * tx.gasprice * feePpm) / 1_000_000`
- Immutable hard cap: `MAX_EXECUTION_FEE_CAP_PPM = 5000` (`0.5%` of gas cost).
- Fee config updates are timelocked and observable on-chain.
- Fee collection is best-effort and non-blocking.
- Fee payout respects queue reserve floor.

## 7A. Queue automation economics
- Auto-reserve default comes from bot pool for each `schedule(...)` call.
- Explicit reserve funding paths still exist (`scheduleWithReserve`, `topUpScheduledReserve`).
- Relayer refund comes from tx reserve and is capped by configured gas limits.
- Queue automation still requires an external sender (owner or relayer); there is no autonomous chain-native execution.

## 8. Metadata trust model
Every admitted policy must expose:
- `policyKey()`
- `policyName()`
- `policyDescription()`
- `policyConfigVersion()`
- `policyConfig()`

Admission enforcement exists in registry/router paths.

## 9. Known limitations and tradeoffs
- Add-on disable path does not exist in current router.
- Registry/entitlement changes do not remove already-enabled add-ons.
- ERC20 thresholds are normalized to 1e18 units via token `decimals()` (still not price-aware).
- Tokens with non-standard/missing `decimals()` metadata fall back to 18-decimal interpretation.
- Large-transfer policy only covers ETH value + ERC20 `transfer` / `transferFrom`.
- Delay is review time, not absolute prevention if owner later executes malicious intent.
- Endpoint/device/signing-environment compromise remains out of protocol control.
- `recovery` is reserved metadata only.
- If relayer is offline, owner can still execute manually.

## 10. Trust boundaries
Users still trust:
- signer wallet integrity,
- frontend integrity,
- RPC read integrity,
- deployed contract correctness,
- governance/operations around registry and entitlement lifecycle.
