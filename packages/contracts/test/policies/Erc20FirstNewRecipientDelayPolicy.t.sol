// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {Erc20FirstNewRecipientDelayPolicy} from "../../src/policies/Erc20FirstNewRecipientDelayPolicy.sol";

contract MockVaultWithRouterErc20Recipient {
    address public immutable router;

    constructor(address router_) {
        router = router_;
    }
}

contract Erc20FirstNewRecipientDelayPolicyTest is Test {
    uint48 internal constant DELAY = 30 minutes;

    Erc20FirstNewRecipientDelayPolicy internal policy;
    MockVaultWithRouterErc20Recipient internal vault;

    address internal constant ROUTER = address(0xAAAA);
    address internal constant ATTACKER = address(0xBAD1);
    address internal constant TOKEN = address(0x1000);
    address internal constant TOKEN_2 = address(0x2000);
    address internal constant RECIPIENT = address(0xBEEF);

    function setUp() public {
        policy = new Erc20FirstNewRecipientDelayPolicy(DELAY);
        vault = new MockVaultWithRouterErc20Recipient(ROUTER);
    }

    function test_FirstTransferToNewRecipient_Delay() public view {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", RECIPIENT, 1);
        (Decision d, uint48 delayOut) = policy.evaluate(address(vault), TOKEN, 0, data);

        assertEq(uint256(d), uint256(Decision.Delay));
        assertEq(delayOut, DELAY);
    }

    function test_FirstTransferFromToNewRecipient_Delay() public view {
        bytes memory data = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)", address(0xA11CE), RECIPIENT, 1
        );
        (Decision d, uint48 delayOut) = policy.evaluate(address(vault), TOKEN, 0, data);

        assertEq(uint256(d), uint256(Decision.Delay));
        assertEq(delayOut, DELAY);
    }

    function test_RepeatRecipientAfterSuccessfulExecution_Allow() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", RECIPIENT, 1);

        (Decision d1, uint48 delay1) = policy.evaluate(address(vault), TOKEN, 0, data);
        assertEq(uint256(d1), uint256(Decision.Delay));
        assertEq(delay1, DELAY);

        vm.prank(ROUTER);
        policy.onExecuted(address(vault), TOKEN, 0, data);

        (Decision d2, uint48 delay2) = policy.evaluate(address(vault), TOKEN, 0, data);
        assertEq(uint256(d2), uint256(Decision.Allow));
        assertEq(delay2, 0);
    }

    function test_NonTransferCalldata_Allow() public view {
        bytes memory data = abi.encodeWithSignature("deposit(uint256)", 1);
        (Decision d, uint48 delayOut) = policy.evaluate(address(vault), TOKEN, 0, data);

        assertEq(uint256(d), uint256(Decision.Allow));
        assertEq(delayOut, 0);
    }

    function test_Rejects_UnauthorizedOnExecutedCaller() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", RECIPIENT, 1);

        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSignature("Erc20FirstNewRecipientDelay_UnauthorizedHookCaller()"));
        policy.onExecuted(address(vault), TOKEN, 0, data);

        assertFalse(policy.knownRecipients(address(vault), TOKEN, RECIPIENT));
    }

    function test_PrimingOnTokenA_DoesNotBypassTokenB() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", RECIPIENT, 1);

        (Decision dA1, uint48 delayA1) = policy.evaluate(address(vault), TOKEN, 0, data);
        assertEq(uint256(dA1), uint256(Decision.Delay));
        assertEq(delayA1, DELAY);

        vm.prank(ROUTER);
        policy.onExecuted(address(vault), TOKEN, 0, data);

        (Decision dA2, uint48 delayA2) = policy.evaluate(address(vault), TOKEN, 0, data);
        assertEq(uint256(dA2), uint256(Decision.Allow));
        assertEq(delayA2, 0);

        (Decision dB, uint48 delayB) = policy.evaluate(address(vault), TOKEN_2, 0, data);
        assertEq(uint256(dB), uint256(Decision.Delay));
        assertEq(delayB, DELAY);
    }

    function test_OnExecuted_UnrelatedCalldata_DoesNotMarkKnownRecipient() public {
        bytes memory unrelated = abi.encodeWithSignature("deposit(uint256)", 1);

        vm.prank(ROUTER);
        policy.onExecuted(address(vault), TOKEN, 0, unrelated);

        assertFalse(policy.knownRecipients(address(vault), TOKEN, RECIPIENT));
    }

    function test_OnExecuted_MalformedTransferCalldata_DoesNotMarkKnownRecipient() public {
        bytes memory malformed = abi.encodePacked(bytes4(0xa9059cbb), bytes32(uint256(uint160(RECIPIENT))));

        vm.prank(ROUTER);
        policy.onExecuted(address(vault), TOKEN, 0, malformed);

        assertFalse(policy.knownRecipients(address(vault), TOKEN, RECIPIENT));
    }
}
