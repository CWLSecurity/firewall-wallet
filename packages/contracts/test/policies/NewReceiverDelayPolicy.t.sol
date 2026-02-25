// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {NewReceiverDelayPolicy} from "../../src/policies/NewReceiverDelayPolicy.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";

contract NewReceiverDelayPolicyTest is Test {
    NewReceiverDelayPolicy policy;

    address receiver1 = address(0xCAFE);
    address receiver2 = address(0xBEEF);

    uint48 DELAY = 1 days;

    function setUp() public {
        policy = new NewReceiverDelayPolicy(DELAY);
    }

    function test_Delay_OnReceiver1() public view {
        (Decision decision, uint48 delay) =
            policy.evaluate(receiver1, address(this), 0, "");

        assertEq(uint256(decision), uint256(Decision.Delay));
        assertEq(uint256(delay), uint256(DELAY));
    }

    function test_Delay_IsIdempotent_SameReceiverCalledTwice() public view {
        (Decision d1, uint48 t1) =
            policy.evaluate(receiver1, address(this), 0, "");

        (Decision d2, uint48 t2) =
            policy.evaluate(receiver1, address(this), 0, "");

        assertEq(uint256(d1), uint256(Decision.Delay));
        assertEq(uint256(d2), uint256(Decision.Delay));
        assertEq(uint256(t1), uint256(DELAY));
        assertEq(uint256(t2), uint256(DELAY));
    }

    function test_Delay_OnAnotherReceiver() public view {
        (Decision decision, uint48 delay) =
            policy.evaluate(receiver2, address(this), 0, "");

        assertEq(uint256(decision), uint256(Decision.Delay));
        assertEq(uint256(delay), uint256(DELAY));
    }

    function test_NotAllow_OnZeroAddress() public view {
        (Decision decision, uint48 delay) =
            policy.evaluate(address(0), address(this), 0, "");

        // минимум: не Allow. (Если у тебя Delay — ок, как сейчас и ожидаем)
        assertTrue(uint256(decision) != uint256(Decision.Allow), "zero address must not be allowed");
        // delay при этом должен быть либо 0 (если Revert), либо DELAY (если Delay)
        if (uint256(decision) == uint256(Decision.Delay)) {
            assertEq(uint256(delay), uint256(DELAY));
        }
    }
}
