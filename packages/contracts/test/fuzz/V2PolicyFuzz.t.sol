// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "../smoke/SmokeBase.t.sol";
import {
    FirewallModule,
    Firewall_RevertedByPolicy,
    Firewall_NotUnlocked
} from "../../src/FirewallModule.sol";
import {PolicyRouter} from "../../src/PolicyRouter.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockReceiver} from "../../src/mocks/MockReceiver.sol";

contract V2PolicyFuzz is SmokeBase {
    function setUp() public {
        _deployV2WithRealBasePacks();
    }

    function testFuzz_VaultTransfer_PathMatchesRouterDecision(
        uint8 basePackSeed,
        bool enableNewReceiverAddon,
        bool enableLargeTransferAddon,
        uint96 amountSeed,
        uint160 recipientSeed,
        uint32 warpSeed
    ) public {
        uint256 basePack = basePackSeed % 2 == 0 ? BASE_PACK_CONSERVATIVE : BASE_PACK_DEFI;
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(basePack);

        if (enableNewReceiverAddon) {
            router.enableAddonPack(ADDON_PACK_NEW_RECEIVER_24H);
        }
        if (enableLargeTransferAddon) {
            router.enableAddonPack(ADDON_PACK_LARGE_TRANSFER_24H);
        }

        address recipient =
            address(uint160(bound(uint256(recipientSeed), uint256(uint160(0x10000)), type(uint160).max)));
        vm.assume(recipient.code.length == 0);
        uint256 amount = bound(uint256(amountSeed), 1, 3 ether);
        vm.deal(address(wallet), 10 ether);

        (Decision decision, uint48 delaySeconds) = router.evaluate(address(wallet), recipient, amount, "");

        if (decision == Decision.Allow) {
            uint256 beforeBalanceAllow = recipient.balance;
            wallet.executeNow(recipient, amount, "");
            assertEq(recipient.balance, beforeBalanceAllow + amount);
            return;
        }

        if (decision == Decision.Revert) {
            vm.expectRevert(Firewall_RevertedByPolicy.selector);
            wallet.executeNow(recipient, amount, "");
            vm.expectRevert(Firewall_RevertedByPolicy.selector);
            wallet.schedule(recipient, amount, "");
            return;
        }

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(recipient, amount, "");

        bytes32 txId = wallet.schedule(recipient, amount, "");
        (, , , , uint48 unlockTime, ) = wallet.getScheduled(txId);
        assertEq(unlockTime, uint48(block.timestamp) + delaySeconds);

        uint256 forward = bound(uint256(warpSeed), 0, uint256(delaySeconds) + 1);
        vm.warp(block.timestamp + forward);

        if (forward < delaySeconds) {
            vm.expectRevert(abi.encodeWithSelector(Firewall_NotUnlocked.selector, txId, unlockTime));
            wallet.executeScheduled(txId);
            return;
        }

        uint256 beforeBalanceDelay = recipient.balance;
        wallet.executeScheduled(txId);
        assertEq(recipient.balance, beforeBalanceDelay + amount);
    }

    function testFuzz_DeFiApproval_PathMatchesRouterDecision(
        bool enableApprovalHardeningAddon,
        bool contractSpender,
        uint160 spenderSeed,
        uint96 amountSeed,
        uint32 warpSeed
    ) public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        if (enableApprovalHardeningAddon) {
            router.enableAddonPack(ADDON_PACK_APPROVAL_HARDENING);
        }

        MockERC20 token = new MockERC20();
        address spender = contractSpender
            ? address(new MockReceiver())
            : address(uint160(bound(uint256(spenderSeed), 1, type(uint160).max)));
        uint256 amount = bound(uint256(amountSeed), 0, 5 ether);
        bytes memory approvalData = abi.encodeWithSignature("approve(address,uint256)", spender, amount);

        (Decision decision, uint48 delaySeconds) =
            router.evaluate(address(wallet), address(token), 0, approvalData);

        if (decision == Decision.Allow) {
            wallet.executeNow(address(token), 0, approvalData);
            assertEq(token.allowance(address(wallet), spender), amount);
            return;
        }

        if (decision == Decision.Revert) {
            vm.expectRevert(Firewall_RevertedByPolicy.selector);
            wallet.executeNow(address(token), 0, approvalData);
            vm.expectRevert(Firewall_RevertedByPolicy.selector);
            wallet.schedule(address(token), 0, approvalData);
            return;
        }

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(address(token), 0, approvalData);

        bytes32 txId = wallet.schedule(address(token), 0, approvalData);
        (, , , , uint48 unlockTime, ) = wallet.getScheduled(txId);
        assertEq(unlockTime, uint48(block.timestamp) + delaySeconds);

        uint256 forward = bound(uint256(warpSeed), 0, uint256(delaySeconds) + 1);
        vm.warp(block.timestamp + forward);

        if (forward < delaySeconds) {
            vm.expectRevert(abi.encodeWithSelector(Firewall_NotUnlocked.selector, txId, unlockTime));
            wallet.executeScheduled(txId);
            return;
        }

        wallet.executeScheduled(txId);
        assertEq(token.allowance(address(wallet), spender), amount);
    }
}
