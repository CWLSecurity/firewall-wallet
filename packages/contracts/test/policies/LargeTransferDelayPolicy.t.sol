// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {LargeTransferDelayPolicy} from "../../src/policies/LargeTransferDelayPolicy.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";

contract MockERC20WithCustomDecimals {
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }
}

contract LargeTransferDelayPolicyTest is Test {
    LargeTransferDelayPolicy policy;
    MockERC20 token;
    MockERC20WithCustomDecimals token6Decimals;

    address receiver = address(0xCAFE);

    uint256 ETH_THRESHOLD = 1 ether;
    uint256 ERC20_THRESHOLD = 2 ether;
    uint48 DELAY = 1 days;

    function setUp() public {
        policy = new LargeTransferDelayPolicy(ETH_THRESHOLD, ERC20_THRESHOLD, DELAY);
        token = new MockERC20();
        token6Decimals = new MockERC20WithCustomDecimals(6);
    }

    function test_Delay_OnEthTransfer_ExactlyThreshold() public view {
        bytes memory emptyData = "";

        (Decision decision, uint48 delay) = policy.evaluate(address(this), receiver, ETH_THRESHOLD, emptyData);

        assertEq(uint256(decision), uint256(Decision.Delay), "ETH transfer at threshold must be delayed");
        assertEq(uint256(delay), uint256(DELAY), "delay must equal configured delay");
    }

    function test_Allow_OnEthTransfer_BelowThreshold() public view {
        bytes memory emptyData = "";

        (Decision decision, uint48 delay) = policy.evaluate(address(this), receiver, ETH_THRESHOLD - 1, emptyData);

        assertEq(uint256(decision), uint256(Decision.Allow), "small ETH transfer must be allowed");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Delay_OnERC20Transfer_ExactlyThreshold() public view {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", receiver, ERC20_THRESHOLD);

        (Decision decision, uint48 delay) = policy.evaluate(address(this), address(token), 0, data);

        assertEq(uint256(decision), uint256(Decision.Delay), "ERC20 transfer must be delayed");
        assertEq(uint256(delay), uint256(DELAY), "delay must equal configured delay");
    }

    function test_Allow_OnNonTransferCall() public view {
        bytes memory data = abi.encodeWithSignature(
            "approve(address,uint256)",
            receiver,
            100
        );

        (Decision decision, uint48 delay) = policy.evaluate(address(this), address(token), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow), "non-related calls must be allowed");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Delay_OnERC20TransferFrom_ExactlyThreshold() public view {
        bytes memory data = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            address(0xA1),
            receiver,
            ERC20_THRESHOLD
        );

        (Decision decision, uint48 delay) = policy.evaluate(address(this), address(token), 0, data);

        assertEq(uint256(decision), uint256(Decision.Delay), "ERC20 transferFrom must be delayed");
        assertEq(uint256(delay), uint256(DELAY), "delay must equal configured delay");
    }

    function test_Delay_OnErc20Transfer_6Decimals_WhenNormalizedAmountHitsThreshold() public view {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", receiver, 2_000_000);

        (Decision decision, uint48 delay) = policy.evaluate(address(this), address(token6Decimals), 0, data);

        assertEq(uint256(decision), uint256(Decision.Delay), "normalized 6-dec amount at threshold must be delayed");
        assertEq(uint256(delay), uint256(DELAY), "delay must equal configured delay");
    }

    function test_Allow_OnErc20Transfer_6Decimals_WhenNormalizedAmountBelowThreshold() public view {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", receiver, 1_999_999);

        (Decision decision, uint48 delay) = policy.evaluate(address(this), address(token6Decimals), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow), "normalized 6-dec amount below threshold must allow");
        assertEq(uint256(delay), 0, "delay must be 0");
    }
}
