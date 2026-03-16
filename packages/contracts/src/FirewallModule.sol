// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Decision} from "./interfaces/IFirewallPolicy.sol";
import {PolicyRouter} from "./PolicyRouter.sol";
import {IProtocolRegistry} from "./interfaces/IProtocolRegistry.sol";

error Firewall_NotInitialized();
error Firewall_Unauthorized();
error Firewall_RevertedByPolicy();
error Firewall_AllowNotSchedulable();
error Firewall_ZeroAddress();
error Firewall_ReentrantCall();
error Firewall_FeeAdminUnauthorized();
error Firewall_InvalidFeeConfig(uint32 feePpm, address feeReceiver);
error Firewall_NoPendingFeeConfig();
error Firewall_FeeConfigNotReady(uint256 activateAt);
error Firewall_InvalidProtocolRegistry(address protocolRegistry);

error Firewall_NotScheduled(bytes32 txId);
error Firewall_AlreadyScheduled(bytes32 txId);
error Firewall_NotUnlocked(bytes32 txId, uint256 unlockTime);
error Firewall_AlreadyExecuted(bytes32 txId);
error Firewall_ExecutionFailed(bytes revertData);

contract FirewallModule {
    bytes32 internal constant STORAGE_SLOT =
        bytes32(uint256(keccak256("firewall.vault.storage.v1")) - 1);
    uint32 public constant EXECUTION_FEE_DENOMINATOR_PPM = 1_000_000;
    uint32 public constant MAX_EXECUTION_FEE_CAP_PPM = 5_000; // 0.5%
    uint48 public constant EXECUTION_FEE_CONFIG_TIMELOCK = 1 days;

    struct ExecutionFeeConfig {
        uint32 feePpm;
        address feeReceiver;
    }

    struct ScheduledTx {
        address to;
        uint256 value;
        bytes data;
        uint48 unlockTime;
        uint48 createdAt;
        uint96 nonce;
        bool executed;
    }

    struct S {
        address router;
        address owner;
        // Reserved for future recovery flows; not used in current execution authorization paths.
        address recovery;
        address feeConfigAdmin;
        address protocolRegistry;
        bool entered;
        uint96 nonce;
        ExecutionFeeConfig executionFeeConfig;
        ExecutionFeeConfig pendingExecutionFeeConfig;
        uint48 pendingExecutionFeeActivationTime;
        mapping(bytes32 => ScheduledTx) scheduled;
        mapping(uint96 => bytes32) scheduledTxIdByNonce;
    }

    function _s() internal pure returns (S storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    event Initialized(address router, address owner, address recovery);
    event FeeConfigAdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    event ExecutionFeeConfigProposed(
        uint32 indexed feePpm, address indexed feeReceiver, uint48 indexed activateAt
    );
    event ExecutionFeeConfigActivated(uint32 indexed feePpm, address indexed feeReceiver);
    event ExecutionFeePaid(
        address indexed feeReceiver,
        bool indexed scheduled,
        bytes32 indexed txId,
        uint256 feeDue,
        uint256 feePaid,
        uint256 gasUsed,
        uint256 gasPrice
    );
    event ProtocolRegistryUpdated(address indexed previousRegistry, address indexed newRegistry);
    event ProtocolInteractionObserved(
        bytes32 indexed protocolId,
        address indexed vault,
        address indexed target,
        bytes4 selector,
        bool scheduled,
        bytes32 txId
    );
    event Scheduled(bytes32 indexed txId, address indexed to, uint256 value, uint48 unlockTime);
    event Executed(bytes32 indexed txId, address indexed to, uint256 value);
    event ExecutedNow(address indexed to, uint256 value);

    // NEW
    event Cancelled(bytes32 indexed txId);
    event TransactionScheduled(bytes32 indexed txId, address indexed to, uint256 value, uint48 unlockTime);
    event TransactionExecuted(bytes32 indexed txId, address indexed to, uint256 value);
    event TransactionCancelled(bytes32 indexed txId);

    function init(
        address router_,
        address owner_,
        address recovery_,
        address feeConfigAdmin_,
        address protocolRegistry_
    ) external {
        S storage s = _s();
        if (s.owner != address(0)) revert Firewall_Unauthorized();
        if (router_ == address(0) || owner_ == address(0) || feeConfigAdmin_ == address(0)) {
            revert Firewall_ZeroAddress();
        }
        if (protocolRegistry_ != address(0) && protocolRegistry_.code.length == 0) {
            revert Firewall_InvalidProtocolRegistry(protocolRegistry_);
        }
        s.router = router_;
        s.owner = owner_;
        s.recovery = recovery_;
        s.feeConfigAdmin = feeConfigAdmin_;
        s.protocolRegistry = protocolRegistry_;
        emit Initialized(router_, owner_, recovery_);
    }

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    modifier onlyFeeConfigAdmin() {
        if (msg.sender != _s().feeConfigAdmin) revert Firewall_FeeAdminUnauthorized();
        _;
    }

    modifier nonReentrant() {
        S storage s = _s();
        if (s.entered) revert Firewall_ReentrantCall();
        s.entered = true;
        _;
        s.entered = false;
    }

    function _onlyOwner() internal view {
        if (_s().owner == address(0)) revert Firewall_NotInitialized();
        if (msg.sender != _s().owner) revert Firewall_Unauthorized();
    }

    function computeTxId(
        address vault,
        uint96 nonce,
        address to,
        uint256 value,
        bytes calldata data
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(vault, nonce, to, value, keccak256(data)));
    }

    function schedule(address to, uint256 value, bytes calldata data)
        external
        onlyOwner
        nonReentrant
        returns (bytes32 txId)
    {
        S storage s = _s();

        (Decision d, uint48 delaySeconds) = PolicyRouter(s.router).evaluate(address(this), to, value, data);

        if (d == Decision.Revert) revert Firewall_RevertedByPolicy();
        if (d == Decision.Allow) revert Firewall_AllowNotSchedulable();

        uint96 scheduledNonce = s.nonce++;
        txId = computeTxId(address(this), scheduledNonce, to, value, data);

        if (s.scheduled[txId].unlockTime != 0) revert Firewall_AlreadyScheduled(txId);

        uint48 unlock = uint48(block.timestamp) + delaySeconds;
        uint48 createdAt = uint48(block.timestamp);

        s.scheduled[txId] = ScheduledTx({
            to: to,
            value: value,
            data: data,
            unlockTime: unlock,
            createdAt: createdAt,
            nonce: scheduledNonce,
            executed: false
        });
        s.scheduledTxIdByNonce[scheduledNonce] = txId;

        emit Scheduled(txId, to, value, unlock);
        emit TransactionScheduled(txId, to, value, unlock);
    }

    // NEW: отмена отложенной транзакции (до исполнения)
    function cancelScheduled(bytes32 txId) external onlyOwner {
        S storage s = _s();
        ScheduledTx storage t = s.scheduled[txId];

        if (t.unlockTime == 0) revert Firewall_NotScheduled(txId);
        if (t.executed) revert Firewall_AlreadyExecuted(txId);

        delete s.scheduled[txId];

        emit Cancelled(txId);
        emit TransactionCancelled(txId);
    }

    function executeScheduled(bytes32 txId) external onlyOwner nonReentrant {
        uint256 gasStart = gasleft();
        S storage s = _s();
        ScheduledTx storage t = s.scheduled[txId];

        if (t.unlockTime == 0) revert Firewall_NotScheduled(txId);
        if (t.executed) revert Firewall_AlreadyExecuted(txId);
        // Re-check current policy state before executing a previously scheduled intent.
        // Execution semantics:
        // - Revert => always blocked.
        // - Delay  => unlock must satisfy max(original unlock, createdAt + current delay).
        // - Allow  => original unlock still applies.
        (Decision d, uint48 currentDelaySeconds) = PolicyRouter(s.router).evaluate(address(this), t.to, t.value, t.data);
        if (d == Decision.Revert) revert Firewall_RevertedByPolicy();

        uint48 requiredUnlockTime = t.unlockTime;
        if (d == Decision.Delay) {
            uint48 currentPolicyUnlock = t.createdAt + currentDelaySeconds;
            if (currentPolicyUnlock > requiredUnlockTime) {
                requiredUnlockTime = currentPolicyUnlock;
            }
        }

        if (block.timestamp < requiredUnlockTime) {
            revert Firewall_NotUnlocked(txId, requiredUnlockTime);
        }

        t.executed = true;

        (bool ok, bytes memory ret) = t.to.call{value: t.value}(t.data);
        if (!ok) revert Firewall_ExecutionFailed(ret);

        PolicyRouter(s.router).notifyExecuted(address(this), t.to, t.value, t.data);
        _emitProtocolInteraction(t.to, t.data, true, txId);
        _chargeExecutionFee(gasStart, true, txId);

        emit Executed(txId, t.to, t.value);
        emit TransactionExecuted(txId, t.to, t.value);
    }

    function executeNow(address to, uint256 value, bytes calldata data) external onlyOwner nonReentrant {
        uint256 gasStart = gasleft();
        S storage s = _s();

        (Decision d, ) = PolicyRouter(s.router).evaluate(address(this), to, value, data);
        if (d != Decision.Allow) revert Firewall_RevertedByPolicy();

        (bool ok, bytes memory ret) = to.call{value: value}(data);
        if (!ok) revert Firewall_ExecutionFailed(ret);

        PolicyRouter(s.router).notifyExecuted(address(this), to, value, data);
        _emitProtocolInteraction(to, data, false, bytes32(0));
        _chargeExecutionFee(gasStart, false, bytes32(0));

        emit ExecutedNow(to, value);
    }

    receive() external payable {}

    function router() external view returns (address) {
        return _s().router;
    }

    function feeConfigAdmin() external view returns (address) {
        return _s().feeConfigAdmin;
    }

    function protocolRegistry() external view returns (address) {
        return _s().protocolRegistry;
    }

    function MAX_EXECUTION_FEE_CAP() external pure returns (uint32) {
        return MAX_EXECUTION_FEE_CAP_PPM;
    }

    function currentExecutionFeeConfig() external view returns (uint32 feePpm, address feeReceiver) {
        ExecutionFeeConfig storage cfg = _s().executionFeeConfig;
        return (cfg.feePpm, cfg.feeReceiver);
    }

    function pendingExecutionFeeConfig()
        external
        view
        returns (uint32 feePpm, address feeReceiver, uint48 activateAt, bool exists)
    {
        S storage s = _s();
        exists = s.pendingExecutionFeeActivationTime != 0;
        ExecutionFeeConfig storage cfg = s.pendingExecutionFeeConfig;
        return (cfg.feePpm, cfg.feeReceiver, s.pendingExecutionFeeActivationTime, exists);
    }

    function transferFeeConfigAdmin(address newAdmin) external onlyFeeConfigAdmin {
        if (newAdmin == address(0)) revert Firewall_ZeroAddress();
        S storage s = _s();
        address oldAdmin = s.feeConfigAdmin;
        s.feeConfigAdmin = newAdmin;
        emit FeeConfigAdminTransferred(oldAdmin, newAdmin);
    }

    function setProtocolRegistry(address protocolRegistry_) external onlyFeeConfigAdmin {
        if (protocolRegistry_ != address(0) && protocolRegistry_.code.length == 0) {
            revert Firewall_InvalidProtocolRegistry(protocolRegistry_);
        }
        S storage s = _s();
        address oldRegistry = s.protocolRegistry;
        s.protocolRegistry = protocolRegistry_;
        emit ProtocolRegistryUpdated(oldRegistry, protocolRegistry_);
    }

    function proposeExecutionFeeConfig(uint32 feePpm, address feeReceiver) external onlyFeeConfigAdmin {
        _assertValidExecutionFeeConfig(feePpm, feeReceiver);
        S storage s = _s();
        uint48 activateAt = uint48(block.timestamp) + EXECUTION_FEE_CONFIG_TIMELOCK;
        s.pendingExecutionFeeConfig = ExecutionFeeConfig({feePpm: feePpm, feeReceiver: feeReceiver});
        s.pendingExecutionFeeActivationTime = activateAt;
        emit ExecutionFeeConfigProposed(feePpm, feeReceiver, activateAt);
    }

    function activateExecutionFeeConfig() external {
        S storage s = _s();
        uint48 activateAt = s.pendingExecutionFeeActivationTime;
        if (activateAt == 0) revert Firewall_NoPendingFeeConfig();
        if (block.timestamp < activateAt) revert Firewall_FeeConfigNotReady(activateAt);

        ExecutionFeeConfig memory cfg = s.pendingExecutionFeeConfig;
        s.executionFeeConfig = cfg;
        delete s.pendingExecutionFeeConfig;
        s.pendingExecutionFeeActivationTime = 0;
        emit ExecutionFeeConfigActivated(cfg.feePpm, cfg.feeReceiver);
    }

    /// @notice Returns the next scheduling nonce.
    ///         Off-chain indexers can iterate [0, nextNonce) with scheduledTxIdByNonce()
    ///         and then inspect each tx via getScheduled().
    function nextNonce() external view returns (uint96) {
        return _s().nonce;
    }

    /// @notice Returns txId that was assigned to a given schedule nonce.
    ///         Mapping is append-only and kept for queue discoverability.
    function scheduledTxIdByNonce(uint96 nonce) external view returns (bytes32) {
        return _s().scheduledTxIdByNonce[nonce];
    }

    /// @notice Read-only view of a scheduled tx without exposing calldata.
    /// @return exists True if scheduled and not executed.
    /// @return executed True if already executed.
    /// @return to Target address.
    /// @return value Native value (ETH).
    /// @return unlockTime Timestamp when execution is allowed.
    /// @return dataHash keccak256(data) of calldata.
    function getScheduled(bytes32 txId)
        external
        view
        returns (
            bool exists,
            bool executed,
            address to,
            uint256 value,
            uint48 unlockTime,
            bytes32 dataHash
        )
    {
        ScheduledTx storage t = _s().scheduled[txId];
        if (t.unlockTime == 0) {
            return (false, false, address(0), 0, 0, bytes32(0));
        }

        executed = t.executed;
        exists = !executed;
        to = t.to;
        value = t.value;
        unlockTime = t.unlockTime;
        dataHash = keccak256(t.data);
    }

    function _assertValidExecutionFeeConfig(uint32 feePpm, address feeReceiver) internal pure {
        if (feePpm > MAX_EXECUTION_FEE_CAP_PPM) {
            revert Firewall_InvalidFeeConfig(feePpm, feeReceiver);
        }
        if (feePpm != 0 && feeReceiver == address(0)) {
            revert Firewall_InvalidFeeConfig(feePpm, feeReceiver);
        }
    }

    function _chargeExecutionFee(uint256 gasStart, bool scheduled, bytes32 txId) internal {
        ExecutionFeeConfig storage cfg = _s().executionFeeConfig;
        uint32 feePpm = cfg.feePpm;
        address feeReceiver = cfg.feeReceiver;
        if (feePpm == 0 || feeReceiver == address(0)) return;

        uint256 gasUsed = gasStart - gasleft();
        uint256 gasCostWei = gasUsed * tx.gasprice;
        uint256 feeDue = (gasCostWei * feePpm) / EXECUTION_FEE_DENOMINATOR_PPM;
        if (feeDue == 0) return;

        uint256 feePaid = feeDue;
        uint256 balance = address(this).balance;
        if (feePaid > balance) feePaid = balance;

        if (feePaid > 0) {
            (bool sent,) = feeReceiver.call{value: feePaid}("");
            if (!sent) feePaid = 0;
        }

        emit ExecutionFeePaid(feeReceiver, scheduled, txId, feeDue, feePaid, gasUsed, tx.gasprice);
    }

    function _emitProtocolInteraction(address target, bytes memory data, bool scheduled, bytes32 txId) internal {
        address registry = _s().protocolRegistry;
        if (registry == address(0)) return;

        bytes32 protocolId;
        bool active;
        try IProtocolRegistry(registry).resolveProtocol(target) returns (bytes32 id, bool isActive) {
            protocolId = id;
            active = isActive;
        } catch {
            return;
        }

        if (protocolId == bytes32(0) || !active) return;
        emit ProtocolInteractionObserved(
            protocolId, address(this), target, _selectorFromData(data), scheduled, txId
        );
    }

    function _selectorFromData(bytes memory data) internal pure returns (bytes4 sel) {
        if (data.length < 4) return bytes4(0);
        return bytes4(data);
    }
}
