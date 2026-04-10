// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {InfiniteApprovalPolicy} from "../../src/policies/InfiniteApprovalPolicy.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";

contract InfiniteApprovalPolicyTest is Test {
    InfiniteApprovalPolicy policy;
    MockERC20 token;

    address spender = address(0xBEEF);

    function setUp() public {
        policy = new InfiniteApprovalPolicy(type(uint256).max, false);
        token = new MockERC20();
    }

    function test_Allows_ApproveZero() public view {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", spender, 0);

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow), "approve(0) must be allowed");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Reverts_ApproveNonZero() public view {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", spender, 1);

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "approve(non-zero) must revert");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Reverts_ApproveMax() public view {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", spender, type(uint256).max);

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "approve(max) must revert");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Allows_IncreaseAllowanceZero() public view {
        bytes memory data = abi.encodeWithSignature("increaseAllowance(address,uint256)", spender, 0);

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow), "increaseAllowance(0) must allow");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Reverts_IncreaseAllowanceNonZero() public view {
        bytes memory data = abi.encodeWithSignature("increaseAllowance(address,uint256)", spender, 1);

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "increaseAllowance(non-zero) must revert");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Reverts_SetApprovalForAll_True() public view {
        bytes memory data = abi.encodeWithSignature("setApprovalForAll(address,bool)", spender, true);

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "setApprovalForAll(true) must revert");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Allows_SetApprovalForAll_False() public view {
        bytes memory data = abi.encodeWithSignature("setApprovalForAll(address,bool)", spender, false);

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow), "setApprovalForAll(false) must allow");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Reverts_PermitEip2612() public view {
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

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "EIP-2612 permit must revert");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Reverts_PermitDaiStyle() public view {
        bytes memory data = abi.encodeWithSignature(
            "permit(address,address,uint256,uint256,bool,uint8,bytes32,bytes32)",
            address(0xA1),
            spender,
            1,
            0,
            true,
            0,
            bytes32(0),
            bytes32(0)
        );

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "DAI-style permit must revert");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Reverts_Permit2Single() public view {
        bytes memory data =
            abi.encodeWithSelector(bytes4(0x2b67b570), address(0xA1), bytes32(uint256(1)), bytes("sig"));

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "Permit2 single permit must revert");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Reverts_Permit2Batch() public view {
        bytes memory data =
            abi.encodeWithSelector(bytes4(0x2a2d80d1), address(0xA1), bytes32(uint256(1)), bytes("sig"));

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "Permit2 batch permit must revert");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Reverts_Permit2Approve() public view {
        bytes memory data = abi.encodeWithSelector(
            bytes4(0x87517c45),
            address(token),
            spender,
            uint160(1),
            uint48(30 days)
        );

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "Permit2 approve must revert");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Reverts_PermitTransferFrom() public view {
        bytes memory data =
            abi.encodeWithSelector(bytes4(0x6949bce4), bytes32(uint256(1)), bytes32(uint256(2)), address(0xA1), bytes("sig"));

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "permitTransferFrom must revert");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Reverts_PermitWitnessTransferFrom() public view {
        bytes memory data =
            abi.encodeWithSelector(bytes4(0x2eda8726), bytes32(uint256(1)), bytes32(uint256(2)), address(0xA1), bytes("sig"));

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Revert), "permitWitnessTransferFrom must revert");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_Allows_Permit_WhenAllowed() public {
        policy = new InfiniteApprovalPolicy(type(uint256).max, true);
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

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow), "permit must allow when enabled");
        assertEq(uint256(delay), 0, "delay must be 0");
    }

    function test_ApprovalLimit_IsLegacyNonFunctional_StrictModeUnaffected() public {
        InfiniteApprovalPolicy strictLow = new InfiniteApprovalPolicy(0, false);
        InfiniteApprovalPolicy strictHigh = new InfiniteApprovalPolicy(type(uint256).max, false);
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", spender, 1);

        (Decision decisionLow,) = strictLow.evaluate(address(token), address(this), 0, data);
        (Decision decisionHigh,) = strictHigh.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decisionLow), uint256(Decision.Revert));
        assertEq(uint256(decisionHigh), uint256(Decision.Revert));
        assertEq(strictLow.APPROVAL_LIMIT_FUNCTIONAL(), false);
        assertEq(strictHigh.APPROVAL_LIMIT_FUNCTIONAL(), false);
    }

    function test_Allows_NonApprovalCall() public view {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", address(0xCAFE), 1);

        (Decision decision, uint48 delay) = policy.evaluate(address(token), address(this), 0, data);

        assertEq(uint256(decision), uint256(Decision.Allow), "non-approval call must allow");
        assertEq(uint256(delay), 0, "delay must be 0");
    }
}
