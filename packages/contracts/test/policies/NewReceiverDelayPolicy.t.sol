// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {NewReceiverDelayPolicy} from "../../src/policies/NewReceiverDelayPolicy.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";

contract MockVaultWithRouterStrict {
    address public immutable router;

    constructor(address router_) {
        router = router_;
    }
}

contract NewReceiverDelayPolicyTest is Test {
    NewReceiverDelayPolicy policy;

    address router = address(0xAAAA);
    address attacker = address(0xBAD1);
    MockVaultWithRouterStrict vault;
    address receiver1 = address(0xCAFE);
    address receiver2 = address(0xBEEF);
    address token = address(0x1000);

    uint48 DELAY = 1 days;

    function setUp() public {
        policy = new NewReceiverDelayPolicy(DELAY);
        vault = new MockVaultWithRouterStrict(router);
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

    function test_Delay_OnERC20Transfer_NewReceiver() public view {
        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            receiver1,
            123
        );

        (Decision decision, uint48 delay) =
            policy.evaluate(address(this), token, 0, data);

        assertEq(uint256(decision), uint256(Decision.Delay));
        assertEq(uint256(delay), uint256(DELAY));
    }

    function test_Delay_OnERC20TransferFrom_NewReceiver() public view {
        bytes memory data = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            address(0xA1),
            receiver2,
            456
        );

        (Decision decision, uint48 delay) =
            policy.evaluate(address(this), token, 0, data);

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

    function test_Rejects_UnauthorizedOnExecutedCaller() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("ReceiverDelay_UnauthorizedHookCaller()"));
        policy.onExecuted(address(vault), receiver1, 0, "");
    }

    function test_ReceiverBecomesKnown_AfterAuthorizedExecutionHook() public {
        (Decision d1, uint48 delay1) = policy.evaluate(address(vault), receiver1, 0, "");
        assertEq(uint256(d1), uint256(Decision.Delay));
        assertEq(delay1, DELAY);

        vm.prank(router);
        policy.onExecuted(address(vault), receiver1, 0, "");

        (Decision d2, uint48 delay2) = policy.evaluate(address(vault), receiver1, 0, "");
        assertEq(uint256(d2), uint256(Decision.Allow));
        assertEq(delay2, 0);
    }
}
