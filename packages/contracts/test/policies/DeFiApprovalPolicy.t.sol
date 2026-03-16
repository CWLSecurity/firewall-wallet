// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {DeFiApprovalPolicy} from "../../src/policies/DeFiApprovalPolicy.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";

contract DeFiApprovalPolicyTest is Test {
    DeFiApprovalPolicy policy;
    MockERC20 token;

    address spender = address(0xBEEF);

    function setUp() public {
        policy = new DeFiApprovalPolicy();
        token = new MockERC20();
    }

    function test_Allows_MaxUint_Approve() public view {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", spender, type(uint256).max);
        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow));
        assertEq(delay, 0);
    }

    function test_Allows_LimitedApprove() public view {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", spender, 123);
        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow));
        assertEq(delay, 0);
    }

    function test_Allows_IncreaseAllowance_NonZero() public view {
        bytes memory data = abi.encodeWithSignature("increaseAllowance(address,uint256)", spender, 1);
        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow));
        assertEq(delay, 0);
    }

    function test_Allows_Permit() public view {
        bytes memory data = abi.encodeWithSignature(
            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
            address(0xA1),
            spender,
            type(uint256).max,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow));
        assertEq(delay, 0);
    }

    function test_Reverts_SetApprovalForAll_True() public view {
        bytes memory data = abi.encodeWithSignature("setApprovalForAll(address,bool)", spender, true);
        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert));
        assertEq(delay, 0);
    }

    function test_Allows_SetApprovalForAll_False() public view {
        bytes memory data = abi.encodeWithSignature("setApprovalForAll(address,bool)", spender, false);
        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow));
        assertEq(delay, 0);
    }
}
