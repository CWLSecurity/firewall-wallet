// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Decision, IFirewallPolicy} from "../interfaces/IFirewallPolicy.sol";

error UnknownContract_Unauthorized();
error UnknownContract_ZeroAddress();

contract UnknownContractBlockPolicy is IFirewallPolicy {
    address public immutable owner;

    /// @notice Global allowlist: target contract -> allowed
    mapping(address => bool) public allowed;

    event AllowedSet(address indexed target, bool allowed);

    constructor(address owner_) {
        if (owner_ == address(0)) revert UnknownContract_ZeroAddress();
        owner = owner_;
    }

    function setAllowed(address target, bool isAllowed) external {
        if (msg.sender != owner) revert UnknownContract_Unauthorized();
        if (target == address(0)) revert UnknownContract_ZeroAddress();
        allowed[target] = isAllowed;
        emit AllowedSet(target, isAllowed);
    }

    function setAllowedBatch(address[] calldata targets, bool isAllowed) external {
        if (msg.sender != owner) revert UnknownContract_Unauthorized();
        uint256 len = targets.length;
        for (uint256 i = 0; i < len; i++) {
            address t = targets[i];
            if (t == address(0)) revert UnknownContract_ZeroAddress();
            allowed[t] = isAllowed;
            emit AllowedSet(t, isAllowed);
        }
    }

    /// @notice Blocks calls to unknown contracts. EOAs are always allowed.
    function evaluate(
        address, // vault (unused in MVP)
        address to,
        uint256, // value (unused)
        bytes calldata // data (unused)
    ) external view returns (Decision decision, uint48 delaySeconds) {
        // If target has code => it a contract. Must be allowlisted.
        if (to.code.length > 0 && !allowed[to]) {
            return (Decision.Revert, 0);
        }
        return (Decision.Allow, 0);
    }
}
