// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "./SmokeBase.t.sol";
import {
    FirewallModule,
    Firewall_RevertedByPolicy,
    Firewall_NotUnlocked
} from "../../src/FirewallModule.sol";
import {PolicyRouter} from "../../src/PolicyRouter.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";

contract V2MultiVaultMatrixStress is SmokeBase {
    uint256 internal constant WALLET_COUNT = 24;
    uint256 internal constant INITIAL_BALANCE = 20 ether;
    uint256 internal constant TRANSFER_CASES = 14;

    FirewallModule[] internal wallets;
    PolicyRouter[] internal routers;
    uint256[] internal basePackByWallet;

    function setUp() public {
        _deployV2WithRealBasePacks();

        for (uint256 i = 0; i < WALLET_COUNT; i++) {
            uint256 basePack = i % 2 == 0 ? BASE_PACK_CONSERVATIVE : BASE_PACK_DEFI;
            (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(basePack);

            wallets.push(wallet);
            routers.push(router);
            basePackByWallet.push(basePack);

            // Diverse add-on topology across wallets.
            if (i % 3 == 0) {
                router.enableAddonPack(ADDON_PACK_NEW_RECEIVER_24H);
            }
            if (i % 4 == 0) {
                router.enableAddonPack(ADDON_PACK_LARGE_TRANSFER_24H);
            }
            if (basePack == BASE_PACK_DEFI && i % 5 == 0) {
                router.enableAddonPack(ADDON_PACK_APPROVAL_HARDENING);
            }

            vm.deal(address(wallet), INITIAL_BALANCE);
        }
    }

    function test_MultiVault_Matrix_PoliciesAndVaultToVaultFlows() public {
        assertEq(wallets.length, WALLET_COUNT);
        assertEq(routers.length, WALLET_COUNT);
        assertEq(basePackByWallet.length, WALLET_COUNT);

        uint256 minEffectivePolicies = type(uint256).max;
        uint256 maxEffectivePolicies = 0;
        for (uint256 i = 0; i < WALLET_COUNT; i++) {
            uint256 effective = _effectivePolicyCount(routers[i]);
            if (effective < minEffectivePolicies) minEffectivePolicies = effective;
            if (effective > maxEffectivePolicies) maxEffectivePolicies = effective;
        }

        // Ensures we actually test multiple policy-set sizes.
        assertLe(minEffectivePolicies, 3);
        assertGe(maxEffectivePolicies, 6);

        uint256[TRANSFER_CASES] memory senders =
            [uint256(0), 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];
        uint256[TRANSFER_CASES] memory recipients =
            [uint256(14), 15, 16, 17, 18, 19, 20, 21, 22, 23, 0, 2, 4, 6];
        uint256[TRANSFER_CASES] memory amounts = [
            uint256(0.02 ether),
            0.03 ether,
            0.30 ether,
            0.40 ether,
            1.20 ether,
            0.01 ether,
            0.26 ether,
            0.80 ether,
            0.06 ether,
            1.10 ether,
            0.049 ether,
            0.07 ether,
            0.20 ether,
            0.005 ether
        ];

        uint256 executedVaultToVault;
        uint256 delayedVaultToVault;
        uint256 immediateVaultToVault;
        uint256 revertedVaultToVault;

        for (uint256 i = 0; i < TRANSFER_CASES; i++) {
            (uint8 flowType, bool executed) =
                _runVaultToVaultCase(senders[i], recipients[i], amounts[i]);

            if (flowType == 0) immediateVaultToVault++;
            if (flowType == 1) delayedVaultToVault++;
            if (flowType == 2) revertedVaultToVault++;
            if (executed) executedVaultToVault++;
        }

        assertGe(executedVaultToVault, 10);
        assertGe(delayedVaultToVault, 4);
        assertGe(immediateVaultToVault, 2);
        assertLe(revertedVaultToVault, TRANSFER_CASES);
    }

    // flowType: 0 = immediate allow, 1 = delayed schedule/execute, 2 = reverted
    function _runVaultToVaultCase(uint256 senderIdx, uint256 recipientIdx, uint256 amount)
        internal
        returns (uint8 flowType, bool executed)
    {
        FirewallModule senderWallet = wallets[senderIdx];
        PolicyRouter senderRouter = routers[senderIdx];
        address recipient = address(wallets[recipientIdx]);

        (Decision decision, uint48 delaySeconds) =
            senderRouter.evaluate(address(senderWallet), recipient, amount, "");

        uint256 recipientBalanceBefore = recipient.balance;

        if (decision == Decision.Allow) {
            senderWallet.executeNow(recipient, amount, "");
            assertEq(recipient.balance, recipientBalanceBefore + amount);
            return (0, true);
        }

        if (decision == Decision.Delay) {
            vm.expectRevert(Firewall_RevertedByPolicy.selector);
            senderWallet.executeNow(recipient, amount, "");

            bytes32 txId = senderWallet.schedule(recipient, amount, "");
            (, , , , uint48 unlockTime, ) = senderWallet.getScheduled(txId);
            assertEq(unlockTime, uint48(block.timestamp) + delaySeconds);

            vm.expectRevert(abi.encodeWithSelector(Firewall_NotUnlocked.selector, txId, unlockTime));
            senderWallet.executeScheduled(txId);

            vm.warp(unlockTime);
            senderWallet.executeScheduled(txId);
            assertEq(recipient.balance, recipientBalanceBefore + amount);
            return (1, true);
        }

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        senderWallet.executeNow(recipient, amount, "");
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        senderWallet.schedule(recipient, amount, "");
        return (2, false);
    }

    function _effectivePolicyCount(PolicyRouter router) internal view returns (uint256 count) {
        count = router.policyCount();
        uint256 addonPackCount = router.addonPackCount();
        for (uint256 i = 0; i < addonPackCount; i++) {
            uint256 packId = router.enabledAddonPackAt(i);
            count += router.enabledAddonPolicyCount(packId);
        }
    }
}
