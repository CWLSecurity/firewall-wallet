# CORE FREEZE v1

Status: Snapshot (Phase 1)
Date: 2026-02-25

This document freezes the Core scope, interfaces, storage layout, invariants, non-goals, and threat model for Firewall Vault v1.

## 1) Scope (Core Contracts)

Core contracts in this repository:
- `FirewallModule` (`packages/contracts/src/FirewallModule.sol`)
- `PolicyRouter` (`packages/contracts/src/PolicyRouter.sol`)
- Policies:
  - `LargeTransferDelayPolicy` (`packages/contracts/src/policies/LargeTransferDelayPolicy.sol`)
  - `NewReceiverDelayPolicy` (`packages/contracts/src/policies/NewReceiverDelayPolicy.sol`)
  - `InfiniteApprovalPolicy` (`packages/contracts/src/policies/InfiniteApprovalPolicy.sol`)
  - `UnknownContractBlockPolicy` (`packages/contracts/src/policies/UnknownContractBlockPolicy.sol`)

Core contract referenced in product docs:
- Factory (Wallet deployment contract).

## 2) Public/External Interfaces (Functions + Events)

### FirewallModule
Events:
- `Initialized(address router, address owner, address recovery)`
- `Scheduled(bytes32 indexed txId, address indexed to, uint256 value, uint48 unlockTime)`
- `Executed(bytes32 indexed txId, address indexed to, uint256 value)`
- `ExecutedNow(address indexed to, uint256 value)`
- `Cancelled(bytes32 indexed txId)`

External/Public:
- `function init(address router_, address owner_, address recovery_) external`
- `function computeTxId(address vault, uint96 nonce, address to, uint256 value, bytes calldata data) public pure returns (bytes32)`
- `function schedule(address to, uint256 value, bytes calldata data) external onlyOwner returns (bytes32 txId)`
- `function cancelScheduled(bytes32 txId) external onlyOwner`
- `function executeScheduled(bytes32 txId) external onlyOwner`
- `function executeNow(address to, uint256 value, bytes calldata data) external onlyOwner`
- `receive() external payable`

### PolicyRouter
Events:
- `FirewallModuleSet(address indexed firewallModule)`
- `PostExecHookFailed(address indexed policy, bytes returndata)`

External/Public:
- `constructor(address[] memory _policies)`
- `function policyCount() external view returns (uint256)`
- `function setFirewallModule(address _module) external`
- `function evaluate(address vault, address to, uint256 value, bytes calldata data) external view returns (Decision decision, uint48 delaySeconds)`
- `function notifyExecuted(address vault, address to, uint256 value, bytes calldata data) external`

### LargeTransferDelayPolicy
External/Public:
- `constructor(uint256 _thresholdWei, uint48 _delaySeconds)`
- `function evaluate(address, address, uint256 value, bytes calldata) external view returns (Decision decision, uint48 delayOut)`

### NewReceiverDelayPolicy
External/Public:
- `constructor(uint48 _delaySeconds)`
- `function evaluate(address vault, address to, uint256, bytes calldata) external view returns (Decision decision, uint48 delayOut)`
- `function onExecuted(address vault, address to, uint256, bytes calldata) external`

### InfiniteApprovalPolicy
External/Public:
- `constructor(uint256 approvalLimit_)`
- `function evaluate(address, address, uint256, bytes calldata data) external view returns (Decision decision, uint48 delaySeconds)`

### UnknownContractBlockPolicy
Events:
- `AllowedSet(address indexed target, bool allowed)`

External/Public:
- `constructor(address owner_)`
- `function setAllowed(address target, bool isAllowed) external`
- `function setAllowedBatch(address[] calldata targets, bool isAllowed) external`
- `function evaluate(address, address to, uint256, bytes calldata) external view returns (Decision decision, uint48 delaySeconds)`

### Factory
MVP interface per product context:
- Deploy new `PolicyRouter` per wallet
- Deploy new `FirewallModule`
- Call `init(router, owner, recovery)`
- Bind router to wallet (one-time)
- Emit `WalletCreated` event

## 3) Storage Layout (Core Contracts)

### FirewallModule (uses explicit storage slot)
Storage slot:
- `bytes32 internal constant STORAGE_SLOT = bytes32(uint256(keccak256("firewall.vault.storage.v1")) - 1);`

Struct `S` at `STORAGE_SLOT`:
- `address router`
- `address owner`
- `address recovery`
- `uint96 nonce`
- `mapping(bytes32 => ScheduledTx) scheduled`

Struct `ScheduledTx`:
- `address to`
- `uint256 value`
- `bytes data`
- `uint48 unlockTime`
- `bool executed`

### PolicyRouter
State:
- `IFirewallPolicy[] public policies`
- `address public immutable owner`
- `address public firewallModule`

### LargeTransferDelayPolicy
State:
- `uint256 public immutable THRESHOLD_WEI`
- `uint48 public immutable DELAY_SECONDS`

### NewReceiverDelayPolicy
State:
- `uint48 public immutable DELAY_SECONDS`
- `mapping(address => mapping(address => bool)) public knownReceivers`

### InfiniteApprovalPolicy
State:
- `uint256 public immutable approvalLimit`

### UnknownContractBlockPolicy
State:
- `address public immutable owner`
- `mapping(address => bool) public allowed`

## 4) Explicit Invariants

Global:
- Core contracts are immutable (no proxy, no upgrade hooks, no admin override).
- No monetization logic inside contracts.
- No hidden backdoors or off-chain dependencies.

FirewallModule:
- `init` is callable only once.
- `onlyOwner` gates all sensitive functions.
- Delay path cannot bypass router evaluation.
- A scheduled transaction cannot execute twice.
- Cancel removes a scheduled transaction correctly (deletes storage).

PolicyRouter:
- `setFirewallModule` is callable only by `owner` and only once (legacy; unused when bound at construction).
- `notifyExecuted` can only be called by the bound `firewallModule`.
 - Router is per-wallet (Factory deploys a fresh router for each wallet).
 - Router owner is the wallet owner (set at construction). Firewall module is bound at construction.

Policies:
- Policy evaluation is deterministic and pure-view (no external calls).

Factory (when implemented):
- Must not be able to control deployed wallets after creation.

## 5) Explicit Non-Goals

- No proxy pattern or upgradeability of Core.
- No admin override or emergency seize.
- No monetization/subscription checks in Core contracts.
- No off-chain dependency for allow/deny decisions.
- No hidden policy bypass or external admin hooks.

## 6) Threat Model Summary

Protects against:
- Direct wallet drain attempts (policy-based allow/revert/delay).
- Infinite approval exploits (explicit block policy).
- Transfers to unknown contracts (allowlist policy).
- New receiver transfer risk (delay + post-exec learning).
- Reentrancy on delayed execution (state set before external call).

Does NOT protect against:
- Malicious or compromised owner keys.
- Malicious policy contracts configured by the owner.
- External protocol risks after an allowed transaction executes.
- MEV, front-running, or network-level censorship.
- Social engineering or signing malicious transactions.
