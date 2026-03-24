// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "./SmokeBase.t.sol";
import {
    FirewallModule,
    Firewall_NotUnlocked,
    Firewall_RevertedByPolicy
} from "../../src/FirewallModule.sol";
import {
    PolicyRouter,
    Router_PackAlreadyEnabled,
    Router_InvalidAddonPack,
    Router_PackNotActive
} from "../../src/PolicyRouter.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockReceiver} from "../../src/mocks/MockReceiver.sol";

contract V2UserFlowsNoUi is SmokeBase {
    uint256 internal constant SMALL_VALUE = 0.01 ether;
    uint256 internal constant MISSING_ADDON_PACK = 999_999;
    bytes32 internal constant FIREWALL_STORAGE_SLOT =
        bytes32(uint256(keccak256("firewall.vault.storage.v1")) - 1);

    function setUp() public {
        _deployV2WithRealBasePacks();
    }

    function test_UserFlow_WalletCreation_InitialStateIsCorrect() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);

        assertTrue(factory.isFactoryVault(address(wallet)));
        assertEq(router.owner(), OWNER);
        assertEq(router.firewallModule(), address(wallet));
        assertEq(router.basePackId(), BASE_PACK_CONSERVATIVE);
        assertEq(router.policyCount(), 3);

        assertEq(wallet.router(), address(router));
        assertEq(wallet.feeConfigAdmin(), address(this));
        assertEq(wallet.protocolRegistry(), address(0));
        assertEq(wallet.nextNonce(), 0);

        assertEq(router.addonPackCount(), 0);
        assertFalse(router.isAddonPackEnabled(ADDON_PACK_APPROVAL_HARDENING));
        assertFalse(router.isAddonPackEnabled(ADDON_PACK_NEW_RECEIVER_24H));
        assertFalse(router.isAddonPackEnabled(ADDON_PACK_LARGE_TRANSFER_24H));

        assertEq(_readAddressAtOffset(address(wallet), 1), OWNER);
        assertEq(_readAddressAtOffset(address(wallet), 2), RECOVERY);
    }

    function test_UserFlow_AddonEnable_ActivatesPolicies_AndRepeatEnableDoesNotCorruptState() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        address receiver = address(0xCAFE);

        assertFalse(router.isAddonPackEnabled(ADDON_PACK_NEW_RECEIVER_24H));
        (Decision beforeDecision, uint48 beforeDelay) = router.evaluate(address(wallet), receiver, SMALL_VALUE, "");
        assertEq(uint256(beforeDecision), uint256(Decision.Delay));
        assertEq(beforeDelay, DEFI_NEW_RECEIVER_DELAY);

        router.enableAddonPack(ADDON_PACK_NEW_RECEIVER_24H);
        assertTrue(router.isAddonPackEnabled(ADDON_PACK_NEW_RECEIVER_24H));
        assertEq(router.addonPackCount(), 1);
        assertEq(router.enabledAddonPackAt(0), ADDON_PACK_NEW_RECEIVER_24H);

        (Decision afterDecision, uint48 afterDelay) = router.evaluate(address(wallet), receiver, SMALL_VALUE, "");
        assertEq(uint256(afterDecision), uint256(Decision.Delay));
        assertEq(afterDelay, ADDON_NEW_RECEIVER_DELAY);

        vm.expectRevert(
            abi.encodeWithSelector(Router_PackAlreadyEnabled.selector, ADDON_PACK_NEW_RECEIVER_24H)
        );
        router.enableAddonPack(ADDON_PACK_NEW_RECEIVER_24H);

        assertEq(router.addonPackCount(), 1);
        assertEq(router.enabledAddonPolicyCount(ADDON_PACK_NEW_RECEIVER_24H), 1);
    }

    function test_UserFlow_AddonEnable_InvalidAndMissingPackHandling() public {
        (, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);

        vm.expectRevert(abi.encodeWithSelector(Router_InvalidAddonPack.selector, BASE_PACK_CONSERVATIVE));
        router.enableAddonPack(BASE_PACK_CONSERVATIVE);

        vm.expectRevert(abi.encodeWithSelector(Router_PackNotActive.selector, MISSING_ADDON_PACK));
        router.enableAddonPack(MISSING_ADDON_PACK);
    }

    function test_UserFlow_Transfer_NewReceiverThenKnownThenLarge() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        address receiver = address(0xBEEFCAFE);
        vm.deal(address(wallet), 5 ether);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(receiver, SMALL_VALUE, "");

        bytes32 firstTxId = wallet.schedule(receiver, SMALL_VALUE, "");
        (, , , , uint48 firstUnlock,) = wallet.getScheduled(firstTxId);
        assertEq(firstUnlock, uint48(block.timestamp) + NEW_RECEIVER_DELAY);

        vm.warp(block.timestamp + NEW_RECEIVER_DELAY);
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

    function test_UserFlow_QueueLifecycle_CreateFailBeforeUnlockCancelAndExecuteStates() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        MockReceiver receiver = new MockReceiver();
        vm.deal(address(wallet), 5 ether);

        bytes32 txId = wallet.schedule(address(receiver), SMALL_VALUE, "");
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
        assertEq(value, SMALL_VALUE);
        assertEq(unlockTime, uint48(block.timestamp) + NEW_RECEIVER_DELAY);
        assertEq(dataHash, keccak256(bytes("")));

        vm.expectRevert(
            abi.encodeWithSelector(Firewall_NotUnlocked.selector, txId, block.timestamp + NEW_RECEIVER_DELAY)
        );
        wallet.executeScheduled(txId);

        wallet.cancelScheduled(txId);
        (bool existsAfterCancel, bool executedAfterCancel, , , , ) = wallet.getScheduled(txId);
        assertFalse(existsAfterCancel);
        assertFalse(executedAfterCancel);

        bytes32 txId2 = wallet.schedule(address(receiver), SMALL_VALUE, "");
        vm.warp(block.timestamp + NEW_RECEIVER_DELAY);
        wallet.executeScheduled(txId2);

        (bool existsAfterExec, bool executedAfterExec, , , , ) = wallet.getScheduled(txId2);
        assertFalse(existsAfterExec);
        assertTrue(executedAfterExec);
        assertEq(address(receiver).balance, SMALL_VALUE);
    }

    function test_UserFlow_ApprovalAddon_OnDeFiBaseChangesRealDecision() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();
        MockReceiver spender = new MockReceiver();
        bytes memory approveData = abi.encodeWithSignature("approve(address,uint256)", address(spender), 1);

        (Decision beforeDecision, uint48 beforeDelay) = router.evaluate(address(wallet), address(token), 0, approveData);
        assertEq(uint256(beforeDecision), uint256(Decision.Delay));
        assertEq(beforeDelay, DEFI_NEW_SPENDER_DELAY);

        router.enableAddonPack(ADDON_PACK_APPROVAL_HARDENING);
        assertTrue(router.isAddonPackEnabled(ADDON_PACK_APPROVAL_HARDENING));

        (Decision afterDecision, uint48 afterDelay) = router.evaluate(address(wallet), address(token), 0, approveData);
        assertEq(uint256(afterDecision), uint256(Decision.Revert));
        assertEq(afterDelay, 0);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(address(token), 0, approveData);
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.schedule(address(token), 0, approveData);
    }

    function _readAddressAtOffset(address target, uint256 offset) internal view returns (address) {
        bytes32 slot = bytes32(uint256(FIREWALL_STORAGE_SLOT) + offset);
        return address(uint160(uint256(vm.load(target, slot))));
    }
}
