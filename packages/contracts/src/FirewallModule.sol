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
error Firewall_ZeroReserveAmount();
error Firewall_InsufficientUnreservedBalance(uint256 available, uint256 required);
error Firewall_InvalidPermitExecutor(address expected, address actual);
error Firewall_PermitExpired(uint256 deadline);
error Firewall_PermitNonceUsed(uint256 nonce);
error Firewall_InvalidPermitSignature();
error Firewall_InvalidPermitSignatureLength(uint256 providedLength);
error Firewall_InvalidPermitSigner(address signer, address owner);
error Firewall_ReserveRefundTransferFailed(address executor, uint256 refundWei);
error Firewall_QueueExecutorUnauthorized(address caller);

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

interface IERC1155Receiver is IERC165 {
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4);

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);
}

contract FirewallModule is IERC165, IERC721Receiver, IERC1155Receiver {
    bytes32 internal constant STORAGE_SLOT =
        bytes32(uint256(keccak256("firewall.vault.storage.v1")) - 1);
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant EIP712_NAME_HASH = keccak256("FirewallModule");
    bytes32 internal constant EIP712_VERSION_HASH = keccak256("2");
    bytes32 internal constant EXECUTE_SCHEDULED_PERMIT_TYPEHASH = keccak256(
        "ExecuteScheduledPermit(bytes32 txId,address executor,uint256 nonce,uint256 deadline,uint256 maxFeePerGasWei,uint256 maxGasUsed,uint256 maxRefundWei)"
    );
    uint256 internal constant SECP256K1N_DIV_2 =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;
    uint32 public constant EXECUTION_FEE_DENOMINATOR_PPM = 1_000_000;
    uint32 public constant MAX_EXECUTION_FEE_CAP_PPM = 5_000; // 0.5%
    uint48 public constant EXECUTION_FEE_CONFIG_TIMELOCK = 1 days;
    uint256 public constant DEFAULT_BOT_AUTO_RESERVE_WEI = 30_000_000_000_000; // 0.00003 ether
    uint256 public constant DEFAULT_BOT_REFUND_MAX_GAS_PRICE_WEI = 100_000_000; // 0.1 gwei
    uint256 public constant DEFAULT_BOT_REFUND_MAX_GAS_USED = 300_000;

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

    struct ExecuteScheduledPermit {
        address executor;
        uint256 nonce;
        uint256 deadline;
        uint256 maxFeePerGasWei;
        uint256 maxGasUsed;
        uint256 maxRefundWei;
    }

    struct ScheduledExecutionContext {
        address to;
        uint256 value;
        bytes data;
        uint256 txReserveWei;
        uint256 reservedFloorWei;
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
        uint256 botGasPoolWei;
        uint256 botAutoReservePerTxWei;
        uint256 botRefundMaxGasPriceWei;
        uint256 botRefundMaxGasUsed;
        uint256 totalScheduledReserveWei;
        mapping(bytes32 => ScheduledTx) scheduled;
        mapping(uint96 => bytes32) scheduledTxIdByNonce;
        mapping(bytes32 => uint256) scheduledReserveWei;
        mapping(bytes32 => uint256) scheduledBotPoolReserveWei;
        mapping(uint256 => bool) usedExecutePermitNonces;
        mapping(address => bool) queueExecutorAllowed;
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
    event ScheduledReserveFunded(
        bytes32 indexed txId, uint256 addedReserveWei, uint256 txReserveWei, uint256 totalReservedWei
    );
    event ScheduledReserveReleased(bytes32 indexed txId, uint256 releasedReserveWei, uint256 totalReservedWei);
    event BotGasBufferFunded(address indexed payer, uint256 addedWei, uint256 totalWei);
    event BotGasConfigUpdated(
        uint256 autoReserveWei, uint256 refundMaxGasPriceWei, uint256 refundMaxGasUsed
    );
    event BotReserveAllocated(bytes32 indexed txId, uint256 reserveWei, uint256 remainingBotGasWei);
    event BotReserveReleased(bytes32 indexed txId, uint256 returnedWei, uint256 botGasWei);
    event QueueExecutorUpdated(address indexed executor, bool enabled);
    event Executed(bytes32 indexed txId, address indexed to, uint256 value);
    event ExecutedByExecutor(
        bytes32 indexed txId, address indexed executor, address indexed to, uint256 value
    );
    event ExecutorRefundPaid(
        bytes32 indexed txId,
        address indexed executor,
        uint256 refundDueWei,
        uint256 refundPaidWei,
        uint256 gasUsed,
        uint256 gasPriceWei
    );
    event ExecutedWithPermit(
        bytes32 indexed txId,
        address indexed executor,
        uint256 indexed permitNonce,
        uint256 refundDueWei,
        uint256 refundPaidWei,
        uint256 gasUsed,
        uint256 gasPriceWei
    );
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
    ) external payable {
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
        s.botAutoReservePerTxWei = DEFAULT_BOT_AUTO_RESERVE_WEI;
        s.botRefundMaxGasPriceWei = DEFAULT_BOT_REFUND_MAX_GAS_PRICE_WEI;
        s.botRefundMaxGasUsed = DEFAULT_BOT_REFUND_MAX_GAS_USED;
        if (msg.value > 0) {
            s.botGasPoolWei = msg.value;
            emit BotGasBufferFunded(msg.sender, msg.value, msg.value);
        }
        emit BotGasConfigUpdated(
            s.botAutoReservePerTxWei, s.botRefundMaxGasPriceWei, s.botRefundMaxGasUsed
        );
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

    modifier onlyQueueExecutor() {
        _onlyQueueExecutor();
        _;
    }

    function _onlyOwner() internal view {
        if (_s().owner == address(0)) revert Firewall_NotInitialized();
        if (msg.sender != _s().owner) revert Firewall_Unauthorized();
    }

    function _onlyQueueExecutor() internal view {
        if (!_s().queueExecutorAllowed[msg.sender]) {
            revert Firewall_QueueExecutorUnauthorized(msg.sender);
        }
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
        txId = _schedule(to, value, data, true);
    }

    function scheduleWithReserve(address to, uint256 value, bytes calldata data)
        external
        payable
        onlyOwner
        nonReentrant
        returns (bytes32 txId)
    {
        txId = _schedule(to, value, data, false);
        if (msg.value > 0) {
            _fundScheduledReserve(txId, msg.value);
        }
    }

    function topUpScheduledReserve(bytes32 txId) external payable onlyOwner {
        if (msg.value == 0) revert Firewall_ZeroReserveAmount();

        S storage s = _s();
        ScheduledTx storage t = s.scheduled[txId];
        if (t.unlockTime == 0) revert Firewall_NotScheduled(txId);
        if (t.executed) revert Firewall_AlreadyExecuted(txId);

        _fundScheduledReserve(txId, msg.value);
    }

    function cancelScheduled(bytes32 txId) external onlyOwner {
        S storage s = _s();
        ScheduledTx storage t = s.scheduled[txId];

        if (t.unlockTime == 0) revert Firewall_NotScheduled(txId);
        if (t.executed) revert Firewall_AlreadyExecuted(txId);

        _releaseScheduledReserve(txId);
        delete s.scheduled[txId];

        emit Cancelled(txId);
        emit TransactionCancelled(txId);
    }

    function executeScheduled(bytes32 txId) external onlyOwner nonReentrant {
        uint256 gasStart = gasleft();
        ScheduledExecutionContext memory ctx = _prepareAndExecuteScheduled(txId);
        _releaseScheduledReserve(txId);
        _emitProtocolInteraction(ctx.to, ctx.data, true, txId);
        _chargeExecutionFee(gasStart, true, txId, ctx.reservedFloorWei);

        emit Executed(txId, ctx.to, ctx.value);
        emit TransactionExecuted(txId, ctx.to, ctx.value);
    }

    function executeScheduledByExecutor(bytes32 txId) external onlyQueueExecutor nonReentrant {
        uint256 gasStart = gasleft();
        ScheduledExecutionContext memory ctx = _prepareAndExecuteScheduled(txId);
        (uint256 refundDueWei, uint256 refundPaidWei, uint256 gasUsed) =
            _payExecutorRefund(msg.sender, gasStart, ctx.txReserveWei, ctx.reservedFloorWei);
        _deductBotPoolReserveForRefund(txId, refundPaidWei);
        _releaseScheduledReserve(txId);
        _emitProtocolInteraction(ctx.to, ctx.data, true, txId);
        _chargeExecutionFee(gasStart, true, txId, ctx.reservedFloorWei);

        emit ExecutorRefundPaid(txId, msg.sender, refundDueWei, refundPaidWei, gasUsed, tx.gasprice);
        emit ExecutedByExecutor(txId, msg.sender, ctx.to, ctx.value);
        emit Executed(txId, ctx.to, ctx.value);
        emit TransactionExecuted(txId, ctx.to, ctx.value);
    }

    function executeScheduledWithPermit(
        bytes32 txId,
        ExecuteScheduledPermit calldata permit,
        bytes calldata signature
    ) external nonReentrant {
        _verifyExecutePermit(txId, permit, signature);
        uint256 gasStart = gasleft();
        _s().usedExecutePermitNonces[permit.nonce] = true;

        ScheduledExecutionContext memory ctx = _prepareAndExecuteScheduled(txId);
        (uint256 refundDueWei, uint256 refundPaidWei, uint256 gasUsed) = _payPermitExecutorRefund(
            permit, gasStart, ctx.txReserveWei, ctx.reservedFloorWei
        );
        _deductBotPoolReserveForRefund(txId, refundPaidWei);

        _releaseScheduledReserve(txId);
        _emitProtocolInteraction(ctx.to, ctx.data, true, txId);
        _chargeExecutionFee(gasStart, true, txId, ctx.reservedFloorWei);

        emit ExecutedWithPermit(
            txId,
            permit.executor,
            permit.nonce,
            refundDueWei,
            refundPaidWei,
            gasUsed,
            tx.gasprice
        );
        emit Executed(txId, ctx.to, ctx.value);
        emit TransactionExecuted(txId, ctx.to, ctx.value);
    }

    function executeNow(address to, uint256 value, bytes calldata data) external onlyOwner nonReentrant {
        uint256 gasStart = gasleft();
        S storage s = _s();
        _assertSufficientUnreservedBalance(value, s.totalScheduledReserveWei);

        (Decision d, ) = PolicyRouter(s.router).evaluate(address(this), to, value, data);
        if (d != Decision.Allow) revert Firewall_RevertedByPolicy();

        (bool ok, bytes memory ret) = to.call{value: value}(data);
        if (!ok) revert Firewall_ExecutionFailed(ret);

        PolicyRouter(s.router).notifyExecuted(address(this), to, value, data);
        _emitProtocolInteraction(to, data, false, bytes32(0));
        _chargeExecutionFee(gasStart, false, bytes32(0), s.totalScheduledReserveWei);

        emit ExecutedNow(to, value);
    }

    receive() external payable {}

    /// @notice ERC721 safe transfer hook.
    ///         Accepts inbound NFTs to keep Vault custody deterministic for end users.
    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return 0x150b7a02;
    }

    /// @notice ERC1155 single transfer hook.
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return 0xf23a6e61;
    }

    /// @notice ERC1155 batch transfer hook.
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return 0xbc197c81;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == 0x01ffc9a7 // IERC165
            || interfaceId == 0x150b7a02 // IERC721Receiver
            || interfaceId == 0x4e2312e0; // IERC1155Receiver
    }

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

    function setQueueExecutor(address executor, bool enabled) external onlyOwner {
        if (executor == address(0)) revert Firewall_ZeroAddress();
        _s().queueExecutorAllowed[executor] = enabled;
        emit QueueExecutorUpdated(executor, enabled);
    }

    function isQueueExecutor(address executor) external view returns (bool) {
        return _s().queueExecutorAllowed[executor];
    }

    function fundBotGasBuffer() external payable onlyOwner {
        if (msg.value == 0) revert Firewall_ZeroReserveAmount();
        S storage s = _s();
        s.botGasPoolWei += msg.value;
        emit BotGasBufferFunded(msg.sender, msg.value, s.botGasPoolWei);
    }

    function setBotGasConfig(
        uint256 autoReserveWei,
        uint256 refundMaxGasPriceWei,
        uint256 refundMaxGasUsed
    ) external onlyOwner {
        S storage s = _s();
        s.botAutoReservePerTxWei = autoReserveWei;
        s.botRefundMaxGasPriceWei = refundMaxGasPriceWei;
        s.botRefundMaxGasUsed = refundMaxGasUsed;
        emit BotGasConfigUpdated(autoReserveWei, refundMaxGasPriceWei, refundMaxGasUsed);
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

    function executePermitDigest(bytes32 txId, ExecuteScheduledPermit calldata permit)
        external
        view
        returns (bytes32)
    {
        return _executePermitDigest(txId, permit);
    }

    /// @notice Returns the next scheduling nonce.
    ///         Off-chain indexers can iterate [0, nextNonce) with scheduledTxIdByNonce()
    ///         and then inspect each tx via getScheduled().
    function nextNonce() external view returns (uint96) {
        return _s().nonce;
    }

    function scheduledReserve(bytes32 txId) external view returns (uint256) {
        return _s().scheduledReserveWei[txId];
    }

    function totalScheduledReserve() external view returns (uint256) {
        return _s().totalScheduledReserveWei;
    }

    function botGasBuffer() external view returns (uint256) {
        return _s().botGasPoolWei;
    }

    function botGasConfig()
        external
        view
        returns (uint256 autoReserveWei, uint256 refundMaxGasPriceWei, uint256 refundMaxGasUsed)
    {
        S storage s = _s();
        return (s.botAutoReservePerTxWei, s.botRefundMaxGasPriceWei, s.botRefundMaxGasUsed);
    }

    function scheduledBotPoolReserve(bytes32 txId) external view returns (uint256) {
        return _s().scheduledBotPoolReserveWei[txId];
    }

    function isExecutePermitNonceUsed(uint256 nonce) external view returns (bool) {
        return _s().usedExecutePermitNonces[nonce];
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

    function _chargeExecutionFee(uint256 gasStart, bool scheduled, bytes32 txId, uint256 reservedFloorWei)
        internal
    {
        ExecutionFeeConfig storage cfg = _s().executionFeeConfig;
        uint32 feePpm = cfg.feePpm;
        address feeReceiver = cfg.feeReceiver;
        if (feePpm == 0 || feeReceiver == address(0)) return;

        uint256 gasUsed = gasStart - gasleft();
        uint256 gasCostWei = gasUsed * tx.gasprice;
        uint256 feeDue = (gasCostWei * feePpm) / EXECUTION_FEE_DENOMINATOR_PPM;
        if (feeDue == 0) return;

        uint256 feePaid = feeDue;
        uint256 spendable = _availableUnreservedBalance(reservedFloorWei);
        if (feePaid > spendable) feePaid = spendable;

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

    function _verifyExecutePermit(
        bytes32 txId,
        ExecuteScheduledPermit calldata permit,
        bytes calldata signature
    ) internal view {
        if (msg.sender != permit.executor) {
            revert Firewall_InvalidPermitExecutor(permit.executor, msg.sender);
        }
        if (block.timestamp > permit.deadline) {
            revert Firewall_PermitExpired(permit.deadline);
        }
        if (_s().usedExecutePermitNonces[permit.nonce]) {
            revert Firewall_PermitNonceUsed(permit.nonce);
        }

        bytes32 digest = _executePermitDigest(txId, permit);
        address signer = _recoverSigner(digest, signature);
        address owner = _s().owner;
        if (signer != owner) {
            revert Firewall_InvalidPermitSigner(signer, owner);
        }
    }

    function _prepareAndExecuteScheduled(bytes32 txId)
        internal
        returns (ScheduledExecutionContext memory ctx)
    {
        S storage s = _s();
        ScheduledTx storage t = s.scheduled[txId];

        if (t.unlockTime == 0) revert Firewall_NotScheduled(txId);
        if (t.executed) revert Firewall_AlreadyExecuted(txId);

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

        uint256 txReserveWei = s.scheduledReserveWei[txId];
        uint256 reservedFloorWei = s.totalScheduledReserveWei - txReserveWei;
        _assertSufficientUnreservedBalance(t.value, reservedFloorWei);

        t.executed = true;
        (bool ok, bytes memory ret) = t.to.call{value: t.value}(t.data);
        if (!ok) revert Firewall_ExecutionFailed(ret);

        PolicyRouter(s.router).notifyExecuted(address(this), t.to, t.value, t.data);

        ctx = ScheduledExecutionContext({
            to: t.to,
            value: t.value,
            data: t.data,
            txReserveWei: txReserveWei,
            reservedFloorWei: reservedFloorWei
        });
    }

    function _payPermitExecutorRefund(
        ExecuteScheduledPermit calldata permit,
        uint256 gasStart,
        uint256 txReserveWei,
        uint256 reservedFloorWei
    ) internal returns (uint256 refundDueWei, uint256 refundPaidWei, uint256 gasUsed) {
        gasUsed = gasStart - gasleft();

        uint256 effectiveGasPrice = tx.gasprice;
        if (permit.maxFeePerGasWei < effectiveGasPrice) {
            effectiveGasPrice = permit.maxFeePerGasWei;
        }

        uint256 cappedGasUsed = gasUsed;
        if (permit.maxGasUsed > 0 && cappedGasUsed > permit.maxGasUsed) {
            cappedGasUsed = permit.maxGasUsed;
        }

        refundDueWei = cappedGasUsed * effectiveGasPrice;
        if (permit.maxRefundWei > 0 && refundDueWei > permit.maxRefundWei) {
            refundDueWei = permit.maxRefundWei;
        }
        if (refundDueWei > txReserveWei) {
            refundDueWei = txReserveWei;
        }

        uint256 refundableWei = _availableUnreservedBalance(reservedFloorWei);
        refundPaidWei = refundDueWei;
        if (refundPaidWei > refundableWei) {
            refundPaidWei = refundableWei;
        }
        if (refundPaidWei > 0) {
            (bool sent,) = permit.executor.call{value: refundPaidWei}("");
            if (!sent) revert Firewall_ReserveRefundTransferFailed(permit.executor, refundPaidWei);
        }
    }

    function _payExecutorRefund(
        address executor,
        uint256 gasStart,
        uint256 txReserveWei,
        uint256 reservedFloorWei
    ) internal returns (uint256 refundDueWei, uint256 refundPaidWei, uint256 gasUsed) {
        S storage s = _s();
        gasUsed = gasStart - gasleft();

        uint256 cappedGasUsed = gasUsed;
        if (s.botRefundMaxGasUsed > 0 && cappedGasUsed > s.botRefundMaxGasUsed) {
            cappedGasUsed = s.botRefundMaxGasUsed;
        }

        uint256 effectiveGasPrice = tx.gasprice;
        if (s.botRefundMaxGasPriceWei > 0 && effectiveGasPrice > s.botRefundMaxGasPriceWei) {
            effectiveGasPrice = s.botRefundMaxGasPriceWei;
        }

        refundDueWei = cappedGasUsed * effectiveGasPrice;
        if (refundDueWei > txReserveWei) {
            refundDueWei = txReserveWei;
        }

        uint256 refundableWei = _availableUnreservedBalance(reservedFloorWei);
        refundPaidWei = refundDueWei;
        if (refundPaidWei > refundableWei) {
            refundPaidWei = refundableWei;
        }
        if (refundPaidWei > 0) {
            (bool sent,) = executor.call{value: refundPaidWei}("");
            if (!sent) revert Firewall_ReserveRefundTransferFailed(executor, refundPaidWei);
        }
    }

    function _schedule(address to, uint256 value, bytes calldata data, bool reserveFromBotPool)
        internal
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
        if (reserveFromBotPool) {
            _autoReserveFromBotPool(txId);
        }
    }

    function _fundScheduledReserve(bytes32 txId, uint256 amountWei) internal {
        if (amountWei == 0) revert Firewall_ZeroReserveAmount();

        S storage s = _s();
        uint256 nextTxReserve = s.scheduledReserveWei[txId] + amountWei;
        s.scheduledReserveWei[txId] = nextTxReserve;
        s.totalScheduledReserveWei += amountWei;

        emit ScheduledReserveFunded(txId, amountWei, nextTxReserve, s.totalScheduledReserveWei);
    }

    function _releaseScheduledReserve(bytes32 txId) internal {
        S storage s = _s();
        uint256 botReservedWei = s.scheduledBotPoolReserveWei[txId];
        if (botReservedWei > 0) {
            delete s.scheduledBotPoolReserveWei[txId];
            s.botGasPoolWei += botReservedWei;
            emit BotReserveReleased(txId, botReservedWei, s.botGasPoolWei);
        }

        uint256 reservedWei = s.scheduledReserveWei[txId];
        if (reservedWei == 0) return;

        delete s.scheduledReserveWei[txId];
        s.totalScheduledReserveWei -= reservedWei;
        emit ScheduledReserveReleased(txId, reservedWei, s.totalScheduledReserveWei);
    }

    function _autoReserveFromBotPool(bytes32 txId) internal {
        S storage s = _s();
        uint256 reserveTargetWei = s.botAutoReservePerTxWei;
        if (reserveTargetWei == 0) return;

        uint256 availablePoolWei = s.botGasPoolWei;
        if (availablePoolWei == 0) return;

        uint256 reserveWei = reserveTargetWei;
        if (reserveWei > availablePoolWei) {
            reserveWei = availablePoolWei;
        }
        if (reserveWei == 0) return;

        s.botGasPoolWei = availablePoolWei - reserveWei;
        s.scheduledBotPoolReserveWei[txId] += reserveWei;
        _fundScheduledReserve(txId, reserveWei);
        emit BotReserveAllocated(txId, reserveWei, s.botGasPoolWei);
    }

    function _deductBotPoolReserveForRefund(bytes32 txId, uint256 consumedWei) internal {
        if (consumedWei == 0) return;

        S storage s = _s();
        uint256 botReserveWei = s.scheduledBotPoolReserveWei[txId];
        if (botReserveWei == 0) return;

        if (consumedWei >= botReserveWei) {
            s.scheduledBotPoolReserveWei[txId] = 0;
            return;
        }

        unchecked {
            s.scheduledBotPoolReserveWei[txId] = botReserveWei - consumedWei;
        }
    }

    function _assertSufficientUnreservedBalance(uint256 requiredWei, uint256 reservedFloorWei) internal view {
        uint256 availableWei = _availableUnreservedBalance(reservedFloorWei);
        if (availableWei < requiredWei) {
            revert Firewall_InsufficientUnreservedBalance(availableWei, requiredWei);
        }
    }

    function _availableUnreservedBalance(uint256 reservedFloorWei) internal view returns (uint256) {
        uint256 balance = address(this).balance;
        if (balance <= reservedFloorWei) return 0;
        unchecked {
            return balance - reservedFloorWei;
        }
    }

    function _executePermitDigest(bytes32 txId, ExecuteScheduledPermit calldata permit)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                EXECUTE_SCHEDULED_PERMIT_TYPEHASH,
                txId,
                permit.executor,
                permit.nonce,
                permit.deadline,
                permit.maxFeePerGasWei,
                permit.maxGasUsed,
                permit.maxRefundWei
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        return keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, EIP712_NAME_HASH, EIP712_VERSION_HASH, block.chainid, address(this))
        );
    }

    function _recoverSigner(bytes32 digest, bytes calldata signature) internal pure returns (address signer) {
        if (signature.length != 65) {
            revert Firewall_InvalidPermitSignatureLength(signature.length);
        }

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (uint256(s) > SECP256K1N_DIV_2 || (v != 27 && v != 28)) {
            revert Firewall_InvalidPermitSignature();
        }

        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) {
            revert Firewall_InvalidPermitSignature();
        }
    }
}
