# Firewall Vault v1 Pack Matrix (Canonical)

Last updated: 2026-03-16

## Pack taxonomy
Base packs:
- Base `0` Conservative
- Base `1` DeFi Trader

Add-on packs:
- Add-on `2` Approval Hardening
- Add-on `3` New Receiver 24h Delay
- Add-on `4` Large Transfer 24h Delay

## Matrix
| Pack | Type | Included policies | Key parameters (defaults) | Intended user profile | Core caveats |
|---|---|---|---|---|---|
| Conservative (`0`) | BASE | `InfiniteApprovalPolicy`, `LargeTransferDelayPolicy`, `NewReceiverDelayPolicy` | `InfiniteApprovalPolicy(allowPermit=false)`; `LargeTransferDelayPolicy(ETH_THRESHOLD_WEI=0.05 ether, ERC20_THRESHOLD_UNITS=0.05 ether, DELAY_SECONDS=3600)`; `NewReceiverDelayPolicy(DELAY_SECONDS=3600)` | Users prioritizing strict baseline safety | Higher friction by design; first new receiver delays include contracts |
| DeFi Trader (`1`) | BASE | `DeFiApprovalPolicy`, `ApprovalToNewSpenderDelayPolicy`, `Erc20FirstNewRecipientDelayPolicy`, `LargeTransferDelayPolicy`, `NewEOAReceiverDelayPolicy` | `DeFiApprovalPolicy(ALLOW_MAX_APPROVAL=true, ALLOW_PERMIT=true, BLOCK_SET_APPROVAL_FOR_ALL_TRUE=true)`; `ApprovalToNewSpenderDelayPolicy(DELAY_SECONDS=1800)`; `Erc20FirstNewRecipientDelayPolicy(DELAY_SECONDS=1800)`; `LargeTransferDelayPolicy(ETH_THRESHOLD_WEI=0.25 ether, ERC20_THRESHOLD_UNITS=0.25 ether, DELAY_SECONDS=1800)`; `NewEOAReceiverDelayPolicy(DELAY_SECONDS=1800)` | Active DeFi users needing lower friction contract interactions | First-risk controls are token-scoped (`vault+token+spender/recipient`); first new EOA transfer paths are still delayed |
| Approval Hardening (`2`) | ADDON | `InfiniteApprovalPolicy` | `InfiniteApprovalPolicy(approvalLimit=max, allowPermit=false)` | Strict approval protection. Blocks risky token approval patterns including permit-style approvals. | Add-on is persistent once enabled in current router |
| New Receiver 24h Delay (`3`) | ADDON | `NewReceiverDelayPolicy` | `NewReceiverDelayPolicy(DELAY_SECONDS=86400)` | Delays the first transfer to any new receiver by 24 hours. | Add-on is persistent once enabled in current router |
| Large Transfer 24h Delay (`4`) | ADDON | `LargeTransferDelayPolicy` | `LargeTransferDelayPolicy(ETH_THRESHOLD_WEI=1 ether, ERC20_THRESHOLD_UNITS=1, DELAY_SECONDS=86400)` | Delays large ETH and ERC20 transfers by 24 hours. | Add-on is persistent once enabled in current router |

## Composition rules
- Effective policy set: `base pack + enabled add-on snapshots`.
- Final decision folding: `REVERT > DELAY > ALLOW`.
- Add-ons cannot weaken base behavior.
- Enabled add-ons are permanent snapshots (one-time premium upgrade model).
- Subscription-style expiring add-on validity is incompatible with current router semantics without core changes.
- Duplicate policy addresses are rejected by router checks.
- Policy registration rejects non-contract policy addresses.
- Policy registration/binding requires policy introspection metadata:
  - `policyKey`, `policyName`, `policyDescription`, `policyConfigVersion`, `policyConfig`.

## Monetization alignment
- Premium add-on packs follow one-time permanent upgrade semantics.
- Execution fee (when enabled) applies to `executeNow`/`executeScheduled` only and is best-effort.
- Canonical monetization/trust wording: `MONETIZATION.md`.

## Scheduled queue semantics
- `executeScheduled(txId)` always re-checks current policy.
- Execution is allowed only when:
  - current decision is not `Revert`, and
  - current time satisfies `max(originalUnlockTime, createdAt + currentDelaySeconds)` when current decision is `Delay`.

## Large transfer caveat
- Delay trigger uses `>=` threshold semantics.
- ERC20 thresholding compares raw token units (`ERC20_THRESHOLD_UNITS`), not economically normalized value.
- Coverage is limited to native ETH value and ERC20 `transfer` / `transferFrom` selector shapes.

## Optional policies not in default packs
- `UnknownContractBlockPolicy` exists in codebase but is not part of default curated packs (`0`, `1`, `2`).
- Its allowlist is mapping-based and non-enumerable on-chain; full allowlist reconstruction requires `AllowedSet` event indexing.

## Pack reconstruction APIs
- `packCount()` / `packIdAt(index)` enumerate known pack ids.
- `getPackMeta(packId)` returns:
  - `active`
  - `packType`
  - `metadata` hash
  - `slug`
  - `version`
  - `policyCount`
- `getPackPolicies(packId)` returns the canonical policy address list.
