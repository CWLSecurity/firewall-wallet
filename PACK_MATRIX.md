# Firewall Vault Pack Matrix (Canonical)

Last updated: 2026-03-24

## Pack Taxonomy
Base packs:
- Base `0` Conservative (`Vault Safe` in UI)
- Base `1` DeFi Trader

Add-on packs:
- Add-on `2` Approval Hardening
- Add-on `3` New Receiver 24h Delay
- Add-on `4` Large Transfer 24h Delay

## Matrix
| Pack | Type | Included policies | Key parameters (defaults) | Intended profile | Core caveats |
|---|---|---|---|---|---|
| Conservative (`0`) | BASE | `InfiniteApprovalPolicy`, `LargeTransferDelayPolicy`, `NewReceiverDelayPolicy` | `InfiniteApprovalPolicy(allowPermit=false)`; `LargeTransferDelayPolicy(ETH_THRESHOLD_WEI=0.05 ether, ERC20_THRESHOLD_UNITS=0.05 ether, DELAY_SECONDS=3600)`; `NewReceiverDelayPolicy(DELAY_SECONDS=3600)` | Strict baseline safety | Higher friction; first new receiver delay includes contracts |
| DeFi Trader (`1`) | BASE | `DeFiApprovalPolicy`, `ApprovalToNewSpenderDelayPolicy`, `Erc20FirstNewRecipientDelayPolicy`, `LargeTransferDelayPolicy`, `NewEOAReceiverDelayPolicy` | `DeFiApprovalPolicy(ALLOW_MAX_APPROVAL=true, ALLOW_PERMIT=true, BLOCK_SET_APPROVAL_FOR_ALL_TRUE=true)`; `ApprovalToNewSpenderDelayPolicy(DELAY_SECONDS=1800)`; `Erc20FirstNewRecipientDelayPolicy(DELAY_SECONDS=1800)`; `LargeTransferDelayPolicy(ETH_THRESHOLD_WEI=0.25 ether, ERC20_THRESHOLD_UNITS=0.25 ether, DELAY_SECONDS=1800)`; `NewEOAReceiverDelayPolicy(DELAY_SECONDS=1800, unknown_contract_selector_action=delay_first_call)` | Active DeFi usage with guardrails | First-risk controls are token-scoped (`vault+token+spender/recipient`); first new EOA transfer remains delayed; first unknown-selector call to a new contract target is delayed |
| Approval Hardening (`2`) | ADDON | `InfiniteApprovalPolicy` | strict approval guard profile (`allowPermit=false`) | Extra approval hardening | Persistent once enabled in current router line |
| New Receiver 24h Delay (`3`) | ADDON | `NewReceiverDelayPolicy` | `DELAY_SECONDS=86400` | 24h first-receiver review window | Persistent once enabled in current router line |
| Large Transfer 24h Delay (`4`) | ADDON | `LargeTransferDelayPolicy` | `ETH_THRESHOLD_WEI=1 ether`, `ERC20_THRESHOLD_UNITS=1`, `DELAY_SECONDS=86400` | 24h high-value outflow delay | Persistent once enabled in current router line |

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
