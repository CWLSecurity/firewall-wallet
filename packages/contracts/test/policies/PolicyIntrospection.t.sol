// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {
    IPolicyIntrospection,
    PolicyConfigEntry,
    PolicyConfigValueType
} from "../../src/interfaces/IPolicyIntrospection.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {InfiniteApprovalPolicy} from "../../src/policies/InfiniteApprovalPolicy.sol";
import {DeFiApprovalPolicy} from "../../src/policies/DeFiApprovalPolicy.sol";
import {ApprovalToNewSpenderDelayPolicy} from "../../src/policies/ApprovalToNewSpenderDelayPolicy.sol";
import {Erc20FirstNewRecipientDelayPolicy} from "../../src/policies/Erc20FirstNewRecipientDelayPolicy.sol";
import {LargeTransferDelayPolicy} from "../../src/policies/LargeTransferDelayPolicy.sol";
import {NewReceiverDelayPolicy} from "../../src/policies/NewReceiverDelayPolicy.sol";
import {NewEOAReceiverDelayPolicy} from "../../src/policies/NewEOAReceiverDelayPolicy.sol";
import {UnknownContractBlockPolicy} from "../../src/policies/UnknownContractBlockPolicy.sol";

contract PolicyIntrospectionTest is Test {
    InfiniteApprovalPolicy internal infiniteApproval;
    DeFiApprovalPolicy internal defiApproval;
    ApprovalToNewSpenderDelayPolicy internal approvalToNewSpenderDelay;
    Erc20FirstNewRecipientDelayPolicy internal erc20FirstNewRecipientDelay;
    LargeTransferDelayPolicy internal largeTransfer;
    NewReceiverDelayPolicy internal newReceiver;
    NewEOAReceiverDelayPolicy internal newEoaReceiver;
    UnknownContractBlockPolicy internal unknownContract;

    function setUp() public {
        infiniteApproval = new InfiniteApprovalPolicy(type(uint256).max, false);
        defiApproval = new DeFiApprovalPolicy();
        approvalToNewSpenderDelay = new ApprovalToNewSpenderDelayPolicy(30 minutes);
        erc20FirstNewRecipientDelay = new Erc20FirstNewRecipientDelayPolicy(30 minutes);
        largeTransfer = new LargeTransferDelayPolicy(0.25 ether, 0.25 ether, 30 minutes);
        newReceiver = new NewReceiverDelayPolicy(1 hours);
        newEoaReceiver = new NewEOAReceiverDelayPolicy(30 minutes);
        unknownContract = new UnknownContractBlockPolicy(address(this));
    }

    function test_InfiniteApproval_IntrospectionAndConfig() public view {
        InfiniteApprovalPolicy policy = infiniteApproval;

        assertEq(IPolicyIntrospection(address(policy)).policyKey(), keccak256("infinite-approval-v1"));
        assertEq(IPolicyIntrospection(address(policy)).policyName(), "InfiniteApprovalPolicy");
        assertTrue(bytes(IPolicyIntrospection(address(policy)).policyDescription()).length > 0);
        assertEq(IPolicyIntrospection(address(policy)).policyConfigVersion(), 1);
        assertEq(policy.approvalLimit(), type(uint256).max);
        assertEq(policy.allowPermit(), false);
        assertEq(policy.APPROVAL_LIMIT_FUNCTIONAL(), false);

        PolicyConfigEntry[] memory cfg = IPolicyIntrospection(address(policy)).policyConfig();
        assertEq(cfg.length, 5);
        assertEq(cfg[0].key, bytes32("allow_permit"));
        assertEq(uint8(cfg[0].valueType), uint8(PolicyConfigValueType.Bool));
        assertEq(_asBool(cfg[0]), false);
        assertEq(cfg[2].key, bytes32("approval_limit_functional"));
        assertEq(_asBool(cfg[2]), false);
        assertEq(cfg[3].key, bytes32("legacy_approval_limit"));
        assertEq(_asUint(cfg[3]), type(uint256).max);
    }

    function test_DeFiApproval_IntrospectionAndConfig() public view {
        DeFiApprovalPolicy policy = defiApproval;

        assertEq(IPolicyIntrospection(address(policy)).policyKey(), keccak256("defi-approval-v1"));
        assertEq(IPolicyIntrospection(address(policy)).policyName(), "DeFiApprovalPolicy");
        assertTrue(bytes(IPolicyIntrospection(address(policy)).policyDescription()).length > 0);
        assertEq(IPolicyIntrospection(address(policy)).policyConfigVersion(), 1);
        assertEq(policy.ALLOW_MAX_APPROVAL(), true);
        assertEq(policy.ALLOW_PERMIT(), true);
        assertEq(policy.BLOCK_SET_APPROVAL_FOR_ALL_TRUE(), true);

        PolicyConfigEntry[] memory cfg = IPolicyIntrospection(address(policy)).policyConfig();
        assertEq(cfg.length, 3);
        assertEq(cfg[0].key, bytes32("allow_max_approval"));
        assertEq(_asBool(cfg[0]), true);
    }

    function test_ApprovalToNewSpenderDelay_IntrospectionAndConfig() public view {
        ApprovalToNewSpenderDelayPolicy policy = approvalToNewSpenderDelay;

        assertEq(IPolicyIntrospection(address(policy)).policyKey(), keccak256("approval-to-new-spender-delay-v1"));
        assertEq(IPolicyIntrospection(address(policy)).policyName(), "ApprovalToNewSpenderDelayPolicy");
        assertTrue(bytes(IPolicyIntrospection(address(policy)).policyDescription()).length > 0);
        assertEq(IPolicyIntrospection(address(policy)).policyConfigVersion(), 2);
        assertEq(policy.DELAY_SECONDS(), 30 minutes);

        PolicyConfigEntry[] memory cfg = IPolicyIntrospection(address(policy)).policyConfig();
        assertEq(cfg.length, 5);
        assertEq(cfg[0].key, bytes32("delay_seconds"));
        assertEq(_asUint(cfg[0]), 30 minutes);
        assertEq(cfg[1].key, bytes32("known_scope"));
        assertEq(cfg[4].key, bytes32("permit2_approve_supported"));
        assertEq(_asBool(cfg[4]), true);
    }

    function test_Erc20FirstNewRecipientDelay_IntrospectionAndConfig() public view {
        Erc20FirstNewRecipientDelayPolicy policy = erc20FirstNewRecipientDelay;

        assertEq(
            IPolicyIntrospection(address(policy)).policyKey(), keccak256("erc20-first-new-recipient-delay-v1")
        );
        assertEq(IPolicyIntrospection(address(policy)).policyName(), "Erc20FirstNewRecipientDelayPolicy");
        assertTrue(bytes(IPolicyIntrospection(address(policy)).policyDescription()).length > 0);
        assertEq(IPolicyIntrospection(address(policy)).policyConfigVersion(), 1);
        assertEq(policy.DELAY_SECONDS(), 30 minutes);

        PolicyConfigEntry[] memory cfg = IPolicyIntrospection(address(policy)).policyConfig();
        assertEq(cfg.length, 4);
        assertEq(cfg[0].key, bytes32("delay_seconds"));
        assertEq(_asUint(cfg[0]), 30 minutes);
        assertEq(cfg[1].key, bytes32("known_scope"));
    }

    function test_LargeTransferDelay_IntrospectionAndConfig() public view {
        LargeTransferDelayPolicy policy = largeTransfer;

        assertEq(IPolicyIntrospection(address(policy)).policyKey(), keccak256("large-transfer-delay-v1"));
        assertEq(IPolicyIntrospection(address(policy)).policyName(), "LargeTransferDelayPolicy");
        assertTrue(bytes(IPolicyIntrospection(address(policy)).policyDescription()).length > 0);
        assertEq(IPolicyIntrospection(address(policy)).policyConfigVersion(), 2);
        assertEq(policy.ETH_THRESHOLD_WEI(), 0.25 ether);
        assertEq(policy.ERC20_THRESHOLD_UNITS(), 0.25 ether);
        assertEq(policy.DELAY_SECONDS(), 30 minutes);

        PolicyConfigEntry[] memory cfg = IPolicyIntrospection(address(policy)).policyConfig();
        assertEq(cfg.length, 6);
        assertEq(cfg[0].key, bytes32("eth_threshold_wei"));
        assertEq(_asUint(cfg[0]), 0.25 ether);
        assertEq(cfg[1].key, bytes32("erc20_threshold_units"));
        assertEq(_asUint(cfg[1]), 0.25 ether);
        assertEq(cfg[2].key, bytes32("delay_seconds"));
        assertEq(_asUint(cfg[2]), 30 minutes);
        assertEq(cfg[5].key, bytes32("erc20_threshold_unit_scale"));
    }

    function test_NewReceiverDelay_IntrospectionAndConfig() public view {
        NewReceiverDelayPolicy policy = newReceiver;

        assertEq(IPolicyIntrospection(address(policy)).policyKey(), keccak256("new-receiver-delay-v1"));
        assertEq(IPolicyIntrospection(address(policy)).policyName(), "NewReceiverDelayPolicy");
        assertTrue(bytes(IPolicyIntrospection(address(policy)).policyDescription()).length > 0);
        assertEq(IPolicyIntrospection(address(policy)).policyConfigVersion(), 1);
        assertEq(policy.DELAY_SECONDS(), 1 hours);
        assertEq(policy.EOA_ONLY(), false);

        PolicyConfigEntry[] memory cfg = IPolicyIntrospection(address(policy)).policyConfig();
        assertEq(cfg.length, 3);
        assertEq(cfg[0].key, bytes32("delay_seconds"));
        assertEq(_asUint(cfg[0]), 1 hours);
        assertEq(cfg[1].key, bytes32("eoa_only"));
        assertEq(_asBool(cfg[1]), false);
    }

    function test_NewEOAReceiverDelay_IntrospectionAndConfig() public view {
        NewEOAReceiverDelayPolicy policy = newEoaReceiver;

        assertEq(IPolicyIntrospection(address(policy)).policyKey(), keccak256("new-eoa-receiver-delay-v1"));
        assertEq(IPolicyIntrospection(address(policy)).policyName(), "NewEOAReceiverDelayPolicy");
        assertTrue(bytes(IPolicyIntrospection(address(policy)).policyDescription()).length > 0);
        assertEq(IPolicyIntrospection(address(policy)).policyConfigVersion(), 4);
        assertEq(policy.DELAY_SECONDS(), 30 minutes);
        assertEq(policy.EOA_ONLY(), true);

        PolicyConfigEntry[] memory cfg = IPolicyIntrospection(address(policy)).policyConfig();
        assertEq(cfg.length, 7);
        assertEq(cfg[0].key, bytes32("delay_seconds"));
        assertEq(_asUint(cfg[0]), 30 minutes);
        assertEq(cfg[1].key, bytes32("eoa_only"));
        assertEq(_asBool(cfg[1]), true);
        assertEq(cfg[3].key, bytes32("unknown_contract_selector_action"));
        assertEq(cfg[4].key, bytes32("unknown_contract_selector_scope"));
        assertEq(cfg[5].key, bytes32("unknown_eoa_selector_action"));
        assertEq(cfg[6].key, bytes32("unknown_contract_revalidate"));
    }

    function test_UnknownContract_IntrospectionAndConfig() public view {
        UnknownContractBlockPolicy policy = unknownContract;

        assertEq(IPolicyIntrospection(address(policy)).policyKey(), keccak256("unknown-contract-block-v1"));
        assertEq(IPolicyIntrospection(address(policy)).policyName(), "UnknownContractBlockPolicy");
        assertTrue(bytes(IPolicyIntrospection(address(policy)).policyDescription()).length > 0);
        assertEq(IPolicyIntrospection(address(policy)).policyConfigVersion(), 1);
        assertEq(policy.owner(), address(this));

        PolicyConfigEntry[] memory cfg = IPolicyIntrospection(address(policy)).policyConfig();
        assertEq(cfg.length, 4);
        assertEq(cfg[0].key, bytes32("owner"));
        assertEq(_asAddress(cfg[0]), address(this));
        assertEq(cfg[3].key, bytes32("allowlist_reconstruct"));
    }

    function test_InfiniteApproval_ApprovalLimitIsExplicitlyNonFunctional() public {
        InfiniteApprovalPolicy strictLow = new InfiniteApprovalPolicy(0, false);
        InfiniteApprovalPolicy strictHigh = new InfiniteApprovalPolicy(type(uint256).max, false);
        bytes memory approveOne = abi.encodeWithSignature("approve(address,uint256)", address(0xBEEF), 1);

        (Decision dLow,) = strictLow.evaluate(address(this), address(this), 0, approveOne);
        (Decision dHigh,) = strictHigh.evaluate(address(this), address(this), 0, approveOne);
        assertEq(uint256(dLow), uint256(Decision.Revert));
        assertEq(uint256(dHigh), uint256(Decision.Revert));
        assertEq(strictLow.APPROVAL_LIMIT_FUNCTIONAL(), false);
        assertEq(strictHigh.APPROVAL_LIMIT_FUNCTIONAL(), false);
    }

    function _asUint(PolicyConfigEntry memory entry) internal pure returns (uint256) {
        return uint256(entry.value);
    }

    function _asBool(PolicyConfigEntry memory entry) internal pure returns (bool) {
        return uint256(entry.value) != 0;
    }

    function _asAddress(PolicyConfigEntry memory entry) internal pure returns (address) {
        return address(uint160(uint256(entry.value)));
    }
}
