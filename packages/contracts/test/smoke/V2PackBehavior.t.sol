// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "./SmokeBase.t.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {FirewallModule, Firewall_RevertedByPolicy, Firewall_ExecutionFailed} from "../../src/FirewallModule.sol";
import {PolicyRouter} from "../../src/PolicyRouter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockReceiver} from "../../src/mocks/MockReceiver.sol";

contract RevertingToken {
    function approve(address, uint256) external pure returns (bool) {
        revert("APPROVE_FAILED");
    }

    function transfer(address, uint256) external pure returns (bool) {
        revert("TRANSFER_FAILED");
    }
}

contract V2PackBehavior is SmokeBase {
    uint256 internal constant SMALL_VALUE = 0.01 ether;
    address internal constant SPENDER_EOA = address(0xBEEF);

    function setUp() public {
        _deployV2WithRealBasePacks();
    }

    function test_Base1DeFiTrader_FirstApprovalToNewContract_Delayed() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();
        MockReceiver spender = new MockReceiver();

        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(spender), type(uint256).max);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(address(token), 0, data);

        bytes32 txId = wallet.schedule(address(token), 0, data);
        (, , , , uint48 unlockTime,) = wallet.getScheduled(txId);
        assertEq(unlockTime, uint48(block.timestamp) + DEFI_NEW_SPENDER_DELAY);

        vm.warp(block.timestamp + DEFI_NEW_SPENDER_DELAY);
        wallet.executeScheduled(txId);

        assertEq(token.allowance(address(wallet), address(spender)), type(uint256).max);
    }

    function test_Base0Conservative_ApproveMax_StillBlocked() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        MockERC20 token = new MockERC20();

        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", SPENDER_EOA, type(uint256).max);
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(address(token), 0, data);
    }

    function test_Base0Conservative_ApproveZero_NotReverted() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        MockERC20 token = new MockERC20();

        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", SPENDER_EOA, 0);
        (Decision d,) = router.evaluate(address(wallet), address(token), 0, data);

        assertTrue(uint256(d) != uint256(Decision.Revert));
    }

    function test_Base0Conservative_ApproveNonZero_Blocked() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        MockERC20 token = new MockERC20();

        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", SPENDER_EOA, 1);
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(address(token), 0, data);
    }

    function test_Base1DeFiTrader_RepeatApprovalToKnownContract_Allowed() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();
        MockReceiver spender = new MockReceiver();

        _primeKnownContractSpender(wallet, token, address(spender));

        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(spender), 1);
        wallet.executeNow(address(token), 0, data);

        assertEq(token.allowance(address(wallet), address(spender)), 1);
    }

    function test_Base1DeFiTrader_FailedApprovalExecution_DoesNotMarkKnownSpender() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        RevertingToken token = new RevertingToken();
        MockReceiver spender = new MockReceiver();

        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(spender), 1);
        bytes32 txId = wallet.schedule(address(token), 0, data);
        vm.warp(block.timestamp + DEFI_NEW_SPENDER_DELAY);

        bytes memory expected = abi.encodeWithSignature("Error(string)", "APPROVE_FAILED");
        vm.expectRevert(abi.encodeWithSelector(Firewall_ExecutionFailed.selector, expected));
        wallet.executeScheduled(txId);

        assertFalse(defiApprovalToNewSpender.knownSpenders(address(wallet), address(token), address(spender)));
        (Decision d, uint48 delayOut) = router.evaluate(address(wallet), address(token), 0, data);
        assertEq(uint256(d), uint256(Decision.Delay));
        assertEq(delayOut, DEFI_NEW_SPENDER_DELAY);
    }

    function test_Base1DeFiTrader_ApprovalToEoa_Blocked() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();

        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", SPENDER_EOA, 1);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(address(token), 0, data);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.schedule(address(token), 0, data);
    }

    function test_Base1DeFiTrader_PermitBasedApproval_AllowedForKnownContractSpender() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();
        MockReceiver spender = new MockReceiver();

        _primeKnownContractSpender(wallet, token, address(spender));
        bytes memory permitData = _permitData(address(wallet), address(spender));
        (Decision d, uint48 delay) = router.evaluate(address(wallet), address(token), 0, permitData);

        assertEq(uint256(d), uint256(Decision.Allow));
        assertEq(delay, 0);
    }

    function test_Base0Conservative_PermitBasedApproval_StillBlocked() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        MockERC20 token = new MockERC20();

        bytes memory permitData = _permitData(address(wallet), SPENDER_EOA);
        (Decision d, uint48 delay) = router.evaluate(address(wallet), address(token), 0, permitData);

        assertEq(uint256(d), uint256(Decision.Revert));
        assertEq(delay, 0);
    }

    function test_Base1DeFiTrader_FirstPermitToNewContractSpender_Delayed() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();
        MockReceiver spender = new MockReceiver();

        bytes memory permitData = _permitData(address(wallet), address(spender));
        (Decision d, uint48 delay) = router.evaluate(address(wallet), address(token), 0, permitData);

        assertEq(uint256(d), uint256(Decision.Delay));
        assertEq(delay, DEFI_NEW_SPENDER_DELAY);
    }

    function test_Base1DeFiTrader_FirstSwapToNewRouter_NotDelayed() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockReceiver routerLike = new MockReceiver();

        bytes memory data = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            1,
            0,
            new address[](0),
            address(this),
            block.timestamp + 1 hours
        );

        wallet.executeNow(address(routerLike), 0, data);
        assertEq(routerLike.callCount(), 1);
    }

    function test_Base1DeFiTrader_FirstDepositToNewContract_NotDelayed() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockReceiver poolLike = new MockReceiver();

        bytes memory data = abi.encodeWithSignature("deposit(uint256)", 1);
        wallet.executeNow(address(poolLike), 0, data);

        assertEq(poolLike.callCount(), 1);
    }

    function test_Base1DeFiTrader_FirstTransferToNewEOA_StillDelayed() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_DEFI);
        address receiver = address(0xCAFE);
        vm.deal(address(wallet), 1 ether);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(receiver, SMALL_VALUE, "");

        bytes32 txId = wallet.schedule(receiver, SMALL_VALUE, "");
        (bool exists,,,,,) = wallet.getScheduled(txId);
        assertTrue(exists);
    }

    function test_Base1DeFiTrader_FirstErc20TransferToNewRecipient_Delayed() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();
        address recipient = address(0xC0FFEE);
        token.mint(address(wallet), 10 ether);

        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 0.1 ether);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(address(token), 0, data);

        bytes32 txId = wallet.schedule(address(token), 0, data);
        (, , , , uint48 unlockTime,) = wallet.getScheduled(txId);
        assertEq(unlockTime, uint48(block.timestamp) + DEFI_NEW_ERC20_RECIPIENT_DELAY);
    }

    function test_Base1DeFiTrader_RepeatErc20Recipient_AllowedAfterSuccessfulExecution() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_DEFI);
        MockERC20 token = new MockERC20();
        address recipient = address(0xC0FFEE);
        token.mint(address(wallet), 10 ether);

        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 0.1 ether);

        bytes32 txId = wallet.schedule(address(token), 0, data);
        vm.warp(block.timestamp + DEFI_NEW_ERC20_RECIPIENT_DELAY);
        wallet.executeScheduled(txId);
        assertEq(token.balanceOf(recipient), 0.1 ether);

        wallet.executeNow(address(token), 0, data);
        assertEq(token.balanceOf(recipient), 0.2 ether);
    }

    function test_Base1DeFiTrader_FailedTransferExecution_DoesNotMarkKnownRecipient() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        RevertingToken token = new RevertingToken();
        MockReceiver recipient = new MockReceiver();
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", address(recipient), 1);

        bytes32 txId = wallet.schedule(address(token), 0, data);
        vm.warp(block.timestamp + DEFI_NEW_ERC20_RECIPIENT_DELAY);

        bytes memory expected = abi.encodeWithSignature("Error(string)", "TRANSFER_FAILED");
        vm.expectRevert(abi.encodeWithSelector(Firewall_ExecutionFailed.selector, expected));
        wallet.executeScheduled(txId);

        assertFalse(defiErc20FirstRecipient.knownRecipients(address(wallet), address(token), address(recipient)));
        (Decision d, uint48 delayOut) = router.evaluate(address(wallet), address(token), 0, data);
        assertEq(uint256(d), uint256(Decision.Delay));
        assertEq(delayOut, DEFI_NEW_ERC20_RECIPIENT_DELAY);
    }

    function test_Base0Conservative_StrictFirstNewReceiverBehavior_StillWorks() public {
        (FirewallModule wallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        MockReceiver receiver = new MockReceiver();
        bytes memory data = abi.encodeWithSignature("ping(uint256)", 1);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(address(receiver), 0, data);

        bytes32 txId = wallet.schedule(address(receiver), 0, data);
        (bool exists,,,,,) = wallet.getScheduled(txId);
        assertTrue(exists);
    }

    function test_LargeTransferDelay_StillWorksAcrossPacks() public {
        (FirewallModule conservativeWallet, PolicyRouter conservativeRouter) =
            _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        (FirewallModule defiWallet, PolicyRouter defiRouter) = _createWalletAndRouter(BASE_PACK_DEFI);
        (FirewallModule vaultWallet, PolicyRouter vaultRouter) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        _enableStrongDelayAddons(vaultRouter);

        address conservativeReceiver = address(0xA001);
        address defiReceiver = address(0xA002);
        address vaultReceiver = address(0xA003);

        vm.deal(address(conservativeWallet), 2 ether);
        vm.deal(address(defiWallet), 2 ether);
        vm.deal(address(vaultWallet), 5 ether);

        _primeKnownEoaReceiver(conservativeWallet, conservativeReceiver, NEW_RECEIVER_DELAY);
        _primeKnownEoaReceiver(defiWallet, defiReceiver, DEFI_NEW_RECEIVER_DELAY);
        _primeKnownEoaReceiver(vaultWallet, vaultReceiver, ADDON_NEW_RECEIVER_DELAY);

        (Decision d0, uint48 delay0) =
            conservativeRouter.evaluate(address(conservativeWallet), conservativeReceiver, LARGE_THRESHOLD + 1, "");
        assertEq(uint256(d0), uint256(Decision.Delay));
        assertEq(delay0, LARGE_DELAY);

        (Decision d1, uint48 delay1) =
            defiRouter.evaluate(address(defiWallet), defiReceiver, DEFI_LARGE_THRESHOLD + 1, "");
        assertEq(uint256(d1), uint256(Decision.Delay));
        assertEq(delay1, DEFI_LARGE_DELAY);

        (Decision d2, uint48 delay2) =
            vaultRouter.evaluate(address(vaultWallet), vaultReceiver, ADDON_LARGE_THRESHOLD + 1, "");
        assertEq(uint256(d2), uint256(Decision.Delay));
        assertEq(delay2, ADDON_LARGE_DELAY);
    }

    function test_LargeTransferDelay_ExactThresholdNowDelaysAcrossPacks() public {
        (FirewallModule conservativeWallet, PolicyRouter conservativeRouter) =
            _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        (FirewallModule defiWallet, PolicyRouter defiRouter) = _createWalletAndRouter(BASE_PACK_DEFI);
        (FirewallModule vaultWallet, PolicyRouter vaultRouter) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        _enableStrongDelayAddons(vaultRouter);

        address conservativeReceiver = address(0xA101);
        address defiReceiver = address(0xA102);
        address vaultReceiver = address(0xA103);

        vm.deal(address(conservativeWallet), 2 ether);
        vm.deal(address(defiWallet), 2 ether);
        vm.deal(address(vaultWallet), 5 ether);

        _primeKnownEoaReceiver(conservativeWallet, conservativeReceiver, NEW_RECEIVER_DELAY);
        _primeKnownEoaReceiver(defiWallet, defiReceiver, DEFI_NEW_RECEIVER_DELAY);
        _primeKnownEoaReceiver(vaultWallet, vaultReceiver, ADDON_NEW_RECEIVER_DELAY);

        (Decision d0, uint48 delay0) =
            conservativeRouter.evaluate(address(conservativeWallet), conservativeReceiver, LARGE_THRESHOLD, "");
        assertEq(uint256(d0), uint256(Decision.Delay));
        assertEq(delay0, LARGE_DELAY);

        (Decision d1, uint48 delay1) =
            defiRouter.evaluate(address(defiWallet), defiReceiver, DEFI_LARGE_THRESHOLD, "");
        assertEq(uint256(d1), uint256(Decision.Delay));
        assertEq(delay1, DEFI_LARGE_DELAY);

        (Decision d2, uint48 delay2) =
            vaultRouter.evaluate(address(vaultWallet), vaultReceiver, ADDON_LARGE_THRESHOLD, "");
        assertEq(uint256(d2), uint256(Decision.Delay));
        assertEq(delay2, ADDON_LARGE_DELAY);
    }

    function test_SecurityAddons_AppliesStrongerDelayAndStrictApproval() public {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        _enableAllSecurityAddons(router);
        MockERC20 token = new MockERC20();
        address receiver = address(0xD00D);
        vm.deal(address(wallet), 5 ether);

        // Strict approval / permit behavior remains conservative with approval-hardening add-on enabled.
        bytes memory approveMaxData =
            abi.encodeWithSignature("approve(address,uint256)", SPENDER_EOA, type(uint256).max);
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(address(token), 0, approveMaxData);

        bytes memory permitData = _permitData(address(wallet), SPENDER_EOA);
        (Decision permitDecision, uint48 permitDelay) = router.evaluate(address(wallet), address(token), 0, permitData);
        assertEq(uint256(permitDecision), uint256(Decision.Revert));
        assertEq(permitDelay, 0);

        // First transfer to a new receiver is delayed for the full 24h add-on window.
        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(receiver, SMALL_VALUE, "");

        bytes32 txId = wallet.schedule(receiver, SMALL_VALUE, "");
        (, , , , uint48 unlockTime,) = wallet.getScheduled(txId);
        assertEq(unlockTime, uint48(block.timestamp) + ADDON_NEW_RECEIVER_DELAY);
    }

    function test_RepeatInteractionAfterFirstSuccessfulExecution_BehavesCorrectly() public {
        (FirewallModule conservativeWallet,) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        (FirewallModule defiWallet,) = _createWalletAndRouter(BASE_PACK_DEFI);

        MockReceiver contractReceiver = new MockReceiver();
        bytes memory contractData = abi.encodeWithSignature("ping(uint256)", 1);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        conservativeWallet.executeNow(address(contractReceiver), 0, contractData);

        bytes32 txIdContract = conservativeWallet.schedule(address(contractReceiver), 0, contractData);
        vm.warp(block.timestamp + NEW_RECEIVER_DELAY);
        conservativeWallet.executeScheduled(txIdContract);
        assertEq(contractReceiver.callCount(), 1);

        conservativeWallet.executeNow(address(contractReceiver), 0, contractData);
        assertEq(contractReceiver.callCount(), 2);

        address eoaReceiver = address(0xBEEFCAFE);
        vm.deal(address(defiWallet), 1 ether);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        defiWallet.executeNow(eoaReceiver, SMALL_VALUE, "");

        bytes32 txIdEoa = defiWallet.schedule(eoaReceiver, SMALL_VALUE, "");
        vm.warp(block.timestamp + DEFI_NEW_RECEIVER_DELAY);
        defiWallet.executeScheduled(txIdEoa);
        uint256 afterFirst = eoaReceiver.balance;

        defiWallet.executeNow(eoaReceiver, SMALL_VALUE, "");
        assertEq(eoaReceiver.balance, afterFirst + SMALL_VALUE);
    }

    function _permitData(address owner, address spender) internal view returns (bytes memory) {
        return abi.encodeWithSignature(
            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
            owner,
            spender,
            type(uint256).max,
            block.timestamp + 1 days,
            uint8(27),
            bytes32(0),
            bytes32(0)
        );
    }

    function _primeKnownEoaReceiver(FirewallModule wallet, address receiver, uint48 delaySeconds) internal {
        bytes32 txId = wallet.schedule(receiver, SMALL_VALUE, "");
        vm.warp(block.timestamp + delaySeconds);
        wallet.executeScheduled(txId);
    }

    function _primeKnownContractSpender(FirewallModule wallet, MockERC20 token, address spender) internal {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", spender, 1);
        bytes32 txId = wallet.schedule(address(token), 0, data);
        vm.warp(block.timestamp + DEFI_NEW_SPENDER_DELAY);
        wallet.executeScheduled(txId);
    }

    function _enableStrongDelayAddons(PolicyRouter router) internal {
        _grantEntitlement(ADDON_PACK_NEW_RECEIVER_24H, true);
        router.enableAddonPack(ADDON_PACK_NEW_RECEIVER_24H);
        _grantEntitlement(ADDON_PACK_LARGE_TRANSFER_24H, true);
        router.enableAddonPack(ADDON_PACK_LARGE_TRANSFER_24H);
    }

    function _enableAllSecurityAddons(PolicyRouter router) internal {
        _grantEntitlement(ADDON_PACK_APPROVAL_HARDENING, true);
        router.enableAddonPack(ADDON_PACK_APPROVAL_HARDENING);
        _enableStrongDelayAddons(router);
    }
}
