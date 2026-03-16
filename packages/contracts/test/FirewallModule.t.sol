pragma solidity ^0.8.23;

import "forge-std/Test.sol";

// Импортируем сам контракт + ошибки (они на уровне файла)
import {
    FirewallModule,
    Firewall_Unauthorized,
    Firewall_RevertedByPolicy,
    Firewall_AllowNotSchedulable,
    Firewall_NotScheduled,
    Firewall_NotUnlocked,
    Firewall_AlreadyExecuted,
    Firewall_ExecutionFailed,
    Firewall_ZeroAddress,
    Firewall_InvalidFeeConfig,
    Firewall_FeeConfigNotReady,
    Firewall_FeeAdminUnauthorized
} from "../src/FirewallModule.sol";

import {Decision} from "../src/interfaces/IFirewallPolicy.sol";
import {ProtocolRegistry} from "../src/ProtocolRegistry.sol";

contract MockRouter {
    Decision public decision;
    uint48 public delaySeconds;

    uint256 public notifyCalls;

    constructor(Decision d, uint48 delay) {
        decision = d;
        delaySeconds = delay;
    }

    function evaluate(
        address,
        address,
        uint256,
        bytes calldata
    ) external view returns (Decision, uint48) {
        return (decision, delaySeconds);
    }

    function notifyExecuted(
        address,
        address,
        uint256,
        bytes calldata
    ) external {
        notifyCalls++;
    }

    function setDecision(Decision d, uint48 delay) external {
        decision = d;
        delaySeconds = delay;
    }
}

contract MockReceiver {
    address public lastSender;
    uint256 public lastValue;
    bytes public lastData;

    receive() external payable {
        lastSender = msg.sender;
        lastValue = msg.value;
        lastData = "";
    }

    fallback() external payable {
        lastSender = msg.sender;
        lastValue = msg.value;
        lastData = msg.data;
    }
}

contract RevertingReceiver {
    fallback() external payable {
        revert("NOPE");
    }

    receive() external payable {
        revert("NOPE");
    }
}

contract RevertingProtocolRegistry {
    function resolveProtocol(address) external pure returns (bytes32 protocolId, bool active) {
        revert("NO_PROTOCOL");
    }
}

