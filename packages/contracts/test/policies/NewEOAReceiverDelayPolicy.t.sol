// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {NewEOAReceiverDelayPolicy} from "../../src/policies/NewEOAReceiverDelayPolicy.sol";
import {MockReceiver} from "../../src/mocks/MockReceiver.sol";

contract MockVaultWithRouter {
    address public immutable router;

    constructor(address router_) {
        router = router_;
    }
}

contract NewEOAReceiverDelayPolicyTest is Test {
    NewEOAReceiverDelayPolicy policy;

    address router = address(0xAAAA);
    address attacker = address(0xBAD1);
    MockVaultWithRouter vault;
    address eoaReceiver = address(0xCAFE);
    address token = address(0x1000);
    uint48 DELAY = 1 days;

    function setUp() public {
        policy = new NewEOAReceiverDelayPolicy(DELAY);
        vault = new MockVaultWithRouter(router);
    }

    function test_Delay_OnNewEOAReceiver() public view {
        (Decision decision, uint48 delay) = policy.evaluate(address(vault), eoaReceiver, 0, "");
        assertEq(uint256(decision), uint256(Decision.Delay));
        assertEq(delay, DELAY);
    }

    function test_Allow_OnNewContractReceiver() public {
        MockReceiver receiver = new MockReceiver();
        (Decision decision, uint48 delay) = policy.evaluate(address(vault), address(receiver), 0, "");
        assertEq(uint256(decision), uint256(Decision.Allow));
        assertEq(delay, 0);
    }

    function test_Delay_OnERC20Transfer_ToEOA() public view {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", eoaReceiver, 123);
        (Decision decision, uint48 delay) = policy.evaluate(address(vault), token, 0, data);
        assertEq(uint256(decision), uint256(Decision.Delay));
        assertEq(delay, DELAY);
    }

    function test_Allow_OnERC20Transfer_ToContract() public {
        MockReceiver receiver = new MockReceiver();
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", address(receiver), 123);
        (Decision decision, uint48 delay) = policy.evaluate(address(vault), token, 0, data);
        assertEq(uint256(decision), uint256(Decision.Allow));
        assertEq(delay, 0);
    }

    function test_Delay_OnUnknownSelector_ToNewContractTarget() public {
        MockReceiver protocol = new MockReceiver();
        bytes memory data = abi.encodeWithSignature("swap(uint256)", 1);
        (Decision decision, uint48 delay) = policy.evaluate(address(vault), address(protocol), 0, data);
        assertEq(uint256(decision), uint256(Decision.Delay));
        assertEq(delay, DELAY);
    }

    function test_UnknownSelector_ContractTargetBecomesKnown_AfterExecutionHook() public {
        MockReceiver protocol = new MockReceiver();
        bytes memory data = abi.encodeWithSignature("swap(uint256)", 1);

        (Decision d1, uint48 delay1) = policy.evaluate(address(vault), address(protocol), 0, data);
        assertEq(uint256(d1), uint256(Decision.Delay));
        assertEq(delay1, DELAY);

        vm.prank(router);
        policy.onExecuted(address(vault), address(protocol), 0, data);

        (Decision d2, uint48 delay2) = policy.evaluate(address(vault), address(protocol), 0, data);
        assertEq(uint256(d2), uint256(Decision.Allow));
        assertEq(delay2, 0);
    }

    function test_UnknownSelector_ContractTargetScope_IsPerSelector() public {
        MockReceiver protocol = new MockReceiver();
        bytes memory swapData = abi.encodeWithSignature("swap(uint256)", 1);
        bytes memory depositData = abi.encodeWithSignature("deposit(uint256)", 1);

        vm.prank(router);
        policy.onExecuted(address(vault), address(protocol), 0, swapData);

        (Decision swapDecision, uint48 swapDelay) = policy.evaluate(address(vault), address(protocol), 0, swapData);
        assertEq(uint256(swapDecision), uint256(Decision.Allow));
        assertEq(swapDelay, 0);

        (Decision depositDecision, uint48 depositDelay) =
            policy.evaluate(address(vault), address(protocol), 0, depositData);
        assertEq(uint256(depositDecision), uint256(Decision.Delay));
        assertEq(depositDelay, DELAY);
    }

    function test_ApprovalLikeSelector_ToContract_RemainsAllow() public {
        MockReceiver contractTarget = new MockReceiver();
        bytes memory approveData = abi.encodeWithSignature("approve(address,uint256)", address(0xCAFE), 10);

        (Decision decision, uint48 delay) = policy.evaluate(address(vault), address(contractTarget), 0, approveData);
        assertEq(uint256(decision), uint256(Decision.Allow));
        assertEq(delay, 0);
    }

    function test_ApprovalLikeSelector_Permit2Approve_ToContract_RemainsAllow() public {
        MockReceiver contractTarget = new MockReceiver();
        bytes memory permit2ApproveData = abi.encodeWithSelector(
            bytes4(0x87517c45),
            address(0xA1),
            address(0xCAFE),
            uint160(1),
            uint48(30 days)
        );

        (Decision decision, uint48 delay) =
            policy.evaluate(address(vault), address(contractTarget), 0, permit2ApproveData);
        assertEq(uint256(decision), uint256(Decision.Allow));
        assertEq(delay, 0);
    }

    function test_Delay_OnERC721SafeTransfer_ToEOA() public view {
        bytes memory data = abi.encodeWithSelector(
            bytes4(0x42842e0e),
            address(0xA1),
            eoaReceiver,
            uint256(1)
        );
        (Decision decision, uint48 delay) = policy.evaluate(address(vault), token, 0, data);
        assertEq(uint256(decision), uint256(Decision.Delay));
        assertEq(delay, DELAY);
    }

    function test_Delay_OnUnknownSelector_ToEOA_WithCalldata() public view {
        bytes memory data = abi.encodeWithSignature("any(bytes32)", bytes32(uint256(1)));
        (Decision decision, uint48 delay) = policy.evaluate(address(vault), eoaReceiver, 1, data);
        assertEq(uint256(decision), uint256(Decision.Delay));
        assertEq(delay, DELAY);
    }

    function test_Rejects_UnauthorizedOnExecutedCaller() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("ReceiverDelay_UnauthorizedHookCaller()"));
        policy.onExecuted(address(vault), eoaReceiver, 0, "");
    }

    function test_ReceiverBecomesKnown_AfterAuthorizedExecutionHook() public {
        (Decision d1, uint48 delay1) = policy.evaluate(address(vault), eoaReceiver, 0, "");
        assertEq(uint256(d1), uint256(Decision.Delay));
        assertEq(delay1, DELAY);

        vm.prank(router);
        policy.onExecuted(address(vault), eoaReceiver, 0, "");

        (Decision d2, uint48 delay2) = policy.evaluate(address(vault), eoaReceiver, 0, "");
        assertEq(uint256(d2), uint256(Decision.Allow));
        assertEq(delay2, 0);
    }

    function test_UnknownSelector_ContractTargetCodehashChange_ReDelays() public {
        MockReceiver protocol = new MockReceiver();
        bytes memory data = abi.encodeWithSignature("swap(uint256)", 1);

        vm.prank(router);
        policy.onExecuted(address(vault), address(protocol), 0, data);

        (Decision beforeChange, uint48 beforeDelay) = policy.evaluate(address(vault), address(protocol), 0, data);
        assertEq(uint256(beforeChange), uint256(Decision.Allow));
        assertEq(beforeDelay, 0);

        vm.etch(address(protocol), hex"60006000f3");

        (Decision afterChange, uint48 afterDelay) = policy.evaluate(address(vault), address(protocol), 0, data);
        assertEq(uint256(afterChange), uint256(Decision.Delay));
        assertEq(afterDelay, DELAY);
    }
}
