// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "./SmokeBase.t.sol";
import {FirewallModule, Firewall_NotScheduled} from "../../src/FirewallModule.sol";
import {PolicyRouter} from "../../src/PolicyRouter.sol";

contract V2QueueStressSmoke is SmokeBase {
    uint256 internal constant SMALL_VALUE = 0.01 ether;

    function setUp() public {
        _deployV2WithRealBasePacks();
    }

    function test_QueueStress_MixedReasons_InterleavedCancelExecuteAndStateIsolation() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);

        address knownLargeReceiver = address(0xD001);
        address newReceiverA = address(0xD002);
        address newReceiverC = address(0xD003);

        vm.deal(address(wallet), 20 ether);

        // Prime known receiver so large-transfer tx is isolated to large-transfer policy reason.
        bytes32 primeTxId = wallet.schedule(knownLargeReceiver, SMALL_VALUE, "");
        uint48 primeUnlockTime = _unlockTime(wallet, primeTxId);
        vm.warp(primeUnlockTime);
        wallet.executeScheduled(primeTxId);

        router.enableAddonPack(ADDON_PACK_LARGE_TRANSFER_24H);

        uint96 startNonce = wallet.nextNonce();
        uint48 queuedAt = uint48(block.timestamp);

        bytes32 txA = wallet.schedule(newReceiverA, SMALL_VALUE, "");
        bytes32 txB = wallet.schedule(knownLargeReceiver, ADDON_LARGE_THRESHOLD + 1, "");
        bytes32 txC = wallet.schedule(newReceiverC, SMALL_VALUE, "");

        assertEq(wallet.nextNonce(), startNonce + 3);
        assertEq(wallet.scheduledTxIdByNonce(startNonce), txA);
        assertEq(wallet.scheduledTxIdByNonce(startNonce + 1), txB);
        assertEq(wallet.scheduledTxIdByNonce(startNonce + 2), txC);

        _assertScheduledPending(
            wallet, txA, newReceiverA, SMALL_VALUE, queuedAt + NEW_RECEIVER_DELAY, keccak256(bytes(""))
        );
        _assertScheduledPending(
            wallet,
            txB,
            knownLargeReceiver,
            ADDON_LARGE_THRESHOLD + 1,
            queuedAt + ADDON_LARGE_DELAY,
            keccak256(bytes(""))
        );
        _assertScheduledPending(
            wallet, txC, newReceiverC, SMALL_VALUE, queuedAt + NEW_RECEIVER_DELAY, keccak256(bytes(""))
        );

        // Same-rule multi-queue (new-receiver) transactions stay independent.
        assertEq(_unlockTime(wallet, txA), _unlockTime(wallet, txC));

        wallet.cancelScheduled(txB);
        _assertScheduledMissing(wallet, txB);

        _assertScheduledPending(
            wallet, txA, newReceiverA, SMALL_VALUE, queuedAt + NEW_RECEIVER_DELAY, keccak256(bytes(""))
        );
        _assertScheduledPending(
            wallet, txC, newReceiverC, SMALL_VALUE, queuedAt + NEW_RECEIVER_DELAY, keccak256(bytes(""))
        );

        vm.warp(queuedAt + NEW_RECEIVER_DELAY);
        wallet.executeScheduled(txC);
        _assertScheduledExecuted(wallet, txC);
        _assertScheduledPending(
            wallet, txA, newReceiverA, SMALL_VALUE, queuedAt + NEW_RECEIVER_DELAY, keccak256(bytes(""))
        );
        assertEq(newReceiverC.balance, SMALL_VALUE);

        wallet.executeScheduled(txA);
        _assertScheduledExecuted(wallet, txA);
        assertEq(newReceiverA.balance, SMALL_VALUE);

        vm.warp(queuedAt + ADDON_LARGE_DELAY);
        vm.expectRevert(abi.encodeWithSelector(Firewall_NotScheduled.selector, txB));
        wallet.executeScheduled(txB);

        assertEq(wallet.nextNonce(), startNonce + 3);
        assertEq(wallet.scheduledTxIdByNonce(startNonce), txA);
        assertEq(wallet.scheduledTxIdByNonce(startNonce + 1), txB);
        assertEq(wallet.scheduledTxIdByNonce(startNonce + 2), txC);
    }

    function _unlockTime(FirewallModule wallet, bytes32 txId) internal view returns (uint48 unlockTime) {
        (, , , , unlockTime, ) = wallet.getScheduled(txId);
    }

    function _assertScheduledPending(
        FirewallModule wallet,
        bytes32 txId,
        address expectedTo,
        uint256 expectedValue,
        uint48 expectedUnlock,
        bytes32 expectedDataHash
    ) internal view {
        (
            bool exists,
            bool executed,
            address to,
            uint256 value,
            uint48 unlockTime,
            bytes32 dataHash
        ) = wallet.getScheduled(txId);
        assertTrue(exists);
        assertFalse(executed);
        assertEq(to, expectedTo);
        assertEq(value, expectedValue);
        assertEq(unlockTime, expectedUnlock);
        assertEq(dataHash, expectedDataHash);
    }

    function _assertScheduledMissing(FirewallModule wallet, bytes32 txId) internal view {
        (bool exists, bool executed, , , , ) = wallet.getScheduled(txId);
        assertFalse(exists);
        assertFalse(executed);
    }

    function _assertScheduledExecuted(FirewallModule wallet, bytes32 txId) internal view {
        (bool exists, bool executed, , , , ) = wallet.getScheduled(txId);
        assertFalse(exists);
        assertTrue(executed);
    }
}
