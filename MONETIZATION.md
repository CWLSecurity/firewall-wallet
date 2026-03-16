# Firewall Vault Monetization Model (Canonical)

Last updated: 2026-03-16

## 1. Executive summary
Firewall Vault currently monetizes B2C primarily through one-time premium add-on pack enablement and secondarily through an optional execution fee on protected execution paths.

For B2B, core contracts already include protocol/vault identification primitives that enable future licensing, analytics, and integration billing workflows. Live on-chain B2B billing is intentionally not implemented in the current architecture.

## 2. B2C monetization model
- Premium add-on packs are one-time permanent security upgrades.
- Add-on enablement uses router snapshot semantics:
  - on `enableAddonPack(packId)`, policy addresses are copied into router-owned active state,
  - post-enable registry/entitlement changes do not retroactively disable already-enabled packs.
- Pack subscriptions/expiring pack validity are incompatible with current router semantics unless core router behavior changes.

This aligns with the current security model because policy enforcement is deterministic from router active state and does not depend on live off-chain/business status checks.

## 3. B2C execution fee model
### Where fee is charged
- Charged only on successful:
  - `FirewallModule.executeNow(...)`
  - `FirewallModule.executeScheduled(...)`
- Not charged on:
  - `FirewallModule.schedule(...)`
  - failed/reverted execution attempts.

### Current formula and cap
- Runtime formula in module:
  - `feeDue = (gasUsed * tx.gasprice * feePpm) / 1_000_000`
  - `gasUsed = gasStart - gasleft()` measured inside `FirewallModule` execution path.
- Hard cap is immutable on-chain:
  - `MAX_EXECUTION_FEE_CAP_PPM = 5000` (0.5% in ppm denominator `1_000_000`).
- Fee config updates are timelocked and publicly introspectable:
  - `proposeExecutionFeeConfig(feePpm, feeReceiver)`
  - `pendingExecutionFeeConfig()`
  - `activateExecutionFeeConfig()`
  - `currentExecutionFeeConfig()`

### Best-effort collection semantics
- Fee transfer is best-effort and non-blocking:
  - `feePaid = min(feeDue, vaultBalanceAtChargeTime)`,
  - if transfer to `feeReceiver` fails, execution is not reverted.
- Execution safety/liveness is preserved even when fee is not fully collected.
- This is not guaranteed-revenue accounting.

### Predictability caveat
- The fee basis is module-measured execution gas and `tx.gasprice` in EVM context.
- It should not be described as an exact percentage of the user’s full network fee in every environment.

## 4. B2B monetization model
Current architecture is prepared for future B2B monetization paths, including:
- protocol licensing,
- protocol-specific integrations,
- protocol-specific packs,
- protocol analytics / usage billing (off-chain),
- trusted-vault partner integrations.

Implemented foundations support these paths, but:
- no live on-chain protocol billing is active,
- no protocol payment status currently gates or alters `FirewallModule` execution.

## 5. Core monetization primitives already present
- Execution fee controls in `FirewallModule`:
  - immutable cap constant/view,
  - timelocked pending->active config flow,
  - fee payment event with due/paid telemetry.
- `ProtocolRegistry`:
  - target contract -> protocol id mapping,
  - protocol metadata/status and enumeration.
- `ProtocolInteractionObserved` event from `FirewallModule`:
  - emitted when executed target resolves to a known active protocol.
- `TrustedVaultRegistry`:
  - on-chain recognized-vault primitive for partner integrations.
- `FirewallFactory.isFactoryVault(address)`:
  - immutable-origin primitive for factory-created vault detection.

## 6. Monetization boundaries and trust model
On-chain enforced now:
- policy decision enforcement (`REVERT > DELAY > ALLOW`),
- add-on snapshot permanence once enabled,
- execution fee cap/timelock configuration constraints.

Business/integration primitives (not default security boundaries):
- protocol registry mappings,
- trusted vault recognition flags,
- protocol interaction telemetry.

Still off-chain by design:
- protocol billing settlement,
- analytics aggregation/invoicing,
- commercial entitlement lifecycle beyond on-chain pack enable checks.

## 7. What would require core changes later
- Expiring/subscription pack model:
  - requires router semantics to support runtime validity/deactivation, which does not exist now.
- Strict fee collection mode:
  - would require explicit revert-on-unpaid-fee behavior (currently non-blocking by design).
- Stronger on-chain B2B settlement:
  - would require dedicated billing/entitlement contracts that become execution-relevant.

## 8. Recommended public positioning
Use precise wording:
- "Premium packs are one-time permanent security upgrades for a vault."
- "Execution fee is capped on-chain at 0.5% of module-measured execution gas cost, with timelocked config changes."
- "Current fee collection is best-effort and does not interrupt protected execution."
- "Protocol monetization primitives are implemented; live on-chain B2B billing is not yet implemented."

Avoid wording that implies:
- expiring premium pack subscriptions exist today,
- execution fee is an exact percentage of full network fee in all environments,
- protocol registry/trusted-vault primitives automatically enforce policy/security decisions.
