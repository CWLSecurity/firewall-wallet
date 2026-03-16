// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Decision, IFirewallPolicy} from "../interfaces/IFirewallPolicy.sol";
import {
    IPolicyIntrospection,
    PolicyConfigEntry,
    PolicyConfigValueType
} from "../interfaces/IPolicyIntrospection.sol";

/// @notice DeFi-oriented approval policy for base pack 1 (DeFi Trader).
///         - allow approve(max)
///         - allow permit()
///         - keep setApprovalForAll(true) blocked
contract DeFiApprovalPolicy is IFirewallPolicy, IPolicyIntrospection {
    bytes4 internal constant SET_APPROVAL_FOR_ALL_SELECTOR = 0xa22cb465;
    bytes4 internal constant PERMIT_SELECTOR = 0xd505accf;

    bool public constant ALLOW_MAX_APPROVAL = true;
    bool public constant ALLOW_PERMIT = true;
    bool public constant BLOCK_SET_APPROVAL_FOR_ALL_TRUE = true;

    function policyKey() external pure returns (bytes32) {
        return keccak256("defi-approval-v1");
    }

    function policyName() external pure returns (string memory) {
        return "DeFiApprovalPolicy";
    }

    function policyDescription() external pure returns (string memory) {
        return "DeFi-oriented approvals: permit allowed, setApprovalForAll(true) blocked.";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 1;
    }

    function policyConfig() external pure returns (PolicyConfigEntry[] memory entries) {
        entries = new PolicyConfigEntry[](3);
        entries[0] = PolicyConfigEntry({
            key: bytes32("allow_max_approval"),
            valueType: PolicyConfigValueType.Bool,
            value: bytes32(uint256(ALLOW_MAX_APPROVAL ? 1 : 0)),
            unit: bytes32("bool")
        });
        entries[1] = PolicyConfigEntry({
            key: bytes32("allow_permit"),
            valueType: PolicyConfigValueType.Bool,
            value: bytes32(uint256(ALLOW_PERMIT ? 1 : 0)),
            unit: bytes32("bool")
        });
        entries[2] = PolicyConfigEntry({
            key: bytes32("block_setapproval_true"),
            valueType: PolicyConfigValueType.Bool,
            value: bytes32(uint256(BLOCK_SET_APPROVAL_FOR_ALL_TRUE ? 1 : 0)),
            unit: bytes32("bool")
        });
    }

    function evaluate(
        address,
        address,
        uint256,
        bytes calldata data
    ) external pure returns (Decision decision, uint48 delaySeconds) {
        if (data.length < 4) return (Decision.Allow, 0);

        bytes4 sel;
        assembly {
            sel := calldataload(data.offset)
        }

        if (sel == SET_APPROVAL_FOR_ALL_SELECTOR) {
            if (data.length < 68) return (Decision.Allow, 0);
            uint256 approved;
            assembly {
                approved := calldataload(add(data.offset, 36))
            }
            if (approved != 0) {
                return (Decision.Revert, 0);
            }
            return (Decision.Allow, 0);
        }

        if (sel == PERMIT_SELECTOR) {
            return (Decision.Allow, 0);
        }

        return (Decision.Allow, 0);
    }
}
