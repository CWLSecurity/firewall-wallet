// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "./SmokeBase.t.sol";
import {
    FirewallModule,
    Firewall_RevertedByPolicy,
    Firewall_NotUnlocked,
    Firewall_NotScheduled,
    Firewall_AlreadyExecuted
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

contract V2StrictCoverageDelayedFlows is SmokeBase {
    uint256 internal constant SMALL_VALUE = 0.01 ether;
    uint256 internal constant MISSING_ADDON_PACK = 999_999;

    function setUp() public {
        _deployV2WithRealBasePacks();
    }

    function test_Strict_WalletCreation_InitialQueueAndModuleState() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);

        assertTrue(factory.isFactoryVault(address(wallet)));
        assertEq(router.owner(), OWNER);
        assertEq(router.firewallModule(), address(wallet));
        assertEq(router.basePackId(), BASE_PACK_CONSERVATIVE);
        assertEq(router.policyCount(), 3);

        assertEq(wallet.router(), address(router));
        assertEq(wallet.nextNonce(), 0);
        assertEq(wallet.scheduledTxIdByNonce(0), bytes32(0));

        (bool exists, bool executed, address to, uint256 value, uint48 unlockTime, bytes32 dataHash) =
            wallet.getScheduled(bytes32(uint256(123456)));
        assertFalse(exists);
        assertFalse(executed);
        assertEq(to, address(0));
        assertEq(value, 0);
        assertEq(unlockTime, 0);
        assertEq(dataHash, bytes32(0));

        assertEq(router.addonPackCount(), 0);
        assertFalse(router.isAddonPackEnabled(ADDON_PACK_APPROVAL_HARDENING));
        assertFalse(router.isAddonPackEnabled(ADDON_PACK_NEW_RECEIVER_24H));
        assertFalse(router.isAddonPackEnabled(ADDON_PACK_LARGE_TRANSFER_24H));
    }

    function test_Strict_AddonEnable_OnlyTargetAddonBecomesEnabled() public {
        (, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);

        assertFalse(router.isAddonPackEnabled(ADDON_PACK_APPROVAL_HARDENING));
        assertFalse(router.isAddonPackEnabled(ADDON_PACK_NEW_RECEIVER_24H));
        assertFalse(router.isAddonPackEnabled(ADDON_PACK_LARGE_TRANSFER_24H));
        assertEq(router.addonPackCount(), 0);

        router.enableAddonPack(ADDON_PACK_NEW_RECEIVER_24H);

        assertEq(router.addonPackCount(), 1);
        assertEq(router.enabledAddonPackAt(0), ADDON_PACK_NEW_RECEIVER_24H);
        assertTrue(router.isAddonPackEnabled(ADDON_PACK_NEW_RECEIVER_24H));
        assertFalse(router.isAddonPackEnabled(ADDON_PACK_APPROVAL_HARDENING));
        assertFalse(router.isAddonPackEnabled(ADDON_PACK_LARGE_TRANSFER_24H));

        vm.expectRevert(
            abi.encodeWithSelector(Router_PackAlreadyEnabled.selector, ADDON_PACK_NEW_RECEIVER_24H)
        );
        router.enableAddonPack(ADDON_PACK_NEW_RECEIVER_24H);
    }

    function test_Strict_AddonEnable_InvalidMissingInactiveAndBasePackHandling() public {
        (, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);

        vm.expectRevert(abi.encodeWithSelector(Router_InvalidAddonPack.selector, BASE_PACK_CONSERVATIVE));
        router.enableAddonPack(BASE_PACK_CONSERVATIVE);

        vm.expectRevert(abi.encodeWithSelector(Router_PackNotActive.selector, MISSING_ADDON_PACK));
        router.enableAddonPack(MISSING_ADDON_PACK);

        registry.setPackActive(ADDON_PACK_NEW_RECEIVER_24H, false);
        vm.expectRevert(abi.encodeWithSelector(Router_PackNotActive.selector, ADDON_PACK_NEW_RECEIVER_24H));
        router.enableAddonPack(ADDON_PACK_NEW_RECEIVER_24H);
    }

    function test_Strict_24HourNewReceiverDelay_BeforeAndAfterAddon_WithBoundaries() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        address receiverBase = address(0xCAFE01);
        address receiverAddonBoundary = address(0xCAFE02);
        address receiverAddonAfter = address(0xCAFE03);

        vm.deal(address(wallet), 10 ether);

        (Decision baseDecision, uint48 baseDelay) = router.evaluate(address(wallet), receiverBase, SMALL_VALUE, "");
        assertEq(uint256(baseDecision), uint256(Decision.Delay));
        assertEq(baseDelay, DEFI_NEW_RECEIVER_DELAY);

        bytes32 baseTxId = wallet.schedule(receiverBase, SMALL_VALUE, "");
        (, , , , uint48 baseUnlockTime,) = wallet.getScheduled(baseTxId);
        assertEq(baseUnlockTime, uint48(block.timestamp) + DEFI_NEW_RECEIVER_DELAY);

        vm.warp(uint256(baseUnlockTime) - 1);
        _expectNotUnlocked(baseTxId, baseUnlockTime);
        wallet.executeScheduled(baseTxId);

        vm.warp(baseUnlockTime);
        wallet.executeScheduled(baseTxId);
        assertEq(receiverBase.balance, SMALL_VALUE);

        router.enableAddonPack(ADDON_PACK_NEW_RECEIVER_24H);

        (Decision addonDecision, uint48 addonDelay) =
            router.evaluate(address(wallet), receiverAddonBoundary, SMALL_VALUE, "");
        assertEq(uint256(addonDecision), uint256(Decision.Delay));
        assertEq(addonDelay, ADDON_NEW_RECEIVER_DELAY);

        bytes32 addonBoundaryTxId = wallet.schedule(receiverAddonBoundary, SMALL_VALUE, "");
        (, , , , uint48 addonBoundaryUnlockTime,) = wallet.getScheduled(addonBoundaryTxId);
        assertEq(addonBoundaryUnlockTime, uint48(block.timestamp) + ADDON_NEW_RECEIVER_DELAY);

        vm.warp(uint256(addonBoundaryUnlockTime) - 1);
        _expectNotUnlocked(addonBoundaryTxId, addonBoundaryUnlockTime);
        wallet.executeScheduled(addonBoundaryTxId);

        vm.warp(addonBoundaryUnlockTime);
        wallet.executeScheduled(addonBoundaryTxId);
        assertEq(receiverAddonBoundary.balance, SMALL_VALUE);

        bytes32 addonAfterTxId = wallet.schedule(receiverAddonAfter, SMALL_VALUE, "");
        (, , , , uint48 addonAfterUnlockTime,) = wallet.getScheduled(addonAfterTxId);
        assertEq(addonAfterUnlockTime, uint48(block.timestamp) + ADDON_NEW_RECEIVER_DELAY);

        vm.warp(uint256(addonAfterUnlockTime) + 1);
        wallet.executeScheduled(addonAfterTxId);
        assertEq(receiverAddonAfter.balance, SMALL_VALUE);
    }

    function test_Strict_24HourLargeTransferDelay_BeforeAndAfterAddon_WithBoundaries() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        address receiver = address(0xBEEF01);
        uint256 largeValue = ADDON_LARGE_THRESHOLD + 1;

        vm.deal(address(wallet), 10 ether);

        _primeKnownEthReceiver(wallet, receiver, NEW_RECEIVER_DELAY);

        (Decision baseDecision, uint48 baseDelay) = router.evaluate(address(wallet), receiver, largeValue, "");
        assertEq(uint256(baseDecision), uint256(Decision.Delay));
        assertEq(baseDelay, LARGE_DELAY);

        bytes32 baseTxId = wallet.schedule(receiver, largeValue, "");
        (, , , , uint48 baseUnlockTime,) = wallet.getScheduled(baseTxId);
        assertEq(baseUnlockTime, uint48(block.timestamp) + LARGE_DELAY);

        vm.warp(uint256(baseUnlockTime) - 1);
        _expectNotUnlocked(baseTxId, baseUnlockTime);
        wallet.executeScheduled(baseTxId);

        vm.warp(baseUnlockTime);
        wallet.executeScheduled(baseTxId);

        router.enableAddonPack(ADDON_PACK_LARGE_TRANSFER_24H);

        (Decision addonDecision, uint48 addonDelay) = router.evaluate(address(wallet), receiver, largeValue, "");
        assertEq(uint256(addonDecision), uint256(Decision.Delay));
        assertEq(addonDelay, ADDON_LARGE_DELAY);

        bytes32 addonBoundaryTxId = wallet.schedule(receiver, largeValue, "");
        (, , , , uint48 addonBoundaryUnlockTime,) = wallet.getScheduled(addonBoundaryTxId);
        assertEq(addonBoundaryUnlockTime, uint48(block.timestamp) + ADDON_LARGE_DELAY);

        vm.warp(uint256(addonBoundaryUnlockTime) - 1);
        _expectNotUnlocked(addonBoundaryTxId, addonBoundaryUnlockTime);
        wallet.executeScheduled(addonBoundaryTxId);

        vm.warp(addonBoundaryUnlockTime);
        wallet.executeScheduled(addonBoundaryTxId);

        bytes32 addonAfterTxId = wallet.schedule(receiver, largeValue, "");
        (, , , , uint48 addonAfterUnlockTime,) = wallet.getScheduled(addonAfterTxId);
        assertEq(addonAfterUnlockTime, uint48(block.timestamp) + ADDON_LARGE_DELAY);

        vm.warp(uint256(addonAfterUnlockTime) + 1);
        wallet.executeScheduled(addonAfterTxId);
    }

    function test_Strict_QueueLifecycle_CancelBeforeAfterUnlock_SecondCancel_ExecuteAndCancelStates() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        MockReceiver receiver = new MockReceiver();

        vm.deal(address(wallet), 3 ether);

        bytes32 txIdBeforeUnlock = wallet.schedule(address(receiver), SMALL_VALUE, "");
        uint48 unlockBefore = _unlockTime(wallet, txIdBeforeUnlock);
        assertEq(unlockBefore, uint48(block.timestamp) + NEW_RECEIVER_DELAY);
        _assertScheduledPending(
            wallet,
            txIdBeforeUnlock,
            address(receiver),
            SMALL_VALUE,
            unlockBefore,
            keccak256(bytes(""))
        );

        _expectNotUnlocked(txIdBeforeUnlock, unlockBefore);
        wallet.executeScheduled(txIdBeforeUnlock);

        wallet.cancelScheduled(txIdBeforeUnlock);
        _assertScheduledMissing(wallet, txIdBeforeUnlock);

        vm.expectRevert(abi.encodeWithSelector(Firewall_NotScheduled.selector, txIdBeforeUnlock));
        wallet.cancelScheduled(txIdBeforeUnlock);

        vm.expectRevert(abi.encodeWithSelector(Firewall_NotScheduled.selector, txIdBeforeUnlock));
        wallet.executeScheduled(txIdBeforeUnlock);

        bytes32 txIdAfterUnlockCancel = wallet.schedule(address(receiver), SMALL_VALUE, "");
        uint48 unlockAfterUnlockCancel = _unlockTime(wallet, txIdAfterUnlockCancel);
        vm.warp(unlockAfterUnlockCancel);
        wallet.cancelScheduled(txIdAfterUnlockCancel);
        _assertScheduledMissing(wallet, txIdAfterUnlockCancel);

        vm.expectRevert(abi.encodeWithSelector(Firewall_NotScheduled.selector, txIdAfterUnlockCancel));
        wallet.executeScheduled(txIdAfterUnlockCancel);

        bytes32 txIdExecuted = wallet.schedule(address(receiver), SMALL_VALUE, "");
        uint48 unlockExecuted = _unlockTime(wallet, txIdExecuted);
        vm.warp(unlockExecuted);
        wallet.executeScheduled(txIdExecuted);

        _assertScheduledExecuted(wallet, txIdExecuted);

        vm.expectRevert(abi.encodeWithSelector(Firewall_AlreadyExecuted.selector, txIdExecuted));
        wallet.cancelScheduled(txIdExecuted);
    }

    function test_Strict_TransferBoundaries_ETH_JustBelowExactlyAndJustAbove() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        address knownReceiver = address(0xDEAD01);

        vm.deal(address(wallet), 5 ether);
        _primeKnownEthReceiver(wallet, knownReceiver, NEW_RECEIVER_DELAY);

        uint256 below = LARGE_THRESHOLD - 1;
        uint256 exact = LARGE_THRESHOLD;
        uint256 above = LARGE_THRESHOLD + 1;

        (Decision belowDecision, uint48 belowDelay) = router.evaluate(address(wallet), knownReceiver, below, "");
        assertEq(uint256(belowDecision), uint256(Decision.Allow));
        assertEq(belowDelay, 0);

        (Decision exactDecision, uint48 exactDelay) = router.evaluate(address(wallet), knownReceiver, exact, "");
        assertEq(uint256(exactDecision), uint256(Decision.Delay));
        assertEq(exactDelay, LARGE_DELAY);

        (Decision aboveDecision, uint48 aboveDelay) = router.evaluate(address(wallet), knownReceiver, above, "");
        assertEq(uint256(aboveDecision), uint256(Decision.Delay));
        assertEq(aboveDelay, LARGE_DELAY);

        wallet.executeNow(knownReceiver, below, "");

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(knownReceiver, exact, "");
        bytes32 exactTxId = wallet.schedule(knownReceiver, exact, "");
        (, , , , uint48 exactUnlockTime,) = wallet.getScheduled(exactTxId);
        assertEq(exactUnlockTime, uint48(block.timestamp) + LARGE_DELAY);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(knownReceiver, above, "");
        bytes32 aboveTxId = wallet.schedule(knownReceiver, above, "");
        (, , , , uint48 aboveUnlockTime,) = wallet.getScheduled(aboveTxId);
        assertEq(aboveUnlockTime, uint48(block.timestamp) + LARGE_DELAY);
    }

    function test_Strict_TransferBoundaries_ERC20_JustBelowExactlyAndJustAbove() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        MockERC20 token = new MockERC20();
        address recipient = address(0xDEAD02);
        uint256 threshold = LARGE_ERC20_THRESHOLD_UNITS;

        token.mint(address(wallet), 5 ether);

        bytes memory primeData = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1);
        bytes32 primeTxId = wallet.schedule(address(token), 0, primeData);
        uint48 primeUnlockTime = _unlockTime(wallet, primeTxId);
        assertEq(primeUnlockTime, uint48(block.timestamp) + NEW_RECEIVER_DELAY);

        vm.warp(primeUnlockTime);
        wallet.executeScheduled(primeTxId);
        assertEq(token.balanceOf(recipient), 1);

        {
            bytes memory belowData =
                abi.encodeWithSignature("transfer(address,uint256)", recipient, threshold - 1);
            _assertDecision(
                router,
                address(wallet),
                address(token),
                0,
                belowData,
                Decision.Allow,
                0
            );
            wallet.executeNow(address(token), 0, belowData);
            assertEq(token.balanceOf(recipient), threshold);
        }

        {
            bytes memory exactData = abi.encodeWithSignature("transfer(address,uint256)", recipient, threshold);
            _assertDecision(
                router,
                address(wallet),
                address(token),
                0,
                exactData,
                Decision.Delay,
                LARGE_DELAY
            );
            vm.expectRevert(Firewall_RevertedByPolicy.selector);
            wallet.executeNow(address(token), 0, exactData);
            bytes32 exactTxId = wallet.schedule(address(token), 0, exactData);
            uint48 exactUnlockTime = _unlockTime(wallet, exactTxId);
            assertEq(exactUnlockTime, uint48(block.timestamp) + LARGE_DELAY);
        }

        {
            bytes memory aboveData =
                abi.encodeWithSignature("transfer(address,uint256)", recipient, threshold + 1);
            _assertDecision(
                router,
                address(wallet),
                address(token),
                0,
                aboveData,
                Decision.Delay,
                LARGE_DELAY
            );
            vm.expectRevert(Firewall_RevertedByPolicy.selector);
            wallet.executeNow(address(token), 0, aboveData);
            bytes32 aboveTxId = wallet.schedule(address(token), 0, aboveData);
            uint48 aboveUnlockTime = _unlockTime(wallet, aboveTxId);
            assertEq(aboveUnlockTime, uint48(block.timestamp) + LARGE_DELAY);
        }
    }

    function test_Strict_ApprovalFlow_DeFiBaseToHardening_AddonTransitionAndAllowedPath() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();
        MockReceiver spender = new MockReceiver();

        bytes memory approveNonZero = abi.encodeWithSignature("approve(address,uint256)", address(spender), 1);
        _assertDecision(
            router,
            address(wallet),
            address(token),
            0,
            approveNonZero,
            Decision.Delay,
            DEFI_NEW_SPENDER_DELAY
        );

        bytes32 baseTxId = wallet.schedule(address(token), 0, approveNonZero);
        uint48 baseUnlockTime = _unlockTime(wallet, baseTxId);
        assertEq(baseUnlockTime, uint48(block.timestamp) + DEFI_NEW_SPENDER_DELAY);

        vm.warp(uint256(baseUnlockTime) - 1);
        _expectNotUnlocked(baseTxId, baseUnlockTime);
        wallet.executeScheduled(baseTxId);

        vm.warp(baseUnlockTime);
        wallet.executeScheduled(baseTxId);
        assertEq(token.allowance(address(wallet), address(spender)), 1);

        router.enableAddonPack(ADDON_PACK_APPROVAL_HARDENING);

        _assertDecision(
            router,
            address(wallet),
            address(token),
            0,
            approveNonZero,
            Decision.Revert,
            0
        );

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(address(token), 0, approveNonZero);
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.schedule(address(token), 0, approveNonZero);

        bytes memory approveZero = abi.encodeWithSignature("approve(address,uint256)", address(spender), 0);
        _assertDecision(router, address(wallet), address(token), 0, approveZero, Decision.Allow, 0);

        wallet.executeNow(address(token), 0, approveZero);
        assertEq(token.allowance(address(wallet), address(spender)), 0);
    }

    function test_Strict_Isolation_NewReceiverAddonDoesNotAffectApprovalPolicyFamily() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();
        MockReceiver spender = new MockReceiver();

        bytes memory approveNonZero = abi.encodeWithSignature("approve(address,uint256)", address(spender), 1);

        (Decision beforeDecision, uint48 beforeDelay) = router.evaluate(address(wallet), address(token), 0, approveNonZero);
        assertEq(uint256(beforeDecision), uint256(Decision.Delay));
        assertEq(beforeDelay, DEFI_NEW_SPENDER_DELAY);

        router.enableAddonPack(ADDON_PACK_NEW_RECEIVER_24H);

        (Decision afterDecision, uint48 afterDelay) = router.evaluate(address(wallet), address(token), 0, approveNonZero);
        assertEq(uint256(afterDecision), uint256(Decision.Delay));
        assertEq(afterDelay, DEFI_NEW_SPENDER_DELAY);

        router.enableAddonPack(ADDON_PACK_LARGE_TRANSFER_24H);

        (Decision afterLargeAddonDecision, uint48 afterLargeAddonDelay) =
            router.evaluate(address(wallet), address(token), 0, approveNonZero);
        assertEq(uint256(afterLargeAddonDecision), uint256(Decision.Delay));
        assertEq(afterLargeAddonDelay, DEFI_NEW_SPENDER_DELAY);
    }

    function test_Strict_QueueIsolation_DifferentDelayReasonsRemainIndependent() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();
        MockReceiver spender = new MockReceiver();
        address newReceiver = address(0xFEE123);

        vm.deal(address(wallet), 1 ether);

        router.enableAddonPack(ADDON_PACK_NEW_RECEIVER_24H);

        bytes memory approvalData = abi.encodeWithSignature("approve(address,uint256)", address(spender), 1);

        bytes32 approvalTxId = wallet.schedule(address(token), 0, approvalData);
        (, , , , uint48 approvalUnlockTime,) = wallet.getScheduled(approvalTxId);
        assertEq(approvalUnlockTime, uint48(block.timestamp) + DEFI_NEW_SPENDER_DELAY);

        bytes32 receiverTxId = wallet.schedule(newReceiver, SMALL_VALUE, "");
        (, , , , uint48 receiverUnlockTime,) = wallet.getScheduled(receiverTxId);
        assertEq(receiverUnlockTime, uint48(block.timestamp) + ADDON_NEW_RECEIVER_DELAY);

        assertEq(wallet.nextNonce(), 2);
        assertEq(wallet.scheduledTxIdByNonce(0), approvalTxId);
        assertEq(wallet.scheduledTxIdByNonce(1), receiverTxId);

        wallet.cancelScheduled(receiverTxId);

        vm.warp(approvalUnlockTime);
        wallet.executeScheduled(approvalTxId);
        assertEq(token.allowance(address(wallet), address(spender)), 1);

        vm.expectRevert(abi.encodeWithSelector(Firewall_NotScheduled.selector, receiverTxId));
        wallet.executeScheduled(receiverTxId);

        assertTrue(router.isAddonPackEnabled(ADDON_PACK_NEW_RECEIVER_24H));
        assertFalse(router.isAddonPackEnabled(ADDON_PACK_APPROVAL_HARDENING));
        assertFalse(router.isAddonPackEnabled(ADDON_PACK_LARGE_TRANSFER_24H));
    }

    function _expectNotUnlocked(bytes32 txId, uint48 unlockTime) internal {
        vm.expectRevert(abi.encodeWithSelector(Firewall_NotUnlocked.selector, txId, uint256(unlockTime)));
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

    function _primeKnownEthReceiver(FirewallModule wallet, address receiver, uint48 delaySeconds) internal {
        bytes32 txId = wallet.schedule(receiver, SMALL_VALUE, "");
        vm.warp(block.timestamp + delaySeconds);
        wallet.executeScheduled(txId);
    }
}
