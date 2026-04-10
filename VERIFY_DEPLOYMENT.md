# Verify Firewall Vault Deployment (Current v2)

Last updated: 2026-03-25

## 1) Verify core wiring
For target deployment verify:
- `FirewallFactory`
- `PolicyRouterDeployer`
- `PolicyPackRegistry`
- entitlement manager
- wallet `FirewallModule`
- wallet `PolicyRouter`
- optional `ProtocolRegistry`
- optional `TrustedVaultRegistry`

Check router immutables:
- owner
- firewall module address
- registry address
- base pack id

Factory checks:
- `createWallet(owner, ...)` enforces caller equals owner.
- `createWallet(...)` is payable and forwards init value to module bot pool.
- `feeConfigAdmin()` defaults to wallet owner.

## 2) Verify registry packs
Expected curated packs:
- Base `0` Conservative
- Base `1` DeFi Trader
- Add-on `2` Approval Hardening
- Add-on `3` New Receiver 24h Delay
- Add-on `4` Large Transfer 24h Delay

For registry reconstruction verify:
- `packCount() == 5`
- `packIdAt(0..4)` returns `0,1,2,3,4`
- `getPackMeta(packId)` returns expected metadata

For each pack verify:
- active status
- pack type (`BASE` / `ADDON`)
- policy list

## 3) Verify wallet policy snapshots
For wallet router verify:
- base `policies(i)` list
- enabled add-on pack ids
- enabled add-on policy snapshot entries

## 4) Verify policy identity
For each active policy read:
- `policyKey()`
- `policyName()`
- `policyDescription()`
- `policyConfigVersion()`
- `policyConfig()`

## 5) Verify policy parameters
Read structured config from `policyConfig()` and verify expected key/value pairs.

Current test-stage note:
- conservative large-transfer thresholds may be `0` in current deploy scripts.
- production target remains restoring conservative threshold to `0.05 ETH`.

## 6) Verify critical behavior assumptions
- Decision order remains `REVERT > DELAY > ALLOW`.
- Strict non-zero approval hard blocks are present in strict packs.
- DeFi pack includes spender/recipient compensating controls.
- DeFi line delays first unknown-selector call:
  - to first-time EOAs,
  - and per first-time `(contract target, selector)` pair.
- `executeScheduled` path is policy-rechecked.

## 7) Verify queue introspection/read paths
- `nextNonce()` for queue nonce upper-bound.
- `scheduledTxIdByNonce(nonce)` for deterministic txId lookup.
- `getScheduled(txId)` for existence/executed/unlock/dataHash.
- reserve views:
  - `scheduledReserve(txId)`
  - `totalScheduledReserve()`
- bot pool views:
  - `botGasBuffer()`
  - `botGasConfig()`
  - `scheduledBotPoolReserve(txId)`
- queue executor views:
  - `isQueueExecutor(executor)`

## 7A) Verify queue automation path (authorized relayer)
- `schedule(...)`:
  - delayed tx is created,
  - auto-reserve may be allocated from bot pool.
- `scheduleWithReserve(...)` / `topUpScheduledReserve(...)`:
  - explicit reserve funding increases reserve while tx is pending.
- `setQueueExecutor(relayer, true)`:
  - only owner can authorize relayer executor.
- `executeScheduledByExecutor(...)`:
  - rejects unauthorized caller (`Firewall_QueueExecutorUnauthorized`),
  - rejects early execution (`Firewall_NotUnlocked`),
  - applies policy re-check before execution.
- after successful relayer execution:
  - tx becomes executed in `getScheduled(txId)`,
  - reserve is released (`scheduledReserve(txId) == 0`).

## 7B) Verify bot refund and reserve accounting
- On relayer execution, check `ExecutorRefundPaid` event fields:
  - `refundDueWei`, `refundPaidWei`, `gasUsed`, `gasPriceWei`.
- Confirm refund caps from `botGasConfig()` are respected.
- For owner-manual execution/cancel path, confirm bot-origin reserve returns to pool.

## 8) Verify execution fee safety controls
- `MAX_EXECUTION_FEE_CAP()` equals hard cap (`0.5%` of gas cost).
- `currentExecutionFeeConfig()` matches expected config.
- `pendingExecutionFeeConfig()` is consistent with timelock behavior.
- `schedule(...)` path should not emit/charge execution fee.
- fee payout should not intentionally consume protected reserved queue floor.

## 9) Verify B2B foundation primitives
- `ProtocolRegistry.resolveProtocol(target)`
- `TrustedVaultRegistry.isRecognizedVault(vault)`
- `FirewallFactory.isFactoryVault(vault)`
- `FirewallFactory.latestWalletOfOwner(owner)`

## 10) Verify documented limitations
- Add-ons persist once enabled.
- Registry deactivation/entitlement revocation does not remove enabled add-ons.
- ERC20 thresholding is raw-unit based.
- `recovery` is reserved metadata only.
- Queue automation needs external sender (owner or relayer).

## 11) Verify NFT receive hooks on wallet module
For wallet `FirewallModule`, verify:
- `supportsInterface(0x01ffc9a7) == true` (`IERC165`)
- `supportsInterface(0x150b7a02) == true` (`IERC721Receiver`)
- `supportsInterface(0x4e2312e0) == true` (`IERC1155Receiver`)
