// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "./SmokeBase.t.sol";
import {FirewallModule, Firewall_RevertedByPolicy, Firewall_NotUnlocked, Firewall_AlreadyExecuted} from
    "../../src/FirewallModule.sol";
import {PolicyRouter} from "../../src/PolicyRouter.sol";
import {MockReceiver} from "../../src/mocks/MockReceiver.sol";

contract V2CoreFlowSmoke is SmokeBase {
    uint256 internal constant SMALL_VALUE = 0.01 ether;

    function setUp() public {
        _deployV2WithRealBasePacks();
    }

    /// @dev NewReceiverDelayPolicy delays first transfer to an unseen receiver.
    ///      This helper executes that first delayed transfer so subsequent small transfers are immediately allowed.
    function _primeKnownReceiver(FirewallModule wallet, address receiver) internal {
        bytes32 txId = wallet.schedule(receiver, SMALL_VALUE, "");
        vm.warp(block.timestamp + NEW_RECEIVER_DELAY);
        wallet.executeScheduled(txId);
    }

    function test_Smoke_FullDeployAndCreateWallet() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);

        assertTrue(address(wallet) != address(0));
        assertTrue(address(router) != address(0));
        assertTrue(address(wallet) != address(router));
        assertEq(router.basePackId(), BASE_PACK_CONSERVATIVE);
        assertEq(router.owner(), OWNER);
        assertEq(router.firewallModule(), address(wallet));
        assertEq(router.policyCount(), 3);
    }

    function test_Smoke_SafeTransferAllowed() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        MockReceiver receiver = new MockReceiver();
        vm.deal(address(wallet), 5 ether);

        // Precondition: receiver must already be known under real base policy behavior.
        _primeKnownReceiver(wallet, address(receiver));
        assertEq(address(receiver).balance, SMALL_VALUE);

        wallet.executeNow(address(receiver), SMALL_VALUE, "");
        assertEq(address(receiver).balance, SMALL_VALUE * 2);
    }

    function test_Smoke_LargeTransferDelayed() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        MockReceiver receiver = new MockReceiver();

        vm.deal(address(wallet), 5 ether);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(address(receiver), LARGE_THRESHOLD + 1, "");

        uint48 expectedUnlock = uint48(block.timestamp) + LARGE_DELAY;
        bytes32 txId = wallet.schedule(address(receiver), LARGE_THRESHOLD + 1, "");

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
        assertEq(to, address(receiver));
        assertEq(value, LARGE_THRESHOLD + 1);
        assertEq(unlockTime, expectedUnlock);
        assertEq(dataHash, keccak256(bytes("")));
    }

    function test_Smoke_ExecuteScheduledAndNoDoubleExecution() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        MockReceiver receiver = new MockReceiver();

        vm.deal(address(wallet), 5 ether);
        bytes32 txId = wallet.schedule(address(receiver), LARGE_THRESHOLD + 1, "");

        vm.expectRevert(abi.encodeWithSelector(Firewall_NotUnlocked.selector, txId, block.timestamp + LARGE_DELAY));
        wallet.executeScheduled(txId);

        vm.warp(block.timestamp + LARGE_DELAY);
        wallet.executeScheduled(txId);
        assertEq(address(receiver).balance, LARGE_THRESHOLD + 1);

        vm.expectRevert(abi.encodeWithSelector(Firewall_AlreadyExecuted.selector, txId));
        wallet.executeScheduled(txId);
    }
}
