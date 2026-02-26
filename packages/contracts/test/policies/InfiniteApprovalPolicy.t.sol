// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {InfiniteApprovalPolicy} from "../../src/policies/InfiniteApprovalPolicy.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

// ВАЖНО: Decision — глобальный enum
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";

contract InfiniteApprovalPolicyTest is Test {
    InfiniteApprovalPolicy policy;
    MockERC20 token;

    address spender = address(0xBEEF);

    function setUp() public {
        policy = new InfiniteApprovalPolicy(0, false);
        token = new MockERC20();
    }

    function test_RevertsOn_MaxUint_Approve() public view {
        bytes memory data = abi.encodeWithSignature(
            "approve(address,uint256)",
            spender,
            type(uint256).max
        );

        (Decision decision, uint48 delay) =
            policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "must revert on infinite approval");
        assertEq(uint256(delay), 0, "delay must be 0 for revert");
    }

    function test_RevertsOn_IncreaseAllowance_WhenAboveLimit() public {
        policy = new InfiniteApprovalPolicy(1000, false);
        bytes memory data = abi.encodeWithSignature(
            "increaseAllowance(address,uint256)",
            spender,
            1000
        );

        (Decision decision, uint48 delay) =
            policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "increaseAllowance above limit must revert");
        assertEq(uint256(delay), 0, "delay must be 0 for revert");
    }

    function test_AllowsOn_IncreaseAllowance_WhenBelowLimit() public {
        policy = new InfiniteApprovalPolicy(1000, false);
        bytes memory data = abi.encodeWithSignature(
            "increaseAllowance(address,uint256)",
            spender,
            999
        );

        (Decision decision, uint48 delay) =
            policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow), "increaseAllowance below limit must allow");
        assertEq(uint256(delay), 0, "delay must be 0 for allow");
    }

    function test_RevertsOn_SetApprovalForAll_True() public view {
        bytes memory data = abi.encodeWithSignature(
            "setApprovalForAll(address,bool)",
            spender,
            true
        );

        (Decision decision, uint48 delay) =
            policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "setApprovalForAll(true) must revert");
        assertEq(uint256(delay), 0, "delay must be 0 for revert");
    }

    function test_AllowsOn_SetApprovalForAll_False() public view {
        bytes memory data = abi.encodeWithSignature(
            "setApprovalForAll(address,bool)",
            spender,
            false
        );

        (Decision decision, uint48 delay) =
            policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow), "setApprovalForAll(false) must allow");
        assertEq(uint256(delay), 0, "delay must be 0 for allow");
    }

    function test_RevertsOn_Permit() public view {
        bytes memory data = abi.encodeWithSignature(
            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
            address(0xA1),
            spender,
            100,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );

        (Decision decision, uint48 delay) =
            policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "permit must revert");
        assertEq(uint256(delay), 0, "delay must be 0 for revert");
    }

    function test_AllowsOn_Permit_WhenAllowed() public {
        policy = new InfiniteApprovalPolicy(0, true);
        bytes memory data = abi.encodeWithSignature(
            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
            address(0xA1),
            spender,
            100,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );

        (Decision decision, uint48 delay) =
            policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow), "permit must allow when enabled");
        assertEq(uint256(delay), 0, "delay must be 0 for allow");
    }

    function test_AllowsOn_SmallApprove() public view {
        bytes memory data = abi.encodeWithSignature(
            "approve(address,uint256)",
            spender,
            123
        );

        (Decision decision, uint48 delay) =
            policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow), "small approve must be allowed");
        assertEq(uint256(delay), 0, "delay must be 0 for allow");
    }

    function test_Allows_NonApproveCall() public view {
        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(0xCAFE),
            1
        );

        (Decision decision, uint48 delay) =
            policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow), "non-approve must be allowed");
        assertEq(uint256(delay), 0, "delay must be 0 for allow");
    }

    function test_Reverts_EvenIf_TargetIsEOA_WhenApproveMax() public view {
        bytes memory data = abi.encodeWithSignature(
            "approve(address,uint256)",
            spender,
            type(uint256).max
        );

        (Decision decision, uint48 delay) =
            policy.evaluate(address(0x1234), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "approve(max) must revert even for EOA target");
        assertEq(uint256(delay), 0, "delay must be 0 for revert");
    }
}
