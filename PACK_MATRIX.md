# Firewall Vault Pack Matrix (Canonical)

Last updated: 2026-04-28

## Pack Taxonomy
Base packs:
- Base `0` Conservative (`Vault` in UI)
- Base `1` DeFi Trader

Add-on packs:
- Add-on `2` New Receiver 24h Delay
- Add-on `3` Large Transfer 24h Delay

## Matrix
| Pack | Type | Included policies | Key parameters (defaults) | Intended profile | Core caveats |
|---|---|---|---|---|---|
| Conservative (`0`) | BASE | `LargeTransferDelayPolicy`, `NewReceiverDelayPolicy` | `LargeTransferDelayPolicy(ETH_THRESHOLD_WEI=10 ether, ERC20_THRESHOLD_UNITS=10 ether, DELAY_SECONDS=3600)`; `NewReceiverDelayPolicy(DELAY_SECONDS=3600)` | Vault-first protection with low routine friction | First new receiver delay includes contracts; large-transfer threshold is fixed and amount-based |
| DeFi Trader (`1`) | BASE | `DeFiApprovalPolicy`, `ApprovalToNewSpenderDelayPolicy`, `Erc20FirstNewRecipientDelayPolicy`, `LargeTransferDelayPolicy`, `NewEOAReceiverDelayPolicy` | `DeFiApprovalPolicy(ALLOW_MAX_APPROVAL=true, ALLOW_PERMIT=true, BLOCK_SET_APPROVAL_FOR_ALL_TRUE=true)`; `ApprovalToNewSpenderDelayPolicy(DELAY_SECONDS=1800)`; `Erc20FirstNewRecipientDelayPolicy(DELAY_SECONDS=1800)`; `LargeTransferDelayPolicy(ETH_THRESHOLD_WEI=0.25 ether, ERC20_THRESHOLD_UNITS=0.25 ether, DELAY_SECONDS=1800)`; `NewEOAReceiverDelayPolicy(DELAY_SECONDS=1800, unknown_contract_selector_action=delay_first_call, unknown_contract_selector_scope=target+selector, unknown_eoa_selector_action=delay_first_call)` | Active DeFi usage with guardrails | First-risk controls are token-scoped (`vault+token+spender/recipient`); first new EOA transfer remains delayed; unknown-selector calls are delayed for first-time EOAs and first-time `(target,selector)` contract interactions |
| New Receiver 24h Delay (`2`) | ADDON | `NewReceiverDelayPolicy` | `DELAY_SECONDS=86400` | 24h first-receiver review window | Persistent once enabled in current router line |
| Large Transfer 24h Delay (`3`) | ADDON | `LargeTransferDelayPolicy` | `ETH_THRESHOLD_WEI=10 ether`, `ERC20_THRESHOLD_UNITS=10 ether`, `DELAY_SECONDS=86400` | 24h high-value outflow delay | Persistent once enabled in current router line |

## Composition Rules
- Effective policy set = `base pack + enabled add-on snapshots`.
- Decision fold = `REVERT > DELAY > ALLOW`.
- Add-ons cannot weaken base behavior.
- Current router model keeps enabled add-ons active (no disable path).
- Duplicate policy addresses are rejected.
- Admissible policies require introspection metadata.

## Scheduled Queue Semantics
- `executeScheduled(txId)` re-checks current policy state.
- Execution requires:
  - current decision is not `Revert`, and
  - delay condition satisfied when current decision is `Delay`.
- Additive automation path:
  - `schedule(...)` auto-reserves per-tx gas budget from Vault bot pool,
  - `scheduleWithReserve(...)` / `topUpScheduledReserve(...)` remain available for explicit reserve funding,
  - `setQueueExecutor(executor, enabled)` grants/revokes relayer execution rights,
  - `executeScheduledByExecutor(...)` allows authorized relayer execution without owner key in bot,
  - owner-only `executeScheduled(...)` remains available as manual fallback.
- Reserve behavior:
  - per-tx reserve tracked via `scheduledReserve(txId)`,
  - aggregate reserve tracked via `totalScheduledReserve()`,
  - bot-origin reserve tracked via `scheduledBotPoolReserve(txId)`,
  - reserve is released on cancel or execution.

## Large Transfer Caveats
- Trigger comparator: `>=`.
- ERC20 threshold is raw token units (`ERC20_THRESHOLD_UNITS`), not price-normalized value.
- Policy scope is intentionally narrow (`ETH value`, ERC20 `transfer`, `transferFrom`).

## Optional Policies Not in Default Curated Packs
- `UnknownContractBlockPolicy` exists in codebase, not in default curated packs.

## Reconstruction APIs
- `packCount()` / `packIdAt(index)`
- `getPackMeta(packId)`
- `getPackPolicies(packId)`
