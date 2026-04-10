// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "./SmokeBase.t.sol";
import {
    FirewallModule,
    Firewall_NotScheduled,
    Firewall_NotUnlocked,
    Firewall_InvalidPermitExecutor,
    Firewall_PermitExpired,
    Firewall_PermitNonceUsed,
    Firewall_QueueExecutorUnauthorized
} from "../../src/FirewallModule.sol";

contract V2QueuePermitExecution is SmokeBase {
    uint256 internal constant OWNER_PK = 0xA11CE;
    uint256 internal constant RELAYER_PK = 0xB0B;
    uint256 internal constant SMALL_VALUE = 0.01 ether;

    address internal relayer;

    function setUp() public {
        OWNER = vm.addr(OWNER_PK);
        relayer = vm.addr(RELAYER_PK);
        _deployV2WithRealBasePacks();
        vm.deal(OWNER, 10 ether);
    }

    function test_ReserveLifecycle_ScheduleTopUpCancelReleasesReserve() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        address receiver = address(0xBEEF10);

        vm.prank(OWNER);
        bytes32 txId = wallet.scheduleWithReserve{value: 0.002 ether}(receiver, SMALL_VALUE, "");

        assertEq(wallet.scheduledReserve(txId), 0.002 ether);
        assertEq(wallet.totalScheduledReserve(), 0.002 ether);

        vm.prank(OWNER);
        wallet.topUpScheduledReserve{value: 0.001 ether}(txId);

        assertEq(wallet.scheduledReserve(txId), 0.003 ether);
        assertEq(wallet.totalScheduledReserve(), 0.003 ether);

        vm.prank(OWNER);
        wallet.cancelScheduled(txId);

        assertEq(wallet.scheduledReserve(txId), 0);
        assertEq(wallet.totalScheduledReserve(), 0);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Firewall_NotScheduled.selector, txId));
        wallet.topUpScheduledReserve{value: 1}(txId);
    }

    function test_ExecuteScheduledWithPermit_PaysRelayerFromReservedBalance() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        address receiver = address(0xBEEF11);
        vm.deal(address(wallet), 1 ether);

        vm.prank(OWNER);
        bytes32 txId = wallet.scheduleWithReserve{value: 0.003 ether}(receiver, SMALL_VALUE, "");
        (, , , , uint48 unlockTime, ) = wallet.getScheduled(txId);
        vm.warp(unlockTime);

        FirewallModule.ExecuteScheduledPermit memory permit = FirewallModule.ExecuteScheduledPermit({
            executor: relayer,
            nonce: 11,
            deadline: block.timestamp + 1 hours,
            maxFeePerGasWei: 2 gwei,
            maxGasUsed: 500_000,
            maxRefundWei: 0.003 ether
        });
        bytes memory signature = _signPermit(wallet, txId, permit);

        uint256 relayerBalanceBefore = relayer.balance;
        vm.txGasPrice(1 gwei);
        vm.prank(relayer);
        wallet.executeScheduledWithPermit(txId, permit, signature);

        (bool exists, bool executed, , , , ) = wallet.getScheduled(txId);
        assertFalse(exists);
        assertTrue(executed);
        assertEq(receiver.balance, SMALL_VALUE);

        assertEq(wallet.scheduledReserve(txId), 0);
        assertEq(wallet.totalScheduledReserve(), 0);
        assertTrue(wallet.isExecutePermitNonceUsed(11));
        assertGt(relayer.balance, relayerBalanceBefore);
    }

    function test_ExecuteScheduledWithPermit_RejectsWrongExecutorExpiredAndReusedNonce() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        address receiverA = address(0xBEEF12);
        address receiverB = address(0xBEEF13);
        vm.deal(address(wallet), 1 ether);

        vm.prank(OWNER);
        bytes32 txIdA = wallet.scheduleWithReserve{value: 0.002 ether}(receiverA, SMALL_VALUE, "");
        (, , , , uint48 unlockA, ) = wallet.getScheduled(txIdA);
        vm.warp(unlockA);

        FirewallModule.ExecuteScheduledPermit memory wrongExecutorPermit = FirewallModule.ExecuteScheduledPermit({
            executor: relayer,
            nonce: 21,
            deadline: block.timestamp + 1 hours,
            maxFeePerGasWei: 2 gwei,
            maxGasUsed: 500_000,
            maxRefundWei: 0.002 ether
        });
        bytes memory wrongExecutorSig = _signPermit(wallet, txIdA, wrongExecutorPermit);

        vm.prank(address(0xAAAA));
        vm.expectRevert(
            abi.encodeWithSelector(Firewall_InvalidPermitExecutor.selector, relayer, address(0xAAAA))
        );
        wallet.executeScheduledWithPermit(txIdA, wrongExecutorPermit, wrongExecutorSig);

        FirewallModule.ExecuteScheduledPermit memory expiredPermit = FirewallModule.ExecuteScheduledPermit({
            executor: relayer,
            nonce: 22,
            deadline: block.timestamp - 1,
            maxFeePerGasWei: 2 gwei,
            maxGasUsed: 500_000,
            maxRefundWei: 0.002 ether
        });
        bytes memory expiredSig = _signPermit(wallet, txIdA, expiredPermit);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(Firewall_PermitExpired.selector, expiredPermit.deadline));
        wallet.executeScheduledWithPermit(txIdA, expiredPermit, expiredSig);

        FirewallModule.ExecuteScheduledPermit memory usedNoncePermitA = FirewallModule.ExecuteScheduledPermit({
            executor: relayer,
            nonce: 23,
            deadline: block.timestamp + 1 hours,
            maxFeePerGasWei: 2 gwei,
            maxGasUsed: 500_000,
            maxRefundWei: 0.002 ether
        });
        bytes memory usedNonceSigA = _signPermit(wallet, txIdA, usedNoncePermitA);
        vm.prank(relayer);
        wallet.executeScheduledWithPermit(txIdA, usedNoncePermitA, usedNonceSigA);

        vm.prank(OWNER);
        bytes32 txIdB = wallet.scheduleWithReserve{value: 0.002 ether}(receiverB, SMALL_VALUE, "");
        (, , , , uint48 unlockB, ) = wallet.getScheduled(txIdB);
        vm.warp(unlockB);

        FirewallModule.ExecuteScheduledPermit memory reusedNoncePermitB = FirewallModule.ExecuteScheduledPermit({
            executor: relayer,
            nonce: 23,
            deadline: block.timestamp + 1 hours,
            maxFeePerGasWei: 2 gwei,
            maxGasUsed: 500_000,
            maxRefundWei: 0.002 ether
        });
        bytes memory reusedNonceSigB = _signPermit(wallet, txIdB, reusedNoncePermitB);
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(Firewall_PermitNonceUsed.selector, 23));
        wallet.executeScheduledWithPermit(txIdB, reusedNoncePermitB, reusedNonceSigB);
    }

    function test_ExecuteScheduledByExecutor_RequiresAuthorizationAndUnlock() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        address receiver = address(0xBEEF14);
        vm.deal(address(wallet), 1 ether);

        vm.prank(OWNER);
        bytes32 txId = wallet.schedule(receiver, SMALL_VALUE, "");
        (, , , , uint48 unlockTime, ) = wallet.getScheduled(txId);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(Firewall_QueueExecutorUnauthorized.selector, relayer));
        wallet.executeScheduledByExecutor(txId);

        vm.prank(OWNER);
        wallet.setQueueExecutor(relayer, true);
        assertTrue(wallet.isQueueExecutor(relayer));

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(Firewall_NotUnlocked.selector, txId, unlockTime));
        wallet.executeScheduledByExecutor(txId);

        vm.warp(unlockTime);
        vm.prank(relayer);
        wallet.executeScheduledByExecutor(txId);

        (bool exists, bool executed, , , , ) = wallet.getScheduled(txId);
        assertFalse(exists);
        assertTrue(executed);
        assertEq(receiver.balance, SMALL_VALUE);
    }

    function test_QueueExecutor_CanBeRevokedByOwner() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        vm.prank(OWNER);
        wallet.setQueueExecutor(relayer, true);
        assertTrue(wallet.isQueueExecutor(relayer));

        vm.prank(OWNER);
        wallet.setQueueExecutor(relayer, false);
        assertFalse(wallet.isQueueExecutor(relayer));
    }

    function test_BotGasPool_AutoReserveAndManualExecutionReturnsReserve() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        address receiver = address(0xBEEF15);
        vm.deal(address(wallet), 1 ether);

        vm.prank(OWNER);
        wallet.fundBotGasBuffer{value: 0.0002 ether}();

        uint256 bufferBeforeSchedule = wallet.botGasBuffer();
        (uint256 autoReserveWei,,) = wallet.botGasConfig();

        vm.prank(OWNER);
        bytes32 txId = wallet.schedule(receiver, SMALL_VALUE, "");

        assertEq(wallet.scheduledReserve(txId), autoReserveWei);
        assertEq(wallet.scheduledBotPoolReserve(txId), autoReserveWei);
        assertEq(wallet.botGasBuffer(), bufferBeforeSchedule - autoReserveWei);

        (, , , , uint48 unlockTime, ) = wallet.getScheduled(txId);
        vm.warp(unlockTime);

        vm.prank(OWNER);
        wallet.executeScheduled(txId);

        assertEq(wallet.scheduledReserve(txId), 0);
        assertEq(wallet.scheduledBotPoolReserve(txId), 0);
        assertEq(wallet.botGasBuffer(), bufferBeforeSchedule);
    }

    function test_BotGasPool_ExecutorRefundIsPaidFromReservedBuffer() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        address receiver = address(0xBEEF16);
        vm.deal(address(wallet), 1 ether);

        vm.prank(OWNER);
        wallet.fundBotGasBuffer{value: 0.003 ether}();

        vm.prank(OWNER);
        wallet.setBotGasConfig(0.002 ether, 2 gwei, 500_000);
        vm.prank(OWNER);
        wallet.setQueueExecutor(relayer, true);

        uint256 poolBeforeSchedule = wallet.botGasBuffer();
        vm.prank(OWNER);
        bytes32 txId = wallet.schedule(receiver, SMALL_VALUE, "");

        assertEq(wallet.scheduledReserve(txId), 0.002 ether);
        assertEq(wallet.scheduledBotPoolReserve(txId), 0.002 ether);
        assertEq(wallet.botGasBuffer(), poolBeforeSchedule - 0.002 ether);

        (, , , , uint48 unlockTime, ) = wallet.getScheduled(txId);
        vm.warp(unlockTime);

        uint256 relayerBalanceBefore = relayer.balance;
        vm.txGasPrice(1 gwei);
        vm.prank(relayer);
        wallet.executeScheduledByExecutor(txId);

        assertEq(wallet.scheduledReserve(txId), 0);
        assertEq(wallet.scheduledBotPoolReserve(txId), 0);
        assertGt(relayer.balance, relayerBalanceBefore);
        assertLt(wallet.botGasBuffer(), poolBeforeSchedule);
    }

    function _signPermit(
        FirewallModule wallet,
        bytes32 txId,
        FirewallModule.ExecuteScheduledPermit memory permit
    ) internal view returns (bytes memory) {
        bytes32 digest = wallet.executePermitDigest(txId, permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);
        return abi.encodePacked(r, s, v);
    }
}
