// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {ApprovalToNewSpenderDelayPolicy} from "../../src/policies/ApprovalToNewSpenderDelayPolicy.sol";
import {MockReceiver} from "../../src/mocks/MockReceiver.sol";

contract MockVaultWithRouterApproval {
    address public immutable router;

    constructor(address router_) {
        router = router_;
    }
}

contract ApprovalToNewSpenderDelayPolicyTest is Test {
    uint48 internal constant DELAY = 30 minutes;

    ApprovalToNewSpenderDelayPolicy internal policy;
    MockVaultWithRouterApproval internal vault;

    address internal constant ROUTER = address(0xAAAA);
    address internal constant ATTACKER = address(0xBAD1);
    address internal constant TOKEN = address(0x1000);
    address internal constant TOKEN_2 = address(0x2000);
    address internal constant EOA_SPENDER = address(0xBEEF);

    function setUp() public {
        policy = new ApprovalToNewSpenderDelayPolicy(DELAY);
        vault = new MockVaultWithRouterApproval(ROUTER);
    }

    function test_ApproveZero_Allow() public view {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", EOA_SPENDER, 0);
        (Decision d, uint48 delayOut) = policy.evaluate(address(vault), TOKEN, 0, data);

        assertEq(uint256(d), uint256(Decision.Allow));
        assertEq(delayOut, 0);
    }

    function test_ApproveNonZero_EoaSpender_Revert() public view {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", EOA_SPENDER, 1);
        (Decision d, uint48 delayOut) = policy.evaluate(address(vault), TOKEN, 0, data);

        assertEq(uint256(d), uint256(Decision.Revert));
        assertEq(delayOut, 0);
    }

    function test_ApproveNonZero_NewContractSpender_DelayThenAllowAfterExecution() public {
        MockReceiver contractSpender = new MockReceiver();
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(contractSpender), 1);

        (Decision d1, uint48 delay1) = policy.evaluate(address(vault), TOKEN, 0, data);
        assertEq(uint256(d1), uint256(Decision.Delay));
        assertEq(delay1, DELAY);

        vm.prank(ROUTER);
        policy.onExecuted(address(vault), TOKEN, 0, data);

        (Decision d2, uint48 delay2) = policy.evaluate(address(vault), TOKEN, 0, data);
        assertEq(uint256(d2), uint256(Decision.Allow));
        assertEq(delay2, 0);
    }

    function test_IncreaseAllowance_MirrorsApproveRules() public {
        MockReceiver contractSpender = new MockReceiver();

        bytes memory zeroData = abi.encodeWithSignature("increaseAllowance(address,uint256)", EOA_SPENDER, 0);
        (Decision dz, uint48 delayZ) = policy.evaluate(address(vault), TOKEN, 0, zeroData);
        assertEq(uint256(dz), uint256(Decision.Allow));
        assertEq(delayZ, 0);

        bytes memory eoaData = abi.encodeWithSignature("increaseAllowance(address,uint256)", EOA_SPENDER, 1);
        (Decision de, uint48 delayE) = policy.evaluate(address(vault), TOKEN, 0, eoaData);
        assertEq(uint256(de), uint256(Decision.Revert));
        assertEq(delayE, 0);

        bytes memory contractData =
            abi.encodeWithSignature("increaseAllowance(address,uint256)", address(contractSpender), 1);
        (Decision dc1, uint48 delayC1) = policy.evaluate(address(vault), TOKEN, 0, contractData);
        assertEq(uint256(dc1), uint256(Decision.Delay));
        assertEq(delayC1, DELAY);

        vm.prank(ROUTER);
        policy.onExecuted(address(vault), TOKEN, 0, contractData);
        (Decision dc2, uint48 delayC2) = policy.evaluate(address(vault), TOKEN, 0, contractData);
        assertEq(uint256(dc2), uint256(Decision.Allow));
        assertEq(delayC2, 0);
    }

    function test_PermitEip2612_MirrorsSpenderRules() public {
        MockReceiver contractSpender = new MockReceiver();

        bytes memory zeroPermit = _permitEip2612Data(address(vault), EOA_SPENDER, 0);
        (Decision d0, uint48 delay0) = policy.evaluate(address(vault), TOKEN, 0, zeroPermit);
        assertEq(uint256(d0), uint256(Decision.Allow));
        assertEq(delay0, 0);

        bytes memory eoaPermit = _permitEip2612Data(address(vault), EOA_SPENDER, 1);
        (Decision d1, uint48 delay1) = policy.evaluate(address(vault), TOKEN, 0, eoaPermit);
        assertEq(uint256(d1), uint256(Decision.Revert));
        assertEq(delay1, 0);

        bytes memory contractPermit = _permitEip2612Data(address(vault), address(contractSpender), 1);
        (Decision d2, uint48 delay2) = policy.evaluate(address(vault), TOKEN, 0, contractPermit);
        assertEq(uint256(d2), uint256(Decision.Delay));
        assertEq(delay2, DELAY);

        vm.prank(ROUTER);
        policy.onExecuted(address(vault), TOKEN, 0, contractPermit);
        (Decision d3, uint48 delay3) = policy.evaluate(address(vault), TOKEN, 0, contractPermit);
        assertEq(uint256(d3), uint256(Decision.Allow));
        assertEq(delay3, 0);
    }

    function test_PermitDai_MirrorsSpenderRules() public {
        MockReceiver contractSpender = new MockReceiver();

        bytes memory revokePermit = _permitDaiData(address(vault), EOA_SPENDER, false);
        (Decision d0, uint48 delay0) = policy.evaluate(address(vault), TOKEN, 0, revokePermit);
        assertEq(uint256(d0), uint256(Decision.Allow));
        assertEq(delay0, 0);

        bytes memory eoaPermit = _permitDaiData(address(vault), EOA_SPENDER, true);
        (Decision d1, uint48 delay1) = policy.evaluate(address(vault), TOKEN, 0, eoaPermit);
        assertEq(uint256(d1), uint256(Decision.Revert));
        assertEq(delay1, 0);

        bytes memory contractPermit = _permitDaiData(address(vault), address(contractSpender), true);
        (Decision d2, uint48 delay2) = policy.evaluate(address(vault), TOKEN, 0, contractPermit);
        assertEq(uint256(d2), uint256(Decision.Delay));
        assertEq(delay2, DELAY);

        vm.prank(ROUTER);
        policy.onExecuted(address(vault), TOKEN, 0, contractPermit);
        (Decision d3, uint48 delay3) = policy.evaluate(address(vault), TOKEN, 0, contractPermit);
        assertEq(uint256(d3), uint256(Decision.Allow));
        assertEq(delay3, 0);
    }

    function test_Permit2Approve_MirrorsSpenderRules() public {
        MockReceiver contractSpender = new MockReceiver();

        bytes memory zeroApproval = _permit2ApproveData(TOKEN, EOA_SPENDER, 0);
        (Decision d0, uint48 delay0) = policy.evaluate(address(vault), TOKEN, 0, zeroApproval);
        assertEq(uint256(d0), uint256(Decision.Allow));
        assertEq(delay0, 0);

        bytes memory eoaApproval = _permit2ApproveData(TOKEN, EOA_SPENDER, 1);
        (Decision d1, uint48 delay1) = policy.evaluate(address(vault), TOKEN, 0, eoaApproval);
        assertEq(uint256(d1), uint256(Decision.Revert));
        assertEq(delay1, 0);

        bytes memory contractApproval = _permit2ApproveData(TOKEN, address(contractSpender), 1);
        (Decision d2, uint48 delay2) = policy.evaluate(address(vault), TOKEN, 0, contractApproval);
        assertEq(uint256(d2), uint256(Decision.Delay));
        assertEq(delay2, DELAY);

        vm.prank(ROUTER);
        policy.onExecuted(address(vault), TOKEN, 0, contractApproval);
        (Decision d3, uint48 delay3) = policy.evaluate(address(vault), TOKEN, 0, contractApproval);
        assertEq(uint256(d3), uint256(Decision.Allow));
        assertEq(delay3, 0);
    }

    function test_Rejects_UnauthorizedOnExecutedCaller() public {
        MockReceiver contractSpender = new MockReceiver();
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(contractSpender), 1);

        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSignature("ApprovalToNewSpenderDelay_UnauthorizedHookCaller()"));
        policy.onExecuted(address(vault), TOKEN, 0, data);

        assertFalse(policy.knownSpenders(address(vault), TOKEN, address(contractSpender)));
    }

    function test_PrimingOnTokenA_DoesNotBypassTokenB() public {
        MockReceiver contractSpender = new MockReceiver();
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(contractSpender), 1);

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

    function test_Permit2PrimesPerUnderlyingToken_NotGlobalOnPermit2Target() public {
        MockReceiver contractSpender = new MockReceiver();
        address permit2Target = TOKEN;

        bytes memory tokenAApproval = _permit2ApproveData(TOKEN, address(contractSpender), 1);
        bytes memory tokenBApproval = _permit2ApproveData(TOKEN_2, address(contractSpender), 1);

        (Decision d1, uint48 delay1) = policy.evaluate(address(vault), permit2Target, 0, tokenAApproval);
        assertEq(uint256(d1), uint256(Decision.Delay));
        assertEq(delay1, DELAY);

        vm.prank(ROUTER);
        policy.onExecuted(address(vault), permit2Target, 0, tokenAApproval);

        (Decision d2, uint48 delay2) = policy.evaluate(address(vault), permit2Target, 0, tokenAApproval);
        assertEq(uint256(d2), uint256(Decision.Allow));
        assertEq(delay2, 0);

        (Decision d3, uint48 delay3) = policy.evaluate(address(vault), permit2Target, 0, tokenBApproval);
        assertEq(uint256(d3), uint256(Decision.Delay));
        assertEq(delay3, DELAY);
    }

    function test_OnExecuted_UnrelatedCalldata_DoesNotMarkKnownSpender() public {
        MockReceiver contractSpender = new MockReceiver();
        bytes memory unrelated = abi.encodeWithSignature("deposit(uint256)", 1);

        vm.prank(ROUTER);
        policy.onExecuted(address(vault), TOKEN, 0, unrelated);

        assertFalse(policy.knownSpenders(address(vault), TOKEN, address(contractSpender)));
    }

    function test_OnExecuted_MalformedApproveCalldata_DoesNotMarkKnownSpender() public {
        MockReceiver contractSpender = new MockReceiver();
        bytes memory malformed = abi.encodePacked(bytes4(0x095ea7b3), bytes32(uint256(uint160(address(contractSpender)))));

        vm.prank(ROUTER);
        policy.onExecuted(address(vault), TOKEN, 0, malformed);

        assertFalse(policy.knownSpenders(address(vault), TOKEN, address(contractSpender)));
    }

    function _permitEip2612Data(address owner, address spender, uint256 value)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
            owner,
            spender,
            value,
            123,
            uint8(27),
            bytes32(0),
            bytes32(0)
        );
    }

    function _permitDaiData(address holder, address spender, bool allowed)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "permit(address,address,uint256,uint256,bool,uint8,bytes32,bytes32)",
            holder,
            spender,
            0,
            0,
            allowed,
            uint8(27),
            bytes32(0),
            bytes32(0)
        );
    }

    function _permit2ApproveData(address token, address spender, uint160 amount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(bytes4(0x87517c45), token, spender, amount, uint48(30 days));
    }
}
