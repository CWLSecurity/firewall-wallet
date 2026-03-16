# Verify Firewall Vault Deployment (Current v1 / v1.5)

## 1) Verify core wiring
For target deployment verify:
- `FirewallFactory`
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

## 2) Verify registry packs
Expected curated packs:
- Base `0` Conservative
- Base `1` DeFi Trader
- Add-on `2` Approval Hardening
- Add-on `3` New Receiver 24h Delay
- Add-on `4` Large Transfer 24h Delay

For registry reconstruction verify:
- `packCount() == 3`
- `packIdAt(0..2)` returns `0,1,2` in registration order
- `getPackMeta(packId)` returns expected `active`, `packType`, `metadata`, `slug`, `version`, `policyCount`

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

Expected keys include:
- `infinite-approval-v1`
- `defi-approval-v1`
- `approval-to-new-spender-delay-v1`
- `erc20-first-new-recipient-delay-v1`
- `large-transfer-delay-v1`
- `new-receiver-delay-v1`
- `new-eoa-receiver-delay-v1`

## 5) Verify policy parameters
Read structured config from `policyConfig()` and verify expected key/value pairs.
Legacy getters can be used as cross-check.

Strict approval policy:
- `allowPermit()` and behavior expectations in strict packs.
- `approval_limit_functional` must be `false` in strict mode metadata.

DeFi compensating policies:
- `DELAY_SECONDS()` on spender/recipient delay policies.
- known-state scope expectations:
  - spender policy keying: `(vault, token, spender)`
  - recipient policy keying: `(vault, token, recipient)`

## 6) Verify security behavior assumptions
- Decision order remains `REVERT > DELAY > ALLOW`.
- Strict non-zero approval hard blocks are present in strict packs.
- DeFi pack includes spender/recipient compensating controls.
- `executeScheduled` path is policy-rechecked:
  - current `Revert` blocks execution,
  - current `Delay` requires `max(originalUnlockTime, createdAt + currentDelaySeconds)`,
  - current `Allow` still requires original unlock time.

## 7) Verify queue introspection/read paths
- `nextNonce()` for queue nonce upper-bound.
- `scheduledTxIdByNonce(nonce)` for deterministic txId lookup.
- `getScheduled(txId)` for existence/executed/unlock/dataHash.

## 8) Verify execution fee safety controls
- `MAX_EXECUTION_FEE_CAP()` / `MAX_EXECUTION_FEE_CAP_PPM` equals hard cap (`0.5%` of gas cost).
- `currentExecutionFeeConfig()` matches expected active config.
- `pendingExecutionFeeConfig()` exposes pending config and activation time when proposal exists.
- activation is timelocked:
  - propose first
  - activation only after timelock.
- `schedule(...)` path should not emit/charge execution fee.
- fee basis and telemetry checks:
  - confirm `ExecutionFeePaid` logs include `gasUsed`, `gasPrice`, `feeDue`, `feePaid`,
  - confirm `feeDue = (gasUsed * gasPrice * feePpm) / 1_000_000`.
- best-effort semantics checks:
  - insufficient vault balance may produce `feePaid < feeDue`,
  - fee transfer failure should not revert protected execution.

## 9) Verify B2B foundation primitives
- protocol mapping:
  - `ProtocolRegistry.resolveProtocol(target)`
  - protocol enumeration/meta getters
- trusted vault checks:
  - `TrustedVaultRegistry.isRecognizedVault(vault)`
- factory-origin vault checks:
  - `FirewallFactory.isFactoryVault(vault)`
- protocol interaction event path:
  - `FirewallModule` emits protocol interaction signal for known active protocol target.

## 10) Verify documented limitations
- Add-ons persist once enabled.
- Registry deactivation/entitlement revocation does not remove enabled add-ons.
- Expiring subscription-style add-on validity is unsupported without router semantic changes.
- ERC20 thresholding in large transfer policy is raw-unit based.
- Large transfer policy scope is not universal arbitrary-calldata economic coverage.
- Unknown-contract allowlist reconstruction requires `AllowedSet` event indexing.
- `recovery` is currently reserved metadata only.
- Execution fee is module-measured gas based and best-effort (not guaranteed-revenue accounting).