contract FirewallModuleTest is Test {
    address internal OWNER = address(0xA11CE);
    address internal RECOVERY = address(0xB0B);
    address internal FEE_ADMIN = address(0xFEE);
    address internal FEE_RECEIVER = address(0xFAEE);

    MockReceiver internal receiver;

    function setUp() public {
        receiver = new MockReceiver();
    }

    function _deployAndInit(address router) internal returns (FirewallModule m) {
        m = new FirewallModule();
        vm.prank(OWNER);
        m.init(router, OWNER, RECOVERY, FEE_ADMIN, address(0));
    }

    // -------------------- init / auth --------------------

    function testInit_secondInit_revertsUnauthorized() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(OWNER);
        vm.expectRevert(Firewall_Unauthorized.selector);
        m.init(address(r), OWNER, RECOVERY, FEE_ADMIN, address(0));
    }

    function testInit_zeroRouter_revertsZeroAddress() public {
        FirewallModule m = new FirewallModule();
        vm.prank(OWNER);
        vm.expectRevert(Firewall_ZeroAddress.selector);
        m.init(address(0), OWNER, RECOVERY, FEE_ADMIN, address(0));
    }

    function testInit_zeroOwner_revertsZeroAddress() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = new FirewallModule();
        vm.prank(OWNER);
        vm.expectRevert(Firewall_ZeroAddress.selector);
        m.init(address(r), address(0), RECOVERY, FEE_ADMIN, address(0));
    }

    function testExecuteNow_onlyOwner_revertsForNonOwner() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(address(0xDEAD));
        vm.expectRevert(Firewall_Unauthorized.selector);
        m.executeNow(address(receiver), 0.1 ether, "");
    }

    function testSchedule_onlyOwner_revertsForNonOwner() public {
        MockRouter r = new MockRouter(Decision.Delay, 5);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(address(0xDEAD));
        vm.expectRevert(Firewall_Unauthorized.selector);
        m.schedule(address(receiver), 0.1 ether, "");
    }

    function testExecuteScheduled_onlyOwner_revertsForNonOwner() public {
        MockRouter r = new MockRouter(Decision.Delay, 5);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(address(0xDEAD));
        vm.expectRevert(Firewall_Unauthorized.selector);
        m.executeScheduled(bytes32(uint256(1)));
    }

    function testCancelScheduled_onlyOwner_revertsForNonOwner() public {
        MockRouter r = new MockRouter(Decision.Delay, 5);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(address(0xDEAD));
        vm.expectRevert(Firewall_Unauthorized.selector);
        m.cancelScheduled(bytes32(uint256(1)));
    }

    // -------------------- executeNow --------------------

    function testExecuteNow_whenAllow_executesAndNotifies() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.expectCall(
            address(r),
            abi.encodeWithSelector(
                MockRouter.evaluate.selector,
                address(m),
                address(receiver),
                0.2 ether,
                bytes("")
            )
        );

        vm.expectCall(
            address(r),
            abi.encodeWithSelector(
                MockRouter.notifyExecuted.selector,
                address(m),
                address(receiver),
                0.2 ether,
                bytes("")
            )
        );

        vm.prank(OWNER);
        m.executeNow(address(receiver), 0.2 ether, "");

        assertEq(address(receiver).balance, 0.2 ether);
        assertEq(receiver.lastSender(), address(m));
        assertEq(receiver.lastValue(), 0.2 ether);
        assertEq(r.notifyCalls(), 1);
    }

    function testExecuteNow_whenDelay_revertsByPolicy() public {
        MockRouter r = new MockRouter(Decision.Delay, 10);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        m.executeNow(address(receiver), 0.2 ether, "");
    }

    function testExecuteNow_whenRevert_revertsByPolicy() public {
        MockRouter r = new MockRouter(Decision.Revert, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        m.executeNow(address(receiver), 0.2 ether, "");
    }

    function testExecuteNow_whenCallFails_revertsExecutionFailed() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        RevertingReceiver bad = new RevertingReceiver();

        vm.prank(OWNER);
        bytes memory expected = abi.encodeWithSignature("Error(string)", "NOPE");

        vm.expectRevert(abi.encodeWithSelector(Firewall_ExecutionFailed.selector, expected));
        m.executeNow(address(bad), 0.1 ether, "");
    }

    // -------------------- schedule --------------------

    function testSchedule_whenAllow_revertsAllowNotSchedulable() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(OWNER);
        vm.expectRevert(Firewall_AllowNotSchedulable.selector);
        m.schedule(address(receiver), 0.1 ether, "");
    }

    function testSchedule_whenRevert_revertsByPolicy() public {
        MockRouter r = new MockRouter(Decision.Revert, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(OWNER);
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        m.schedule(address(receiver), 0.1 ether, "");
    }

    function testSchedule_whenDelay_returnsTxId() public {
        MockRouter r = new MockRouter(Decision.Delay, 7);
        FirewallModule m = _deployAndInit(address(r));

        bytes32 expectedTxId = m.computeTxId(address(m), 0, address(receiver), 0.3 ether, "");
        vm.expectEmit(true, true, false, true);
        emit FirewallModule.TransactionScheduled(
            expectedTxId,
            address(receiver),
            0.3 ether,
            uint48(block.timestamp + 7)
        );

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.3 ether, "");

        assertTrue(txId != bytes32(0));
    }

    function testSchedule_whenDelay_returnsExpectedTxId() public {
        MockRouter r = new MockRouter(Decision.Delay, 7);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.3 ether, "");

        bytes32 expected = m.computeTxId(address(m), 0, address(receiver), 0.3 ether, "");
        assertEq(txId, expected);
    }

    function testSchedule_getScheduled_readsDetails() public {
        MockRouter r = new MockRouter(Decision.Delay, 7);
        FirewallModule m = _deployAndInit(address(r));

        bytes memory data = hex"";
        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.3 ether, data);

        (
            bool exists,
            bool executed,
            address to,
            uint256 value,
            uint48 unlockTime,
            bytes32 dataHash
        ) = m.getScheduled(txId);

        assertTrue(exists);
        assertFalse(executed);
        assertEq(to, address(receiver));
        assertEq(value, 0.3 ether);
        assertEq(unlockTime, uint48(block.timestamp + 7));
        assertEq(dataHash, keccak256(data));
    }

    function testCancelScheduled_getScheduled_notExists() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.2 ether, "");

        vm.prank(OWNER);
        m.cancelScheduled(txId);

        (bool exists, bool executed, , , , ) = m.getScheduled(txId);
        assertFalse(exists);
        assertFalse(executed);
    }

    // -------------------- executeScheduled --------------------

    function testExecuteScheduled_unknownTx_revertsNotScheduled() public {
        MockRouter r = new MockRouter(Decision.Delay, 5);
        FirewallModule m = _deployAndInit(address(r));

        bytes32 txId = bytes32(uint256(123));

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Firewall_NotScheduled.selector, txId));
        m.executeScheduled(txId);
    }

    function testExecuteScheduled_beforeUnlock_revertsNotUnlocked() public {
        MockRouter r = new MockRouter(Decision.Delay, 10);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.4 ether, "");

        vm.prank(OWNER);
        uint256 expectedUnlock = block.timestamp + 10;

        vm.expectRevert(abi.encodeWithSelector(Firewall_NotUnlocked.selector, txId, expectedUnlock));
        m.executeScheduled(txId);
    }

    function testExecuteScheduled_afterUnlock_executesAndNotifies() public {
        MockRouter r = new MockRouter(Decision.Delay, 10);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.5 ether, "");

        vm.warp(block.timestamp + 10);

        vm.expectEmit(true, true, false, true);
        emit FirewallModule.TransactionExecuted(txId, address(receiver), 0.5 ether);

        vm.expectCall(
            address(r),
            abi.encodeWithSelector(
                MockRouter.notifyExecuted.selector,
                address(m),
                address(receiver),
                0.5 ether,
                bytes("")
            )
        );

        vm.prank(OWNER);
        m.executeScheduled(txId);

        assertEq(address(receiver).balance, 0.5 ether);
        assertEq(receiver.lastSender(), address(m));
        assertEq(receiver.lastValue(), 0.5 ether);
        assertEq(r.notifyCalls(), 1);
    }

    function testExecuteScheduled_afterUnlock_revertsIfIntentNowReverted() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.2 ether, "");

        vm.warp(block.timestamp + 1);
        r.setDecision(Decision.Revert, 0);

        vm.prank(OWNER);
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        m.executeScheduled(txId);

        (bool exists, bool executed, , , , ) = m.getScheduled(txId);
        assertTrue(exists);
        assertFalse(executed);
    }

    function testExecuteScheduled_afterUnlock_executesWhenIntentNowAllowed() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.2 ether, "");

        vm.warp(block.timestamp + 1);
        r.setDecision(Decision.Allow, 0);

        vm.prank(OWNER);
        m.executeScheduled(txId);

        assertEq(address(receiver).balance, 0.2 ether);
    }

    function testExecuteScheduled_revertsWhenCurrentDelayWindowNotMet() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        uint256 createdAt = block.timestamp;
        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.2 ether, "");

        vm.warp(block.timestamp + 1);
        r.setDecision(Decision.Delay, 10);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Firewall_NotUnlocked.selector, txId, createdAt + 10));
        m.executeScheduled(txId);

        vm.warp(createdAt + 10);
        vm.prank(OWNER);
        m.executeScheduled(txId);
        assertEq(address(receiver).balance, 0.2 ether);
    }

    function testExecuteScheduled_allowDecisionStillRespectsOriginalUnlock() public {
        MockRouter r = new MockRouter(Decision.Delay, 10);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.2 ether, "");

        vm.warp(block.timestamp + 1);
        r.setDecision(Decision.Allow, 0);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Firewall_NotUnlocked.selector, txId, block.timestamp + 9));
        m.executeScheduled(txId);
    }

    function testExecuteScheduled_shorterCurrentDelayDoesNotBypassOriginalUnlock() public {
        MockRouter r = new MockRouter(Decision.Delay, 10);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.2 ether, "");

        vm.warp(block.timestamp + 1);
        r.setDecision(Decision.Delay, 1);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Firewall_NotUnlocked.selector, txId, block.timestamp + 9));
        m.executeScheduled(txId);
    }

    function testExecuteScheduled_getScheduled_executedNotExists() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.2 ether, "");

        vm.warp(block.timestamp + 1);

        vm.prank(OWNER);
        m.executeScheduled(txId);

        (bool exists, bool executed, , , , ) = m.getScheduled(txId);
        assertFalse(exists);
        assertTrue(executed);
    }

    function testExecuteScheduled_twice_revertsAlreadyExecuted() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.2 ether, "");

        vm.warp(block.timestamp + 1);

        vm.prank(OWNER);
        m.executeScheduled(txId);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Firewall_AlreadyExecuted.selector, txId));
        m.executeScheduled(txId);
    }

    function testCancelScheduled_removesTx() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.2 ether, "");

        vm.expectEmit(true, true, false, true);
        emit FirewallModule.TransactionCancelled(txId);

        vm.prank(OWNER);
        m.cancelScheduled(txId);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Firewall_NotScheduled.selector, txId));
        m.executeScheduled(txId);
    }

    function testExecuteScheduled_whenCallFails_revertsExecutionFailed() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);

        RevertingReceiver bad = new RevertingReceiver();

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(bad), 0.1 ether, "");

        vm.warp(block.timestamp + 1);

        vm.prank(OWNER);
        bytes memory expected = abi.encodeWithSignature("Error(string)", "NOPE");

        vm.expectRevert(abi.encodeWithSelector(Firewall_ExecutionFailed.selector, expected));
        m.executeScheduled(txId);
    }

    function testQueueIntrospection_tracksNonceAndTxIdByNonce() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));

        assertEq(m.nextNonce(), 0);

        vm.prank(OWNER);
        bytes32 txId0 = m.schedule(address(receiver), 0.2 ether, "");
        assertEq(m.nextNonce(), 1);
        assertEq(m.scheduledTxIdByNonce(0), txId0);

        vm.prank(OWNER);
        bytes32 txId1 = m.schedule(address(receiver), 0.3 ether, "");
        assertEq(m.nextNonce(), 2);
        assertEq(m.scheduledTxIdByNonce(1), txId1);
    }

    function testQueueIntrospection_keepsTxIdMappingAfterCancel() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.2 ether, "");
        assertEq(m.scheduledTxIdByNonce(0), txId);

        vm.prank(OWNER);
        m.cancelScheduled(txId);

        assertEq(m.scheduledTxIdByNonce(0), txId);
    }

    function testFeeConfig_CannotExceedHardCap() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));
        uint32 tooHigh = type(uint32).max;

        vm.prank(FEE_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(Firewall_InvalidFeeConfig.selector, tooHigh, FEE_RECEIVER));
        m.proposeExecutionFeeConfig(tooHigh, FEE_RECEIVER);
    }

    function testFeeConfig_TimelockAndVisibility() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));

        (uint32 currentFeePpm, address currentReceiver) = m.currentExecutionFeeConfig();
        assertEq(currentFeePpm, 0);
        assertEq(currentReceiver, address(0));

        vm.prank(FEE_ADMIN);
        m.proposeExecutionFeeConfig(2_500, FEE_RECEIVER);

        (uint32 pendingFeePpm, address pendingReceiver, uint48 activateAt, bool exists) =
            m.pendingExecutionFeeConfig();
        assertTrue(exists);
        assertEq(pendingFeePpm, 2_500);
        assertEq(pendingReceiver, FEE_RECEIVER);
        assertEq(activateAt, uint48(block.timestamp + m.EXECUTION_FEE_CONFIG_TIMELOCK()));

        vm.expectRevert(abi.encodeWithSelector(Firewall_FeeConfigNotReady.selector, activateAt));
        m.activateExecutionFeeConfig();

        vm.warp(activateAt);
        m.activateExecutionFeeConfig();

        (currentFeePpm, currentReceiver) = m.currentExecutionFeeConfig();
        assertEq(currentFeePpm, 2_500);
        assertEq(currentReceiver, FEE_RECEIVER);
        (, , uint48 clearedAt, bool pendingExists) = m.pendingExecutionFeeConfig();
        assertFalse(pendingExists);
        assertEq(clearedAt, 0);
    }

    function testFeeConfig_OnlyFeeAdminCanPropose() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.prank(address(0xBAD));
        vm.expectRevert(Firewall_FeeAdminUnauthorized.selector);
        m.proposeExecutionFeeConfig(500, FEE_RECEIVER);
    }

    function testExecuteNow_ChargesFee_WhenEnabled() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));
        _activateFee(m, 5_000, FEE_RECEIVER);

        vm.deal(address(m), 2 ether);
        vm.txGasPrice(1 gwei);

        vm.recordLogs();
        vm.prank(OWNER);
        m.executeNow(address(receiver), 0.2 ether, "");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 feeDue, uint256 feePaid, uint256 gasUsed, uint256 gasPrice, bool scheduled, bytes32 txId) =
            _findFeePaidLog(logs);
        assertFalse(scheduled);
        assertEq(txId, bytes32(0));
        assertGt(gasUsed, 0);
        assertEq(gasPrice, 1 gwei);
        assertEq(feePaid, feeDue);
        assertGt(feePaid, 0);
        assertEq(address(receiver).balance, 0.2 ether);
        assertEq(FEE_RECEIVER.balance, feePaid);
    }

    function testExecuteScheduled_ChargesFee_WhenEnabled() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));
        _activateFee(m, 5_000, FEE_RECEIVER);

        vm.deal(address(m), 2 ether);
        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.2 ether, "");

        vm.warp(block.timestamp + 1);
        vm.txGasPrice(2 gwei);

        vm.recordLogs();
        vm.prank(OWNER);
        m.executeScheduled(txId);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 feeDue, uint256 feePaid, uint256 gasUsed, uint256 gasPrice, bool scheduled, bytes32 loggedTxId) =
            _findFeePaidLog(logs);
        assertTrue(scheduled);
        assertEq(loggedTxId, txId);
        assertGt(gasUsed, 0);
        assertEq(gasPrice, 2 gwei);
        assertEq(feePaid, feeDue);
        assertGt(feePaid, 0);
        assertEq(address(receiver).balance, 0.2 ether);
        assertEq(FEE_RECEIVER.balance, feePaid);
    }

    function testExecuteNow_ZeroFeeModeStillWorks() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));

        vm.deal(address(m), 1 ether);
        vm.prank(OWNER);
        m.executeNow(address(receiver), 0.2 ether, "");

        assertEq(address(receiver).balance, 0.2 ether);
        assertEq(FEE_RECEIVER.balance, 0);
    }

    function testExecuteNow_FeeDoesNotBreakEthSend_WhenVaultBalanceMatchesValueOnly() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));
        _activateFee(m, 5_000, FEE_RECEIVER);

        vm.txGasPrice(1 gwei);
        vm.deal(address(m), 0.3 ether);

        vm.recordLogs();
        vm.prank(OWNER);
        m.executeNow(address(receiver), 0.3 ether, "");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 feeDue, uint256 feePaid,, , ,) = _findFeePaidLog(logs);
        assertGt(feeDue, 0);
        assertEq(feePaid, 0);
        assertEq(address(receiver).balance, 0.3 ether);
    }

    function testExecuteScheduled_CurrentDelaySemanticsRemainUnderFeeMode() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));
        _activateFee(m, 5_000, FEE_RECEIVER);

        vm.deal(address(m), 1 ether);
        uint256 createdAt = block.timestamp;
        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0.2 ether, "");

        vm.warp(block.timestamp + 1);
        r.setDecision(Decision.Delay, 10);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Firewall_NotUnlocked.selector, txId, createdAt + 10));
        m.executeScheduled(txId);
    }

    function testProtocolInteraction_EmittedForKnownProtocolTarget_ExecuteNow() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));
        ProtocolRegistry protocolRegistry = new ProtocolRegistry(address(this));

        bytes32 protocolId = keccak256("uniswap-v4");
        protocolRegistry.registerProtocol(protocolId, true, "uniswap-v4", 1, keccak256("dex"));
        protocolRegistry.setProtocolTarget(protocolId, address(receiver), true);

        vm.prank(FEE_ADMIN);
        m.setProtocolRegistry(address(protocolRegistry));

        vm.deal(address(m), 1 ether);
        bytes memory callData = abi.encodeWithSignature("swap(uint256)", 1);

        vm.recordLogs();
        vm.prank(OWNER);
        m.executeNow(address(receiver), 0, callData);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (bytes32 loggedProtocolId, address vault, address target, bytes4 selector, bool scheduled, bytes32 txId) =
            _findProtocolInteractionLog(logs);
        assertEq(loggedProtocolId, protocolId);
        assertEq(vault, address(m));
        assertEq(target, address(receiver));
        assertEq(selector, bytes4(callData));
        assertFalse(scheduled);
        assertEq(txId, bytes32(0));
    }

    function testProtocolInteraction_EmittedForKnownProtocolTarget_ExecuteScheduled() public {
        MockRouter r = new MockRouter(Decision.Delay, 1);
        FirewallModule m = _deployAndInit(address(r));
        ProtocolRegistry protocolRegistry = new ProtocolRegistry(address(this));

        bytes32 protocolId = keccak256("aave-v3");
        protocolRegistry.registerProtocol(protocolId, true, "aave-v3", 1, keccak256("lending"));
        protocolRegistry.setProtocolTarget(protocolId, address(receiver), true);

        vm.prank(FEE_ADMIN);
        m.setProtocolRegistry(address(protocolRegistry));

        vm.deal(address(m), 1 ether);
        bytes memory callData = abi.encodeWithSignature("deposit(uint256)", 1);
        vm.prank(OWNER);
        bytes32 txId = m.schedule(address(receiver), 0, callData);

        vm.warp(block.timestamp + 1);
        vm.recordLogs();
        vm.prank(OWNER);
        m.executeScheduled(txId);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (bytes32 loggedProtocolId, address vault, address target, bytes4 selector, bool scheduled, bytes32 loggedTxId)
        = _findProtocolInteractionLog(logs);
        assertEq(loggedProtocolId, protocolId);
        assertEq(vault, address(m));
        assertEq(target, address(receiver));
        assertEq(selector, bytes4(callData));
        assertTrue(scheduled);
        assertEq(loggedTxId, txId);
    }

    function testProtocolInteraction_RevertingRegistryDoesNotAffectExecution() public {
        MockRouter r = new MockRouter(Decision.Allow, 0);
        FirewallModule m = _deployAndInit(address(r));
        RevertingProtocolRegistry badRegistry = new RevertingProtocolRegistry();

        vm.prank(FEE_ADMIN);
        m.setProtocolRegistry(address(badRegistry));

        vm.deal(address(m), 1 ether);
        vm.prank(OWNER);
        m.executeNow(address(receiver), 0.2 ether, "");
        assertEq(address(receiver).balance, 0.2 ether);
    }

    function _activateFee(FirewallModule m, uint32 feePpm, address feeReceiver) internal {
        vm.prank(FEE_ADMIN);
        m.proposeExecutionFeeConfig(feePpm, feeReceiver);
        vm.warp(block.timestamp + m.EXECUTION_FEE_CONFIG_TIMELOCK());
        m.activateExecutionFeeConfig();
    }

    function _findFeePaidLog(Vm.Log[] memory logs)
        internal
        pure
        returns (
            uint256 feeDue,
            uint256 feePaid,
            uint256 gasUsed,
            uint256 gasPrice,
            bool scheduled,
            bytes32 txId
        )
    {
        bytes32 sig = keccak256("ExecutionFeePaid(address,bool,bytes32,uint256,uint256,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 4 && logs[i].topics[0] == sig) {
                scheduled = uint256(logs[i].topics[2]) != 0;
                txId = logs[i].topics[3];
                (feeDue, feePaid, gasUsed, gasPrice) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
                return (feeDue, feePaid, gasUsed, gasPrice, scheduled, txId);
            }
        }
        revert("fee log not found");
    }

    function _findProtocolInteractionLog(Vm.Log[] memory logs)
        internal
        pure
        returns (
            bytes32 protocolId,
            address vault,
            address target,
            bytes4 selector,
            bool scheduled,
            bytes32 txId
        )
    {
        bytes32 sig =
            keccak256("ProtocolInteractionObserved(bytes32,address,address,bytes4,bool,bytes32)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 4 && logs[i].topics[0] == sig) {
                protocolId = logs[i].topics[1];
                vault = address(uint160(uint256(logs[i].topics[2])));
                target = address(uint160(uint256(logs[i].topics[3])));
                (selector, scheduled, txId) = abi.decode(logs[i].data, (bytes4, bool, bytes32));
                return (protocolId, vault, target, selector, scheduled, txId);
            }
        }
        revert("protocol log not found");
    }
}
