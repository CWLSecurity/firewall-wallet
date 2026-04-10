// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {SmokeBase} from "../smoke/SmokeBase.t.sol";
import {
    FirewallModule,
    Firewall_RevertedByPolicy
} from "../../src/FirewallModule.sol";
import {PolicyRouter} from "../../src/PolicyRouter.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

contract V2BaseMainnetFork is Test, SmokeBase {
    address internal constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    address internal constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function testFork_ConservativeEthFlow_OnBaseFork() public {
        if (!_enableFork()) return;

        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_CONSERVATIVE);
        address recipient = address(0xCAFE1234);
        uint256 amount = 0.2 ether;
        vm.deal(address(wallet), 2 ether);

        (Decision decision, uint48 delaySeconds) = router.evaluate(address(wallet), recipient, amount, "");
        assertEq(uint256(decision), uint256(Decision.Delay));
        assertGe(delaySeconds, NEW_RECEIVER_DELAY);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(recipient, amount, "");

        bytes32 txId = wallet.schedule(recipient, amount, "");
        (, , , , uint48 unlockTime, ) = wallet.getScheduled(txId);
        vm.warp(unlockTime);
        wallet.executeScheduled(txId);

        assertEq(recipient.balance, amount);
    }

    function testFork_WethTransferFlow_OnBaseFork() public {
        if (!_enableFork()) return;

        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        address recipient = address(0xCAFE5678);
        uint256 amount = 0.8 ether;

        deal(WETH_BASE, address(wallet), 2 ether);
        bytes memory transferData = abi.encodeWithSignature("transfer(address,uint256)", recipient, amount);

        (Decision decision, uint48 delaySeconds) = router.evaluate(address(wallet), WETH_BASE, 0, transferData);
        assertEq(uint256(decision), uint256(Decision.Delay));
        assertGe(delaySeconds, DEFI_NEW_ERC20_RECIPIENT_DELAY);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(WETH_BASE, 0, transferData);

        bytes32 txId = wallet.schedule(WETH_BASE, 0, transferData);
        (, , , , uint48 unlockTime, ) = wallet.getScheduled(txId);
        vm.warp(unlockTime);
        wallet.executeScheduled(txId);

        assertEq(IERC20Like(WETH_BASE).balanceOf(recipient), amount);
    }

    function testFork_UsdcTransferFlow_OnBaseFork() public {
        if (!_enableFork()) return;

        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(BASE_PACK_DEFI);
        address recipient = address(0xCAFE9ABC);
        uint256 amount = 5e6; // 5 USDC (6 decimals)

        deal(USDC_BASE, address(wallet), 20e6);
        bytes memory transferData = abi.encodeWithSignature("transfer(address,uint256)", recipient, amount);

        (Decision decision, uint48 delaySeconds) = router.evaluate(address(wallet), USDC_BASE, 0, transferData);
        assertEq(uint256(decision), uint256(Decision.Delay));
        assertGe(delaySeconds, DEFI_NEW_ERC20_RECIPIENT_DELAY);

        vm.expectRevert(Firewall_RevertedByPolicy.selector);
        wallet.executeNow(USDC_BASE, 0, transferData);

        bytes32 txId = wallet.schedule(USDC_BASE, 0, transferData);
        (, , , , uint48 unlockTime, ) = wallet.getScheduled(txId);
        vm.warp(unlockTime);
        wallet.executeScheduled(txId);

        assertEq(IERC20Like(USDC_BASE).balanceOf(recipient), amount);
    }

    function _enableFork() internal returns (bool) {
        if (!vm.envOr("RUN_FORK_TESTS", false)) return false;
        string memory rpc = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return false;

        vm.createSelectFork(rpc);
        _deployV2WithRealBasePacks();
        return true;
    }
}
