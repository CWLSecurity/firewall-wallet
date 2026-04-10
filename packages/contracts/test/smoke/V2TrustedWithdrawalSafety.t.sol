// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "./SmokeBase.t.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {FirewallModule, Firewall_RevertedByPolicy} from "../../src/FirewallModule.sol";
import {PolicyRouter} from "../../src/PolicyRouter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract V2TrustedWithdrawalSafety is SmokeBase {
    uint256 internal constant LARGE_WITHDRAW_WEI = 1 ether;
    uint256 internal constant SMALL_WITHDRAW_WEI = 0.01 ether;
    uint256 internal constant LONG_SAFETY_WARP = 366 days;

    function setUp() public {
        _deployV2WithRealBasePacks();
    }

    function test_TrustedNativeWithdraw_Matrix_NoPermanentRevertAcrossReachableStates() public {
        uint8[4] memory conservativeMasks = [uint8(0), uint8(2), uint8(4), uint8(6)];
        for (uint256 i = 0; i < conservativeMasks.length; i++) {
            _runNativeScenario(BASE_PACK_CONSERVATIVE, conservativeMasks[i], i);
        }

        for (uint8 mask = 0; mask < 8; mask++) {
            _runNativeScenario(BASE_PACK_DEFI, mask, mask);
        }
    }

    function test_TrustedErc20Withdraw_Matrix_NoPermanentRevertAcrossReachableStates() public {
        uint8[4] memory conservativeMasks = [uint8(0), uint8(2), uint8(4), uint8(6)];
        for (uint256 i = 0; i < conservativeMasks.length; i++) {
            _runErc20Scenario(BASE_PACK_CONSERVATIVE, conservativeMasks[i], i);
        }

        for (uint8 mask = 0; mask < 8; mask++) {
            _runErc20Scenario(BASE_PACK_DEFI, mask, mask);
        }
    }

    function test_TrustedNativeWithdraw_RepeatSmallTransfersRemainExecutable() public {
        _runRepeatTrustedSmallNative(BASE_PACK_CONSERVATIVE, 6, address(0xC0A1));
        _runRepeatTrustedSmallNative(BASE_PACK_DEFI, 7, address(0xD0A1));
    }

    function _runNativeScenario(uint256 basePackId, uint8 mask, uint256 idx) internal {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(basePackId);
        _enableMask(router, basePackId, mask);

        address trusted = address(uint160(0x100000 + (basePackId * 0x100) + idx));
        vm.deal(address(wallet), 4 ether);
        uint256 beforeBalance = trusted.balance;

        _withdrawNativeWithFallback(wallet, router, basePackId, trusted, LARGE_WITHDRAW_WEI, true);

        assertEq(
            trusted.balance - beforeBalance,
            LARGE_WITHDRAW_WEI,
            "trusted native transfer should complete"
        );
    }

    function _runErc20Scenario(uint256 basePackId, uint8 mask, uint256 idx) internal {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(basePackId);
        _enableMask(router, basePackId, mask);

        MockERC20 token = new MockERC20();
        token.mint(address(wallet), 5 ether);
        address trusted = address(uint160(0x200000 + (basePackId * 0x100) + idx));

        _withdrawErc20WithFallback(
            wallet, router, basePackId, token, trusted, LARGE_WITHDRAW_WEI, true
        );
        assertEq(token.balanceOf(trusted), LARGE_WITHDRAW_WEI, "trusted erc20 transfer should complete");
    }

    function _runRepeatTrustedSmallNative(uint256 basePackId, uint8 mask, address trusted) internal {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(basePackId);
        _enableMask(router, basePackId, mask);
        vm.deal(address(wallet), 3 ether);

        // First transfer may be delayed; this primes trusted-receiver state.
        _withdrawNativeWithFallback(wallet, router, basePackId, trusted, LARGE_WITHDRAW_WEI, false);
        uint256 afterFirst = trusted.balance;

        for (uint256 i = 0; i < 3; i++) {
            (Decision d,) = router.evaluate(address(wallet), trusted, SMALL_WITHDRAW_WEI, "");
            assertEq(
                uint256(d),
                uint256(Decision.Allow),
                "small trusted native transfer should be immediate after priming"
            );
            wallet.executeNow(trusted, SMALL_WITHDRAW_WEI, "");
        }

        assertEq(
            trusted.balance - afterFirst,
            SMALL_WITHDRAW_WEI * 3,
            "repeated small trusted withdrawals should remain executable"
        );
    }

    function _withdrawNativeWithFallback(
        FirewallModule wallet,
        PolicyRouter router,
        uint256 basePackId,
        address trusted,
        uint256 amount,
        bool hardenAfterSchedule
    ) internal {
        (Decision d,) = router.evaluate(address(wallet), trusted, amount, "");
        assertTrue(
            uint256(d) != uint256(Decision.Revert),
            "trusted native withdrawal unexpectedly reverted by policies"
        );

        if (d == Decision.Allow) {
            wallet.executeNow(trusted, amount, "");
            return;
        }

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(trusted, amount, "");
        bytes32 txId = wallet.schedule(trusted, amount, "");

        if (hardenAfterSchedule) {
            _enableMaxHardening(router, basePackId);
        }

        vm.warp(block.timestamp + LONG_SAFETY_WARP);
        wallet.executeScheduled(txId);
    }

    function _withdrawErc20WithFallback(
        FirewallModule wallet,
        PolicyRouter router,
        uint256 basePackId,
        MockERC20 token,
        address trusted,
        uint256 amount,
        bool hardenAfterSchedule
    ) internal {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", trusted, amount);

        (Decision d,) = router.evaluate(address(wallet), address(token), 0, data);
        assertTrue(
            uint256(d) != uint256(Decision.Revert),
            "trusted erc20 withdrawal unexpectedly reverted by policies"
        );

        if (d == Decision.Allow) {
            wallet.executeNow(address(token), 0, data);
            return;
        }

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(address(token), 0, data);
        bytes32 txId = wallet.schedule(address(token), 0, data);

        if (hardenAfterSchedule) {
            _enableMaxHardening(router, basePackId);
        }

        vm.warp(block.timestamp + LONG_SAFETY_WARP);
        wallet.executeScheduled(txId);
    }

    function _enableMask(PolicyRouter router, uint256 basePackId, uint8 mask) internal {
        if ((mask & 0x01) != 0) {
            if (basePackId == BASE_PACK_DEFI) {
                _enableAddonIfDisabled(router, ADDON_PACK_APPROVAL_HARDENING);
            }
        }
        if ((mask & 0x02) != 0) {
            _enableAddonIfDisabled(router, ADDON_PACK_NEW_RECEIVER_24H);
        }
        if ((mask & 0x04) != 0) {
            _enableAddonIfDisabled(router, ADDON_PACK_LARGE_TRANSFER_24H);
        }
    }

    function _enableMaxHardening(PolicyRouter router, uint256 basePackId) internal {
        if (basePackId == BASE_PACK_DEFI) {
            _enableAddonIfDisabled(router, ADDON_PACK_APPROVAL_HARDENING);
        }
        _enableAddonIfDisabled(router, ADDON_PACK_NEW_RECEIVER_24H);
        _enableAddonIfDisabled(router, ADDON_PACK_LARGE_TRANSFER_24H);
    }

    function _enableAddonIfDisabled(PolicyRouter router, uint256 packId) internal {
        if (router.isAddonPackEnabled(packId)) {
            return;
        }
        _grantEntitlement(packId, true);
        router.enableAddonPack(packId);
    }
}
