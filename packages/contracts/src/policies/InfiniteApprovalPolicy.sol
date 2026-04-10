// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Decision, IFirewallPolicy} from "../interfaces/IFirewallPolicy.sol";
import {
    IPolicyIntrospection,
    PolicyConfigEntry,
    PolicyConfigValueType
} from "../interfaces/IPolicyIntrospection.sol";

contract InfiniteApprovalPolicy is IFirewallPolicy, IPolicyIntrospection {
    bytes4 internal constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 internal constant INCREASE_ALLOWANCE_SELECTOR = 0x39509351;
    bytes4 internal constant SET_APPROVAL_FOR_ALL_SELECTOR = 0xa22cb465;
    bytes4 internal constant PERMIT_EIP2612_SELECTOR = 0xd505accf;
    bytes4 internal constant PERMIT_DAI_SELECTOR = 0x8fcbaf0c;
    bytes4 internal constant PERMIT2_APPROVE_SELECTOR = 0x87517c45;
    bytes4 internal constant PERMIT2_SINGLE_SELECTOR = 0x2b67b570;
    bytes4 internal constant PERMIT2_BATCH_SELECTOR = 0x2a2d80d1;
    bytes4 internal constant PERMIT2_TRANSFER_FROM_SELECTOR = 0x6949bce4;
    bytes4 internal constant PERMIT2_WITNESS_TRANSFER_FROM_SELECTOR = 0x2eda8726;

    /// @notice Legacy config retained for introspection/backward compatibility.
    ///         Strict mode blocks any non-zero approve/increaseAllowance regardless of this value.
    uint256 public immutable approvalLimit;
    /// @notice If true, permit() is allowed (DeFi-friendly). If false, permit() is blocked.
    bool public immutable allowPermit;
    /// @notice Explicitly indicates whether `approvalLimit` is used by runtime enforcement.
    ///         In the current strict model this value is always false.
    bool public constant APPROVAL_LIMIT_FUNCTIONAL = false;

    constructor(uint256 approvalLimit_, bool allowPermit_) {
        approvalLimit = approvalLimit_;
        allowPermit = allowPermit_;
    }

    function policyKey() external pure returns (bytes32) {
        return keccak256("infinite-approval-v1");
    }

    function policyName() external pure returns (string memory) {
        return "InfiniteApprovalPolicy";
    }

    function policyDescription() external pure returns (string memory) {
        return "Strict approvals: non-zero approve/increaseAllowance revert; permit-like calls depend on allowPermit.";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 1;
    }

    function policyConfig() external view returns (PolicyConfigEntry[] memory entries) {
        entries = new PolicyConfigEntry[](5);
        entries[0] = PolicyConfigEntry({
            key: bytes32("allow_permit"),
            valueType: PolicyConfigValueType.Bool,
            value: _boolToBytes32(allowPermit),
            unit: bytes32("bool")
        });
        entries[1] = PolicyConfigEntry({
            key: bytes32("strict_nonzero_mode"),
            valueType: PolicyConfigValueType.Bool,
            value: _boolToBytes32(true),
            unit: bytes32("bool")
        });
        entries[2] = PolicyConfigEntry({
            key: bytes32("approval_limit_functional"),
            valueType: PolicyConfigValueType.Bool,
            value: _boolToBytes32(APPROVAL_LIMIT_FUNCTIONAL),
            unit: bytes32("bool")
        });
        entries[3] = PolicyConfigEntry({
            key: bytes32("legacy_approval_limit"),
            valueType: PolicyConfigValueType.Uint256,
            value: bytes32(approvalLimit),
            unit: bytes32("raw")
        });
        entries[4] = PolicyConfigEntry({
            key: bytes32("permit_mode"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("allowPermit_flag"),
            unit: bytes32("mode")
        });
    }

    function evaluate(
        address,
        address,
        uint256,
        bytes calldata data
    ) external view returns (Decision decision, uint48 delaySeconds) {
        if (data.length < 4) return (Decision.Allow, 0);

        bytes4 sel;
        assembly {
            sel := calldataload(data.offset)
        }

        if (sel == APPROVE_SELECTOR) {
            if (data.length < 68) return (Decision.Allow, 0);

            uint256 amount;
            assembly {
                amount := calldataload(add(data.offset, 36))
            }

            // Strict mode: only approve(0) is allowed.
            return (amount == 0 ? Decision.Allow : Decision.Revert, 0);
        }

        if (sel == INCREASE_ALLOWANCE_SELECTOR) {
            if (data.length < 68) return (Decision.Allow, 0);
            uint256 added;
            assembly {
                added := calldataload(add(data.offset, 36))
            }

            // Strict mode: only increaseAllowance(..., 0) is allowed.
            return (added == 0 ? Decision.Allow : Decision.Revert, 0);
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

        if (
            sel == PERMIT_EIP2612_SELECTOR || sel == PERMIT_DAI_SELECTOR || sel == PERMIT2_APPROVE_SELECTOR
                || sel == PERMIT2_SINGLE_SELECTOR
                || sel == PERMIT2_BATCH_SELECTOR || sel == PERMIT2_TRANSFER_FROM_SELECTOR
                || sel == PERMIT2_WITNESS_TRANSFER_FROM_SELECTOR
        ) {
            // Block or allow permit-like approvals/signatures based on pack mode.
            return (allowPermit ? Decision.Allow : Decision.Revert, 0);
        }

        return (Decision.Allow, 0);
    }

    function _boolToBytes32(bool value) internal pure returns (bytes32) {
        return value ? bytes32(uint256(1)) : bytes32(0);
    }
}
