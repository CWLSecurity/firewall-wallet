// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "./SmokeBase.t.sol";
import {FirewallModule, Firewall_RevertedByPolicy} from "../../src/FirewallModule.sol";
import {PolicyRouter} from "../../src/PolicyRouter.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockReceiver} from "../../src/mocks/MockReceiver.sol";

contract V2StateIsolationSmoke is SmokeBase {
    uint256 internal constant SMALL_VALUE = 0.01 ether;
    uint256 internal constant ERC20_TRANSFER_VALUE = 0.1 ether;

    function setUp() public {
        _deployV2WithRealBasePacks();
    }

    function test_StateIsolation_AddonEnable_IsPerWalletRouterOnly() public {
        (FirewallModule walletA, PolicyRouter routerA) = _createWalletAndRouter(BASE_PACK_DEFI);
        (FirewallModule walletB, PolicyRouter routerB) = _createWalletAndRouter(BASE_PACK_DEFI);
        address receiver = address(0xAA01);

        _assertDecision(routerA, address(walletA), receiver, SMALL_VALUE, "", Decision.Delay, DEFI_NEW_RECEIVER_DELAY);
        _assertDecision(routerB, address(walletB), receiver, SMALL_VALUE, "", Decision.Delay, DEFI_NEW_RECEIVER_DELAY);

        routerA.enableAddonPack(ADDON_PACK_NEW_RECEIVER_24H);

        assertTrue(routerA.isAddonPackEnabled(ADDON_PACK_NEW_RECEIVER_24H));
        assertFalse(routerB.isAddonPackEnabled(ADDON_PACK_NEW_RECEIVER_24H));

        _assertDecision(
            routerA,
            address(walletA),
            address(0xAA02),
            SMALL_VALUE,
            "",
            Decision.Delay,
            ADDON_NEW_RECEIVER_DELAY
        );
        _assertDecision(
            routerB,
            address(walletB),
            address(0xAA03),
            SMALL_VALUE,
            "",
            Decision.Delay,
            DEFI_NEW_RECEIVER_DELAY
        );
    }

    function test_StateIsolation_NewReceiverKnownState_DoesNotLeakAcrossWallets() public {
        (FirewallModule walletA,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        (FirewallModule walletB,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        address receiver = address(0xBB01);

        vm.deal(address(walletA), 1 ether);
        vm.deal(address(walletB), 1 ether);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        walletA.executeNow(receiver, SMALL_VALUE, "");

        bytes32 txIdA = walletA.schedule(receiver, SMALL_VALUE, "");
        uint48 unlockA = _unlockTime(walletA, txIdA);
        assertEq(unlockA, uint48(block.timestamp) + NEW_RECEIVER_DELAY);

        vm.warp(unlockA);
        walletA.executeScheduled(txIdA);
        walletA.executeNow(receiver, SMALL_VALUE, "");

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        walletB.executeNow(receiver, SMALL_VALUE, "");

        bytes32 txIdB = walletB.schedule(receiver, SMALL_VALUE, "");
        uint48 unlockB = _unlockTime(walletB, txIdB);
        assertEq(unlockB, uint48(block.timestamp) + NEW_RECEIVER_DELAY);
    }

    function test_StateIsolation_DeFiKnownSpender_DoesNotLeakAcrossWallets() public {
        (FirewallModule walletA,) = _createWalletAndRouter(BASE_PACK_DEFI);
        (FirewallModule walletB, PolicyRouter routerB) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();
        MockReceiver spender = new MockReceiver();

        bytes memory approveData = abi.encodeWithSignature("approve(address,uint256)", address(spender), 1);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        walletA.executeNow(address(token), 0, approveData);

        bytes32 txIdA = walletA.schedule(address(token), 0, approveData);
        uint48 unlockA = _unlockTime(walletA, txIdA);
        assertEq(unlockA, uint48(block.timestamp) + DEFI_NEW_SPENDER_DELAY);

        vm.warp(unlockA);
        walletA.executeScheduled(txIdA);
        walletA.executeNow(address(token), 0, approveData);
        assertEq(token.allowance(address(walletA), address(spender)), 1);

        _assertDecision(
            routerB,
            address(walletB),
            address(token),
            0,
            approveData,
            Decision.Delay,
            DEFI_NEW_SPENDER_DELAY
        );

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        walletB.executeNow(address(token), 0, approveData);

        bytes32 txIdB = walletB.schedule(address(token), 0, approveData);
        uint48 unlockB = _unlockTime(walletB, txIdB);
        assertEq(unlockB, uint48(block.timestamp) + DEFI_NEW_SPENDER_DELAY);
    }

    function test_StateIsolation_DeFiKnownRecipient_DoesNotLeakAcrossWallets() public {
        (FirewallModule walletA,) = _createWalletAndRouter(BASE_PACK_DEFI);
        (FirewallModule walletB, PolicyRouter routerB) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();
        address recipient = address(0xCC01);

        token.mint(address(walletA), 5 ether);
        token.mint(address(walletB), 5 ether);

        bytes memory transferData = abi.encodeWithSignature("transfer(address,uint256)", recipient, ERC20_TRANSFER_VALUE);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        walletA.executeNow(address(token), 0, transferData);

        bytes32 txIdA = walletA.schedule(address(token), 0, transferData);
        uint48 unlockA = _unlockTime(walletA, txIdA);
        assertEq(unlockA, uint48(block.timestamp) + DEFI_NEW_ERC20_RECIPIENT_DELAY);

        vm.warp(unlockA);
        walletA.executeScheduled(txIdA);
        walletA.executeNow(address(token), 0, transferData);
        assertEq(token.balanceOf(recipient), ERC20_TRANSFER_VALUE * 2);

        _assertDecision(
            routerB,
            address(walletB),
            address(token),
            0,
            transferData,
            Decision.Delay,
            DEFI_NEW_ERC20_RECIPIENT_DELAY
        );

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        walletB.executeNow(address(token), 0, transferData);

        bytes32 txIdB = walletB.schedule(address(token), 0, transferData);
        uint48 unlockB = _unlockTime(walletB, txIdB);
        assertEq(unlockB, uint48(block.timestamp) + DEFI_NEW_ERC20_RECIPIENT_DELAY);
    }

    function _assertDecision(
        PolicyRouter router,
        address vault,
        address to,
        uint256 value,
        bytes memory data,
        Decision expectedDecision,
        uint48 expectedDelay
    ) internal view {
        (Decision actualDecision, uint48 actualDelay) = router.evaluate(vault, to, value, data);
        assertEq(uint256(actualDecision), uint256(expectedDecision));
        assertEq(actualDelay, expectedDelay);
    }

    function _unlockTime(FirewallModule wallet, bytes32 txId) internal view returns (uint48 unlockTime) {
        (, , , , unlockTime, ) = wallet.getScheduled(txId);
    }
}
