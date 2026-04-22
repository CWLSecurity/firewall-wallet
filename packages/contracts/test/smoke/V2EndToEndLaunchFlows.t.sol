// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "./SmokeBase.t.sol";
import {
    FirewallModule,
    Firewall_NotUnlocked,
    Firewall_RevertedByPolicy,
    Firewall_QueueExecutorUnauthorized
} from "../../src/FirewallModule.sol";
import {PolicyRouter} from "../../src/PolicyRouter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockReceiver} from "../../src/mocks/MockReceiver.sol";

contract V2EndToEndLaunchFlows is SmokeBase {
    uint256 internal constant RELAYER_PK = 0xB0B42;
    uint256 internal constant SMALL_VALUE = 0.01 ether;

    address internal relayer;

    function setUp() public {
        relayer = vm.addr(RELAYER_PK);
        _deployV2WithRealBasePacks();
        vm.deal(address(this), 10 ether);
    }

    function test_E2E_ConservativeJourney_NewReceiverAndLargeTransfer() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        address receiver = address(0xBEEF101);
        vm.deal(address(wallet), 5 ether);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(receiver, SMALL_VALUE, "");

        bytes32 firstTxId = wallet.schedule(receiver, SMALL_VALUE, "");
        (, , , , uint48 unlockFirst,) = wallet.getScheduled(firstTxId);
        assertEq(unlockFirst, uint48(block.timestamp) + NEW_RECEIVER_DELAY);

        vm.expectRevert(abi.encodeWithSelector(Firewall_NotUnlocked.selector, firstTxId, unlockFirst));
        wallet.executeScheduled(firstTxId);

        vm.warp(unlockFirst);
        wallet.executeScheduled(firstTxId);
        assertEq(receiver.balance, SMALL_VALUE);

        wallet.executeNow(receiver, SMALL_VALUE, "");
        assertEq(receiver.balance, SMALL_VALUE * 2);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(receiver, LARGE_THRESHOLD + 1, "");

        bytes32 largeTxId = wallet.schedule(receiver, LARGE_THRESHOLD + 1, "");
        (, , , , uint48 largeUnlock,) = wallet.getScheduled(largeTxId);
        assertEq(largeUnlock, uint48(block.timestamp) + LARGE_DELAY);
    }

    function test_E2E_DeFiJourney_DelayThenAddonHardBlock() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();
        MockReceiver spender = new MockReceiver();
        bytes memory approveData = abi.encodeWithSignature("approve(address,uint256)", address(spender), 1);

        bytes32 delayedApproveTx = wallet.schedule(address(token), 0, approveData);
        (, , , , uint48 unlockTime,) = wallet.getScheduled(delayedApproveTx);
        assertEq(unlockTime, uint48(block.timestamp) + DEFI_NEW_SPENDER_DELAY);

        vm.warp(unlockTime);
        wallet.executeScheduled(delayedApproveTx);

        wallet.executeNow(address(token), 0, approveData);

        router.enableAddonPack(ADDON_PACK_APPROVAL_HARDENING);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(address(token), 0, approveData);
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.schedule(address(token), 0, approveData);
    }

    function test_E2E_ExecutorJourney_AuthorizedExecutionAndRefundPath() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        address receiver = address(0xBEEF102);
        vm.deal(address(wallet), 5 ether);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(Firewall_QueueExecutorUnauthorized.selector, relayer));
        wallet.executeScheduledByExecutor(bytes32(uint256(123)));

        wallet.setQueueExecutor(relayer, true);
        assertTrue(wallet.isQueueExecutor(relayer));

        wallet.fundBotGasBuffer{value: 0.003 ether}();
        wallet.setBotGasConfig(0.001 ether, 2 gwei, 500_000);

        uint256 relayerBalanceBefore = relayer.balance;
        uint256 botBufferBefore = wallet.botGasBuffer();

        bytes32 txId = wallet.schedule(receiver, SMALL_VALUE, "");
        assertEq(wallet.scheduledReserve(txId), 0.001 ether);
        assertEq(wallet.botGasBuffer(), botBufferBefore - 0.001 ether);

        (, , , , uint48 unlockTime,) = wallet.getScheduled(txId);
        vm.warp(unlockTime);

        vm.txGasPrice(1 gwei);
        vm.prank(relayer);
        wallet.executeScheduledByExecutor(txId);

        assertEq(receiver.balance, SMALL_VALUE);
        assertEq(wallet.scheduledReserve(txId), 0);
        assertGt(relayer.balance, relayerBalanceBefore);
    }
}
