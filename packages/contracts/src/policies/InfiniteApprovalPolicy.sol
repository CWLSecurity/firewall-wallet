// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Decision, IFirewallPolicy} from "../interfaces/IFirewallPolicy.sol";

contract InfiniteApprovalPolicy is IFirewallPolicy {
    bytes4 internal constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 internal constant INCREASE_ALLOWANCE_SELECTOR = 0x39509351;
    bytes4 internal constant SET_APPROVAL_FOR_ALL_SELECTOR = 0xa22cb465;
    bytes4 internal constant PERMIT_SELECTOR = 0xd505accf;

    /// @notice If set to 0, only blocks approve(spender, type(uint256).max) (legacy behavior).
    ///         If set > 0, blocks approve(spender, amount) for any amount >= approvalLimit.
    uint256 public immutable approvalLimit;
    /// @notice If true, permit() is allowed (DeFi-friendly). If false, permit() is blocked.
    bool public immutable allowPermit;

    constructor(uint256 approvalLimit_, bool allowPermit_) {
        approvalLimit = approvalLimit_;
        allowPermit = allowPermit_;
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

            // Always block explicit MAX_UINT approvals
            if (amount == type(uint256).max) {
                return (Decision.Revert, 0);
            }

            // Optional stricter mode: block "very large" approvals too
            uint256 limit = approvalLimit;
            if (limit != 0 && amount >= limit) {
                return (Decision.Revert, 0);
            }

            return (Decision.Allow, 0);
        }

        if (sel == INCREASE_ALLOWANCE_SELECTOR) {
            if (data.length < 68) return (Decision.Allow, 0);
            uint256 added;
            assembly {
                added := calldataload(add(data.offset, 36))
            }

            // Conservative: block increases that are "very large"
            uint256 limit = approvalLimit;
            if (limit == 0) {
                return (Decision.Allow, 0);
            }
            if (added >= limit) {
                return (Decision.Revert, 0);
            }
            return (Decision.Allow, 0);
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
            // MVP: optionally allow permit (preset-driven).
            return (allowPermit ? Decision.Allow : Decision.Revert, 0);
        }

        return (Decision.Allow, 0);
    }
}
