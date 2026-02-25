// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Decision, IFirewallPolicy} from "../interfaces/IFirewallPolicy.sol";

contract InfiniteApprovalPolicy is IFirewallPolicy {
    bytes4 internal constant APPROVE_SELECTOR = 0x095ea7b3;

    /// @notice If set to 0, only blocks approve(spender, type(uint256).max) (legacy behavior).
    ///         If set > 0, blocks approve(spender, amount) for any amount >= approvalLimit.
    uint256 public immutable approvalLimit;

    constructor(uint256 approvalLimit_) {
        approvalLimit = approvalLimit_;
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

        if (sel != APPROVE_SELECTOR) return (Decision.Allow, 0);
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
}
