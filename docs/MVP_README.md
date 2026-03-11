# Firewall Vault MVP

## Product Summary
Firewall Vault is a non-custodial on-chain transaction firewall wallet for EVM networks.

A user creates a dedicated wallet contract (`FirewallModule`) via `FirewallFactory`. Every outgoing action from that wallet is checked by a `PolicyRouter`, which aggregates policy decisions (`Allow`, `Delay`, `Revert`) from a fixed base pack plus optional enabled add-on snapshots.

The MVP goal is hard on-chain enforcement for common drain vectors while keeping daily DeFi usage possible.

## Networks Supported
- Base (primary / first production target)
- Local Anvil (development and smoke checks)
- Base fork (simulation against Base state)

## Core Components
- `PolicyPackRegistry`: curated on-chain catalog of base/add-on policy packs.
- `FirewallFactory`: creates new user wallets and binds them to a base pack id.
- `FirewallModule`: user wallet with `executeNow`, `schedule`, `executeScheduled`, `cancelScheduled`, `getScheduled`.
- `PolicyRouter`: evaluates all policies for each action and applies final decision rules:
  - any policy `Revert` => final `Revert`
  - otherwise, if any policy `Delay` => final `Delay` with max delay
  - otherwise => `Allow`
- `SimpleEntitlementManager` / `IEntitlementManager`: minimal hook for add-on access control.
- Policies (MVP base packs):
  - `InfiniteApprovalPolicy`
  - `LargeTransferDelayPolicy`
  - `NewReceiverDelayPolicy`

## Base packs
Base pack IDs are used at wallet creation:
- Preset `0` = Conservative
- Preset `1` = DeFi Trader

Base pack is permanent per wallet and cannot be removed.
Add-on packs can only add extra checks and cannot weaken base protections.
Enabled add-ons are snapshotted into the wallet router at enable time.
Later registry deactivation only blocks new enablements and does not disable already-enabled wallets.

### Preset 0: Conservative
Included policies:
- `InfiniteApprovalPolicy(approvalLimit=max, allowPermit=false)`
- `LargeTransferDelayPolicy(...)`
- `NewReceiverDelayPolicy(...)`

Key behavior:
- ERC20 `transfer` / `transferFrom` to a new receiver: `Delay` (until receiver becomes known after successful execution).
- Large ERC20 transfer amount: `Delay` (amount above configured threshold).
- `approve(spender, type(uint256).max)`: `Revert`.
- `increaseAllowance(spender, x)`: allowed unless `x` crosses configured policy limit (with current max-limit config this stays allowed for practical values).
- `setApprovalForAll(operator, true)`: `Revert`.
- `permit(...)`: `Revert` (blocked in Preset 0).

### Preset 1: DeFi Trader
Included policies:
- `InfiniteApprovalPolicy(approvalLimit=max, allowPermit=true)`
- `LargeTransferDelayPolicy(...)`
- `NewReceiverDelayPolicy(...)`

Key behavior:
- ERC20 `transfer` / `transferFrom` to a new receiver: `Delay`.
- Large ERC20 transfer amount: `Delay`.
- `approve(spender, type(uint256).max)`: `Revert`.
- `increaseAllowance(spender, x)`: allowed unless `x` crosses configured policy limit (with current max-limit config this stays allowed for practical values).
- `setApprovalForAll(operator, true)`: `Revert`.
- `permit(...)`: allowed by `InfiniteApprovalPolicy` in Preset 1.

Note: final router decision is the aggregate across all policies. Even when permit is allowed by `InfiniteApprovalPolicy`, another policy can still return `Delay` for the same call context.

## Delayed Transactions
How delay works:
1. User calls `schedule(to, value, data)` on their `FirewallModule`.
2. Router evaluates the call:
   - `Revert` => rejected immediately
   - `Allow` => cannot be scheduled (use `executeNow`)
   - `Delay` => stored with unlock time and returned `txId`
3. After unlock time, user calls `executeScheduled(txId)`.
4. Optional cancellation before execution: `cancelScheduled(txId)`.

How to inspect delayed txs:
- On-chain read: `FirewallModule.getScheduled(txId)` returns:
  - `exists`, `executed`, `to`, `value`, `unlockTime`, `dataHash`
- Events for indexing and monitoring:
  - `Scheduled` / `TransactionScheduled`
  - `Executed` / `TransactionExecuted`
  - `Cancelled` / `TransactionCancelled`

## Threat Model Summary
Designed to reduce impact from:
- malicious infinite approvals,
- unsafe operator approvals,
- first-time receiver risk (delay window),
- large transfer risk (delay window).

Security posture:
- enforcement is on-chain,
- no custody transfer,
- policy checks happen before wallet execution,
- delayed path creates reaction time for owner.

## Non-Goals and Caveats (MVP)
- Not an anti-phishing UI layer.
- Not a guarantee against all social engineering.
- Not an upgradeable safety engine (core is immutable by design intent).
- Delay is not prevention if user intentionally executes malicious calls after unlock.
- Policies are explicit and deterministic; no off-chain ML/risk oracle.

## How To Verify Safety
- Run tests locally:
  - `forge build`
  - `forge test -vvv`
- Inspect open-source policy logic directly under `packages/contracts/src/`.
- Review preset wiring in deployment scripts under `packages/contracts/script/`.
- Verify deployed addresses:
  - from deployment outputs / logs,
  - by reading registry packs on-chain:
    - `getPackPolicies(packId)`
    - `isPackActive(packId)`
- Run smoke script to produce concrete wallet/router/txId traces for manual verification.

## Quickstart
From `packages/contracts`:

```bash
forge build
forge test -vvv
```

Deploy V2 factory on Base (example):

```bash
forge script script/DeployFactoryBaseMainnet.s.sol:DeployFactoryBaseMainnet \
  --rpc-url $BASE_RPC_URL \
  --private-key $DEPLOYER_PK \
  --broadcast
```

Run MVP smoke script on Anvil (self-deploy path):

```bash
forge script script/SmokeMvpBase.s.sol:SmokeMvpBase \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $DEPLOYER_PK \
  --broadcast -vvv
```

Run MVP smoke script on Base fork (attach or self-deploy):

```bash
forge script script/SmokeMvpBase.s.sol:SmokeMvpBase \
  --fork-url $BASE_RPC_URL \
  --private-key $DEPLOYER_PK \
  --broadcast -vvv
```

Optional env vars for smoke script:
- `MVP_FACTORY`: existing factory address to attach instead of deploying a new one.
- `MVP_RECOVERY`: recovery address (default is deployer).
