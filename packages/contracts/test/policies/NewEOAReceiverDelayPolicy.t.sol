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
}
